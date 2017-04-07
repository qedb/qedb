// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class ExpressionDifferenceResource {
  ExpressionResource left;
  ExpressionResource right;
  DifferenceBranch difference;
}

class DifferenceBranch {
  bool resolved;
  bool different;
  bool rearrange;
  bool invertRule;
  RuleResource rule;
  List<DifferenceBranch> arguments;
}

Future<ExpressionDifferenceResource> resolveExpressionDifference(
    Session s, ExpressionDifferenceResource body) async {
  // Decode expressions.
  final left = new Expr.fromBase64(body.left.data);
  final right = new Expr.fromBase64(body.right.data);

  // Get rearrangeable functions.
  final rearrangeable =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Get computable functions via operator tables.
  // (it is reasonable to assume +-* are the operator characters)
  final compOps = await s.select(
      db.operator,
      WHERE({
        'character': IN(['+', '-', '*'])
      }));
  final compOpMap = new Map<String, int>.fromIterable(compOps,
      key: (db.OperatorRow row) => row.character,
      value: (db.OperatorRow row) => row.id);
  final computableFnIds = [compOpMap['+'], compOpMap['-'], compOpMap['*']];

  // Get difference tree.
  final result = getExpressionDiff(left, right, rearrangeable);

  // Resolve difference tree.
  if (result.numericInequality) {
    body.difference = new DifferenceBranch()
      ..different = true
      ..resolved = false;
  } else if (result.diff.different) {
    body.difference = await resolveTreeDiff(s, result.diff, computableFnIds);
  } else {
    body.difference = new DifferenceBranch()..different = false;
  }

  return body;
}

Future<DifferenceBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch, List<int> computableFnIds) async {
  final outputBranch = new DifferenceBranch();
  outputBranch.different = branch.different;
  outputBranch.rearrange = branch.rearranged;

  if (outputBranch.rearrange) {
    outputBranch.resolved = true;
    return outputBranch;
  } else if (outputBranch.different) {
    // Try to find rule.

    final exprParams = [
      ARRAY(branch.replaced.left.toArray(), 'integer'),
      ARRAY(branch.replaced.right.toArray(), 'integer')
    ];
    final ruleParams = [SQL('left_array_data'), SQL('right_array_data')];
    final computableIds = ARRAY(computableFnIds, 'integer');

    for (var i = 0; i < 4; i++) {
      final param12 = i < 2 ? exprParams : exprParams.reversed.toList();
      final param34 = i % 2 == 0 ? ruleParams : ruleParams.reversed.toList();
      final rules = await s.select(
          db.rule,
          SQL('WHERE'),
          FUNCTION('expr_match_rule', param12[0], param12[1], param34[0],
              param34[1], computableIds),
          LIMIT(1));

      if (rules.isNotEmpty) {
        outputBranch.invertRule == !(i % 2 == 0);
        outputBranch.resolved = true;
        outputBranch.rule = new RuleResource()..loadRow(rules.single, s.data);
        return outputBranch;
      }
    }

    // Fallback to processing individual arguments.
    if (branch.argumentDifference.isNotEmpty) {
      // Attempt to resolve all arguments.
      outputBranch.arguments = [];
      outputBranch.resolved = true;

      for (final argBranch in branch.argumentDifference) {
        if (argBranch.different) {
          final result = await resolveTreeDiff(s, argBranch, computableFnIds);
          outputBranch.arguments.add(result);

          if (!result.resolved) {
            outputBranch.resolved = false;
          }
        } else {
          outputBranch.arguments.add(new DifferenceBranch()..different = false);
        }
      }
    } else {
      outputBranch.resolved = false;
    }

    return outputBranch;
  } else {
    return outputBranch;
  }
}
