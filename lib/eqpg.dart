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
import 'package:eqpg/tables.dart' as table;

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

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  @ApiMethod(path: 'descriptor/create', method: 'POST')
  Future<QueryResult> createDescriptor(CreateDescriptor body) =>
      callApiMethod((s) => _createDescriptor(s, body), pool);

  @ApiMethod(path: 'descriptor/{id}/translations/create', method: 'POST')
  Future<QueryResult> createTranslation(int id, CreateTranslation body) =>
      callApiMethod((s) => _createTranslation(s, id, body), pool);

  @ApiMethod(path: 'subject/create', method: 'POST')
  Future<QueryResult> createSubject(CreateSubject body) =>
      callApiMethod((s) => _createSubject(s, body), pool);

  @ApiMethod(path: 'category/create', method: 'POST')
  Future<QueryResult> createCategory(CreateCategory body) =>
      callApiMethod((s) => _createCategory(s, body), pool);

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<QueryResult> createFunction(CreateFunction body) =>
      callApiMethod((s) => _createFunction(s, body), pool);

  @ApiMethod(path: 'expression/{id}/retrieveTree', method: 'GET')
  Future<ExpressionTree> retrieveExpressionTree(int id) =>
      new MethodCaller<ExpressionTree>().run(
          (db) =>
              _retrieveExpressionTree(new Session(db, new QueryResult()), id),
          pool);

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<QueryResult> createDefinition(CreateDefinition body) =>
      callApiMethod((s) => _createDefinition(s, body), pool);

  @ApiMethod(path: 'lineage/create', method: 'POST')
  Future<QueryResult> createLineage(CreateLineage body) =>
      callApiMethod((s) => _createLineage(s, body), pool);
}

/// Utility to reuse method calling boilerplate.
class MethodCaller<T> {
  Future<T> run(Future<T> handler(Connection db), Pool pool) {
    final completer = new Completer<T>();

    // Get connection.
    pool.connect()
      ..then((db) {
        // Run all methods in a transaction.
        db.runInTransaction(() async {
          completer.complete(await handler(db));
        })
          ..then((_) => db.close())
          ..catchError((error, stackTrace) {
            db.close();
            completer.completeError(error, stackTrace);
          });
      })
      ..catchError(completer.completeError);

    return completer.future;
  }
}

/// Utility to reuse method calling boilerplate.
Future<QueryResult> callApiMethod(Future handler(Session s), Pool pool) {
  return new MethodCaller<QueryResult>().run((db) async {
    final result = new QueryResult();
    await handler(new Session(db, result));
    result.finalize();
    return result;
  }, pool);
}
