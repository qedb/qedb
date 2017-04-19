// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<List<db.LineageRow>> listLineages(Session s) async {
  // List all lineages.
  final lineages = await s.select(db.lineage);

  // List all first and last steps.
  final steps = new List<int>();
  lineages.forEach(
      (lineage) => steps..add(lineage.steps.first)..add(lineage.steps.last));
  await _listLineageSteps(s, steps);

  return lineages;
}

Future<db.LineageRow> readLineage(Session s, int id) async {
  final lineage = await s.selectById(db.lineage, id);
  await _listLineageSteps(s, lineage.steps);
  return lineage;
}

Future<List<db.LineageStepRow>> _listLineageSteps(
    Session s, List<int> ids) async {
  final steps = await s.selectByIds(db.lineageStep, ids);
  await s.selectByIds(db.expression, steps.map((step) => step.expressionId));
  return steps;
}
