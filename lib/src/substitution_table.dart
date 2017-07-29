// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class SubstitutionTable {
  final entries = new List<SubsEntry>();

  /// Load rules from database.
  /// Note that this function will not check for existing duplicates.
  Future loadRules(Session s) async {
    final rules = await s.select(db.rule);
    final conditions = await s.select(db.ruleCondition);
    conditions.sort((a, b) => a.id - b.id);
    final substitutionIds = new List<int>();
    substitutionIds.addAll(rules.map((r) => r.substitutionId));
    substitutionIds.addAll(conditions.map((c) => c.substitutionId));
    final subss = await getSubsMap(s, substitutionIds);

    // Collect conditions into map.
    final ruleConditions = new Map<int, List<SubsCondition>>();
    for (final condition in conditions) {
      ruleConditions.putIfAbsent(
          condition.ruleId, () => new List<SubsCondition>());
      ruleConditions[condition.ruleId].add(new SubsCondition.from(
          condition.id, subss[condition.substitutionId]));
    }

    // Add entry for each rule.
    for (final rule in rules) {
      entries.add(new SubsEntry.from(rule.id, SubsType.rule,
          subss[rule.substitutionId], ruleConditions[rule.id] ?? []));
    }
  }

  /// Search for first entry that matches the given [substitution]. Returns null
  /// if nothing is found.
  SubsSearchResult searchSubstitution(Session s, Subs substitution,
      List<SubsType> use, List<SubsType> useForConditions,
      [int conditionDepthCutoff = 1, bool isCondition = false]) {
    num compute(int id, List<num> args) => _exprCompute(s, id, args);

    // Simply loop through all [entries] and match in 4 ways.
    for (final entry in entries) {
      // If this entry has conditions but the [conditionDepthCutoff] <= 0, skip
      // to the next entry. Also skip if ![isCondition] and [use] specifies we
      // do not want this entry type for normal matching or [isCondition] and
      // [useForConditions] specifies we do not want this type for condition
      // proofs.
      if ((entry.conditions.isNotEmpty && conditionDepthCutoff <= 0) ||
          (!isCondition && !use.contains(entry.type)) ||
          (isCondition && !useForConditions.contains(entry.type))) {
        continue;
      }

      reverseSearch:
      for (var i = 0; i < 4; i++) {
        final rItself = i % 2 != 0;
        final rTarget = i >= 2;

        final pat = rItself ? entry.subs.inverted : entry.subs;
        final sub = rTarget ? substitution.inverted : substitution;

        // Compare substitution with pattern.
        try {
          final mapping = new ExprMapping();
          var isMatch = false;

          // Free substitutions must match exactly (no mapping).
          if (entry.type == SubsType.free) {
            isMatch = sub == pat;
          } else {
            isMatch = compareSubstitutions(sub, pat, compute, mapping);
          }

          if (isMatch) {
            // A match was found!
            // Recursively call this function for all conditions.
            final conditionProofs = new List<SubsSearchResult>();
            for (final condition in entry.conditions) {
              final remappedSubs = condition.subs.remap(mapping);
              final result = searchSubstitution(s, remappedSubs, use,
                  useForConditions, conditionDepthCutoff - 1, true);
              if (result != null) {
                conditionProofs.add(result);
              } else {
                // Condition cannot be resolved: continue outer loop.
                continue reverseSearch;
              }
            }

            // Return result.
            return new SubsSearchResult.from(
                entry, conditionProofs, rItself, rTarget);
          }
        } on EqLibException {
          // An exception is thrown if during remapping there is an eqlib strict
          // mode violation (see eqlib ExprMapping source).
          continue;
        }
      }
    }

    // Nothing was found.
    return null;
  }
}

// Note: in order to reduce the number of classes required, the following
// classes are compatible with the rpc package so they can directly be used in
// the resolver API response.

/// Types of substitutions that can be used to resolve a substitution. We avoid
/// using an enum because the rpc package cannot handle enums.
class SubsType {
  @ApiProperty(required: true)
  int index;

  SubsType();
  SubsType._(this.index);

  static final rule = new SubsType._(0);
  static final proof = new SubsType._(1);
  static final free = new SubsType._(2);
  static final builtin = new SubsType._(3);

  @override
  bool operator ==(other) => other is SubsType && other.index == index;

  @override
  int get hashCode => index;
}

/// Entry in the list of all known substitutions
class SubsEntry {
  int referenceId;
  SubsType type;

  @ApiProperty(ignore: true)
  Subs subs;

  List<SubsCondition> conditions;

  SubsEntry();
  SubsEntry.from(this.referenceId, this.type, this.subs, this.conditions);
}

/// Substitution condition for [SubsEntry]
class SubsCondition {
  int id;

  @ApiProperty(ignore: true)
  Subs subs;

  SubsCondition();
  SubsCondition.from(this.id, this.subs);
}

/// Result data when searching for a substitution.
class SubsSearchResult {
  SubsEntry entry;
  List<SubsSearchResult> conditionProofs;
  bool reverseItself;
  bool reverseTarget;

  SubsSearchResult();
  SubsSearchResult.from(
      this.entry, this.conditionProofs, this.reverseItself, this.reverseTarget);
}
