// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.OperatorRow> createOperator(Session s, OperatorResource body) {
  return operatorHelper.insert(s, {
    'function_id': body.function.id,
    'precedence_level': body.precedenceLevel,
    'associativity': body.associativity,
    'unicode_character': body.unicodeCharacter,
    'latex_command': body.latexCommand
  });
}
