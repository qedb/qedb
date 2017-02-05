// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.dbutils;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqpg/tables.dart' as table;

part 'src/generated/result.dart';
part 'src/generated/helpers.dart';

final log = new Logger('dbutils');

/// Session state
class Session {
  final Connection db;
  final QueryResult result;
  Session(this.db, this.result);
}

/// Class for passing custom SQL to the TableHelper.
class Sql {
  final String sql;
  final Map<String, dynamic> parameters;

  Sql(this.sql, [this.parameters = const {}]);
  Sql.arrayAppend(String array, String append, String castAs, this.parameters)
      : sql = 'array_append($array, $append)::$castAs';
}

/// DB data Stream mapper.
typedef R TableMapper<R extends table.DbTable>(Row r);

/// Saves data to correct field in QueryResult.
typedef void DataSaver<R extends table.DbTable>(QueryResult result, R record);

class TableHelper<R extends table.DbTable> {
  final String tableName, rowFormatter;
  final TableMapper<R> mapper;
  final DataSaver<R> saver;

  TableHelper(this.tableName, this.rowFormatter, this.mapper, this.saver);

  /// Format a query parameter value.
  String _formatParameter(
      String key, dynamic value, Map<String, dynamic> parameters) {
    if (value is Sql) {
      // Does not check for key collisions, assumes you know what you are doing.
      parameters.addAll(value.parameters);
      return value.sql;
    } else {
      return '@$key';
    }
  }

  /// Insert a record.
  Future<R> insert(Session s, Map<String, dynamic> parameters) async {
    final keys = parameters.keys.toList();
    final values = parameters.values.toList();
    final subs = new List<String>.generate(
        keys.length, (i) => _formatParameter(keys[i], values[i], parameters));

    final sql = subs.isNotEmpty
        ? '''
INSERT INTO $tableName (${keys.join(',')})
VALUES (${subs.join(',')})
RETURNING $rowFormatter'''
        : 'INSERT INTO $tableName DEFAULT VALUES RETURNING $rowFormatter';
    log.info(sql);
    final record = await s.db.query(sql, parameters).map(mapper).single;

    // Inserts are always saved by convention.
    saver(s.result, record);

    return record;
  }

  /// Insert a record using custom SQL.
  Future<R> insertCustom(
      Session s, String sql, Map<String, dynamic> parameters) async {
    final record = await s.db.query(sql, parameters).map(mapper).single;
    saver(s.result, record);
    return record;
  }

  /// Select a record.
  /// This function is intentionally limited in functionality. For more complex
  /// selects you can use raw queries with [selectCustom].
  Future<List<R>> select(Session s, Map<String, dynamic> parameters,
      {bool save: true}) async {
    final keys = parameters.keys.toList();
    final values = parameters.values.toList();
    final conditions = new List<String>.generate(keys.length, (i) {
      final format = _formatParameter(keys[i], values[i], parameters);
      return '${keys[i]} = $format';
    }).join(' AND ');

    // Return mapped results.
    final sql = 'SELECT $rowFormatter FROM $tableName WHERE $conditions';
    log.info(sql);
    final result = await s.db.query(sql, parameters).map(mapper).toList();
    if (save) {
      result.forEach((record) => saver(s.result, record));
    }
    return result;
  }

  /// Process custom select statement.
  Future<List<R>> selectCustom(
      Session s, String sql, Map<String, dynamic> parameters) async {
    final result = await s.db.query(sql, parameters).map(mapper).toList();
    result.forEach((record) => saver(s.result, record));
    return result;
  }

  /// Select a single record.
  Future<R> selectOne(Session s, Map<String, dynamic> parameters,
          {bool save: true}) async =>
      (await select(s, parameters, save: save)).single;

  /// Check if a given record exists.
  Future<bool> exists(Session s, Map<String, dynamic> parameters,
      {bool save: false}) async {
    return (await select(s, parameters, save: save)).isNotEmpty;
  }

  /// Get a record ID for the given parameters.
  Future<int> getId(Session s, Map<String, dynamic> parameters) async {
    final records = await select(s, parameters);
    if (records.isNotEmpty) {
      return records.single.id;
    } else {
      return (await insert(s, parameters)).id;
    }
  }
}
