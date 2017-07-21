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
  SubstitutionSearchResult searchSubstitution(Session s, Subs substitution,
      [int conditionDepthCutoff = 1]) {
    // Computing closure.
    num compute(int id, List<num> args) => _exprCompute(s, id, args);

    // Simply loop through all [entries] and match in 4 ways.
    for (final entry in entries) {
      // If this entry has conditions but the [conditionDepthCutoff] <= 0, skip
      // to the next entry.
      if (entry.conditions.isNotEmpty && conditionDepthCutoff <= 0) {
        continue;
      }

      reverseSearch:
      for (var i = 0; i < 4; i++) {
        final rItself = i % 2 != 0;
        final rTarget = i >= 2;

        final pat = rItself ? entry.substitution.inverted : entry.substitution;
        final sub = rTarget ? substitution.inverted : substitution;

        // Compare substitution with pattern.
        if (compareSubstitutions(sub, pat, compute)) {
          // A match was found!
          // Recursively call this function for all conditions.
          final conditionProofs = new List<ConditionSearchResult>();
          for (final condition in entry.conditions) {
            final result = searchSubstitution(
                s, condition.substitution, conditionDepthCutoff - 1);
            if (result == null) {
              // Condition cannot be resolved: continue outer loop.
              continue reverseSearch;
            } else {
              conditionProofs.add(new ConditionSearchResult(condition, result));
            }
          }

          // Return result.
          return new SubstitutionSearchResult(
              entry, conditionProofs, rItself, rTarget);
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
  final List<ConditionSearchResult> conditionProofs;
  final bool reverseItself;
  final bool reverseTarget;

  SubstitutionSearchResult(
      this.entry, this.conditionProofs, this.reverseItself, this.reverseTarget);
}

class ConditionSearchResult {
  final SubstitutionEntry condition;
  final SubstitutionSearchResult result;

  ConditionSearchResult(this.condition, this.result);
}
