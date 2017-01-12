// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertFunction = '''
INSERT INTO function
VALUES (DEFAULT, @categoryId:int4, @generic:bool,
  @latexTemplate:text, @useParentheses:bool)
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
      'generic': input.generic,
      'latexTemplate': input.latexTemplate,
      'useParentheses': input.useParentheses
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

    // Insert labels and tags.
    await _addFunctionDescriptor(db, function.id, 'label', input.labels);
    await _addFunctionDescriptor(db, function.id, 'tag', input.tags);

    completer.complete(function);
  }).catchError(completer.completeError);

  return completer.future;
}

Future<List<table.Descriptor>> _addFunctionDescriptor(
    PostgreSQLExecutionContext db,
    int functionId,
    String type,
    List<String> names) async {
  // Select existing descriptors.
  final result = await db.query(
      'SELECT * FROM descriptor WHERE type = @type AND name IN (@names)',
      substitutionValues: {'type': type, 'names': names.join(',')});

  // Parse result.
  final descriptors = new List<table.Descriptor>.generate(
      result.length, (i) => new table.Descriptor.from(result[i]));

  // Remove all names that are already found.
  for (final descriptor in descriptors) {
    names.remove(descriptor.name);
  }

  // Insert remaining descriptors.
  // Note that batch queries are not a concern here.
  for (final name in names) {
    final result = await db.query(
        'INSERT INTO descriptor VALUES (DEFAULT, @name:text, @type) RETURNING *',
        substitutionValues: {'name': name, 'type': type});
    descriptors.add(new table.Descriptor.from(result.first));
  }

  // Link descriptors to function.
  for (final descriptor in descriptors) {
    await db.query(
        'INSERT INTO function_descriptor VALUES (DEFAULT, @functionId:int4, @descriptorId:int4)',
        substitutionValues: {
          'functionId': functionId,
          'descriptorId': descriptor.id
        });
  }

  return descriptors;
}

class CreateFunction {
  int categoryId;
  bool generic;
  String latexTemplate;
  bool useParentheses;
  OperatorConfiguration asOperator;
  List<String> labels;
  List<String> tags;
}

class OperatorConfiguration {
  int precedenceLevel;
  String evaluationType;
}
