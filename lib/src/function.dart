// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertFunction = '''
INSERT INTO function (category_id, argument_count, latex_template, generic)
VALUES (@categoryId:int4, @argumentCount:int2, @latexTemplate:text, @generic:bool)
RETURNING *
''';

const sqlInsertOperatorConfig = '''
INSERT INTO operator_configuration
VALUES (DEFAULT, @functionId:int4, @precedenceLevel:int2, @evaluationType)
RETURNING *
''';

Future<table.Function> _createFunction(DbPool db, CreateFunction input) async {
  final completer = new Completer<table.Function>();

  db.transaction((db) async {
    // Insert new function.
    final result = await db.query(sqlInsertFunction, substitutionValues: {
      'categoryId': input.categoryId,
      'argumentCount': input.argumentCount,
      'latexTemplate': input.latexTemplate,
      'generic': input.generic
    });
    final function = new table.Function.from(result.first);

    // If this is an operator, insert the operator configuration.
    if (input.asOperator != null) {
      // If the query fails this should throw an error.
      await db.query(sqlInsertOperatorConfig, substitutionValues: {
        'functionId': function.id,
        'precedenceLevel': input.asOperator.precedenceLevel,
        'evaluationType': input.asOperator.evaluationType
      });
    }

    completer.complete(function);
  }).catchError(completer.completeError);

  return completer.future;
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
