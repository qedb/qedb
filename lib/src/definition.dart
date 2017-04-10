// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

/// Used to determine if an expression is valid under the given category.
String queryIntersectFunctionIds(List<int> functionIds) => '''
SELECT id, argument_count FROM function WHERE category_id IN (
  SELECT unnest(array_append(parents, id))
  FROM category WHERE id = @categoryId)
INTERSECT
SELECT id, argument_count FROM function WHERE id IN (${functionIds.join(',')})''';

Future<db.DefinitionRow> createDefinition(
    Session s, DefinitionResource body) async {
  // Decode expression headers.
  final leftData = _decodeCodecHeader(body.rule.leftExpression.data);
  final rightData = _decodeCodecHeader(body.rule.rightExpression.data);

  // Retrieve all function IDs that are defined under this category.
  final allIds = leftData.functionIds.toSet()..addAll(rightData.functionIds);
  // INTERSECT result
  final intres = await s.conn.query(queryIntersectFunctionIds(allIds.toList()),
      {'categoryId': body.rule.category.id}).toList();

  // Process INTERSECT result into a map.
  final intmap = new Map<int, int>.fromIterable(intres,
      key: (row) => row[0], value: (row) => row[1]);

  // Validate if all functions are defined in the context category.
  if (intres.length != allIds.length) {
    final missing = allIds.difference(intmap.keys.toSet());
    throw new UnprocessableEntityError(
        'given category does not contain some functions: $missing');
  }

  // Decode expressions.
  final leftDecoded = exprCodecDecode(leftData);
  final rightDecoded = exprCodecDecode(rightData);

  // Insert expressions.
  final leftExpr = await _createExpression(s, leftDecoded);
  final rightExpr = await _createExpression(s, rightDecoded);

  // Insert rule.
  final rule = await createRule(s, body.rule.category.id, leftExpr.id,
      rightExpr.id, leftDecoded, rightDecoded);

  // Insert definition.
  return await s.insert(db.definition, VALUES({'rule_id': rule.id}));
}

Future<List<db.DefinitionRow>> listDefinitions(Session s) async {
  final definitions = await s.select(db.definition);
  await listRules(s, definitions.map((row) => row.ruleId).toList());
  return definitions;
}
