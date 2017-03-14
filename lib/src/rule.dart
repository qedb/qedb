// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.RuleRow> _createRule(Session s, int categoryId, int leftExpressionId,
    int rightExpressionId) async {
  return await ruleHelper.insert(s, {
    'category_id': categoryId,
    'left_expression_id': leftExpressionId,
    'right_expression_id': rightExpressionId
  });
}
