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

import 'package:htgen/dynamic.dart' as ht;
import 'package:editex/katex.dart' as katex;

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

  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  // Construct editors.
  final root = querySelector('#proof-editor');

  // If there are query parameters with an initial step or rule, retrieve them.
  // Use try block to catch parsing errors.
  final q = Uri.base.queryParameters;
  StepBase firstStep;
  try {
    if (q.containsKey('initialstep')) {
      // Retrieve step and add readonly row.
      final step = await db.readStep(int.parse(q['initialstep']));
      final expr = new Expr.fromBase64(step.expression.data);
      final stepid = step.id.toRadixString(36).padLeft(6, '0');
      final latex = '${step.expression.latex}'
          '\\quad\\left(\\mathtt{step~\\#$stepid}\\right)';

      firstStep =
          new StepStatic(interface, db, root, null, expr, latex, step.id, null);
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

      firstStep =
          new StepStatic(interface, db, root, null, expr, latex, null, r.id);
    } else if (window.localStorage.containsKey(localStorageKey)) {
      final json = JSON.decode(window.localStorage[localStorageKey]);
      firstStep = loadStorageJson(json, interface, db, root, null);
    } else {
      firstStep = new StepEditor(interface, db, root, null);
    }
  } finally {
    // Listen to window blur for proof localStorage backup.
    window.onBeforeUnload.listen((_) {
      window.localStorage[localStorageKey] =
          JSON.encode(writeStorageJson(firstStep));
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
