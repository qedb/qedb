// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

/// Create rule from given proof.
///
/// A new rule can be defined in one of four ways:
///
/// 1. *From a definition:* `isDefinition` = true, `leftExpression.data` and
///    `rightExpression.data` are set.
/// 2. *From a proof:* `proof.id` is set.
/// 3. *From two connecting steps:* `proof.firstStep.id` and
///    `proof.lastStep.id` are set.
/// 4. *From a single step:* `step.id` is set (must be an equation, e.g. the top
///    level function is [SpecialFunction.equals]).
Future<db.RuleRow> createRule(Session s, RuleResource body) async {
  if (body.isDefinition != null && body.isDefinition) {
    return createRuleFromDefinition(
        s,
        checkNull(() => body.leftExpression.data),
        checkNull(() => body.rightExpression.data));
  } else if (body.proof != null) {
    if (body.proof.id != null) {
      return createRuleFromProof(s, body.proof.id);
    } else {
      return createRuleFromSteps(s, checkNull(() => body.proof.firstStep.id),
          checkNull(() => body.proof.lastStep.id));
    }
  } else if (body.step != null) {
    return createRuleFromStep(s, checkNull(() => body.step.id));
  } else {
    throw new UnprocessableEntityError('not enough parameters');
  }
}

Future<db.RuleRow> createRuleFromDefinition(
    Session s, String leftData, String rightData) {
  return _createRule(
      s, new Expr.fromBase64(leftData), new Expr.fromBase64(rightData),
      isDefinition: true);
}

Future<db.RuleRow> createRuleFromProof(Session s, int proofId) async {
  // Load first and last expression from proof.
  final proof = await s.selectById(db.proof, proofId);

  // Load expressions.
  await _listStepsById(s, [proof.firstStepId, proof.lastStepId]);
  final leftExpr = s.data
      .expressionTable[s.data.stepTable[proof.firstStepId].expressionId].expr;
  final rightExpr = s.data
      .expressionTable[s.data.stepTable[proof.lastStepId].expressionId].expr;

  return _createRule(s, leftExpr, rightExpr, proofId: proofId);
}

Future<db.RuleRow> createRuleFromSteps(
    Session s, int firstStepId, int lastStepId) async {
  /// Check if the steps connect.
  final steps = await _listStepsBetween(s, firstStepId, lastStepId);
  if (steps.first.id != firstStepId || steps.last.id != lastStepId) {
    throw new UnprocessableEntityError('steps do not connect');
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
    } else {
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
    final map = await getExpressionMap(s, [firstId, lastId]);

    return _createRule(s, map[firstId], map[lastId], proofId: proofId);
  }
}

Future<db.RuleRow> createRuleFromStep(Session s, int stepId) async {
  // Get step expression.
  final step = await s.selectById(db.step, stepId);
  final expr = await s.selectById(db.expression, step.expressionId);

  if (expr.nodeType == 'function' &&
      expr.nodeValue == s.specialFunctions[SpecialFunction.equals]) {
    // Trace back to initial step.
    final steps = await _listStepsBetween(s, -1, stepId);

    // This must be a 'copy_rule' or 'copy_proof' step.
    if (['copy_rule', 'copy_proof'].contains(steps.first.type)) {
      // Retrieve left and right expression.
      assert(expr.nodeArguments.length == 2);
      final map = await getExpressionMap(s, expr.nodeArguments);
      return _createRule(
          s, map[expr.nodeArguments[0]], map[expr.nodeArguments[1]],
          stepId: step.id);
    } else {
      throw new UnprocessableEntityError(
          "origin of step does not have type 'copy_rule' or 'copy_proof'");
    }
  } else {
    throw new UnprocessableEntityError('step expression is not an equation');
  }
}

/// Create unchecked rule.
Future<db.RuleRow> _createRule(Session s, Expr leftExpr, Expr rightExpr,
    {int stepId, int proofId, bool isDefinition: false}) async {
  // Check if a similar rule already exists.
  // It should not be possible to directly resolve this rule using
  // [resolveExpressionDifference].
  final difference = await _resolveExpressionDifference(s, leftExpr, rightExpr);
  if (!difference.different) {
    throw new UnprocessableEntityError('rule sides must be different');
  } else if (difference.resolved) {
    throw new UnprocessableEntityError('rule is directly resolvable');
  }

  // Computing closure.
  num compute(int id, List<num> args) => _exprCompute(s, id, args);

  // Evaluate expressions.
  final leftEval = leftExpr.evaluate(compute);
  final rightEval = rightExpr.evaluate(compute);

  // Insert expressions.
  final leftRow = await _createExpression(s, leftEval);
  final rightRow = await _createExpression(s, rightEval);

  return s.insert(
      db.rule,
      VALUES({
        'step_id': stepId,
        'proof_id': proofId,
        'is_definition': isDefinition,
        'left_expression_id': leftRow.id,
        'right_expression_id': rightRow.id,
        'left_array_data': ARRAY(leftEval.toArray(), 'integer'),
        'right_array_data': ARRAY(rightEval.toArray(), 'integer')
      }));
}

/// Retrieve rule as [Rule] object from eqlib.
Future<Rule> _getEqLibRule(Session s, int id) async {
  final rule = await s.selectById(db.rule, id);
  final map = await getExpressionMap(
      s, [rule.leftExpressionId, rule.rightExpressionId]);
  return new Rule(map[rule.leftExpressionId], map[rule.rightExpressionId]);
}

Future<List<db.RuleRow>> listRules(Session s, [Iterable<int> ids]) async {
  final rules =
      await (ids == null ? s.select(db.rule) : s.selectByIds(db.rule, ids));

  // Select left and right expressions.
  final expressionIds = new List<int>();
  for (final rule in rules) {
    expressionIds.add(rule.leftExpressionId);
    expressionIds.add(rule.rightExpressionId);
  }
  await listExpressions(s, expressionIds);

  return rules;
}

Future<db.RuleRow> deleteRule(Session s, int id) {
  // Foreign key constraints should make this safe.
  return s.deleteOne(db.rule, WHERE({'id': IS(id)}));
}
