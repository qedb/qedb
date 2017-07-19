// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

class SubstitutionTable {
  final entries = new List<ConditionalSubstitutionEntry>();

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
    final ruleConditions = new Map<int, List<SubstitutionEntry>>();
    for (final condition in conditions) {
      ruleConditions.putIfAbsent(
          condition.ruleId, () => new List<SubstitutionEntry>());
      ruleConditions[condition.ruleId].add(new SubstitutionEntry(
          subss[condition.substitutionId],
          SubstitutionType.condition,
          condition.id));
    }

    // Add entry for each rule.
    for (final rule in rules) {
      entries.add(new ConditionalSubstitutionEntry(subss[rule.substitutionId],
          SubstitutionType.rule, rule.id, ruleConditions[rule.id] ?? []));
    }
  }

  /// Search for first entry that matches the given [substitution]. Returns null
  /// if nothing is found.
  SubstitutionSearchResult searchSubstitution(Session s, Subs substitution) {
    // Computing closure.
    num compute(int id, List<num> args) => _exprCompute(s, id, args);

    // Simply loop through all [entries] and match in 4 ways.
    for (final entry in entries) {
      reverseSearch:
      for (var i = 0; i < 4; i++) {
        final rSides = i % 2 != 0;
        final rEval = i >= 2;

        final sub = rEval ? substitution.inverted : substitution;
        final pat = rSides ? entry.substitution.inverted : entry.substitution;

        // Compare substitution with pattern.
        if (compareSubstitutions(sub, pat, compute)) {
          // A match was found!
          // Recursively call this function for all conditions.
          final conditionProofs = new List<SubstitutionSearchResult>();
          for (final condition in entry.conditions) {
            final result = searchSubstitution(s, condition.substitution);
            if (result == null) {
              // Condition cannot be resolved: continue outer loop.
              continue reverseSearch;
            } else {
              conditionProofs.add(result);
            }
          }

          // Return result.
          return new SubstitutionSearchResult(
              entry, conditionProofs, rSides, rEval);
        }
      }
    }

    // Nothing was found.
    return null;
  }
}

enum SubstitutionType { rule, condition, proof, free }

class SubstitutionEntry {
  final Subs substitution;
  final SubstitutionType type;
  final int referenceId;

  SubstitutionEntry(this.substitution, this.type, this.referenceId);
}

class ConditionalSubstitutionEntry extends SubstitutionEntry {
  final List<SubstitutionEntry> conditions;

  ConditionalSubstitutionEntry(Subs substitution, SubstitutionType type,
      int referenceId, this.conditions)
      : super(substitution, type, referenceId);
}

class SubstitutionSearchResult {
  final SubstitutionEntry entry;
  final List<SubstitutionSearchResult> conditionProofs;
  final bool reverseSides;
  final bool reverseEvaluate;

  SubstitutionSearchResult(this.entry, this.conditionProofs, this.reverseSides,
      this.reverseEvaluate);
}
