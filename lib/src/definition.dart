// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

String sqlIntersectFunctions(List<int> functionIds) => '''
SELECT id FROM function WHERE category_id IN (
  SELECT unnest(array_append(parents, id))
  FROM category WHERE id = @categoryId:int4)
INTERSECT
SELECT id FROM function WHERE id IN (${functionIds.join(',')})''';

Future<table.Definition> _createDefinition(
    DbPool db, CreateDefinition input) async {
  // Decode expression headers.
  final leftData = _decodeCodecHeader(input.left);
  final rightData = _decodeCodecHeader(input.right);

  // For now we only accept single byte signed integers in non-evaluated
  // expressions.
  if (leftData.float64Count > 0 || rightData.float64Count > 0) {
    throw new RpcError(400, 'reject_expr', 'contains float64');
  }

  final completer = new Completer<table.Definition>();

  db.transaction((db) async {
    // Retrieve all function IDs that are defined under this category.
    final allIds = leftData.functionId.toSet()..addAll(rightData.functionId);
    final intersectResult = await db.query(
        sqlIntersectFunctions(allIds.toList()),
        substitutionValues: {'categoryId': input.categoryId});

    // Validate if all functions are defined in the context category.
    if (intersectResult.length != allIds.length) {
      log.info(
          'Definition function ID intersection result: $intersectResult (input: $allIds)');
      throw new RpcError(400, 'reject_expr', 'not all functions are known');
    }

    // Decode and insert expressions.
    final leftDecoded = exprCodecDecode(leftData);
    final rightDecoded = exprCodecDecode(rightData);
    log.info('Definition decoded as $leftDecoded = $rightDecoded');
    final leftExpr = await _createExpression(db, leftDecoded);
    final rightExpr = await _createExpression(db, rightDecoded);

    // Insert rule.
    final rule = await _createRule(db, leftExpr.id, rightExpr.id);

    // Insert definition.
    final insertResult = await db.query(
        'INSERT INTO definition VALUES (DEFAULT, @ruleId:int4) RETURNING *',
        substitutionValues: {'ruleId': rule.id});
    completer.complete(new table.Definition.from(insertResult));
  }).catchError(completer.completeError);

  return completer.future;
}

class CreateDefinition {
  int categoryId;
  String left, right;
}
