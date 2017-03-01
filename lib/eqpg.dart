// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:logging/logging.dart';
import 'package:postgresql/pool.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqpg/dbutils.dart';
import 'package:eqpg/resources.dart';
import 'package:eqpg/schema.dart' as db;

part 'src/exceptions.dart';

part 'src/locale.dart';
part 'src/descriptor.dart';
part 'src/subject.dart';
part 'src/translation.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/expression.dart';
part 'src/rule.dart';
part 'src/definition.dart';
part 'src/expression_lineage.dart';

final log = new Logger('eqpg');

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final Pool pool;

  /// Persistent cache of database data (for some immutable rows).
  final cache = new DbCache();

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  /// Initialize [pool] and [cache].
  Future<Null> initialize() async {
    await pool.start();
    final conn = await pool.connect();
    await cache.initialize(conn);
    conn.close();
  }

  /// Utility to reuse method calling boilerplate.
  Future<T> _runRequestSession<T>(Future<T> handler(Session s)) {
    return _runSandboxed<T>((conn) {
      final data = new SessionData(cache);
      return handler(new Session(conn, data));
    }, pool);
  }

  @ApiMethod(path: 'locale/create', method: 'POST')
  Future<LocaleResource> createLocale(LocaleResource body) =>
      _runRequestSession<LocaleResource>((s) async => new LocaleResource()
        ..load((await _createLocale(s, body)).id, s.data));

  @ApiMethod(path: 'locale/list', method: 'GET')
  List<LocaleResource> listLocales() => _listLocales(cache);

  @ApiMethod(path: 'descriptor/create', method: 'POST')
  Future<DescriptorResource> createDescriptor(DescriptorResource body) =>
      _runRequestSession<DescriptorResource>((s) async =>
          new DescriptorResource()
            ..load((await _createDescriptor(s, body)).id, s.data));

  @ApiMethod(path: 'descriptor/{id}/translations/create', method: 'POST')
  Future<TranslationResource> createTranslation(
          int id, TranslationResource body) =>
      _runRequestSession<TranslationResource>((s) async =>
          new TranslationResource()
            ..loadRow(await _createTranslation(s, id, body), s.data));

  @ApiMethod(path: 'descriptor/{id}/translations/list', method: 'GET')
  Future<List<TranslationResource>> listDescriptorTranslations(int id) =>
      _runRequestSession<List<TranslationResource>>((s) async =>
          (await _listTranslations(s, id))
              .map((r) => new TranslationResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'descriptor/list', method: 'GET')
  Future<List<DescriptorResource>> listDescriptors(
          {String locale: 'en_US'}) async =>
      _runRequestSession<List<DescriptorResource>>((s) async =>
          (await _listDescriptors(s, locale: locale))
              .map((r) => new DescriptorResource()..load(r.id, s.data))
              .toList());

  @ApiMethod(path: 'descriptor/{id}/read', method: 'GET')
  Future<DescriptorResource> readDescriptor(int id) async =>
      new DescriptorResource()
        ..id = id
        ..translations = await listDescriptorTranslations(id);

  @ApiMethod(path: 'subject/create', method: 'POST')
  Future<SubjectResource> createSubject(SubjectResource body) =>
      _runRequestSession<SubjectResource>((s) async => new SubjectResource()
        ..loadRow(await _createSubject(s, body), s.data));

  @ApiMethod(path: 'subject/list', method: 'GET')
  Future<List<SubjectResource>> listSubjects({String locale: 'en_US'}) =>
      _runRequestSession<List<SubjectResource>>((s) async =>
          (await _listSubjects(s, locale: locale))
              .map((r) => new SubjectResource()..load(r.id, s.data))
              .toList());

  @ApiMethod(path: 'category/create', method: 'POST')
  Future<CategoryResource> createCategory(CategoryResource body) =>
      _runRequestSession<CategoryResource>((s) async => new CategoryResource()
        ..loadRow(await _createCategory(s, 0, body), s.data));

  @ApiMethod(path: 'category/list', method: 'GET')
  Future<List<CategoryResource>> listCategories({String locale: ''}) =>
      _runRequestSession<List<CategoryResource>>((s) async =>
          (await _listCategories(s, locale: locale))
              .map((r) => new CategoryResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'category/{id}/category/create', method: 'POST')
  Future<CategoryResource> createSubCategory(int id, CategoryResource body) =>
      _runRequestSession<CategoryResource>((s) async => new CategoryResource()
        ..loadRow(await _createCategory(s, id, body), s.data));

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<FunctionResource> createFunction(FunctionResource body) =>
      _runRequestSession<FunctionResource>((s) async => new FunctionResource()
        ..loadRow(await _createFunction(s, body), s.data));

  @ApiMethod(path: 'operator/create', method: 'POST')
  Future<OperatorResource> createOperator(OperatorResource body) =>
      _runRequestSession<OperatorResource>((s) async => new OperatorResource()
        ..loadRow(await _createOperator(s, body), s.data));

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<DefinitionResource> createDefinition(DefinitionResource body) =>
      _runRequestSession<DefinitionResource>((s) async =>
          new DefinitionResource()
            ..loadRow(await _createDefinition(s, body), s.data));

  @ApiMethod(path: 'expressionLineage/create', method: 'POST')
  Future<ExpressionLineageResource> createLineage(
          ExpressionLineageResource body) =>
      _runRequestSession<ExpressionLineageResource>((s) async =>
          new ExpressionLineageResource()
            ..loadRow(await _createExpressionLineage(s, body), s.data));
}

/// Utility to reuse method calling boilerplate.
Future<T> _runSandboxed<T>(Future<T> handler(Connection conn), Pool pool) {
  final completer = new Completer<T>();

  // Get connection.
  pool.connect()
    ..then((conn) {
      T result;

      // Run in a transaction.
      conn.runInTransaction(() async {
        result = await handler(conn);
      })
        // When the handler inside the transaction is completed:
        ..then((_) {
          conn.close();
          completer.complete(result);
        })
        // When an error occurs during the completion of the handler:
        ..catchError((error, stackTrace) {
          conn.close();
          completer.completeError(error, stackTrace);
        });
    })
    // When an error occurs when obtaining a connection from the pool:
    ..catchError(completer.completeError);

  return completer.future;
}
