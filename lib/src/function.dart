// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateFunction {
  @ApiProperty(required: true)
  int categoryId;

  @ApiProperty(required: true)
  int argumentCount;

  @ApiProperty(required: true)
  String latexTemplate;

  @ApiProperty(required: true)
  bool generic;

  @ApiProperty(required: false)
  CreateTranslation name;

  @ApiProperty(required: false)
  OperatorConfigurationInput asOperator;
}

class OperatorConfigurationInput {
  @ApiProperty(required: true)
  int precedenceLevel;

  @ApiProperty(required: true)
  String associativity;
}

Future<table.Function> _createFunction(Session s, CreateFunction body) async {
  final function = await functionHelper.insert(s, {
    'category_id': body.categoryId,
    'argument_count': body.argumentCount,
    'latex_template': body.latexTemplate,
    'generic': body.generic
  });

  // If this is an operator, insert the operator configuration.
  if (body.asOperator != null) {
    await operatorConfigurationHelper.insert(s, {
      'function_id': function.id,
      'precedence_level': body.asOperator.precedenceLevel,
      'associativity': body.asOperator.associativity
    });
  }

  return function;
}
