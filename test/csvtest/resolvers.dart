// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg.test.csvtest;

/// Value resolver that always resolves to true.
bool resolveTrue(_) => true;

/// Value resolver that always resolves to false.
bool resolveFalse(_) => false;

/// Resolves to true if the given value is empty.
ValueResolver empty(ValueResolver value) => (row) {
      final v = value(row);
      return v == null || (v is String && v.isEmpty);
    };

/// Inverting value resolver.
ValueResolver not(ValueResolver value) => (row) => value(row) == false;

/// Or condition with two value resolvers.
ValueResolver or(ValueResolver a, ValueResolver b) =>
    (row) => a(row) == true || b(row) == true;

/// Resolve to a specific column in a row.
ValueResolver<T> col<T>(String column) => (row) => row.getColumn(column);

/// Split into a list of integers.
ValueResolver<List<int>> intlist(ValueResolver input) => (row) {
      final value = input(row);
      if (value is String) {
        if (value.trim().isEmpty) {
          return [];
        }

        // Parse list by splitting.
        final list = value.split(',');
        return new List<int>.generate(
            list.length, (i) => int.parse(list[i].trim()));
      } else if (value is int) {
        return [value];
      } else {
        throw new Exception('cannot call intlist() on ${value.runtimeType}');
      }
    };

/// If not empty
///
/// Alias for includeIf(not(empty(column([condCol]))), [value]).
ValueResolver ifNe(String condCol, dynamic value) =>
    includeIf(not(empty(col(condCol))), value);

/// If not a OR b
///
/// Alias for includeIf(not(or([condA], [condB])), [value]).
ValueResolver ifNor(ValueResolver condA, ValueResolver condB, dynamic value) =>
    includeIf(not(or(condA, condB)), value);

/// Primary key emulator.
class PrimaryKeyEmulator {
  final db = new Map<String, List<int>>();

  ValueResolver<int> get(String table, dynamic value) => (row) {
        // Get hash code for targeted record.
        final recordHashCode =
            value is ValueResolver ? value(row).hashCode : value.hashCode;

        // Make sure table exists.
        db.putIfAbsent(table, () => new List<int>());

        // Lookup hash code.
        final idx = db[table].indexOf(recordHashCode);
        if (idx != -1) {
          return idx + 1;
        } else {
          db[table].add(recordHashCode);
          return db[table].length;
        }
      };

  ValueResolver<bool> contains(String table, dynamic value) => (row) {
        // Get hash code for targeted record.
        final recordHashCode =
            value is ValueResolver ? value(row).hashCode : value.hashCode;
        return db.containsKey(table)
            ? db[table].contains(recordHashCode)
            : false;
      };
}

/// In-memory function database and expression parser.
class EqlibHelper {
  final map = new Map<String, int>();

  Future<Null> loadKeywords(
      String csvPath, String idColumn, String keywordsColumn) async {
    // Load CSV file.
    final table = const CsvToListConverter(eol: '\n')
        .convert(await new File(csvPath).readAsString());
    final columns = new List<String>.from(table.first);

    for (var i = 1; i < table.length; i++) {
      final row = new Row(columns, table[i]);
      map[row.getColumn(keywordsColumn)] = row.getColumn(idColumn);
    }
  }

  ExprCodecData _encode(ValueResolver<String> input, Row row) {
    final str = input(row);
    final expr = new Expr.parse(str, (String keyword, [bool generic = false]) {
      if (map.containsKey(keyword)) {
        return map[keyword];
      } else {
        throw new Exception('expression contains unknown keyword: $keyword');
      }
    });
    return exprCodecEncode(expr);
  }

  ValueResolver<String> data(ValueResolver<String> expression) => (row) =>
      BASE64.encode(_encode(expression, row).writeToBuffer().asUint8List());

  ValueResolver<String> hash(ValueResolver<String> expression) =>
      (row) => BASE64.encode(sha256
          .convert(_encode(expression, row).writeToBuffer().asUint8List())
          .bytes);

  ValueResolver functionIds(ValueResolver<String> expression) =>
      (row) => _encode(expression, row).functionId;
}
