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
    body.conditions ??= [];
    final conditions = body.conditions.map((cond) {
      final left = new Expr.fromBase64(cond.leftExpression.data);
      final right = new Expr.fromBase64(cond.rightExpression.data);
      return new Rule(left, right);
    });

    final left = new Expr.fromBase64(body.leftExpression.data);
    final right = new Expr.fromBase64(body.rightExpression.data);
    return createRuleFromDefinition(
        s, new Rule(left, right), conditions.toList());
  } else if (body.proof != null) {
    if (body.proof.id != null) {
      return createRuleFromProof(s, body.proof.id);
    } else {
      return createRuleFromSteps(
          s, body.proof.firstStep.id, body.proof.lastStep.id);
    }
  } else if (body.step != null) {
    return createRuleFromStep(s, body.step.id);
  } else {
    throw new UnprocessableEntityError('not enough parameters');
  }
}

Future<db.RuleRow> createRuleFromDefinition(
    Session s, Rule definition, List<Rule> conditions) async {
  // Create conditions and collect ids.
  final conditionIds = conditions.map((cond) async {
    return (await _createCondition(s, cond)).id;
  });

  return _createRule(s, definition, await Future.wait(conditionIds),
      isDefinition: true);
}

Future<db.RuleRow> createRuleFromProof(Session s, int proofId) async {
  // Load first and last expression from proof.
  final proof = await s.selectById(db.proof, proofId);

  // Less optimal but simpler.
  return await createRuleFromSteps(s, proof.firstStepId, proof.lastStepId);
}

Future<db.RuleRow> createRuleFromSteps(
    Session s, int firstStepId, int lastStepId) async {
  /// Check if the steps connect.
  final steps = await _listStepsBetween(s, firstStepId, lastStepId);
  if (steps.first.id != firstStepId || steps.last.id != lastStepId) {
    throw new UnprocessableEntityError('steps do not connect');
  } else {
    // Get proof record for these connecting steps.
    final proof = await _getProofFor(s, steps.first.id, steps.last.id);

    // Load rule expression.
    final firstId = steps.first.expressionId;
    final lastId = steps.last.expressionId;
    final map = await getExpressionMap(s, [firstId, lastId]);
    final rule = new Rule(map[firstId], map[lastId]);

    // Get conditions.
    final conditionIds =
        await _findUnprovenConditions(s, steps.map((step) => step.id));

    return _createRule(s, rule, conditionIds, proofId: proof.id);
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
      final conditionIds = new List<int>();

      // Find unproven conditions.
      conditionIds.addAll(
          await _findUnprovenConditions(s, steps.map((step) => step.id)));

      // Append conditions of initial rule or proof.
      if (steps.first.type == 'copy_rule') {
        // Retrieve rule conditions.
        final ruleConditions = await s.select(
            db.ruleCondition, WHERE({'rule_id': IS(steps.first.ruleId)}));
        conditionIds.addAll(ruleConditions.map((row) => row.conditionId));
      } else if (steps.first.type == 'copy_proof') {
        // Find all unproven conditions in given proof.
        final proof = await s.selectById(db.proof, steps.first.proofId);
        final proofSteps =
            await _listStepsBetween(s, proof.firstStepId, proof.lastStepId);
        final proofConditions =
            await _findUnprovenConditions(s, proofSteps.map((st) => st.id));
        conditionIds.addAll(proofConditions);
      }

      // Get rule expressions and create rule.
      assert(expr.nodeArguments.length == 2);
      final m = await getExpressionMap(s, expr.nodeArguments);
      final rule = new Rule(m[expr.nodeArguments[0]], m[expr.nodeArguments[1]]);
      return _createRule(s, rule, conditionIds, stepId: step.id);
    } else {
      throw new UnprocessableEntityError(
          "origin of step does not have type 'copy_rule' or 'copy_proof'");
    }
  } else {
    throw new UnprocessableEntityError('step expression is not an equation');
  }
}

/// Create unchecked rule.
Future<db.RuleRow> _createRule(Session s, Rule rule, List<int> conditionIds,
    {int stepId, int proofId, bool isDefinition: false}) async {
  // Check if a similar rule already exists.
  // It should not be possible to directly resolve this rule using
  // [resolveExpressionDifference].
  final difference =
      await _resolveExpressionDifference(s, rule.left, rule.right);
  if (!difference.different) {
    throw new UnprocessableEntityError('rule sides must be different');
  } else if (difference.resolved) {
    throw new UnprocessableEntityError('rule is directly resolvable');
  }

  // Computing closure.
  num compute(int id, List<num> args) => _exprCompute(s, id, args);

  // Evaluate expressions.
  final leftEval = rule.left.evaluate(compute);
  final rightEval = rule.right.evaluate(compute);

  // Insert expressions.
  final leftRow = await _createExpression(s, leftEval);
  final rightRow = await _createExpression(s, rightEval);

  // Insert rule.
  final ruleRow = await s.insert(
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

  // Insert conditions.
  await Future.wait(conditionIds
      .map((conditionId) => _createRuleCondition(s, ruleRow.id, conditionId)));

  return ruleRow;
}

/// Create rule_condition record.
Future<db.RuleConditionRow> _createRuleCondition(
    Session s, int ruleId, int conditionId) {
  s.data.ruleConditions.putIfAbsent(ruleId, () => new List<int>());
  s.data.ruleConditions[ruleId].add(conditionId);
  return s.insert(db.ruleCondition,
      VALUES({'rule_id': ruleId, 'condition_id': conditionId}));
}

/// Retrieve decoded [Rule] object.
Future<Rule> _getRule(Session s, int id) async {
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
