// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class ProofData {
  int initialStepId;
  int initialRuleId;
  List<ResolveBranch> steps;
}

enum StepType {
  setExpression,
  copyRule,
  copyProof,
  rearrange,
  substituteRule,
  substituteProof,
  substituteFree
}

String _getStepTypeString(StepType type) {
  switch (type) {
    case StepType.setExpression:
      return 'set';
    case StepType.copyRule:
      return 'copy_rule';
    case StepType.copyProof:
      return 'copy_proof';
    case StepType.rearrange:
      return 'rearrange';
    case StepType.substituteRule:
      return 'substitute_rule';
    case StepType.substituteProof:
      return 'substitute_proof';
    case StepType.substituteFree:
      return 'substitute_free';
    default:
      throw new UnimplementedError('unimplemented step type: $type');
  }
}

/// Intermediary data for building a step.
/// The [ResolveBranch] is first flattened into this class.
class _StepData {
  StepType type;
  int position = 0;
  db.StepRow row;

  /// Expression at node [position] in the right expression tree. This is used
  /// to check rules when [reverseTarget] is set.
  Expr subExprRight;

  /// Resulting expression.
  Expr expression;

  bool reverseItself = false;
  bool reverseTarget = false;

  /// Rule that is supposedly substituted.
  int ruleId;

  /// Map from condition ID of the substitution to condition proof.
  Map<int, _ConditionProof> conditionProofs = {};

  /// Substitution data (used for rules and raw substitutions)
  Subs subs;

  List<int> rearrangeFormat;
}

class _ConditionProof {
  final int ruleId;
  final bool reverseItself;
  final bool reverseTarget;
  final bool selfEvident;

  _ConditionProof(
      this.ruleId, this.reverseItself, this.reverseTarget, this.selfEvident);
}

Future<db.ProofRow> createProof(Session s, ProofData body) async {
  num compute(int id, List<num> args) => _exprCompute(s, id, args);

  if (body.steps.isEmpty) {
    throw new UnprocessableEntityError('proof must have at least one step');
  }

  /// Create intermediary data list.
  final steps = new List<_StepData>();

  if (body.initialStepId != null) {
    steps.add(await _getStepData(s, body.initialStepId));
  } else if (body.initialRuleId != null) {
    steps.add(new _StepData()
      ..type = StepType.copyRule
      ..ruleId = body.initialRuleId
      ..expression = await _getRuleAsExpression(s, body.initialRuleId));
  } else {
    steps.add(new _StepData()
      ..type = StepType.setExpression
      ..expression = body.steps.first.subs.leftExpr);
  }

  /// Flatten list of resolve branches into a step list.
  for (final branch in body.steps) {
    if (branch.subs.leftExpr != steps.last.expression) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      // Note: reverse flattened list so that position integers are unaffected.
      steps.addAll(_flattenResolveBranch(branch).reversed);

      // Use the right side of the branch to later validate that proof
      // reconstruction is correct.
      steps.last.expression = branch.subs.rightExpr;
    }
  }

  // Aggregate all rule IDs (both from substitutions and proofs).
  final ruleIds = new List<int>();
  ruleIds.addAll(steps.map((step) => step.ruleId));
  for (final step in steps) {
    for (final conditionProof in step.conditionProofs.values) {
      ruleIds.add(conditionProof.ruleId);
    }
  }

  // Retrieve rule data.
  final rules = await s.selectByIds(db.rule, ruleIds.where((id) => id != null));
  final subss = await getSubsMap(s, rules.map((r) => r.substitutionId));

  // Store rule substitutions in step data and verify conditions.
  for (final step in steps) {
    if (step.ruleId != null) {
      final rule = await s.selectById(db.rule, step.ruleId);
      step.subs = subss[rule.substitutionId];
    }
  }

  // Retrieve rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Run through all steps.
  Expr expr;
  final processedSteps = new List<_StepData>();
  for (final step in steps) {
    // Apply step to [expr].
    // As a convention we evaluate the expression after each step.
    final nextExpr =
        (await _computeProofStep(s, expr, step, rearrangeableIds, compute))
            .evaluate(compute);

    // If there is no difference with the previous expression, remove this step.
    if (nextExpr == expr) {
      continue;
    } else {
      expr = nextExpr;
    }

    // Compare computed expression with step expression that is already set.
    if (step.expression != null && step.expression.evaluate(compute) != expr) {
      // If an expression is already set for this step, it should be the same
      // after evaluation.
      throw new UnprocessableEntityError('proof reconstruction failed');
    }

    // Set/override the expression.
    step.expression = expr.clone();

    // Add to processed steps.
    processedSteps.add(step);
  }

  // Insert all steps into database.
  final rows = new List<db.StepRow>();
  for (final step in processedSteps) {
    // Skip if this is an existing step.
    if (step.row != null) {
      rows.add(step.row);
      continue;
    }

    final expressionRow = await _createExpression(s, step.expression);

    // Create map with insert values.
    final values = {
      'expression_id': expressionRow.id,
      'step_type': _getStepTypeString(step.type),
      'position': step.position,
      'reverse_itself': step.reverseItself,
      'reverse_target': step.reverseTarget
    };
    if (rows.isNotEmpty) {
      values['previous_id'] = rows.last.id;
    }
    if (step.ruleId != null) {
      values['rule_id'] = step.ruleId;
    }
    if (step.rearrangeFormat != null) {
      values['rearrange_format'] = ARRAY(step.rearrangeFormat, 'integer');
    }

    final stepRow = await s.insert(db.step, VALUES(values));
    rows.add(stepRow);

    for (final conditionId in step.conditionProofs.keys) {
      final conditionProof = step.conditionProofs[conditionId];
      await s.insert(
          db.conditionProof,
          VALUES({
            'step_id': stepRow.id,
            'condition_id': conditionId,
            'follows_rule_id': conditionProof.ruleId,
            'reverse_itself': conditionProof.reverseItself,
            'reverse_target': conditionProof.reverseTarget
          }));
    }
  }

  final values = {'first_step_id': rows.first.id, 'last_step_id': rows.last.id};
  return await s.insert(db.proof, VALUES(values));
}

