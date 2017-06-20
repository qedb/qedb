// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.test.csvtest;

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

/// If not empty, include A, else include B.
ValueResolver ifNeElse(String condCol, dynamic value, dynamic fallback) =>
    includeIf(not(empty(col(condCol))), value, fallback);

/// Primary key emulator.
class PrimaryKeyEmulator {
  final db = new Map<String, List<int>>();

  ValueResolver<int> get(String table, dynamic value, [dynamic mixWith]) =>
      (row) {
        // Get hash code for targeted record.
        var recordHashCode =
            value is ValueResolver ? value(row).hashCode : value.hashCode;

        // Mix with [mixWith] if specified.
        if (mixWith != null) {
          final mixWithHashCode = mixWith is ValueResolver
              ? mixWith(row).hashCode
              : mixWith.hashCode;
          recordHashCode = hashCode2(recordHashCode, mixWithHashCode);
        }

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
}

/// In-memory function database and expression parser.
class EqlibHelper {
  final map = new Map<String, int>();
  final operators = new OperatorConfig(0);

  Future<Null> loadKeywords(String csvPath,
      {String id,
      String keyword,
      String precedenceLevel,
      String associativity,
      String character,
      String type}) async {
    // Load CSV file.
    final table = const CsvToListConverter(eol: '\n')
        .convert(await new File(csvPath).readAsString());
    final columns = new List<String>.from(table.first);

    for (var i = 1; i < table.length; i++) {
      final row = new Row(columns, table[i]);
      final idValue = row.getColumn(id);
      map[row.getColumn(keyword)] = idValue;

      if (row.hasColumn(precedenceLevel)) {
        final typeValue = row.getColumn(type);
        final String operatorCharacter = row.getColumn(character);
        operators.add(new Operator(
            idValue,
            row.getColumn(precedenceLevel),
            row.getColumn(associativity) == 'ltr'
                ? Associativity.ltr
                : Associativity.rtl,
            operatorCharacter.runes.first,
            typeValue == 'infix'
                ? OperatorType.infix
                : typeValue == 'prefix'
                    ? OperatorType.prefix
                    : OperatorType.postfix));
      }
    }

    // Add default setting for implicit multiplication.
    operators.add(new Operator(operators.implicitMultiplyId, 3,
        Associativity.rtl, -1, OperatorType.infix));
  }

  Expr _parse(ValueResolver<String> input, Row row) {
    final str = input(row);
    final expr =
        parseExpression(str, operators, (String keyword, bool generic) {
      if (map.containsKey(keyword)) {
        return map[keyword];
      } else {
        throw new Exception('expression contains unknown keyword: $keyword');
      }
    });
    return expr;
  }

  ValueResolver<String> data(ValueResolver<String> expression) =>
      (row) => BASE64.encode(_parse(expression, row).toBinary().asUint8List());

  ValueResolver<String> hash(ValueResolver<String> expression) =>
      (row) => BASE64.encode(sha256
          .convert(_parse(expression, row).toBinary().asUint8List())
          .bytes);

  ValueResolver functionIds(ValueResolver<String> expression) =>
      (row) => _parse(expression, row).functionIds;

  ValueResolver arrayData(ValueResolver<String> expression) =>
      (row) => _parse(expression, row).toArray();
}
