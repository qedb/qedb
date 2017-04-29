// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class DifferenceRequest {
  @ApiProperty(required: true)
  String leftExpression;

  @ApiProperty(required: true)
  String rightExpression;
}

class DifferenceBranch {
  int position;
  String leftExpression;
  String rightExpression;
  bool resolved;
  bool different;
  bool reverseRule;
  bool reverseEvaluate;
  RuleResource rule;
  List<Rearrangement> rearrangements;
  List<DifferenceBranch> arguments;
}

/// Resolves difference between leftExpression and rightExpression.
Future<DifferenceBranch> resolveExpressionDifference(
    Session s, DifferenceRequest body) async {
  final left = new Expr.fromBase64(checkNull(() => body.leftExpression));
  final right = new Expr.fromBase64(checkNull(() => body.rightExpression));
  return _resolveExpressionDifference(s, left, right);
}

/// Resolves difference between [left] and [right].
Future<DifferenceBranch> _resolveExpressionDifference(
    Session s, Expr left, Expr right) async {
  // Get rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Get difference tree.
  final result = getExpressionDiff(left, right, rearrangeableIds);

  // Resolve difference tree.
  if (result.numericInequality) {
    return new DifferenceBranch()
      ..leftExpression = left.toBase64()
      ..rightExpression = right.toBase64()
      ..different = true
      ..resolved = false;
  } else {
    // Get computable functions.
    final comp = await _loadComputableFunctions(s);
    final computableIds = '+-*~'.split('').map((c) => comp[c]).toList();
    final compute = (int id, List<num> args) => _exprCompute(id, args, comp);
    return await resolveTreeDiff(s, result.branch, computableIds, compute);
  }
}

Future<DifferenceBranch> resolveTreeDiff(Session s, ExprDiffBranch branch,
    List<int> computableIds, ExprCompute compute) async {
  final outputBranch = new DifferenceBranch()
    ..position = branch.position
    ..leftExpression = branch.left.toBase64()
    ..rightExpression = branch.right.toBase64()
    ..different = branch.isDifferent
    ..resolved = false;

  if (!outputBranch.different) {
    outputBranch.resolved = true;
    return outputBranch;
  } else {
    // First check rearrangements.
    outputBranch.rearrangements = branch.rearrangements;
    if (outputBranch.rearrangements.isNotEmpty) {
      outputBranch.resolved = true;
      return outputBranch;
    } else {
      // Evaluate both sides.
      final left = branch.left.evaluate(compute);
      final right = branch.right.evaluate(compute);

      // If both sides are equal after evaluation, this branch is resolved.
      if (left == right) {
        outputBranch
          ..different = false
          ..resolved = true;

        return outputBranch;
      }

      // Search for a rule.
      // Rule searching parameters:
      final exprParams = [
        ARRAY(left.toArray(), 'integer'),
        ARRAY(right.toArray(), 'integer')
      ];
      final ruleParams = [SQL('left_array_data'), SQL('right_array_data')];
      final computableIdsArray = ARRAY(computableIds, 'integer');

      // Try to find rule (4 search methods: normal, invert, mirror, revert).
      for (var i = 0; i < 4; i++) {
        final param12 = i < 2 ? exprParams : exprParams.reversed.toList();
        final param34 = i % 2 == 0 ? ruleParams : ruleParams.reversed.toList();
        final rules = await s.select(
            db.rule,
            SQL('WHERE'),
            FUNCTION('expr_match_rule', param12[0], param12[1], param34[0],
                param34[1], computableIdsArray),
            LIMIT(1));

        if (rules.isNotEmpty) {
          outputBranch
            ..reverseRule = !(i % 2 == 0)
            ..reverseEvaluate = !(i < 2)
            ..rule = (new RuleResource()..loadRow(rules.single, s.data))
            ..resolved = true;

          return outputBranch;
        }
      }

      // Fallback to processing individual arguments.
      if (branch.argumentDifference.isNotEmpty) {
        outputBranch.arguments = await Future.wait(branch.argumentDifference
            .map((arg) => resolveTreeDiff(s, arg, computableIds, compute)));
        outputBranch.resolved =
            outputBranch.arguments.every((arg) => arg.resolved);
      }

      return outputBranch;
    }
  }
}
