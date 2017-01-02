// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg;

import 'dart:async';

import 'package:rpc/rpc.dart';
import 'package:postgres/postgres.dart';

part 'src/dbpool.dart';
part 'src/category.dart';

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final DbPool pool;

  @ApiResource(name: 'category')
  final CategoryResource category;

  factory EqDB(DbConnection connection, int maxConnections) {
    final pool = new DbPool(connection, maxConnections);
    final category = new CategoryResource(pool);
    return new EqDB._(pool, category);
  }

  EqDB._(this.pool, this.category);
}
