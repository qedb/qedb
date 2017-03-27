// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.api;

import 'dart:async';

import 'package:rpc/rpc.dart';
import 'package:logging/logging.dart';
import 'package:postgresql/pool.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqdb/dbutils.dart';
import 'package:eqdb/resources.dart';
import 'package:eqdb/eqdb.dart' as api;

final log = new Logger('eqdb');
const defaultLocale = 'en_US';

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final Pool pool;

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  /// Initialize [pool].
  Future<Null> initialize() async {
    await pool.start();
  }

  /// Utility to reuse method calling boilerplate.
  Future<T> _runRequestSession<T>(Future<T> handler(Session s)) {
    return _runSandboxed<T>((conn) async {
      final data = new SessionData();
      final session = new Session(conn, data);

      // Retrieve all locales.
      // This may seem a bit ridiculous, but the overhead is not actually that
      // big. Additionally, this makes the rest of the code more convenient, and
      // locale codes can be included in all responses for free. A TTL spanning
      // multiple sessions might be used to optimize this in the future.
      await api.listLocales(session);

      return handler(session);
    }, pool);
  }

  @ApiMethod(path: 'locale/create', method: 'POST')
  Future<LocaleResource> createLocale(LocaleResource body) =>
      _runRequestSession<LocaleResource>((s) async => new LocaleResource()
        ..load((await api.createLocale(s, body)).id, s.data));

  @ApiMethod(path: 'locale/list', method: 'GET')
  Future<List<LocaleResource>> listLocales() =>
      // Note that all locales are loaded for each session.
      _runRequestSession<List<LocaleResource>>((s) async => s
          .data.localeTable.values
          .map((r) => new LocaleResource()..loadRow(r, s.data))
          .toList());

  @ApiMethod(path: 'descriptor/create', method: 'POST')
  Future<DescriptorResource> createDescriptor(DescriptorResource body) =>
      _runRequestSession<DescriptorResource>((s) async =>
          new DescriptorResource()
            ..load((await api.createDescriptor(s, body)).id, s.data));

  @ApiMethod(path: 'descriptor/list', method: 'GET')
  Future<List<DescriptorResource>> listDescriptors(
          {String locale: defaultLocale}) async =>
      _runRequestSession<List<DescriptorResource>>((s) async =>
          (await api.listDescriptors(s, [locale]))
              .map((r) => new DescriptorResource()..load(r.id, s.data))
              .toList());

  @ApiMethod(path: 'descriptor/{id}/read', method: 'GET')
  Future<DescriptorResource> readDescriptor(int id) async =>
      new DescriptorResource()
        ..id = id
        ..translations = await listDescriptorTranslations(id);

  @ApiMethod(path: 'descriptor/{id}/translation/create', method: 'POST')
  Future<TranslationResource> createTranslation(
          int id, TranslationResource body) =>
      _runRequestSession<TranslationResource>((s) async =>
          new TranslationResource()
            ..loadRow(await api.createTranslation(s, id, body), s.data));

  @ApiMethod(path: 'descriptor/{id}/translation/list', method: 'GET')
  Future<List<TranslationResource>> listDescriptorTranslations(int id) =>
      _runRequestSession<List<TranslationResource>>((s) async =>
          (await api.listTranslations(s, id))
              .map((r) => new TranslationResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'subject/create', method: 'POST')
  Future<SubjectResource> createSubject(SubjectResource body) =>
      _runRequestSession<SubjectResource>((s) async => new SubjectResource()
        ..loadRow(await api.createSubject(s, body), s.data));

  @ApiMethod(path: 'subject/list', method: 'GET')
  Future<List<SubjectResource>> listSubjects({String locale: defaultLocale}) =>
      _runRequestSession<List<SubjectResource>>((s) async =>
          (await api.listSubjects(s, [locale]))
              .map((r) => new SubjectResource()..load(r.id, s.data))
              .toList());

  @ApiMethod(path: 'category/create', method: 'POST')
  Future<CategoryResource> createCategory(CategoryResource body) =>
      _runRequestSession<CategoryResource>((s) async => new CategoryResource()
        ..loadRow(await api.createCategory(s, 0, body), s.data));

  @ApiMethod(path: 'category/list', method: 'GET')
  Future<List<CategoryResource>> listCategories(
          {String locale: defaultLocale}) =>
      _runRequestSession<List<CategoryResource>>((s) async =>
          (await api.listCategories(s, [locale]))
              .map((r) => new CategoryResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'category/{id}/read', method: 'GET')
  Future<CategoryResource> readCategory(int id,
          {String locale: defaultLocale}) =>
      _runRequestSession<CategoryResource>((s) async => new CategoryResource()
        ..loadRow(await api.readCategory(s, id, [locale]), s.data));

  @ApiMethod(path: 'category/{id}/category/create', method: 'POST')
  Future<CategoryResource> createSubCategory(int id, CategoryResource body) =>
      _runRequestSession<CategoryResource>((s) async => new CategoryResource()
        ..loadRow(await api.createCategory(s, id, body), s.data));

  @ApiMethod(path: 'category/{id}/category/list', method: 'GET')
  Future<List<CategoryResource>> listSubCategories(int id,
          {String locale: defaultLocale}) =>
      _runRequestSession<List<CategoryResource>>((s) async =>
          (await api.listCategories(s, [locale], id))
              .map((r) => new CategoryResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<FunctionResource> createFunction(FunctionResource body) =>
      _runRequestSession<FunctionResource>((s) async => new FunctionResource()
        ..loadRow(await api.createFunction(s, body), s.data));

  @ApiMethod(path: 'function/list', method: 'GET')
  Future<List<FunctionResource>> listFunctions(
          {String locale: defaultLocale}) =>
      _runRequestSession<List<FunctionResource>>((s) async =>
          (await api.listFunctions(s, [locale], 0))
              .map((r) => new FunctionResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'operator/create', method: 'POST')
  Future<OperatorResource> createOperator(OperatorResource body) =>
      _runRequestSession<OperatorResource>((s) async => new OperatorResource()
        ..loadRow(await api.createOperator(s, body), s.data));

  @ApiMethod(path: 'operator/list', method: 'GET')
  Future<List<OperatorResource>> listOperators() =>
      _runRequestSession<List<OperatorResource>>((s) async =>
          (await api.listOperators(s))
              .map((r) => new OperatorResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<DefinitionResource> createDefinition(DefinitionResource body) =>
      _runRequestSession<DefinitionResource>((s) async =>
          new DefinitionResource()
            ..loadRow(await api.createDefinition(s, body), s.data));

  @ApiMethod(path: 'expressionLineage/create', method: 'POST')
  Future<ExpressionLineageResource> createLineage(
          ExpressionLineageResource body) =>
      _runRequestSession<ExpressionLineageResource>((s) async =>
          new ExpressionLineageResource()
            ..loadRow(await api.createExpressionLineage(s, body), s.data));

  @ApiMethod(path: 'expressionDifference/resolve', method: 'POST')
  Future<api.ExpressionDifferenceResource> resolveExpressionDifference(
          api.ExpressionDifferenceResource body) =>
      _runRequestSession<api.ExpressionDifferenceResource>(
          (s) => api.resolveExpressionDifference(s, body));
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
