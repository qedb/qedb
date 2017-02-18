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

part 'src/rule.dart';
part 'src/lineage.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/definition.dart';
part 'src/exceptions.dart';
part 'src/descriptor.dart';
part 'src/expression.dart';
part 'src/expression_tree.dart';

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
    conn.close();
  }

  /// Utility to reuse method calling boilerplate.
  Future<T> _runRequestSession<T>(Future<T> handler(Session s)) {
    return _runSandboxed<T>((conn) {
      final data = new SessionData(cache);
      return handler(new Session(conn, data));
    }, pool);
  }

  @ApiMethod(path: 'descriptor/create', method: 'POST')
  Future<DescriptorResource> createDescriptor(DescriptorResource body) =>
      _runRequestSession<DescriptorResource>((s) async =>
          new DescriptorResource.from(
              await _createDescriptor(s, body), s.data));

  @ApiMethod(path: 'descriptor/{id}/translations/create', method: 'POST')
  Future<TranslationResource> createTranslation(
          int id, TranslationResource body) =>
      _runRequestSession<TranslationResource>((s) async =>
          new TranslationResource.from(
              await _createTranslation(s, id, body), s.data));

  @ApiMethod(path: 'descriptor/{id}/translations/list', method: 'GET')
  Future<List<TranslationResource>> listDescriptorTranslations(int id) =>
      _runRequestSession<List<TranslationResource>>((s) async =>
          (await _listTranslations(s, id))
              .map((r) => new TranslationResource.from(r, s.data))
              .toList());

  @ApiMethod(path: 'subject/create', method: 'POST')
  Future<SubjectResource> createSubject(SubjectResource body) =>
      _runRequestSession<SubjectResource>((s) async =>
          new SubjectResource.from(await _createSubject(s, body), s.data));

  /*@ApiMethod(path: 'category/create', method: 'POST')
  Future<SessionData> createCategory(CreateCategory body) =>
      callApiMethod((s) => _createCategory(s, 0, body), pool);

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<SessionData> createFunction(CreateFunction body) =>
      callApiMethod((s) => _createFunction(s, body), pool);

  @ApiMethod(path: 'expression/{id}/retrieveTree', method: 'GET')
  Future<ExpressionTree> retrieveExpressionTree(int id) =>
      new MethodCaller<ExpressionTree>().run(
          (conn) =>
              _retrieveExpressionTree(new Session(conn, new SessionData()), id),
          pool);

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<SessionData> createDefinition(CreateDefinition body) =>
      callApiMethod((s) => _createDefinition(s, body), pool);

  @ApiMethod(path: 'lineage/create', method: 'POST')
  Future<SessionData> createLineage(CreateLineage body) =>
      callApiMethod((s) => _createLineage(s, body), pool);*/
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
