// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

Future<List<db.ProofRow>> listProofs(Session s) async {
  final proofs = await s.select(db.proof);

  // Select all first and last steps.
  final steps = new List<int>();
  for (final proof in proofs) {
    steps.add(proof.firstStepId);
    steps.add(proof.lastStepId);
  }
  await _listStepsById(s, steps);

  return proofs;
}

Future<List<db.StepRow>> listProofSteps(Session s, int id) async {
  final proof = await s.selectById(db.proof, id);
  final steps = await _listStepsBetween(s, proof.firstStepId, proof.lastStepId);
  final expressionIds = steps.map((step) => step.expressionId);
  await listExpressions(s, expressionIds);
  final ruleIds = steps.where((st) => st.ruleId != null).map((st) => st.ruleId);
  await listRules(s, ruleIds);
  return steps;
}
