// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.OperatorRow> createOperator(Session s, OperatorResource body) {
  return s.insert(
      db.operator,
      VALUES({
        'function_id': body.function.id,
        'precedence_level': body.precedenceLevel,
        'associativity': body.associativity,
        'operator_type': body.operatorType,
        'character': body.character,
        'editor_template': body.editorTemplate
      }));
}

Future<List<db.OperatorRow>> listOperators(Session s) {
  return s.select(db.operator);
}

Future<Map<String, int>> _loadComputableFunctions(Session s) async {
  // Get computable functions via operator tables.
  // (it is reasonable to assume +-*~ are the operator characters)
  final operators =
      await s.select(db.operator, WHERE({'character': IN('+-*~'.split(''))}));
  return new Map<String, int>.fromIterable(operators,
      key: (db.OperatorRow row) => row.character,
      value: (db.OperatorRow row) => row.id);
}

/// Compute function based on [computable] from [_loadComputableFunctions].
num _exprCompute(int id, List<num> args, Map<String, int> computable) {
  // Only do operations that given two integers will always return an integer.
  if (id == computable['+']) {
    return args[0] + args[1];
  } else if (id == computable['-']) {
    return args[0] - args[1];
  } else if (id == computable['*']) {
    return args[0] * args[1];
  } else if (id == computable['~']) {
    return -args[0];
  } else {
    return double.NAN;
  }
}
