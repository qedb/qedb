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
ValueResolver column(String column) => (row) => row.getColumn(column);

/// Split into a list of integers.
ValueResolver intlist(ValueResolver input) => (row) {
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

/// Primary key emulator.
class PrimaryKeyEmulator {
  final db = new Map<String, List<int>>();

  ValueResolver get(String table, dynamic value) => (row) {
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

  ValueResolver contains(String table, dynamic value) => (row) {
        // Get hash code for targeted record.
        final recordHashCode =
            value is ValueResolver ? value(row).hashCode : value.hashCode;
        return db.containsKey(table)
            ? db[table].contains(recordHashCode)
            : false;
      };
}
