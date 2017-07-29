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

  // First proof step that is the entry to the entire chain of steps.
  StepBase firstStep;

  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  // Initialize free condition editor.
  final freeConditions = new List<Subs>();
  final fcEditData = new List<List<List>>();
  final fcWrapper = querySelector('#free-conditions-wrapper');

  // TODO: refactor the shit out of this (combine with create_rule.dart).
  void setupNewFsubsEditor(List leftData, List rightData) {
    // Create HTML elements.
    final left = ht.div('.editex.editex-align-left');
    final right = ht.div('.editex.editex-align-left');
    final input = ht.p('.free-condition.subs-input',
        c: [left, ht.span('.subs-arrow'), right]);
    fcWrapper.append(input);

    // Set validitiy style.
    final valid = [true, true];
    void setValid() {
      input.classes.toggle('free-condition-invalid', valid.any((v) => !v));
    }

    // Setup variables.
    final index = freeConditions.length;
    freeConditions.add(new Subs(null, null));
    fcEditData.add([leftData, rightData]);

    // Create editors and bind events.
    final leftEditor = initializeEditor(left, interface, (expr, data, v) {
      freeConditions[index] = new Subs(expr, freeConditions[index].right);
      fcEditData[index][0] = data;
      firstStep.afterUpdate.add(null);
      valid[0] = v;
      setValid();
    });
    final rightEditor = initializeEditor(right, interface, (expr, data, v) {
      freeConditions[index] = new Subs(freeConditions[index].left, expr);
      fcEditData[index][1] = data;
      firstStep.afterUpdate.add(null);
      valid[1] = v;
      setValid();
    });

    // Set editor data.
    leftEditor.loadData(leftData);
    rightEditor.loadData(rightData);

    // Update expressions.
    try {
      final expr = interface.parse(leftEditor.getParsable());
      freeConditions[index] = new Subs(expr, freeConditions[index].right);
    } on Exception {
      valid[0] = false;
      setValid();
    }

    try {
      final expr = interface.parse(rightEditor.getParsable());
      freeConditions[index] = new Subs(freeConditions[index].left, expr);
    } on Exception {
      valid[1] = false;
      setValid();
    }
  }

  querySelector('#add-free-condition').onClick.listen((_) {
    setupNewFsubsEditor([], []);
  });

  querySelector('#remove-free-condition').onClick.listen((_) {
    fcWrapper.children.last.remove();
    freeConditions.removeLast();
    fcEditData.removeLast();
    firstStep.afterUpdate.add(null);
  });

  // Get proof editor root div.
  final proofRoot = querySelector('#proof-editor');

  // If there are query parameters with an initial step or rule, retrieve them.
  // Use try block to catch parsing errors.
  // TODO: refactor into separate functions.
  final q = Uri.base.queryParameters;
  try {
    if (q.containsKey('initialstep')) {
      // Retrieve step and add readonly row.
      final step = await db.readStep(int.parse(q['initialstep']));
      final expr = new Expr.fromBase64(step.expression.data);
      final stepid = step.id.toRadixString(36).padLeft(6, '0');
      final latex = '${step.expression.latex}'
          '\\quad\\left(\\mathtt{step~\\#$stepid}\\right)';

      firstStep = new StepStatic(interface, db, proofRoot, null, freeConditions,
          expr, latex, step.id, null);
    } else if (q.containsKey('initialrule')) {
      // Retrieve rule and add readonly row.
      final r = await db.readRule(int.parse(q['initialrule']));
      final equals =
          interface.functions.singleWhere((fn) => fn.specialType == 'equals');

      final subs = r.substitution;
      final expr = new FunctionExpr(equals.id, false, [
        new Expr.fromBase64(subs.leftExpression.data),
        new Expr.fromBase64(subs.rightExpression.data)
      ]);

      final latex = '${subs.leftExpression.latex}=${subs.rightExpression.latex}'
          '\\quad\\left(\\mathtt{rule~\\#${r.id}}\\right)';

      firstStep = new StepStatic(interface, db, proofRoot, null, freeConditions,
          expr, latex, null, r.id);
    } else if (window.localStorage.containsKey(localStorageKey)) {
      final json = JSON.decode(window.localStorage[localStorageKey]);
      if (json is Map &&
          json.containsKey('fcEditData') &&
          json.containsKey('steps')) {
        // Restore free conditions.
        for (final freeCondition in json['fcEditData']) {
          setupNewFsubsEditor(freeCondition[0], freeCondition[1]);
        }

        // Restore steps.
        firstStep = loadStorageJson(
            json['steps'], interface, db, proofRoot, null, freeConditions);
      }
    }

    // Fallback mechanism, if firstStep is still null, set it to an empty
    // editor.
    firstStep ??=
        new StepEditor(interface, db, proofRoot, null, freeConditions);
  } finally {
    // Listen to window blur for proof localStorage backup.
    window.onBeforeUnload.listen((_) {
      window.localStorage[localStorageKey] = JSON.encode(
          {'fcEditData': fcEditData, 'steps': writeStorageJson(firstStep)});
    });

    // Build form data on submit.
    final FormElement form = querySelector('form');
    final InputElement dataInput = querySelector('#data');
    if (form != null && dataInput != null) {
      form.onSubmit.listen((e) async {
        e.preventDefault();
        await submitForm(form, dataInput, await firstStep.getData());
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

EdiTeX initializeEditor(Element element, QEDbEdiTeXInterface interface,
    void onUpdate(Expr expr, List editorData, bool valid)) {
  final editor = new EdiTeX(element, interface);
  editor.container.onBlur.listen((_) {
    try {
      onUpdate(interface.parse(editor.getParsable()), editor.getData(), true);
    } on Exception {
      onUpdate(null, editor.getData(), false);
    }
  });
  return editor;
}
