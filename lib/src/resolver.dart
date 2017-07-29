// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class ResolveRequest {
  @ApiProperty(required: true)
  RpcSubs target;

  @ApiProperty(required: true)
  List<RpcSubs> freeConditions;
}

class ResolveBranch {
  int position;
  RpcSubs subs;
  bool resolved;
  bool different;

  /// Matching substitution.
  SubsSearchResult substitution;

  /// Queue of rearrangements.
  List<Rearrangement> rearrangements;

  /// Branch for each argument
  List<ResolveBranch> arguments;
}

/// Resolve difference between left and right side of a given substitution.
Future<ResolveBranch> resolveSubstitution(
    Session s, ResolveRequest body) async {
  // Add free conditions to substitution table for this session.
  // (if the substitution table would be retained across sessions, it would be
  // neccesary to rollback these additions, currently the table is part of the
  // session data which is reconstructed for every request).
  for (var i = 0; i < body.freeConditions.length; i++) {
    // The free condition left/right side may be empty (to be easily integrated
    // into the editor).
    final fc = body.freeConditions[i];
    if (fc.left.isNotEmpty && fc.right.isNotEmpty) {
      s.substitutionTable.entries
          .add(new SubsEntry.from(i, SubsType.free, fc.toSubs(), []));
    }
  }

  // Unpack left and right expression and resolve difference.
  return _resolveSubstitution(s, body.target.toSubs());
}

/// Resolves difference between [subs] left and right.
Future<ResolveBranch> _resolveSubstitution(Session s, Subs subs) async {
  // If the substitution table does not yet contain rules, first load all rules
  // from the database.
  if (s.substitutionTable.entries.every((elm) => elm.type != SubsType.rule)) {
    await s.substitutionTable.loadRules(s);
  }

  // Get rearrangeable functions.
  final rearrangeableIds =
      await s.selectIds(db.function, WHERE({'rearrangeable': IS(true)}));

  // Get difference tree.
  final result = getExpressionDiff(subs.left, subs.right, rearrangeableIds);

  // Resolve difference tree.
  if (result.numericInequality) {
    return new ResolveBranch()
      ..subs = new RpcSubs.from(subs)
      ..different = true
      ..resolved = false;
  } else {
    num compute(int id, List<num> args) => _exprCompute(s, id, args);
    return await resolveTreeDiff(s, result.branch, compute);
  }
}

Future<ResolveBranch> resolveTreeDiff(
    Session s, ExprDiffBranch branch, ExprCompute compute) async {
  final outputBranch = new ResolveBranch()
    ..position = branch.position
    ..subs = new RpcSubs.from(new Subs(branch.left, branch.right))
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

      // Find matching substitution using the substitution table.
      final result = s.substitutionTable.searchSubstitution(
          s,
          new Subs(left, right),
          [SubsType.rule, SubsType.free],
          [SubsType.rule, SubsType.free],
          1);

      if (result != null) {
        outputBranch
          ..substitution = result
          ..resolved = true;
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
