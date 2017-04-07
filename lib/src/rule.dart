// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.RuleRow> createRule(Session s, int categoryId, int leftExpressionId,
    int rightExpressionId, Expr left, Expr right) async {
  return await s.insert(
      db.rule,
      VALUES({
        'category_id': categoryId,
        'left_expression_id': leftExpressionId,
        'right_expression_id': rightExpressionId,
        'left_array_data': ARRAY(left.toArray(), 'integer'),
        'right_array_data': ARRAY(right.toArray(), 'integer')
      }));
}

Future<List<db.RuleRow>> listRules(Session s, [List<int> ids]) async {
  final rules =
      await s.select(db.rule, ids == null ? null : WHERE({'id': IN(ids)}));

  // Select left and right expressions.
  final expressionIds = rules.map((row) => row.leftExpressionId).toList()
    ..addAll(rules.map((row) => row.rightExpressionId));
  await listExpressions(s, expressionIds);

  return rules;
}
