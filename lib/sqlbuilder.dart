// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.sqlbuilder;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';

final log = new Logger('sqlbuilder');

/// Class for rows.
abstract class Record {
  int get id;
}

/// Object mapping function.
typedef R RowMapper<R extends Record>(Row r);

/// Get Map<int, R> where records are saved.
typedef Map<int, R> TableCacheGetter<R extends Record, D>(D data);

/// Table information.
class TableInfo<R, D> {
  final String tableName;
  final String select;
  final RowMapper<R> mapRow;
  final TableCacheGetter<R, D> getCache;

  TableInfo(this.tableName, this.select, this.mapRow, this.getCache);
}

/// SQL snippet (used to distinguish raw sql from variables).
class Sql {
  final String statement;
  Sql(this.statement);
  String toString() => statement;
}

/// Session state
class SessionState<D> {
  final Connection conn;
  final D data;

  SessionState(this.conn, this.data);

  Future<List<R>> run<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return _runMappedQuery<R, D>(
        this, true, table, SQL(_collapse(s1, s2, s3, s4, s5)));
  }

  Future<R> insert<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await _runMappedQuery<R, D>(
            this, true, table, INSERT(table, s1, s2, s3, s4, s5)))
        .single;
  }

  Future<List<R>> select<R extends Record>(TableInfo<R, D> table,
      [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) {
    return _runMappedQuery<R, D>(
        this, true, table, SELECT(table, s1, s2, s3, s4, s5));
  }

  Future<R> selectOne<R extends Record>(TableInfo<R, D> table,
      [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await select(table, s1, s2, s3, s4, s5)).single;
  }

  Future<List<int>> selectIds<R extends Record>(TableInfo<R, D> table,
      [Sql s1, Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await select(table, s1, s2, s3, s4, s5))
        .map((row) => row.id)
        .toList();
  }

  /// Select records by their 'id' field.
  Future<List<R>> selectByIds<R extends Record>(
      TableInfo<R, D> table, Iterable<int> ids) async {
    /// Retrieve all records that are already loaded.
    final records = new List<R>();
    final cache = table.getCache(data);
    final nonCachedIds = new List<int>();
    ids.forEach((id) {
      // Skip null values. This way null values do not have to be filtered out
      // by client code.
      if (id != null) {
        final record = cache[id];
        if (record != null) {
          records.add(record);
        } else {
          nonCachedIds.add(id);
        }
      }
    });

    if (nonCachedIds.isNotEmpty) {
      final selectedRecords = await _runMappedQuery<R, D>(
          this, true, table, SELECT(table, WHERE({'id': IN(nonCachedIds)})));
      records.addAll(selectedRecords);
    }

    return records;
  }

  Future<R> selectById<R extends Record>(TableInfo<R, D> table, int id) async {
    return (await selectByIds(table, [id])).single;
  }

  Future<bool> exists<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await select(table, s1, s2, s3, s4, s5)).isNotEmpty;
  }

  Future<List<R>> update<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) {
    return _runMappedQuery<R, D>(
        this, true, table, UPDATE(table, s1, s2, s3, s4, s5));
  }

  Future<R> updateOne<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await update(table, s1, s2, s3, s4, s5)).single;
  }

  Future<List<R>> delete<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) {
    return _runMappedQuery<R, D>(
        this, true, table, DELETE(table, s1, s2, s3, s4, s5));
  }

  Future<R> deleteOne<R extends Record>(TableInfo<R, D> table, Sql s1,
      [Sql s2, Sql s3, Sql s4, Sql s5]) async {
    return (await delete(table, s1, s2, s3, s4, s5)).single;
  }
}

Future<List<R>> _runMappedQuery<R extends Record, D>(
    SessionState s, bool store, TableInfo<R, D> table, Sql sql) async {
  log.info(sql.statement);
  final result = await s.conn.query(sql.statement).map(table.mapRow).toList();
  if (store) {
    result.forEach((record) => table.getCache(s.data)[record.id] = record);
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

List<String> _encodeValues(Iterable values, TypeConverter converter) {
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

// ignore: non_constant_identifier_names
Sql DELETE(TableInfo table, Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL(
      'DELETE FROM ${table.tableName} $statements RETURNING ${table.select}');
}

/// This code is shared between [WHERE] and [SET].
Sql _flatten(String prefix, Map<String, dynamic> map, String keyValueSeparator,
    String itemSeparator) {
  final converter = new TypeConverter();
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
    final converter = new TypeConverter();
    return SQL('= ${converter.encode(value, null)}');
  }
}

// ignore: non_constant_identifier_names
Sql IS_NOT(dynamic value) {
  if (value is Sql) {
    return SQL('!= $value');
  } else {
    final converter = new TypeConverter();
    return SQL('!= ${converter.encode(value, null)}');
  }
}

// ignore: non_constant_identifier_names
Sql CONTAINS(dynamic value) {
  if (value is Sql) {
    return SQL('@> $value');
  } else {
    final converter = new TypeConverter();
    return SQL('@> ${converter.encode(value, null)}');
  }
}

// ignore: non_constant_identifier_names
Sql IN(dynamic values) {
  if (values is Sql) {
    return SQL('IN $values');
  } else if (values is Iterable) {
    final encoded = _encodeValues(values, new TypeConverter());
    return SQL('IN (${encoded.join(',')})');
  } else {
    throw new ArgumentError('values must be Sql or Iterable');
  }
}

// ignore: non_constant_identifier_names
Sql IN_IDS(List<Record> rows) {
  final ids = rows.map((row) => row.id).toList();
  return SQL('IN (${ids.join(',')})');
}

// ignore: non_constant_identifier_names
Sql VALUES(Map<String, dynamic> values) {
  final encoded = _encodeValues(values.values, new TypeConverter());
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
  final encodedArgs = _encodeValues(args, new TypeConverter());

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
  final encoded = _encodeValues(values, new TypeConverter());
  return SQL('ARRAY[${encoded.join(',')}]' + (type == null ? '' : '::$type[]'));
}

// ignore: non_constant_identifier_names
Sql WITH_RECURSIVE(Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL('WITH RECURSIVE $statements');
}

// ignore: non_constant_identifier_names
Sql AS(Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL('AS ($statements)');
}

// ignore: non_constant_identifier_names
Sql UNION_ALL(Sql s1, [Sql s2, Sql s3, Sql s4, Sql s5]) {
  final statements = _collapse(s1, s2, s3, s4, s5);
  return SQL('UNION ALL $statements');
}

// Extension functions

// ignore: non_constant_identifier_names
Sql DECODE(dynamic data, String type) {
  return FUNCTION('decode', data, type);
}

// ignore: non_constant_identifier_names
Sql DIGEST(dynamic data, String type) {
  return FUNCTION('digest', data, type);
}
