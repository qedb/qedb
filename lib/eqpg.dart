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
import 'package:eqpg/tables.dart' as table;

part 'src/rule.dart';
part 'src/lineage.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/expression.dart';
part 'src/definition.dart';
part 'src/exceptions.dart';

final log = new Logger('eqpg');

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final Pool pool;

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  @ApiMethod(path: 'category/create', method: 'POST')
  Future<table.Category> createCategory(CreateCategory input) =>
      new MethodCaller<table.Category>()
          .execute((db) => _createCategory(db, input), pool);

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<table.Function> createFunction(CreateFunction input) =>
      new MethodCaller<table.Function>()
          .execute((db) => _createFunction(db, input), pool);

  @ApiMethod(path: 'expression/{id}/retrieveTree', method: 'GET')
  Future<RetrieveTree> retrieveExpressionTree(int id) =>
      new MethodCaller<RetrieveTree>()
          .execute((db) => _retrieveExpressionTree(db, id), pool);

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<table.Definition> createDefinition(CreateDefinition input) =>
      new MethodCaller<table.Definition>()
          .execute((db) => _createDefinition(db, input), pool);

  @ApiMethod(path: 'lineage/create', method: 'POST')
  Future<table.Lineage> createLineage(CreateLineage input) =>
      new MethodCaller<table.Lineage>()
          .execute((db) => _createLineage(db, input), pool);
}

/// Utility to reuse method calling boilerplate.
class MethodCaller<T> {
  Future<T> execute(Future<T> handler(Connection db), Pool pool) {
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
