// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

/// Create unchecked condition.
/// With no direct reason, we choose not to evaluate conditions.
Future<db.ConditionRow> _createCondition(Session s, Rule condition) async {
  // Insert expressions.
  final leftRow = await _createExpression(s, condition.left);
  final rightRow = await _createExpression(s, condition.right);

  // Check if condition exists, in this case return that condition.
  final matchingConditions = await s.select(
      db.condition,
      WHERE({
        'left_expression_id': IS(leftRow.id),
        'right_expression_id': IS(rightRow.id)
      }));
  if (matchingConditions.isNotEmpty) {
    return matchingConditions.single;
  } else {
    return s.insert(
        db.condition,
        VALUES({
          'left_expression_id': leftRow.id,
          'right_expression_id': rightRow.id,
          'left_array_data': ARRAY(condition.left.toArray(), 'integer'),
          'right_array_data': ARRAY(condition.right.toArray(), 'integer')
        }));
  }
}
