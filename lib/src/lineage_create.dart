// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class LineageCreateData {
  List<DifferenceBranch> steps;
}

enum LineageStepType {
  setExpression,
  rearrange,
  ruleNormal,
  ruleInvert,
  ruleMirror,
  ruleRevert
}

/// Intermediary data for building a lineage step.
/// The [DifferenceBranch] is first flattened into this class.
class LineageStepBuilder {
  LineageStepType type;
  int position;
  Expr subExprRight;
  Expr expression;
  List<int> rearrange;
  int ruleId;
  Rule rule;

  String get typeString => {
        LineageStepType.setExpression: 'set',
        LineageStepType.rearrange: 'rearrange',
        LineageStepType.ruleNormal: 'rule_normal',
        LineageStepType.ruleInvert: 'rule_invert',
        LineageStepType.ruleMirror: 'rule_mirror',
        LineageStepType.ruleRevert: 'rule_revert'
      }[type];
}

Future<db.LineageRow> createLineage(Session s, LineageCreateData body) async {
  if (body.steps.isEmpty) {
    throw new UnprocessableEntityError('lineage must have at least one step');
  }

  /// Create intermediary data list.
  final steps = new List<LineageStepBuilder>();
  steps.add(new LineageStepBuilder()
    ..position = 0
    ..type = LineageStepType.setExpression
    ..expression = new Expr.fromBase64(body.steps.first.leftData));

  /// Flatten list of difference branches into a step list.
  for (final branch in body.steps) {
    if (new Expr.fromBase64(branch.leftData) != steps.last.expression) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      // Note: reverse flattened list so that position integers are unaffected.
      steps.addAll(_flattenDifferenceBranch(branch).reversed);

      // Use the right side of the branch to later validate that lineage
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
    expr = computeLineageStep(expr, step, rearrangeableIds, compute);

    // As a convention we evaluate the expression after each step.
    expr = expr.evaluate(compute);

    if (step.expression != null && step.expression.evaluate(compute) != expr) {
      // If an expression is already set for this step, it should be the same
      // after evaluation.
      throw new UnprocessableEntityError('lineage reconstruction failed');
    }

    // Set/override the expression.
    step.expression = expr.clone();
  }

  // Insert all steps into database.
  final rows = new List<db.LineageStepRow>();
  for (final step in steps) {
    final expressionRow = await _createExpression(s, step.expression);

    // Create map with insert values.
    final values = {
      'expression_id': expressionRow.id,
      'position': step.position,
      'type': step.typeString
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

    rows.add(await s.insert(db.lineageStep, VALUES(values)));
  }

  return await s.insert(
      db.lineage, VALUES({'steps': ARRAY(rows.map((r) => r.id), 'integer')}));
}

/// Compute result of applying [step], given the [previous] expression. In some
/// cases the computation is backwards. This means the substitution that is
/// applied to [previous] is computed in part based on the resulting expression
/// (fetched from [DifferenceBranch.rightData]).
Expr computeLineageStep(Expr previous, LineageStepBuilder step,
    List<int> rearrangeableIds, ExprCompute compute) {
  assert(step.type != null);
  switch (step.type) {
    case LineageStepType.setExpression:
      return step.expression;

    case LineageStepType.rearrange:
      return previous.rearrangeAt(
          step.rearrange, step.position, rearrangeableIds);

    case LineageStepType.ruleNormal:
      return previous.substituteAt(step.rule, step.position);

    case LineageStepType.ruleInvert:
      return previous.substituteAt(step.rule.inverted, step.position);

    case LineageStepType.ruleMirror:
    case LineageStepType.ruleRevert:
      final rule = step.type == LineageStepType.ruleMirror
          ? step.rule
          : step.rule.inverted;

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

/// Flatten [branch] into a list of lineage steps.
List<LineageStepBuilder> _flattenDifferenceBranch(DifferenceBranch branch) {
  if (!branch.resolved) {
    throw new UnprocessableEntityError('contains unresolved steps');
  } else if (branch.different) {
    final steps = new List<LineageStepBuilder>();
    if (branch.rearrangements.isNotEmpty) {
      // Add step for each rearrangement.
      for (final rearrangement in branch.rearrangements) {
        steps.add(new LineageStepBuilder()
          ..position = rearrangement.position
          ..type = LineageStepType.rearrange
          ..rearrange = rearrangement.format);
      }
    } else if (branch.rule != null) {
      // Add single step for rule.
      final step = new LineageStepBuilder()
        ..position = branch.position
        ..ruleId = branch.rule.id
        ..subExprRight = new Expr.fromBase64(branch.rightData);

      // Determine rule type.
      if (!branch.reverseRule && !branch.reverseEvaluate) {
        step.type = LineageStepType.ruleNormal;
      } else if (branch.reverseRule && !branch.reverseEvaluate) {
        step.type = LineageStepType.ruleInvert;
      } else if (branch.reverseRule && branch.reverseEvaluate) {
        step.type = LineageStepType.ruleMirror;
      } else {
        step.type = LineageStepType.ruleRevert;
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
