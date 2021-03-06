// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

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
