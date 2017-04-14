// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.sqlbuilder;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart' as pg;

final log = new Logger('sqlbuilder');

/// Class for rows.
abstract class Row {
  int get id;
}

/// Object mapping function.
typedef R RowMapper<R extends Row>(pg.Row r);

/// Saves data to correct field in D (session data instance).
typedef void DataSaver<R extends Row, D>(D output, R record);

/// Table information.
class TableInfo<R, D> {
  final String tableName;
  final String select;
  final RowMapper<R> mapper;
  final DataSaver<R, D> saver;

  TableInfo(this.tableName, this.select, this.mapper, this.saver);
}

/// SQL snippet (used to distinguish raw sql from variables).
class Sql {
  final String statement;
  Sql(this.statement);

  @override
  String toString() => statement;
}

/// Session state
class SessionState<D> {
  final pg.Connection conn;
  final D data;

  SessionState(this.conn, this.data);

  Future<T> insert<T>(TableInfo<T, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await _runMappedQuery<T, D>(
            this, true, table, INSERT(table, s1, s2, s3, s4, s5)))
        .single;
  }

  Future<List<T>> select<T extends Row>(TableInfo<T, D> table,
      [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) {
    return _runMappedQuery<T, D>(
        this, true, table, SELECT(table, s1, s2, s3, s4, s5));
  }

  Future<List<int>> selectIds<T extends Row>(TableInfo<T, D> table,
      [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await select(table, s1, s2, s3, s4, s5))
        .map((row) => row.id)
        .toList();
  }

  /// Select records by their 'id' field.
  Future<List<T>> selectByIds<T extends Row>(
      TableInfo<T, D> table, Iterable<int> ids) {
    /// TODO: use cache to reduce queries.
    return _runMappedQuery<T, D>(
        this, true, table, SELECT(table, WHERE({'id': IN(ids)})));
  }

  Future<T> selectById<T extends Row>(TableInfo<T, D> table, int id) async {
    return (await selectByIds(table, [id])).single;
  }

  Future<bool> exists<T extends Row>(TableInfo<T, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await select(table, s1, s2, s3, s4, s5)).isNotEmpty;
  }

  Future<List<T>> update<T>(TableInfo<T, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) {
    return _runMappedQuery<T, D>(
        this, true, table, UPDATE(table, s1, s2, s3, s4, s5));
  }
}

Future<List<T>> _runMappedQuery<T, D>(
    SessionState s, bool store, TableInfo<T, D> table, Sql sql) async {
  log.info(sql.statement);
  final result = await s.conn.query(sql.statement).map(table.mapper).toList();
  if (store) {
    result.forEach((record) => table.saver(s.data, record));
  }
  return result;
}

/// Adds all non-null arguments to a buffer with spaces in between.
String _collapse(Sql s1, Sql s2, Sql s3, Sql s4, Sql s5) {
  final buffer = new StringBuffer();
  if (s1 != null) {
    buffer.write(s1);
    if (s2 != null) {
      buffer.write(' ');
      buffer.write(s2);
      if (s3 != null) {
        buffer.write(' ');
        buffer.write(s3);
        if (s4 != null) {
          buffer.write(' ');
          buffer.write(s4);
          if (s5 != null) {
            buffer.write(' ');
            buffer.write(s5);
          }
        }
      }
    }
  }

  return buffer.toString();
}

List<String> _encodeValues(Iterable values, pg.TypeConverter converter) {
  return values.map((value) {
    if (value is Sql) {
      return value.statement;
    } else {
      return converter.encode(value, null);
    }
  }).toList();
}

// ignore: non_constant_identifier_names
Sql SQL(String statement) => new Sql(statement);

// ignore: non_constant_identifier_names
Sql INSERT(TableInfo table, Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL(
      'INSERT INTO ${table.tableName} $statements RETURNING ${table.select}');
}

// ignore: non_constant_identifier_names
Sql SELECT(TableInfo table, [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL('SELECT ${table.select} FROM ${table.tableName} $statements');
}

// ignore: non_constant_identifier_names
Sql UPDATE(TableInfo table, Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL('UPDATE ${table.tableName} $statements RETURNING ${table.select}');
}

/// This code is shared between [WHERE] and [SET].
Sql _flatten(String prefix, Map<String, dynamic> map, String keyValueSeparator,
    String itemSeparator) {
  final converter = new pg.TypeConverter();
  final buffer = new StringBuffer();
  buffer.write('$prefix ');

  final fields = map.keys.toList();
  for (var i = 0; i < fields.length; i++) {
    if (i != 0) {
      buffer.write(' $itemSeparator ');
    }
    buffer.write(fields[i]);
    buffer.write(keyValueSeparator);

    final value = map[fields[i]];
    if (value is Sql) {
      buffer.write(value.statement);
    } else {
      buffer.write(converter.encode(value, null));
    }
  }

  return SQL(buffer.toString());
}

// ignore: non_constant_identifier_names
Sql WHERE(Map<String, Sql> conditions) {
  return _flatten('WHERE', conditions, ' ', 'AND');
}

// ignore: non_constant_identifier_names
Sql SET(Map<String, dynamic> values) {
  return _flatten('SET', values, '=', ',');
}

// ignore: non_constant_identifier_names
Sql IS(dynamic value) {
  if (value is Sql) {
    return SQL('= $value');
  } else {
    final converter = new pg.TypeConverter();
    return SQL('= ${converter.encode(value, null)}');
  }
}

// ignore: non_constant_identifier_names
Sql IN(dynamic values) {
  if (values is Sql) {
    return SQL('IN $values');
  } else if (values is Iterable) {
    final encoded = _encodeValues(values, new pg.TypeConverter());
    return SQL('IN (${encoded.join(',')})');
  } else {
    throw new ArgumentError('values must be Sql or Iterable');
  }
}

// ignore: non_constant_identifier_names
Sql IN_IDS(List<Row> rows) {
  final ids = rows.map((row) => row.id).toList();
  return SQL('IN (${ids.join(',')})');
}

// ignore: non_constant_identifier_names
Sql VALUES(Map<String, dynamic> values) {
  final encoded = _encodeValues(values.values, new pg.TypeConverter());
  return SQL('(${values.keys.join(',')}) VALUES (${encoded.join(',')})');
}

// ignore: non_constant_identifier_names
Sql SUBQUERY(Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  return SQL('(${_collapse(s1, s2, s3, s4, s5)})');
}

// ignore: non_constant_identifier_names
Sql FUNCTION(String functionFormat,
    [dynamic s1, dynamic s2, dynamic s3, dynamic s4, dynamic s5]) {
  final args = [s1, s2, s3, s4, s5];
  args.removeWhere((s) => s == null);
  final encodedArgs = _encodeValues(args, new pg.TypeConverter());

  final functionInfo = functionFormat.split('::');
  final name = functionInfo.first;
  if (functionInfo.length == 1) {
    return SQL('$name(${encodedArgs.join(',')})');
  } else if (functionInfo.length == 2) {
    final cast = functionInfo.last;
    return SQL('$name(${encodedArgs.join(',')})::$cast');
  } else {
    throw new FormatException('cannot read function format');
  }
}

// ignore: non_constant_identifier_names
Sql LIMIT(int limit) {
  return SQL('LIMIT ($limit)');
}

// ignore: non_constant_identifier_names
Sql ARRAY(Iterable values, String type) {
  final encoded = _encodeValues(values, new pg.TypeConverter());
  return SQL('ARRAY[${encoded.join(',')}]' + (type == null ? '' : '::$type[]'));
}
