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
  bool invertRule;
  RuleResource rule;
  List<DifferenceBranch> arguments;
}

Future<ExpressionDifferenceResource> resolveExpressionDifference(
    Session s, ExpressionDifferenceResource body) async {
  // Decode expressions.
  final left = new Expr.fromBase64(body.left.data);
  final right = new Expr.fromBase64(body.right.data);

  // Get difference tree.
  final result = getExpressionDiff(left, right);

  // Resolve difference tree.
  if (result.numericInequality) {
    body.difference = new DifferenceBranch()
      ..different = true
      ..resolved = false;
  } else if (result.diff.different) {
    body.difference = await resolveTreeDiff(s, result.diff);
  } else {
    body.difference = new DifferenceBranch()..different = false;
  }

  return body;
}

Future<DifferenceBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch) async {
  final outputBranch = new DifferenceBranch();
  outputBranch.different = branch.different;

  if (outputBranch.different) {
    // Try to find matching rule in the database.
    final exprLeft = intarray(branch.diff.left.toArray()).sql;
    final exprRight = intarray(branch.diff.right.toArray()).sql;

    // TODO: add option to override this via the configuration file.
    final computableIds = intarray([1, 2, 3]).sql;

    final selectRule = (String where) async =>
        await ruleHelper.selectCustom(s, '$where LIMIT 1', {});

    // Select rule (non-inverted or inverted).
    // TODO: this can be done in 4 ways (the input can also be inverted for
    // evaluation in the other direction)
    var rules = await selectRule(
        'expr_match_rule($exprLeft, $exprRight, left_array_data, right_array_data, $computableIds)');
    if (rules.isEmpty) {
      rules = await selectRule(
          'expr_match_rule($exprLeft, $exprRight, right_array_data, left_array_data, $computableIds)');
      if (rules.isNotEmpty) {
        outputBranch.invertRule = true;
      }
    } else {
      outputBranch.invertRule = false;
    }

    if (rules.isNotEmpty) {
      outputBranch.resolved = true;
      outputBranch.rule = new RuleResource()..loadRow(rules.single, s.data);
    } else {
      if (branch.arguments.isNotEmpty) {
        // Attempt to resolve all arguments.
        outputBranch.arguments = [];
        outputBranch.resolved = true;

        for (final arg in branch.arguments) {
          if (arg.different) {
            final result = await resolveTreeDiff(s, arg);
            outputBranch.arguments.add(result);

            if (!result.resolved) {
              outputBranch.resolved = false;
            }
          } else {
            outputBranch.arguments
                .add(new DifferenceBranch()..different = false);
          }
        }
      } else {
        outputBranch.resolved = false;
      }
    }
  }

  return outputBranch;
}
