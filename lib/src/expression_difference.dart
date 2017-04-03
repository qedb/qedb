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
      (await functionHelper.select(s, {'rearrangeable': true}))
          .map((row) => row.id)
          .toList();

  // Get computable functions via operator tables.
  // (it is reasonable to assume +-* are the operator characters)
  final compOpMap = new Map<String, int>.fromIterable(
      await operatorHelper.selectIn(s, {
        'character': ["'+'", "'-'", "'*'"]
      }),
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
  outputBranch.rearrange = branch.rearrangeable;

  if (outputBranch.rearrange) {
    outputBranch.resolved = true;
    return outputBranch;
  } else if (outputBranch.different) {
    // Get array data SQL statements.
    final exprLeft = intarray(branch.replace.left.toArray()).sql;
    final exprRight = intarray(branch.replace.right.toArray()).sql;
    final computableIds = intarray(computableFnIds).sql;

    // Closure around function to find matching rule in the database.
    final selectRule = (List<String> params) async => await ruleHelper
        .selectCustom(s, 'expr_match_rule(${params.join(',')}) LIMIT 1', {});

    // Try to find rule.
    final exprParams = [exprLeft, exprRight];
    final ruleParams = ['left_array_data', 'right_array_data'];

    for (var i = 0; i < 4; i++) {
      final rules = await selectRule([]
        ..addAll(i < 2 ? exprParams : exprParams.reversed.toList())
        ..addAll(i % 2 == 0 ? ruleParams : ruleParams.reversed.toList())
        ..add(computableIds));

      if (rules.isNotEmpty) {
        outputBranch.invertRule == !(i % 2 == 0);
        outputBranch.resolved = true;
        outputBranch.rule = new RuleResource()..loadRow(rules.single, s.data);
        return outputBranch;
      }
    }

    // Fallback to processing individual arguments.
    if (branch.arguments.isNotEmpty) {
      // Attempt to resolve all arguments.
      outputBranch.arguments = [];
      outputBranch.resolved = true;

      for (final arg in branch.arguments) {
        if (arg.different) {
          final result = await resolveTreeDiff(s, arg, computableFnIds);
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
