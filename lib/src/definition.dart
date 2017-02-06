// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateDefinition {
  @ApiProperty(required: true)
  int categoryId;

  @ApiProperty(required: true)
  String left;

  @ApiProperty(required: true)
  String right;
}

String queryIntersectFunctionIds(List<int> functionIds) => '''
SELECT id FROM function WHERE category_id IN (
  SELECT unnest(array_append(parents, id))
  FROM category WHERE id = @categoryId)
INTERSECT
SELECT id FROM function WHERE id IN (${functionIds.join(',')})''';

Future<db.DefinitionTable> _createDefinition(
    Session s, CreateDefinition body) async {
  // Decode expression headers.
  final leftData = _decodeCodecHeader(body.left);
  final rightData = _decodeCodecHeader(body.right);

  // For now we only accept single byte signed integers in non-evaluated
  // expressions.
  if (leftData.float64Count > 0) {
    throw new BadRequestError('rejected left expression')
      ..errors.add(new RpcErrorDetail(
          reason: 'left expression contains floating point numbers'));
  } else if (rightData.float64Count > 0) {
    throw new BadRequestError('rejected right expression')
      ..errors.add(new RpcErrorDetail(
          reason: 'right expression contains floating point numbers'));
  }

  // Retrieve all function IDs that are defined under this category.
  final allIds = leftData.functionId.toSet()..addAll(rightData.functionId);
  final intersectResult = await s.conn.query(
      queryIntersectFunctionIds(allIds.toList()),
      {'categoryId': body.categoryId}).toList();

  // Validate if all functions are defined in the context category.
  if (intersectResult.length != allIds.length) {
    final missing = allIds.difference(intersectResult.toSet());
    throw new UnprocessableEntityError(
        'given category does not contain some functions: $missing');
  }

  // Decode expressions.
  final leftDecoded = exprCodecDecode(leftData);
  final rightDecoded = exprCodecDecode(rightData);

  log.info('Definition decoded as $leftDecoded = $rightDecoded');

  // Insert expressions.
  final leftExpr = await _createExpression(s, leftDecoded);
  final rightExpr = await _createExpression(s, rightDecoded);

  // Insert rule.
  final rule = await _createRule(s, body.categoryId, leftExpr.id, rightExpr.id);

  // Insert definition.
  return await definitionHelper.insert(s, {'rule_id': rule.id});
}
