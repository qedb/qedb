// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class DifferenceRequest {
  @ApiProperty(required: true)
  String leftExpression;

  @ApiProperty(required: true)
  String rightExpression;

  @ApiProperty(required: true)
  List<int> proofIds;

  @ApiProperty(required: true)
  List<FreeSubstituion> freeSubstitutions;
}

class FreeSubstituion {
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

  bool reverseSides;
  bool reverseEvaluate;
  RuleResource rule;

  List<Rearrangement> rearrangements;
  List<DifferenceBranch> arguments;

  Expr get leftExpr => new Expr.fromBase64(leftExpression);
  Expr get rightExpr => new Expr.fromBase64(rightExpression);
}

class RuleConditionProof {
  int conditionId;
  RuleResource followsRule;
  ProofResource followsProof;
  bool selfEvident;
}

/// Resolves difference between leftExpression and rightExpression.
Future<DifferenceBranch> resolveExpressionDifference(
    Session s, DifferenceRequest body) async {
  await s.substitutionTable.loadRules(s);
  final left = new Expr.fromBase64(body.leftExpression);
  final right = new Expr.fromBase64(body.rightExpression);
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
    num compute(int id, List<num> args) => _exprCompute(s, id, args);
    return await resolveTreeDiff(s, result.branch, compute);
  }
}

Future<DifferenceBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch, ExprCompute compute,
    [bool useSubstitutionTable = true]) async {
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

      if (useSubstitutionTable) {
        // Find matching substitution using the substitution table.
        final result =
            s.substitutionTable.searchSubstitution(s, new Subs(left, right));

        if (result != null) {
          outputBranch
            ..reverseSides = result.reverseSides
            ..reverseEvaluate = result.reverseEvaluate
            ..rule = new RuleResource().load(result.entry.referenceId, s.data)
            ..resolved = true;
        }
      } else {
        // Find matching substitution in the rule set with _findSubstitutions.
        final results = await findSubstitutions(s, new Subs(left, right),
            subset: SUBQUERY(SQL('SELECT substitution_id FROM rule')),
            returnFirst: true);

        if (results.isNotEmpty) {
          final result = results.first;
          final rule = await s.selectOne(
              db.rule, WHERE({'substitution_id': IS(result.substitution.id)}));

          outputBranch
            ..reverseSides = result.reverseSides
            ..reverseEvaluate = result.reverseEvaluate
            ..rule = (new RuleResource()..loadRow(rule, s.data))
            ..resolved = true;

          return outputBranch;
        }
      }

      // Fallback to processing individual arguments.
      if (branch.argumentDifference.isNotEmpty) {
        outputBranch.arguments = await Future.wait(branch.argumentDifference
            .map((arg) => resolveTreeDiff(s, arg, compute)));
        outputBranch.resolved =
            outputBranch.arguments.every((arg) => arg.resolved);
      }

      return outputBranch;
    }
  }
}
