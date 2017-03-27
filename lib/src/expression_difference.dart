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
  bool different;
  bool unresolved;
  RuleResource rule;
  List<DifferenceBranch> arguments;
}

Future<ExpressionDifferenceResource> resolveExpressionDifference(
    Session s, ExpressionDifferenceResource body) async {
  // Decode expressions.
  final left = new Expr.fromBase64(body.left.data);
  final right = new Expr.fromBase64(body.left.data);

  // Get difference tree.
  final diff = getExpressionDiff(left, right);

  // Resolve difference tree.
  if (diff.numericInequality) {
    body.difference = new DifferenceBranch()
      ..different = true
      ..unresolved = true;
  } else if (diff.hasDiff) {
    body.difference = await resolveTreeDiff(s, diff.diff);
  } else {
    body.difference = new DifferenceBranch();
  }

  return body;
}

Future<DifferenceBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch) async {
  final outputBranch = new DifferenceBranch();
  outputBranch.different = branch.diff != null;

  if (outputBranch.different) {
    // Try to find matching rule in the database.
    final exprLeft = intarray(branch.diff.left.toArray()).sql;
    final exprRight = intarray(branch.diff.right.toArray()).sql;
    final rules = await ruleHelper.selectCustom(
        s,
        'expr_match_rule($exprLeft, $exprRight, left_array_data, right_array_data) LIMIT 1',
        {});

    if (rules.isNotEmpty) {
      outputBranch.unresolved = false;
      outputBranch.rule = new RuleResource()..loadRow(rules.single, s.data);
    } else {
      // Attempt to resolve all arguments.
      outputBranch.arguments = [];
      for (final arg in branch.arguments) {
        final result = await resolveTreeDiff(s, arg);
        outputBranch.arguments.add(result);

        if (result.unresolved) {
          outputBranch.unresolved = true;
        }
      }
    }
  }

  return outputBranch;
}
