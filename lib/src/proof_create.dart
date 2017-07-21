// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class ProofData {
  int initialStepId;
  int initialRuleId;
  List<DifferenceBranch> steps;
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
/// The [DifferenceBranch] is first flattened into this class.
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

  int ruleId;

  /// Substitution data (used for rules and raw substitutions)
  Subs subs;

  List<int> rearrangeFormat;
}

Future<db.ProofRow> createProof(Session s, ProofData body) async {
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
      ..expression = body.steps.first.leftExpr);
  }

  /// Flatten list of difference branches into a step list.
  for (final branch in body.steps) {
    if (branch.leftExpr != steps.last.expression) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      // Note: reverse flattened list so that position integers are unaffected.
      steps.addAll(_flattenDifferenceBranch(branch).reversed);

      // Use the right side of the branch to later validate that proof
      // reconstruction is correct.
      steps.last.expression = branch.rightExpr;
    }
  }

  // Retrieve all rules.
  final ruleIds = steps.map((step) => step.ruleId);
  final rules = await s.selectByIds(db.rule, ruleIds.where((id) => id != null));
  final subss = await getSubsMap(s, rules.map((r) => r.substitutionId));
  for (final step in steps) {
    if (step.ruleId != null) {
      final rule = await s.selectById(db.rule, step.ruleId);
      step.subs = subss[rule.substitutionId];
    }
  }

  // Retrieve rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Computing closure.
  num compute(int id, List<num> args) => _exprCompute(s, id, args);

  // Run through all steps.
  Expr expr;
  final processedSteps = new List<_StepData>();
  for (final step in steps) {
    // If no step type is set (existing step) or this is a copy_rule step. The
    // expression is already computed.
    if (step.type == null || step.type == StepType.copyRule) {
      expr = step.expression.evaluate(compute).clone();
    } else {
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

      if (step.expression != null &&
          step.expression.evaluate(compute) != expr) {
        // If an expression is already set for this step, it should be the same
        // after evaluation.
        throw new UnprocessableEntityError('proof reconstruction failed');
      }

      // Set/override the expression.
      step.expression = expr.clone();
    }

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

    rows.add(await s.insert(db.step, VALUES(values)));
  }

  final values = {'first_step_id': rows.first.id, 'last_step_id': rows.last.id};
  return await s.insert(db.proof, VALUES(values));
}

/// Compute result of applying [step], given the [previous] expression. In some
/// cases the computation is backwards. This means the substitution that is
/// applied to [previous] is computed in part based on the resulting expression
/// (fetched from [DifferenceBranch.rightExpression]).
Future<Expr> _computeProofStep(Session s, Expr previous, _StepData step,
    List<int> rearrangeableIds, ExprCompute compute) async {
  assert(step.type != null);
  switch (step.type) {
    case StepType.setExpression:
      return step.expression;

    case StepType.copyProof:
      throw new UnimplementedError('copy_proof is not implemented');

    case StepType.rearrange:
      return previous.rearrangeAt(
          step.rearrangeFormat, step.position, rearrangeableIds);

    case StepType.substituteRule:
    case StepType.substituteFree:
      final subs = step.reverseItself ? step.subs.inverted : step.subs;
      if (!step.reverseTarget) {
        return previous.substituteAt(subs, step.position);
      } else {
        // Reversed evaluation means that the right sub-expression at this
        // position is used to construct the original expression. When evaluated
        // this must match the expression in [previous] at the step position.
        // From this a new rule can be constructed to substitute the
        // sub-expression into [previous].
        final original = step.subExprRight.substituteAt(subs, 0);
        return previous.substituteAt(
            new Subs(original.evaluate(compute), step.subExprRight),
            step.position);
      }
      break;

    default:
      throw new UnimplementedError('unexpected enum value');
  }
}

/// Flatten [branch] into a list of steps.
List<_StepData> _flattenDifferenceBranch(DifferenceBranch branch) {
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
    } else if (branch.rule != null) {
      // Add single step for rule.
      final step = new _StepData()
        ..type = StepType.substituteRule
        ..position = branch.position
        ..reverseItself = branch.reverseItself
        ..reverseTarget = branch.reverseTarget
        ..ruleId = branch.rule.id
        ..subExprRight = branch.rightExpr;

      steps.add(step);
    } else {
      // Add steps for each argument.
      for (final argument in branch.arguments) {
        steps.addAll(_flattenDifferenceBranch(argument));
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
