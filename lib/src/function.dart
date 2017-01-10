// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertFunction = '''
INSERT INTO function
VALUES (DEFAULT, @categoryId:int4, @generic:bool, @latexTemplate:text,
  @useParentheses:bool, @precedenceLevel:int2, @evaluationType)
RETURNING *
''';

Future<table.Function> _createFunction(DbPool db, CreateFunction input) async {
  final result = await db.query(sqlInsertFunction, {
    'categoryId': input.categoryId,
    'generic': input.generic,
    'latexTemplate': input.latexTemplate,
    'useParentheses': input.useParentheses,
    'precedenceLevel': input.precedenceLevel,
    'evaluationType': input.evaluationType
  });

  // TODO: process labels and tags.

  return new table.Function.from(result.first);
}

class CreateFunction {
  int categoryId;
  bool generic;
  String latexTemplate;
  bool useParentheses;
  int precedenceLevel;
  String evaluationType;
  List<String> labels;
  List<String> tags;
}
