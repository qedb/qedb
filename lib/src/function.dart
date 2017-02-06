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
  CreateOperator operator;
}

class CreateOperator {
  @ApiProperty(required: true)
  int precedenceLevel;

  @ApiProperty(required: true)
  String associativity;
}

Future<db.FunctionTable> _createFunction(Session s, CreateFunction body) async {
  // Non-generic functions with >0 arguments must have a name (soft constraint).
  if (!body.generic && body.argumentCount > 0 && body.name == null) {
    throw new UnprocessableEntityError(
        'non-generic functions with >0 arguments must have a name');
  }

  // Insert function.
  final insertParameters = {
    'category_id': body.categoryId,
    'argument_count': body.argumentCount,
    'latex_template': body.latexTemplate,
    'generic': body.generic
  };

  // If a name is specified, add it to the insert parameters.
  if (body.name != null) {
    // First check if descriptor exists.
    final result = await translationHelper.selectCustom(
        s,
        '''
SELECT * FROM translation
WHERE content = @content AND locale_id = (
  SELECT id FROM locale WHERE code = @locale)''',
        {'content': body.name.content, 'locale': body.name.locale});

    if (result.isNotEmpty) {
      final descriptorId = result.single.descriptorId;

      // Give custom error when there a function exists that uses this as name.
      if (await functionHelper.exists(s, {'descriptor_id': descriptorId})) {
        throw new UnprocessableEntityError(
            'the specified name is already used by another function');
      }

      insertParameters['descriptor_id'] = descriptorId;
    } else {
      insertParameters['descriptor_id'] = (await _createDescriptor(
              s, new CreateDescriptor.fromTranslations([body.name])))
          .id;
    }
  }

  final function = await functionHelper.insert(s, insertParameters);

  // If this is an operator, insert the operator.
  if (body.operator != null) {
    await operatorHelper.insert(s, {
      'function_id': function.id,
      'precedence_level': body.operator.precedenceLevel,
      'associativity': body.operator.associativity
    });
  }

  return function;
}
