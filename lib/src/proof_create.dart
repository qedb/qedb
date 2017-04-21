// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class ProofData {
  List<DifferenceBranch> steps;
}

enum StepType {
  setExpression,
  rearrange,
  ruleNormal,
  ruleInvert,
  ruleMirror,
  ruleRevert
}

/// Intermediary data for building a step.
/// The [DifferenceBranch] is first flattened into this class.
class _StepData {
  StepType type;
  int position;
  Expr subExprRight;
  Expr expression;
  List<int> rearrange;
  int ruleId;
  Rule rule;

  String get typeString => {
        StepType.setExpression: 'set',
        StepType.rearrange: 'rearrange',
        StepType.ruleNormal: 'rule_normal',
        StepType.ruleInvert: 'rule_invert',
        StepType.ruleMirror: 'rule_mirror',
        StepType.ruleRevert: 'rule_revert'
      }[type];
}

Future<db.ProofRow> createProof(Session s, ProofData body) async {
  if (body.steps.isEmpty) {
    throw new UnprocessableEntityError('proof must have at least one step');
  }

  /// Create intermediary data list.
  final steps = new List<_StepData>();
  steps.add(new _StepData()
    ..position = 0
    ..type = StepType.setExpression
    ..expression = new Expr.fromBase64(body.steps.first.leftData));

  /// Flatten list of difference branches into a step list.
  for (final branch in body.steps) {
    if (new Expr.fromBase64(branch.leftData) != steps.last.expression) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      // Note: reverse flattened list so that position integers are unaffected.
      steps.addAll(_flattenDifferenceBranch(branch).reversed);

      // Use the right side of the branch to later validate that proof
      // reconstruction is correct.
      steps.last.expression = new Expr.fromBase64(branch.rightData);
    }
  }

  // Retrieve all rules at once.
  final ruleIds = steps.where((st) => st.ruleId != null).map((st) => st.ruleId);
  final rules = await s.selectByIds(db.rule, ruleIds);

  // Retrieve all rule expressions at once.
  final expressionIds = new List<int>();
  rules.forEach((rule) {
    expressionIds.add(rule.leftExpressionId);
    expressionIds.add(rule.rightExpressionId);
  });
  final expressions = await s.selectByIds(db.expression, expressionIds);

  // Build expression map.
  final expressionMap = new Map<int, Expr>.fromIterable(expressions,
      key: (expr) => expr.id, value: (expr) => new Expr.fromBase64(expr.data));

  // Add parsed rules to steps.
  steps.where((st) => st.ruleId != null).forEach((step) async {
    final rule = await s.selectById(db.rule, step.ruleId);
    step.rule = new Rule(expressionMap[rule.leftExpressionId],
        expressionMap[rule.rightExpressionId]);
  });

  // Retrieve rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Retrieve computable functions.
  final computable = await _loadComputableFunctions(s);
  final compute =
      (int id, List<num> args) => _exprCompute(id, args, computable);

  // Run through all steps.
  Expr expr;
  for (final step in steps) {
    // Apply step to [expr].
    expr = _computeProofStep(expr, step, rearrangeableIds, compute);

    // As a convention we evaluate the expression after each step.
    expr = expr.evaluate(compute);

    if (step.expression != null && step.expression.evaluate(compute) != expr) {
      // If an expression is already set for this step, it should be the same
      // after evaluation.
      throw new UnprocessableEntityError('proof reconstruction failed');
    }

    // Set/override the expression.
    step.expression = expr.clone();
  }

  // Insert all steps into database.
  final rows = new List<db.StepRow>();
  for (final step in steps) {
    final expressionRow = await _createExpression(s, step.expression);

    // Create map with insert values.
    final values = {
      'expression_id': expressionRow.id,
      'position': step.position,
      'step_type': step.typeString
    };
    if (rows.isNotEmpty) {
      values['previous_id'] = rows.last.id;
    }
    if (step.ruleId != null) {
      values['rule_id'] = step.ruleId;
    }
    if (step.rearrange != null) {
      values['rearrange'] = ARRAY(step.rearrange, 'integer');
    }

    rows.add(await s.insert(db.step, VALUES(values)));
  }

  final Map<String, dynamic> values = {
    'steps': ARRAY(rows.map((r) => r.id), 'integer')
  };
  return await s.insert(db.proof, VALUES(values));
}

/// Compute result of applying [step], given the [previous] expression. In some
/// cases the computation is backwards. This means the substitution that is
/// applied to [previous] is computed in part based on the resulting expression
/// (fetched from [DifferenceBranch.rightData]).
Expr _computeProofStep(Expr previous, _StepData step,
    List<int> rearrangeableIds, ExprCompute compute) {
  assert(step.type != null);
  switch (step.type) {
    case StepType.setExpression:
      return step.expression;

    case StepType.rearrange:
      return previous.rearrangeAt(
          step.rearrange, step.position, rearrangeableIds);

    case StepType.ruleNormal:
      return previous.substituteAt(step.rule, step.position);

    case StepType.ruleInvert:
      return previous.substituteAt(step.rule.inverted, step.position);

    case StepType.ruleMirror:
    case StepType.ruleRevert:
      final rule =
          step.type == StepType.ruleMirror ? step.rule : step.rule.inverted;

      // Reversed evaluation means that the right sub-expression at this
      // position is used to construct the original expression. When evaluated
      // this must match the expression in [previous] at the step position. From
      // this a new rule can be constructed to substitute the sub-expression
      // into [previous].

      final original = step.subExprRight.substituteAt(rule.inverted, 0);
      return previous.substituteAt(
          new Rule(original.evaluate(compute), step.subExprRight),
          step.position);

    default:
      throw new ArgumentError('unknown step type');
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
          ..position = rearrangement.position
          ..type = StepType.rearrange
          ..rearrange = rearrangement.format);
      }
    } else if (branch.rule != null) {
      // Add single step for rule.
      final step = new _StepData()
        ..position = branch.position
        ..ruleId = branch.rule.id
        ..subExprRight = new Expr.fromBase64(branch.rightData);

      // Determine rule type.
      if (!branch.reverseRule && !branch.reverseEvaluate) {
        step.type = StepType.ruleNormal;
      } else if (branch.reverseRule && !branch.reverseEvaluate) {
        step.type = StepType.ruleInvert;
      } else if (branch.reverseRule && branch.reverseEvaluate) {
        step.type = StepType.ruleMirror;
      } else {
        step.type = StepType.ruleRevert;
      }

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
