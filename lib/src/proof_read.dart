// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<List<db.ProofRow>> listProofs(Session s) async {
  final proofs = await s.select(db.proof);

  // Select all first and last steps.
  final steps = new List<int>();
  proofs.forEach((p) => steps..add(p.steps.first)..add(p.steps.last));
  await _listStepsById(s, steps);

  return proofs;
}

Future<db.ProofRow> readProof(Session s, int id) async {
  final proof = await s.selectById(db.proof, id);
  await _listStepsById(s, proof.steps);
  return proof;
}

Future<List<db.StepRow>> _listStepsById(Session s, List<int> ids) async {
  final steps = await s.selectByIds(db.step, ids);
  await s.selectByIds(db.expression, steps.map((step) => step.expressionId));
  return steps;
}
