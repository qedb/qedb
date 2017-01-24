// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<table.Function> _createFunction(
    Connection db, CreateFunction input) async {
  // Insert new function.
  const queryInsertFunction = '''
INSERT INTO function (category_id, argument_count, latex_template, generic)
VALUES (@categoryId, @argumentCount, @latexTemplate, @generic)
RETURNING *''';
  final function = await db
      .query(queryInsertFunction, {
        'categoryId': input.categoryId,
        'argumentCount': input.argumentCount,
        'latexTemplate': input.latexTemplate,
        'generic': input.generic
      })
      .map(table.Function.map)
      .single;

  // If this is an operator, insert the operator configuration.
  const queryInsertOperator = '''
INSERT INTO operator_configuration
VALUES (DEFAULT, @functionId, @precedenceLevel, @evaluationType)
RETURNING *''';
  if (input.asOperator != null) {
    await db.query(queryInsertOperator, {
      'functionId': function.id,
      'precedenceLevel': input.asOperator.precedenceLevel,
      'evaluationType': input.asOperator.evaluationType
    }).toList();
  }

  return function;
}

class CreateFunction {
  int categoryId;
  int argumentCount;
  String latexTemplate;
  bool generic;
  OperatorConfiguration asOperator;
}

class OperatorConfiguration {
  int precedenceLevel;
  String evaluationType;
}