/// TODO: move to new file.
/// Compute result of applying [step], given the [previous] expression. In some
/// cases the computation is backwards. This means the substitution that is
/// applied to [previous] is computed in part based on the resulting expression.
Future<Expr> _computeProofStep(Session s, Expr previous, _StepData step,
    List<int> rearrangeableIds, ExprCompute compute) async {
  // If the step type is null, it is an existing step and only the step
  // expression was retrieved.
  if (step.type == null) {
    return step.expression;
  }

  switch (step.type) {
    // In the case of copyRule the resulting expression is generated earlier.
    case StepType.copyRule:
    case StepType.setExpression:
      return step.expression;

    case StepType.copyProof:
      throw new UnimplementedError('copyProof is not implemented');

    case StepType.rearrange:
      return previous.rearrangeAt(
          step.rearrangeFormat, step.position, rearrangeableIds);

    case StepType.substituteRule:
      final subs = step.reverseItself ? step.subs.inverted : step.subs;

      // First substitute rule to obtain mapping for checking the conditions.
      final mapping = new ExprMapping();
      Expr result;
      if (!step.reverseTarget) {
        result = previous.substituteAt(subs, step.position, mapping: mapping);
      } else {
        // Reversed evaluation means that the right sub-expression at this
        // position is used to construct the original expression. When evaluated
        // this must match the expression in [previous] at the step position.
        // From this a new rule can be constructed to substitute the
        // sub-expression into [previous].
        final original =
            step.subExprRight.substituteAt(subs, 0, mapping: mapping);
        result = previous.substituteAt(
            new Subs(original.evaluate(compute), step.subExprRight),
            step.position);
      }
      assert(result != null);

      // Retrieve conditions.
      final ruleConditions =
          await s.select(db.ruleCondition, WHERE({'rule_id': IS(step.ruleId)}));
      final substitutionIds = ruleConditions.map((c) => c.substitutionId);
      final subss = await getSubsMap(s, substitutionIds);

      // Check each condition.
      for (final condition in ruleConditions) {
        if (step.conditionProofs.containsKey(condition.id)) {
          // Get condition and proof substitution.
          final conditionSubs = subss[condition.substitutionId];

          final proof = step.conditionProofs[condition.id];
          final proofRule = await s.selectById(db.rule, proof.ruleId);
          final proofSubs = await getSubs(s, proofRule.substitutionId);

          // Just to make sure both substitutions are indeed set.
          assert(conditionSubs != null && proofSubs != null);

          // Reverse substitutions as specified.
          final pSubs = proofSubs.clone(invert: proof.reverseItself);
          final cSubs = conditionSubs.clone(invert: proof.reverseItself);

          // Compare condition with proof. The proof should be a superset of
          // the condition. The mapping generated by applying the related rule
          // at the given position is applied to the condition first.
          if (!cSubs.remap(mapping).compare(pSubs, compute)) {
            throw new UnprocessableEntityError('condition proof mismatch');
          }
        } else {
          throw new UnprocessableEntityError('missing condition proof');
        }
      }

      return result;

    case StepType.substituteFree:
      // Since subs must match literally, we can combine reverseItself and
      // reverseTarget and perform the operation in one direction.
      final subs = xor(step.reverseItself, step.reverseTarget)
          ? step.subs.inverted
          : step.subs;

      return previous.substituteAt(subs, step.position, literal: true);

    case StepType.substituteProof:
      throw new UnimplementedError('substituteProof is not implemented');
  }

  // Analyzer keeps complaining about the function not returning in all cases.
  throw new Error();
}

