// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

Future<db.StepRow> readStep(Session s, int id) async {
  return (await _listStepsById(s, [id])).single;
}

Future<List<db.StepRow>> _listStepsById(Session s, List<int> ids) async {
  final steps = await s.selectByIds(db.step, ids);
  await listExpressions(s, steps.map((step) => step.expressionId));
  return steps;
}

Future<List<db.StepRow>> _listStepsBetween(Session s, int from, int to) async {
  final steps = await s.run(
      db.step,
      WITH_RECURSIVE(
          SQL('pointer'),
          AS(
              SQL('SELECT * FROM step'),
              WHERE({'id': IS(to)}),
              UNION_ALL(
                  SQL('SELECT step.* FROM step, pointer'),
                  WHERE({
                    'step.id': IS(SQL('pointer.previous_id')),
                    'pointer.id': IS_NOT(from)
                  })))),
      SQL('SELECT * FROM pointer'));

  return steps.reversed.toList();
}

/// Find conditions that have not been satisfied by a proof within the given
/// range of steps. It is not validated if the given step IDs belong together.
/// The returned substitution IDs are not ordered.
Future<List<int>> _findConditions(Session s, Iterable<int> stepIds) async {
  // Rule conditions that are adopted into the proof.
  final adoptedConditions = await s.select(
      db.ruleCondition,
      WHERE({
        'id': IN(SUBQUERY(SQL('SELECT condition_id FROM condition_proof'),
            WHERE({'step_id': IN(stepIds), 'adopt_condition': IS(true)})))
      }));

  // Free substitutions become conditions for applying the proof.
  final freeSubstitutions =
      await s.select(db.step, WHERE({'substitution_id': NOTNULL}));

  final subsIds = new List<int>();
  subsIds.addAll(adoptedConditions.map((cond) => cond.substitutionId));
  subsIds.addAll(freeSubstitutions.map((step) => step.substitutionId));

  return subsIds;
}
