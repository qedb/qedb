// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class LineageCreateData {
  List<ExpressionDifferenceResource> steps;
}

Future<db.LineageRow> createLineage(Session s, LineageCreateData body) async {
  if (body.steps.length < 2) {
    throw new UnprocessableEntityError('lineage must have multiple steps');
  }

  final steps = new List<LineageStepResource>();
  steps.add(new LineageStepResource()
    ..type = 'set'
    ..expression = body.steps.first.left);

  var previousExpression = steps.first.expression;
  for (final difference in body.steps) {
    if (difference.left.data != previousExpression.data) {
      throw new UnprocessableEntityError('steps do not connect');
    } else {
      steps.addAll(_diffBranchToSteps(difference.branch));
      steps.last.expression = difference.left;
      previousExpression = steps.last.expression;
    }
  }

  // Retrieve rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Retrieve all rules that are in the steps.
  final ruleIds = new List<int>();
  steps.forEach((step) => step.rule != null ? ruleIds.add(step.rule.id) : null);
  final rules = await s.selectByIds(db.rule, ruleIds);

  // Retrieve all expressions that are in the rules.
  final expressionIds = new List<int>();
  rules.forEach((rule) =>
      expressionIds..add(rule.leftExpressionId)..add(rule.rightExpressionId));
  final expressions = await s.selectByIds(db.expression, expressionIds);

  // Build expression map.
  final expressionMap = new Map<int, Expr>.fromIterable(expressions,
      key: (expr) => expr.id, value: (expr) => new Expr.fromBase64(expr.data));

  // Run through all steps.
  Expr expr;
  var previousCategoryId;
  final stepExpressions = new List<Expr>();
  for (final step in steps) {
    // Apply step to expr.
    expr = computeLineageStep(expr, step, expressionMap, rearrangeableIds);
    stepExpressions.add(expr);

    // If an expression is set for this step, check if it is the same.
    if (step.expression != null && step.expression.data != expr.toBase64()) {
      throw new UnprocessableEntityError('lineage reconstruction failed');
    }

    // Resolve step category.
    // category ID = lowest{lowest{functions}, previous step, rule category}
    final functionIds = exprCodecEncode(expr).functionIds;
    final exprCategoryId = (await findCategoryLineage(s, functionIds)).last;

    step.category = new CategoryResource();
    step.category.id = previousCategoryId != null
        ? await getLowestCategory(s, exprCategoryId, previousCategoryId)
        : exprCategoryId;
    if (step.rule != null) {
      step.category.id = await getLowestCategory(
          s, step.category.id, (await s.selectById(db.rule, step.rule.id)).id);
    }

    previousCategoryId = step.category.id;
  }

  // Insert all steps into database.
  var previousStepId;
  final rows = new List<db.LineageStepRow>();
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final expression = await _createExpression(s, stepExpressions[i]);
    final row = await s.insert(
        db.lineageStep,
        VALUES({
          'previous_id': previousStepId,
          'category_id': step.category.id,
          'expression_id': expression.id,
          'type': step.type,
          'position': step.position,
          'rule_id': step.rule != null ? step.rule.id : null,
          'invert_rule': step.invertRule,
          'rearrange': step.rearrange
        }));
    rows.add(row);
    previousStepId = row.id;
  }

  return await s.insert(
      db.lineage, VALUES({'steps': ARRAY(rows.map((r) => r.id), 'integer')}));
}

/// Compute result of applying [step] to [expr].
Expr computeLineageStep(Expr expr, LineageStepResource step,
    Map<int, Expr> ruleExpressions, List<int> rearrangeableIds) {
  if (step.type == 'set') {
    return new Expr.fromBase64(step.expression.data);
  } else if (step.type == 'rule') {
    final l = ruleExpressions[step.rule.leftExpression.id];
    final r = ruleExpressions[step.rule.rightExpression.id];
    final rule = step.invertRule ? new Rule(r, l) : new Rule(l, r);
    return expr.substituteAt(rule, step.position);
  } else if (step.type == 'rearrange') {
    return expr.rearrangeAt(step.rearrange, step.position, rearrangeableIds);
  } else {
    throw new ArgumentError('unknown step type');
  }
}

/// Flatten [branch] into a list of lineage steps.
List<LineageStepResource> _diffBranchToSteps(DifferenceBranch branch) {
  if (!branch.resolved) {
    throw new UnprocessableEntityError('contains unresolved steps');
  } else if (branch.different) {
    final steps = new List<LineageStepResource>();
    if (branch.rearrangements.isNotEmpty) {
      // Add step for each rearrangement.
      for (final rearrangement in branch.rearrangements) {
        steps.add(new LineageStepResource()
          ..type = 'rearrange'
          ..position = rearrangement.position
          ..rearrange = rearrangement.format);
      }
    } else if (branch.rule != null) {
      // Add single step for rule.
      steps.add(new LineageStepResource()
        ..type = 'rule'
        ..position = branch.position
        ..rule = branch.rule
        ..invertRule = branch.invertRule);
    } else {
      // Add steps for each argument.
      for (final argument in branch.arguments) {
        steps.addAll(_diffBranchToSteps(argument));
      }
    }

    return steps;
  } else {
    return [];
  }
}
