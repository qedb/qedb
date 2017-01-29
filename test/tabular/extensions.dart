// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg.test.tabular;

class IsEmptyExtension extends Extension {
  @override
  bool processParams(columns, row, params) {
    final value = processValueExtension(columns, row, params);
    return value == null || value is String && value.isEmpty;
  }
}

class PKeyExtension extends Extension {
  final pkeys = new Map<String, int>();

  @override
  dynamic processParams(columns, row, params) {
    if (params.first == 'next') {
      pkeys.putIfAbsent(params[1], () => 0);
      return ++pkeys[params[1]];
    } else {
      return 0;
    }
  }
}

class ColumnExtension extends Extension {
  @override
  dynamic processParams(columns, row, params) {
    var columnName = params.first;
    if (columnName.startsWith('[]')) {
      columnName = columnName.substring('[]'.length);
      final index = columns.indexOf(columnName);
      if (index < row.length) {
        final String value = row[index];
        return value.isEmpty
            ? []
            : processValue(columns, row, value.split(','));
      } else {
        throw new Exception('column "$columnName" not found');
      }
    } else {
      final index = columns.indexOf(columnName);
      if (index != -1 && index < row.length) {
        return processValue(columns, row, row[index]);
      } else {
        throw new Exception('column "$columnName" not found');
      }
    }
  }
}

class EqlibExtension extends Extension {
  final map = new Map<String, int>();
  final index = new List<Expr>();

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
  dynamic processParams(columns, row, params) {
    final subcommand = params.first;
    final input = params.length == 2
        ? params[1]
        : processValueExtension(columns, row, params.sublist(1));
    if (input.isEmpty) {
      print(params);
      print(columns);
      print(row);
    }

    if (input is String) {
      // Parse expression.
      final expr = new Expr.parse(input, (String name, [bool generic = false]) {
        if (map.containsKey(name)) {
          return map[name];
        } else {
          throw new Exception('expression contains unknown name: $name');
        }
      });

      if (subcommand == 'codec') {
        // Return Base64 encoded value.
        return expr.toBase64();
      } else if (subcommand == 'index') {
        // Get index for this expression.
        return getExpressionIndex(expr) + 1;
      } else {
        throw new UnsupportedError('subcommand $subcommand not supported');
      }
    } else {
      throw new Exception('could not resolve eqlib extension input to string');
    }
  }

  /// Return index of given expression in [index] (0 indexed).
  int getExpressionIndex(Expr expr) {
    // Try to find expression.
    final idx = index.indexOf(expr);
    if (idx != -1) {
      return idx;
    } else if (expr is FunctionExpr) {
      // First store all child expressions.
      for (final arg in expr.args) {
        getExpressionIndex(arg);
      }
    }

    // Strore expression and return index.
    index.add(expr);
    return index.length - 1;
  }
}
