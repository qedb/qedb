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
part 'difference_table.dart';
part 'json_storage.dart';

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

  // If there are query parameters with an initial step or rule, retrieve them.
  // Use try block to catch parsing errors.
  // TODO: refactor into separate functions.
  final q = Uri.base.queryParameters;
  try {
    if (q.containsKey('initialStep')) {
      // Retrieve step and add readonly row.
      final step =
          await db.readStep(int.parse(q['initialStep'], onError: (_) => 0));
      final expr = new Expr.fromBase64(step.expression.data);
      final stepid = step.id.toRadixString(36).padLeft(6, '0');
      final latex = '${step.expression.latex}'
          '\\quad\\left(\\mathtt{step~\\#$stepid}\\right)';

      stepRoot = new StepStatic(interface, db, proofRoot, null,
          fcEditor.freeConditions, expr, latex, step.id, null);
    } else if (q.containsKey('initialRule')) {
      // Retrieve rule and add readonly row.
      final r = await db.readRule(int.parse(q['initialRule']));
      bool isEquals(fn) => fn.specialType == 'equals';
      final equals = interface.functions.singleWhere(isEquals);

      final subs = r.substitution;
      final expr = new FunctionExpr(equals.id, false, [
        new Expr.fromBase64(subs.leftExpression.data),
        new Expr.fromBase64(subs.rightExpression.data)
      ]);

      final latex = '${subs.leftExpression.latex}=${subs.rightExpression.latex}'
          '\\quad\\left(\\mathtt{rule~\\#${r.id}}\\right)';

      stepRoot = new StepStatic(interface, db, proofRoot, null,
          fcEditor.freeConditions, expr, latex, null, r.id);
    } else if (window.localStorage.containsKey(localStorageKey)) {
      final json = JSON.decode(window.localStorage[localStorageKey]);
      if (json is Map &&
          json.containsKey('fcEditData') &&
          json.containsKey('steps')) {
        // Restore free conditions.
        for (final freeCondition in json['fcEditData']) {
          fcEditor.addFreeConditionEditor(freeCondition[0], freeCondition[1]);
        }

        // Restore steps.
        stepRoot = loadStorageJson(json['steps'], interface, db, proofRoot,
            null, fcEditor.freeConditions);
      }
    }

    // Fallback mechanism, if firstStep is still null, set it to an empty
    // editor.
    stepRoot ??=
        new StepEditor(interface, db, proofRoot, null, fcEditor.freeConditions);
  } finally {
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
        await submitForm(form, dataInput, await stepRoot.getData());
      });
    }
  }
}

Future<bool> submitForm(
    FormElement form, InputElement dataInput, ProofData data) async {
  try {
    dataInput.value = JSON.encode(data.toJson());
    form.submit();
    return true;
  } on Exception catch (e) {
    window.alert(e.toString());
    return false;
  }
}