/// Flatten [branch] into a list of steps.
List<_StepData> _flattenResolveBranch(ResolveBranch branch) {
  if (!branch.resolved) {
    throw new UnprocessableEntityError('contains unresolved steps');
  } else if (branch.different) {
    final steps = new List<_StepData>();
    if (branch.rearrangements.isNotEmpty) {
      // Add step for each rearrangement.
      for (final rearrangement in branch.rearrangements) {
        steps.add(new _StepData()
          ..type = StepType.rearrange
          ..position = rearrangement.position
          ..rearrangeFormat = rearrangement.format);
      }
    } else if (branch.substitution != null) {
      // Currently supported: rule with at most one layer of conditions that can
      // only be proven by another rule.
      // For other substitutions an exception is raised.
      final s = branch.substitution;
      if (s.entry.type == SubsType.rule) {
        // Collect condition proofs into map.
        final conditionProofs = new Map<int, _ConditionProof>.fromIterables(
            s.entry.conditions.map((entry) => entry.id),
            s.conditionProofs.map((p) {
          if (p.entry.type == SubsType.rule) {
            return new _ConditionProof(
                p.entry.referenceId, p.reverseItself, p.reverseTarget, false);
          } else {
            throw new UnprocessableEntityError(
                'unimplemented substitution type');
          }
        }));

        // Add to step list, validation will be performed later.
        final step = new _StepData()
          ..type = StepType.substituteRule
          ..position = branch.position
          ..reverseItself = s.reverseItself
          ..reverseTarget = s.reverseTarget
          ..ruleId = s.entry.referenceId
          ..subExprRight = branch.subs.rightExpr
          ..conditionProofs.addAll(conditionProofs);

        steps.add(step);
      } else {
        // TODO: implement free conditions.
        throw new UnprocessableEntityError('unimplemented substitution type');
      }
    } else {
      // Add steps for each argument.
      for (final argument in branch.arguments) {
        steps.addAll(_flattenResolveBranch(argument));
      }
    }

    return steps;
  } else {
    return [];
  }
}

/// Retrieve step with given [id] and return data.
Future<_StepData> _getStepData(Session s, int id) async {
  final step = new _StepData();
  step.row = await s.selectById(db.step, id);
  final exprRow = await s.selectById(db.expression, step.row.expressionId);
  step.expression = exprRow.asExpr;
  return step;
}

/// Expand rule with [id] into an equation expression.
Future<Expr> _getRuleAsExpression(Session s, int id) async {
  final rule = await s.selectById(db.rule, id);
  return _substitutionAsEqualsExpression(s, rule.substitutionId);
}

/// Get proof record for given first and last step ID. This function does not
/// check if those steps actually connect and form a valid proof.
Future<db.ProofRow> _getProofFor(
    Session s, int firstStepId, int lastStepId) async {
  final matchingProofs = await s.select(
      db.proof,
      WHERE(
          {'first_step_id': IS(firstStepId), 'last_step_id': IS(lastStepId)}));

  if (matchingProofs.isNotEmpty) {
    return matchingProofs.single;
  } else {
    return await s.insert(db.proof,
        VALUES({'first_step_id': firstStepId, 'last_step_id': lastStepId}));
  }
}
