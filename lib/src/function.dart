// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.FunctionRow> createFunction(Session s, FunctionResource body) async {
  // Non-generic functions with >0 arguments must have a name (soft constraint).
  if (!body.generic && body.argumentCount > 0 && body.descriptor == null) {
    throw new UnprocessableEntityError(
        'non-generic functions with >0 arguments must have a descriptor');
  }

  // Insert function.
  final insertParameters = {
    'category_id': body.category.id,
    'argument_count': body.argumentCount,
    'latex_template': body.latexTemplate,
    'generic': body.generic
  };

  // If a name is specified, add it to the insert parameters.
  if (body.descriptor != null) {
    // Use ID if provided.
    if (body.descriptor.id != null) {
      insertParameters['descriptor_id'] = body.descriptor.id;
    } else {
      // Create descriptor.
      insertParameters['descriptor_id'] =
          (await createDescriptor(s, body.descriptor)).id;
    }
  }

  return await functionHelper.insert(s, insertParameters);
}

Future<db.OperatorRow> createOperator(Session s, OperatorResource body) {
  return operatorHelper.insert(s, {
    'function_id': body.function.id,
    'precedence_level': body.precedenceLevel,
    'associativity': body.associativity
  });
}
