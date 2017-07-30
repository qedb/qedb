// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class ProofData {
  int initialStepId;
  int initialRuleId;

  @ApiProperty(required: true)
  List<ResolveBranch> steps;

  @ApiProperty(required: true)
  List<RpcSubs> freeConditions;
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
      throw new UnprocessableEntityError('unimplemented step type: $type');
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
  Map<int, SubsSearchResult> conditionProofs = {};

  /// Substitution data (used for rules and raw substitutions)
  Subs subs;

  List<int> rearrangeFormat;
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

  /// Parse free conditions.
  final freeConditions = body.freeConditions.map((s) => s.toSubs()).toList();

  /// Flatten list of resolve branches into a step list.
  for (final branch in body.steps) {
    if (branch.subs.leftExpr != steps.last.expression) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      // Note: reverse flattened list so that position integers are unaffected.
      steps.addAll(_flattenResolveBranch(branch, freeConditions).reversed);

      // Use the right side of the branch to later validate that proof
      // reconstruction is correct.
      steps.last.expression = branch.subs.rightExpr;
    }
  }

  // Retrieve rule data in one request (optimization).
  final rules = await s.selectByIds(db.rule, steps.map((step) => step.ruleId));
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
    final nextExpr = (await _computeProofStep(
            s, expr, step, rearrangeableIds, freeConditions, compute))
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
    } else if (step.type == StepType.substituteFree) {
      values['substitution_id'] = (await _createSubstitution(s, step.subs)).id;
    } else if (step.rearrangeFormat != null) {
      values['rearrange_format'] = ARRAY(step.rearrangeFormat, 'integer');
    }

    final stepRow = await s.insert(db.step, VALUES(values));
    rows.add(stepRow);

    for (final conditionId in step.conditionProofs.keys) {
      final proof = step.conditionProofs[conditionId];
      final values = {
        'step_id': stepRow.id,
        'condition_id': conditionId,
        'reverse_itself': proof.reverseItself,
        'reverse_target': proof.reverseTarget
      };

      if (proof.entry.type == SubsType.rule) {
        values['follows_rule_id'] = proof.entry.referenceId;
      } else if (proof.entry.type == SubsType.free) {
        values['adopt_condition'] = true;
      }

      await s.insert(db.conditionProof, VALUES(values));
    }
  }

  final values = {'first_step_id': rows.first.id, 'last_step_id': rows.last.id};
  return await s.insert(db.proof, VALUES(values));
}

/// Flatten [branch] into a list of steps.
List<_StepData> _flattenResolveBranch(
    ResolveBranch branch, List<Subs> freeConditions) {
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
        final conditionProofs = new Map<int, SubsSearchResult>.fromIterables(
            s.entry.conditions.map((entry) => entry.id), s.conditionProofs);

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
      } else if (s.entry.type == SubsType.free) {
        final step = new _StepData()
          ..type = StepType.substituteFree
          ..position = branch.position
          ..reverseItself = s.reverseItself
          ..reverseTarget = s.reverseTarget
          ..subs = freeConditions[s.entry.referenceId];

        steps.add(step);
      } else {
        throw new UnprocessableEntityError('unimplemented substitution type');
      }
    } else {
      // Add steps for each argument.
      for (final argument in branch.arguments) {
        steps.addAll(_flattenResolveBranch(argument, freeConditions));
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
