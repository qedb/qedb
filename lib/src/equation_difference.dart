// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

/*class EquationDifferenceResource {
  ExpressionResource left;
  ExpressionResource right;
  DifferenceBranch difference;
}

class DifferenceBranch {
  List<RuleResource> rules;
  List<DifferenceBranch> arguments;
  bool unresolved;
}

Future<EquationDifferenceResource> resolveEquationDifference(
    Session s, EquationDifferenceResource body) async {
  // Decode expressions.
  final left = new Expr.fromBase64(body.left.data);
  final right = new Expr.fromBase64(body.left.data);

  // Get difference tree.
  final diff = buildEqDiff(left, right);

  // Resolve difference tree.
  if (diff.numericInequality) {
    body.difference = new DifferenceBranch()..unresolved = true;
  } else if (diff.hasDiff) {
    body.difference = await resolveTreeDiff(s, diff.diff);
  } else {
    body.difference = new DifferenceBranch();
  }

  return body;
}

Future<DifferenceBranch> resolveTreeDiff(Session s, EqDiffBranch branch) async {
  final outputBranch = new DifferenceBranch();
  final rules = await resolveRules(s, branch.diff);

  if (rules.isNotEmpty) {
    outputBranch.rules = rules;
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

  return outputBranch;
}

/// Naive implementation:
///
/// + For both left and right side:
/// + Select expressions that are in a rule and share the same node value.
/// + Filter this set of expressions against the full expression pattern.
/// + Pair expressions to form rules.
/// + Evaluate rules to check which fit.
///
Future<List<RuleResource>> resolveRules(Session s, Eq target) async {
  final left = target.left;

  final leftExprs = await expressionHelper.selectCustom(
      s,
      '''
id IN (SELECT left_expression_id FROM rule
 UNION SELECT right_expression_id FROM rule)
AND ((node_type = @node_type AND node_value = @node_value)
OR node_type = 'generic')''',
      selectExpr(left));

  // Filter left expressions.
  final leftList = new List<db.ExpressionRow>();
  for (final row in leftExprs) {
    if (await exprGenericMatch(s, left, row)) {
      leftList.add(row);
    }
  }
}

Map<String, dynamic> selectExpr(Expr target) {
  if (target is NumberExpr) {
    return {'node_type': 'integer', 'node_value': target.value};
  } else if (target is FunctionSymbolExpr) {
    return {
      'node_type': target.isGeneric ? 'generic' : 'function',
      'node_value': target.id
    };
  } else {
    throw new ArgumentError('unsupported Expr format');
  }
}

Future<bool> exprGenericMatch(
    Session s, Expr target, db.ExpressionRow input) async {
  if (input.nodeType == 'generic') {
    return true;
  } else if (target is NumberExpr) {
    return input.nodeType == 'integer' && input.nodeValue == target.value;
  } else if (target is SymbolExpr) {
    return input.nodeType == 'function' && input.nodeValue == target.id;
  } else if (target is FunctionExpr) {
    if (input.nodeType == 'function' &&
        input.nodeValue == target.id &&
        input.nodeArguments.length == target.args.length) {
      // Match all arguments.
      final arguments =
          await expressionHelper.selectIn(s, {'id': input.nodeArguments});
      for (var i = 0; i < arguments.length; i++) {
        if (!await exprGenericMatch(s, target.args[i], arguments[i])) {
          return false;
        }
      }
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}*/
