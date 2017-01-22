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

part 'src/lineage.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/expression.dart';
part 'src/rule.dart';
part 'src/definition.dart';

final log = new Logger('eqpg');

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final Pool pool;

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  @ApiMethod(path: 'createCategory', method: 'POST')
  Future<table.Category> createCategory(CreateCategory input) =>
      new MethodCaller<table.Category, CreateCategory>()
          .execute(input, _createCategory, pool);

  @ApiMethod(path: 'createFunction', method: 'POST')
  Future<table.Function> createFunction(CreateFunction input) =>
      new MethodCaller<table.Function, CreateFunction>()
          .execute(input, _createFunction, pool);

  @ApiMethod(path: 'createDefinition', method: 'POST')
  Future<table.Definition> createDefinition(CreateDefinition input) =>
      new MethodCaller<table.Definition, CreateDefinition>()
          .execute(input, _createDefinition, pool);
}

/// Utility to reuse method calling boilerplate.
class MethodCaller<T, I> {
  Future<T> execute(
      I input, Future<T> handler(Connection db, I input), Pool pool) async {
    final db = await pool.connect();
    final completer = new Completer<T>();

    // Run all methods in a transaction.
    db
        .runInTransaction(() async {
          completer.complete(await handler(db, input));
        })
        .then((_) => db.close())
        .catchError((error, stackTrace) {
          db.close();
          completer.completeError(error, stackTrace);
        });

    return completer.future;
  }
}
