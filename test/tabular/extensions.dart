// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg.test.tabular;

class ColumnExtension extends Extension {
  @override
  dynamic processValue(columns, row, params) {
    var columnName = params.first;
    if (columnName.startsWith('[]')) {
      columnName = columnName.substring('[]'.length);
      final index = columns.indexOf(columnName);
      if (index < row.length) {
        final String value = row[index];
        return value.isEmpty
            ? []
            : globalProcessValue(columns, row, value.split(','));
      } else {
        throw new Exception('column "$columnName" not found');
      }
    } else {
      final index = columns.indexOf(columnName);
      if (index != -1 && index < row.length) {
        return globalProcessValue(columns, row, row[index]);
      } else {
        throw new Exception('column "$columnName" not found');
      }
    }
  }
}

class EqlibCodecExtension extends Extension {
  final map = new Map<String, int>();

  @override
  void processTable(table, configuration) {
    // Get column names.
    final idColumn = configuration['idColumn'];
    final aliasColumn = configuration['aliasColumn'];

    // Get column indices (unsafe).
    final idIdx = table.first.indexOf(idColumn);
    final aliasIdx = table.first.indexOf(aliasColumn);

    // Store data in class state.
    for (final row in table.sublist(1)) {
      map[row[aliasIdx]] = row[idIdx];
    }
  }

  @override
  dynamic processValue(columns, row, params) {
    // If params.length > 1, do another pass through processValueExtension.
    // This allows usage of the column extension in the eqlibCodec extension.
    final str = params.length == 1
        ? params.first
        : processValueExtension(columns, row, params);

    if (str is String) {
      final expr = new Expr.parse(str, (String name, [bool generic = false]) {
        if (map.containsKey(name)) {
          return map[name];
        } else {
          throw new Exception('expression contains unknown name: $name');
        }
      });

      // Return Base64 encoded value.
      return expr.toBase64();
    } else {
      throw new Exception('could not resolve eqlibCodec input to string');
    }
  }
}
