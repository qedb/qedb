// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.RuleRow> createRule(Session s, RuleResource body) async {
  // Decode expression headers.
  final leftData = _decodeCodecHeader(body.leftExpression.data);
  final rightData = _decodeCodecHeader(body.rightExpression.data);

  // Decode expressions.
  final leftDecoded = exprCodecDecode(leftData);
  final rightDecoded = exprCodecDecode(rightData);

  // Insert expressions.
  final leftExpr = await _createExpression(s, leftDecoded);
  final rightExpr = await _createExpression(s, rightDecoded);

  return await s.insert(
      db.rule,
      VALUES({
        'left_expression_id': leftExpr.id,
        'right_expression_id': rightExpr.id,
        'left_array_data': ARRAY(leftDecoded.toArray(), 'integer'),
        'right_array_data': ARRAY(rightDecoded.toArray(), 'integer')
      }));
}

Future<List<db.RuleRow>> listRules(Session s, [Iterable<int> ids]) async {
  final rules =
      await (ids == null ? s.select(db.rule) : s.selectByIds(db.rule, ids));

  // Select left and right expressions.
  final expressionIds = new List<int>();
  rules.forEach((rule) {
    expressionIds.add(rule.leftExpressionId);
    expressionIds.add(rule.rightExpressionId);
  });
  await listExpressions(s, expressionIds);

  return rules;
}
