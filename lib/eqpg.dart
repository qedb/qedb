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
import 'package:postgres/postgres.dart';
import 'package:eqpg/tables.dart' as table;

part 'src/dbpool.dart';
part 'src/lineage.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/expression.dart';
part 'src/definition.dart';

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final DbPool pool;

  EqDB(DbConnection connection, int maxConnections)
      : pool = new DbPool(connection, maxConnections);

  @ApiMethod(path: 'createCategory', method: 'POST')
  Future<table.Category> createCategory(CreateCategory input) =>
      _createCategory(pool, input);

  @ApiMethod(path: 'createFunction', method: 'POST')
  Future<table.Function> createFunction(CreateFunction input) =>
      _createFunction(pool, input);

  @ApiMethod(path: 'createDefinition', method: 'POST')
  Future<table.Definition> createDefinition(CreateDefinition input) =>
      _createDefinition(pool, input);
}
