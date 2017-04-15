// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class DifferenceBranch {
  int position;
  String leftData;
  String rightData;
  bool resolved;
  bool different;
  bool reverseRule;
  bool reverseEvaluate;
  RuleResource rule;
  List<Rearrangement> rearrangements;
  List<DifferenceBranch> arguments;
}

Future<DifferenceBranch> resolveExpressionDifference(
    Session s, DifferenceBranch body) async {
  // Decode expressions.
  final left = new Expr.fromBase64(body.leftData);
  final right = new Expr.fromBase64(body.rightData);

  // Get rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Get computable functions.
  final computable = await _loadComputableFunctions(s);
  final computableIds = '+-*~'.split('').map((c) => computable[c]).toList();

  /// Note: a general conventions is to evaluate expressions before comparing.
  /// This way a matching rule can be found in more cases. Additionally no
  /// ambiguous rearrangements will be added.
  ///
  /// Background: the rule scanning function can also evaluate expressions, so
  /// that `diff(x,x^3) => 3x^2` can be matched with
  /// `diff(?x,?x^?n) => ?n?x^(?n-1)`. However, there is a limitation. The rule
  /// matching function cannot evaluate generics that map to a function. So in
  /// order to match `diff(x,x^(2+1))) => 3x^2` it is necessary to evaluate the
  /// expression first.

  final compute =
      (int id, List<num> args) => _exprCompute(id, args, computable);

  // Get difference tree.
  final result = getExpressionDiff(
      left.evaluate(compute), right.evaluate(compute), rearrangeableIds);

  // Resolve difference tree.
  if (result.numericInequality) {
    return new DifferenceBranch()
      ..leftData = body.leftData
      ..rightData = body.rightData
      ..different = true
      ..resolved = false;
  } else {
    return await resolveTreeDiff(s, result.branch, computableIds);
  }
}

Future<DifferenceBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch, List<int> computableIds) async {
  final outputBranch = new DifferenceBranch()
    ..position = branch.position
    ..leftData = branch.left.toBase64()
    ..rightData = branch.right.toBase64()
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
      // Search for a rule.
      // Rule searching parameters:
      final exprParams = [
        ARRAY(branch.left.toArray(), 'integer'),
        ARRAY(branch.right.toArray(), 'integer')
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
            .map((arg) => resolveTreeDiff(s, arg, computableIds)));
        outputBranch.resolved =
            outputBranch.arguments.every((arg) => arg.resolved);
      }

      return outputBranch;
    }
  }
}
