// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.web.proof_editor;

import 'dart:html';
import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:eqlib/eqlib.dart';
import 'package:eqlib/utils.dart';
import 'package:editex/editex.dart';
import 'package:qedb_client/qedb_client.dart';
import 'package:qedb_client/browser_client.dart';
import 'package:collection/collection.dart';

import 'package:htgen/dynamic.dart' as ht;
import 'package:editex/katex.dart' as katex;
import 'package:qedb/qedb.dart' as qedb show SubsType;

import 'editex_interface.dart';

part 'free_conditions.dart';
part 'step_base.dart';
part 'step_editor.dart';
part 'step_static.dart';
part 'step_json.dart';
part 'difference_table.dart';

const localStorageKey = 'QEDb_PROOF_EDITOR';

Future main() async {
  // Check if this page is the proof editor by checking if the #proof-editor
  // exists (else this is the successfully submitted proof page).
  if (querySelectorAll('#proof-editor').isEmpty) {
    // Clear the localStorage since a proof was submitted successfully.
    window.localStorage.remove(localStorageKey);

    // Terminate function.
    return;
  }

  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  // Declare some variables.
  StepBase stepRoot;

  // Setup free conditions editor.
  final fcEditor = new FreeConditionsEditor(
      interface,
      () => stepRoot.afterUpdate.add(null),
      querySelector('#free-conditions-wrapper'),
      querySelector('#add-free-condition'),
      querySelector('#remove-free-condition'));

  // Get proof editor root div.
  final proofRoot = querySelector('#proof-editor');

  // Try parsing query parameters or localStorage data.
  final q = Uri.base.queryParameters;
  try {
    if (q.containsKey('initialStep')) {
      final stepId = int.parse(q['initialStep']);
      stepRoot = await loadStepFromStep(
          interface, db, proofRoot, fcEditor.freeConditions, stepId);
    } else if (q.containsKey('initialRule')) {
      final ruleId = int.parse(q['initialRule']);
      stepRoot = await loadStepFromRule(
          interface, db, proofRoot, fcEditor.freeConditions, ruleId);
    } else if (window.localStorage.containsKey(localStorageKey)) {
      final json = JSON.decode(window.localStorage[localStorageKey]);

      // Restore free conditions.
      for (final freeCondition in json['fcEditData']) {
        fcEditor.addFreeConditionEditor(freeCondition[0], freeCondition[1]);
      }

      // Restore steps.
      stepRoot = loadStorageJson(json['steps'], interface, db, proofRoot, null,
          fcEditor.freeConditions);
    }
  } finally {
    // If firstStep is still null, set it to an empty editor.
    stepRoot ??=
        new StepEditor(interface, db, proofRoot, null, fcEditor.freeConditions);

    // Listen to window blur for proof localStorage backup.
    window.onBeforeUnload.listen((_) {
      window.localStorage[localStorageKey] = JSON.encode({
        'fcEditData': fcEditor.fcEditData,
        'steps': writeStorageJson(stepRoot)
      });
    });

    // Build form data on submit.
    final FormElement form = querySelector('form');
    final InputElement dataInput = querySelector('#data');
    if (form != null && dataInput != null) {
      form.onSubmit.listen((e) async {
        e.preventDefault();
        try {
          final proofData = await stepRoot.getData();
          dataInput.value = JSON.encode(proofData.toJson());
          form.submit();
        } on Exception {
          // This is really not supposed to happen.
          window.alert(e.toString());
        }
      });
    }
  }
}

Future<StepStatic> loadStepFromStep(EdiTeXInterface interface, QedbApi db,
    Element proofRoot, List<Subs> freeConditions, int stepId) async {
  // Retrieve step and add static step.
  final step = await db.readStep(stepId);
  final expr = new Expr.fromBase64(step.expression.data);
  final stepIdB36 = step.id.toRadixString(36).padLeft(6, '0');

  final latex = '${step.expression.latex}'
      '\\quad\\left(\\mathtt{step~\\#$stepIdB36}\\right)';

  return new StepStatic(interface, db, proofRoot, null, freeConditions, expr,
      latex, step.id, null);
}

Future<StepStatic> loadStepFromRule(QEDbEdiTeXInterface interface, QedbApi db,
    Element proofRoot, List<Subs> freeConditions, int ruleId) async {
// Retrieve rule and add static step.
  final r = await db.readRule(ruleId);
  final subs = r.substitution;
  final expr = new FunctionExpr(interface.specialFunctions['equals'], false, [
    new Expr.fromBase64(subs.leftExpression.data),
    new Expr.fromBase64(subs.rightExpression.data)
  ]);

  final latex = '${subs.leftExpression.latex}=${subs.rightExpression.latex}'
      '\\quad\\left(\\mathtt{rule~\\#$ruleId\\right)';

  return new StepStatic(
      interface, db, proofRoot, null, freeConditions, expr, latex, null, r.id);
}
