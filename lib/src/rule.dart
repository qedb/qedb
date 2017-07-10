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
    final conditions = body.conditions.map((c) => c.substitution.asSubs);
    return createRuleFromDefinition(
        s, body.substitution.asSubs, conditions.toList());
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
    Session s, Subs definition, List<Subs> conditions) async {
  // Create conditions and collect ids.
  final conditionIds = new List<int>();
  for (final condition in conditions) {
    conditionIds.add((await _createSubstitution(s, condition)).id);
  }

  return _createRule(s, definition, conditionIds, isDefinition: true);
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
    final map = await getExprMap(s, [firstId, lastId]);
    final rule = new Subs(map[firstId], map[lastId]);

    // Find conditions.
    final conditionIds = await _findConditions(s, steps.map((step) => step.id));

    // Create rule.
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
      // All conditional substitutions.
      final conditionIds = new List<int>();

      // Find unproven rule conditions.
      conditionIds
          .addAll(await _findConditions(s, steps.map((step) => step.id)));

      // Append conditions of initial rule or proof.
      if (steps.first.type == 'copy_rule') {
        // Retrieve conditions of initial rule.
        final ruleConditions = await s.select(
            db.ruleCondition, WHERE({'rule_id': IS(steps.first.ruleId)}));
        conditionIds.addAll(ruleConditions.map((row) => row.substitutionId));
      } else if (steps.first.type == 'copy_proof') {
        // Find all conditions in the given proof.
        final proof = await s.selectById(db.proof, steps.first.proofId);
        final proofSteps =
            await _listStepsBetween(s, proof.firstStepId, proof.lastStepId);
        final proofConditions =
            await _findConditions(s, proofSteps.map((st) => st.id));
        conditionIds.addAll(proofConditions);
      }

      // Get rule substitution object and create rule.
      assert(expr.nodeArguments.length == 2);
      final m = await getExprMap(s, expr.nodeArguments);
      final subs = new Subs(m[expr.nodeArguments[0]], m[expr.nodeArguments[1]]);
      return _createRule(s, subs, conditionIds, stepId: step.id);
    } else {
      throw new UnprocessableEntityError(
          "origin of step does not have type 'copy_rule' or 'copy_proof'");
    }
  } else {
    throw new UnprocessableEntityError('step expression is not an equation');
  }
}

/// Create unchecked rule.
Future<db.RuleRow> _createRule(Session s, Subs rule, List<int> conditionIds,
    {int stepId, int proofId, bool isDefinition: false}) async {
  // Computing closure.
  num compute(int id, List<num> args) => _exprCompute(s, id, args);

  // Evaluate expressions.
  final leftEval = rule.left.evaluate(compute);
  final rightEval = rule.right.evaluate(compute);

  // Check if a similar rule already exists.
  // It should not be possible to directly resolve this rule using
  // [_resolveExpressionDifference].
  final difference = await _resolveExpressionDifference(s, leftEval, rightEval);
  if (!difference.different) {
    throw new UnprocessableEntityError('rule sides must be different');
  } else if (difference.resolved) {
    throw new UnprocessableEntityError('rule is directly resolvable');
  }

  // Insert substitution.
  final substitution =
      await _createSubstitution(s, new Subs(leftEval, rightEval));

  // Insert rule.
  final ruleRow = await s.insert(
      db.rule,
      VALUES({
        'step_id': stepId,
        'proof_id': proofId,
        'is_definition': isDefinition,
        'substitution_id': substitution.id
      }));

  // Insert conditions.
  await Future.wait(conditionIds
      .map((conditionId) => _createRuleCondition(s, ruleRow.id, conditionId)));

  return ruleRow;
}

/// Create rule_condition record.
Future<db.RuleConditionRow> _createRuleCondition(
    Session s, int ruleId, int substitutionId) {
  return s.insert(db.ruleCondition,
      VALUES({'rule_id': ruleId, 'substitution_id': substitutionId}));
}

Future<List<db.RuleRow>> listRules(Session s, [Iterable<int> ids]) async {
  final rules =
      ids == null ? await s.select(db.rule) : await s.selectByIds(db.rule, ids);

  final substitutionIds = new List<int>();
  substitutionIds.addAll(rules.map((rule) => rule.substitutionId));

  // Select rule conditions.
  final allRuleConditions = ids == null
      ? await s.select(db.ruleCondition)
      : await s.select(db.ruleCondition, WHERE({'rule_id': IN(ids)}));
  for (final row in allRuleConditions) {
    substitutionIds.add(row.substitutionId);
  }

  // Load substitutions.
  final pairs = await _listSubstitutions(s, substitutionIds);

  // Aggregate all expression IDs.
  final expressionIds = new List<int>();
  for (final pair in pairs) {
    expressionIds.add(pair.leftExpressionId);
    expressionIds.add(pair.rightExpressionId);
  }

  // Load expressions.
  await listExpressions(s, expressionIds);

  return rules;
}

Future<db.RuleRow> deleteRule(Session s, int id) {
  // Foreign key constraints should make this safe.
  return s.deleteOne(db.rule, WHERE({'id': IS(id)}));
}
