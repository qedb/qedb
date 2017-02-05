// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg.test.csvtest;

/// Value resolver that always resolves to false.
bool resolveFalse(_) => false;

/// Resolve to a specific column in a row.
ValueResolver column(String column) => (row) => row.getColumn(column);

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
}
