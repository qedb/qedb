// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

/// Create rule from given proof.
Future<db.RuleRow> createRule(Session s, RuleResource body) async {
  /// Check if proof is valid.
  final steps = await _listStepsBetween(
      s, body.proof.firstStep.id, body.proof.lastStep.id);
  if (steps.first.id != body.proof.firstStep.id ||
      steps.last.id != body.proof.lastStep.id) {
    throw new UnprocessableEntityError('invalid proof');
  } else {
    var proofId;

    // Check if a proof ID exists.
    final proofs = await s.select(
        db.proof,
        WHERE({
          'first_step_id': IS(steps.first.id),
          'last_step_id': IS(steps.last.id)
        }));
    if (proofs.isNotEmpty) {
      proofId = proofs.single.id;
    }

    // Else create new proof ID.
    else {
      final proof = await s.insert(
          db.proof,
          VALUES({
            'first_step_id': steps.first.id,
            'last_step_id': steps.last.id
          }));
      proofId = proof.id;
    }

    assert(proofId != null);

    // Pre-load expressions.
    final firstId = steps.first.expressionId;
    final lastId = steps.last.expressionId;
    await s.selectByIds(db.expression, [firstId, lastId]);
    final leftExpr = new Expr.fromBase64(s.data.expressionTable[firstId].data);
    final rightExpr = new Expr.fromBase64(s.data.expressionTable[lastId].data);

    // Insert expressions.
    final leftRow = await _createExpression(s, leftExpr);
    final rightRow = await _createExpression(s, rightExpr);

    // Insert rule.
    return s.insert(
        db.rule,
        VALUES({
          'left_expression_id': leftRow.id,
          'right_expression_id': rightRow.id,
          'left_array_data': ARRAY(leftExpr.toArray(), 'integer'),
          'right_array_data': ARRAY(rightExpr.toArray(), 'integer'),
          'proof_id': proofId
        }));
  }
}

/// Create unchecked rule.
Future<db.RuleRow> _createRule(Session s, RuleResource body) async {
  // Decode expressions.
  final leftExpr = new Expr.fromBase64(body.leftExpression.data);
  final rightExpr = new Expr.fromBase64(body.rightExpression.data);

  // Insert expressions.
  final leftRow = await _createExpression(s, leftExpr);
  final rightRow = await _createExpression(s, rightExpr);

  return s.insert(
      db.rule,
      VALUES({
        'left_expression_id': leftRow.id,
        'right_expression_id': rightRow.id,
        'left_array_data': ARRAY(leftExpr.toArray(), 'integer'),
        'right_array_data': ARRAY(rightExpr.toArray(), 'integer')
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
