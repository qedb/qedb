// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class SubstitutionTable {
  final entries = new List<SubstitutionEntry>();

  /// Load rules from database.
  Future loadRules(Session s) async {
    final rules = await s.select(db.rule);
    final conditions = await s.select(db.ruleCondition);
    conditions.sort((a, b) => a.id - b.id);
    final substitutionIds = new List<int>();
    substitutionIds.addAll(rules.map((r) => r.substitutionId));
    substitutionIds.addAll(conditions.map((c) => c.substitutionId));
    final subss = await getSubsMap(s, substitutionIds);

    // Collect conditions into map.
    final ruleConditions = new Map<int, List<Subs>>();
    for (final condition in conditions) {
      ruleConditions.putIfAbsent(condition.ruleId, () => new List<Subs>());
      ruleConditions[condition.ruleId].add(subss[condition.substitutionId]);
    }

    // Add entry for each rule.
    for (final rule in rules) {
      entries.add(new SubstitutionEntry(subss[rule.substitutionId],
          ruleConditions[rule.id], SubstitutionType.rule, rule.id));
    }
  }

  /// Search for first entry that matches the given [substitution]. Returns null
  /// if nothing is found.
  SubstitutionSearchResult searchSubstitution(Subs substitution) {}
}

enum SubstitutionType { rule, proof, free }

class SubstitutionEntry {
  final Subs substitution;
  final List<Subs> conditions;
  final SubstitutionType type;
  final int referenceId;

  SubstitutionEntry(
      this.substitution, this.conditions, this.type, this.referenceId);
}

class SubstitutionSearchResult {
  final SubstitutionEntry entry;
  final List<SubstitutionSearchResult> conditionProofs;
  final bool reverseSides;
  final bool reverseEvaluate;

  SubstitutionSearchResult(this.entry, this.conditionProofs, this.reverseSides,
      this.reverseEvaluate);
}
