// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.dbutils;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';
import 'package:quiver/collection.dart';

import 'package:eqpg/schema.dart' as db;

part 'src/generated/session_data.dart';
part 'src/generated/helpers.dart';

final log = new Logger('dbutils');

/// Specialized cache for some append-only tables (locale).
class DbCache {
  /// Map of <localeId, localeCode>.
  final locales = new BiMap<int, String>();

  Future<Null> initialize(Connection conn) async {
    /// Load existing locales.
    final result = conn.query('SELECT id, code FROM locale');
    await for (final row in result) {
      locales[row[0]] = row[1];
    }
  }
}

/// Session state
class Session {
  final Connection conn;
  final SessionData data;

  Session(this.conn, this.data);
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
typedef R RowMapper<R extends db.Row>(Row r);

/// Saves data to correct field in SessionData.
typedef void DataSaver<R extends db.Row>(SessionData result, R record);

class TableHelper<R extends db.Row> {
  final String tableName, rowFormatter;
  final RowMapper<R> mapper;
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
    log.info('$sql, $parameters');
    final record = await s.conn.query(sql, parameters).map(mapper).single;

    // Inserts are always saved by convention.
    saver(s.data, record);

    return record;
  }

  /// Insert a record using custom SQL.
  Future<R> insertCustom(
      Session s, String sql, Map<String, dynamic> parameters) async {
    log.info('$sql, $parameters');
    final record = await s.conn.query(sql, parameters).map(mapper).single;
    saver(s.data, record);
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
    final sql = conditions.isNotEmpty
        ? 'SELECT $rowFormatter FROM $tableName WHERE $conditions'
        : 'SELECT $rowFormatter FROM $tableName';
    log.info('$sql, $parameters');
    final result = await s.conn.query(sql, parameters).map(mapper).toList();
    if (save) {
      result.forEach((record) => saver(s.data, record));
    }
    return result;
  }

  /// Process custom select statement.
  Future<List<R>> selectCustom(
      Session s, String sql, Map<String, dynamic> parameters) async {
    log.info('$sql, $parameters');
    final result = await s.conn.query(sql, parameters).map(mapper).toList();
    result.forEach((record) => saver(s.data, record));
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
