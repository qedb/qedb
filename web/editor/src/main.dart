// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';
import 'dart:convert';

import 'package:eqlib/eqlib.dart';
import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';
import 'package:eqdb_client/browser_client.dart';

import 'utils.dart';
import 'editex_interface.dart';

class ExpressionState {
  final bool different, valid;
  final Expr expression;
  ExpressionState(this.different, this.valid, this.expression);
}

/// Editor component with some additional data.
class ExpressionEditor extends EdiTeX {
  final int index;
  final Node parentRowNode;
  final DivElement resolveState;
  final EqDBEdiTeXInterface _interface;
  Completer<DifferenceBranch> _expressionDifference;
  Expr _previousExpression;

  ExpressionEditor(this.index, this.parentRowNode, this.resolveState,
      DivElement container, this._interface)
      : super(container, _interface) {
    resolveState.classes.add('status-none');
  }

  /// Set status for UI appearance.
  void setStatus(String statusName) {
    resolveState.classes
      ..removeWhere((className) => className.startsWith('status-'))
      ..add('status-$statusName');
  }

  /// Re-parse expression, and return result.
  ExpressionState updateState() {
    try {
      final expr = _interface.parse(getParsableContent());
      final different = expr != _previousExpression;
      _previousExpression = expr;
      return new ExpressionState(different, true, expr);
    } catch (e) {
      return new ExpressionState(false, false, null);
    }
  }

  /// Resolve difference with [leftEditor].
  Future<DifferenceBranch> resolveDifference(
      ExpressionEditor leftEditor, EqdbApi db) async {
    if (leftEditor.isNotEmpty && this.isNotEmpty) {
      final left = leftEditor.updateState();
      final right = this.updateState();

      if (!left.valid || !right.valid) {
        setStatus('error');
        return null;
      } else if (left.different || right.different) {
        setStatus('progress');

        // Resolve difference via API.
        try {
          _expressionDifference = new Completer<DifferenceBranch>();
          final result =
              await db.resolveExpressionDifference(new DifferenceBranch()
                ..leftData = left.expression.toBase64()
                ..rightData = right.expression.toBase64());
          _expressionDifference.complete(result);
          setStatus(result.different && !result.resolved ? 'error' : 'valid');
          return result;
        } catch (e) {
          setStatus('error');
          return null;
        }
      } else {
        // Return previously computed difference.
        /// Uses a Completer to deal with concurrent calls.
        /// A concurrent call will change the editor states, as a result the
        /// expressions will not be different anymore in a second call to
        /// [resolveDifference], returning the future value of the previous
        /// call.
        return await _expressionDifference.future;
      }
    } else {
      setStatus('empty');
      return null;
    }
  }
}

class ProofEditor {
  final DivElement container;
  final EqDBEdiTeXInterface interface;
  final EqdbApi db;

  final editors = new List<ExpressionEditor>();

  ProofEditor(this.container, this.db, this.interface);

  Future<ProofData> getData() async {
    final data = new ProofData();
    data.steps = new List<DifferenceBranch>();

    // The first editor sets the proof initial expression and has no
    // difference data.
    for (var i = 1; i < editors.length; i++) {
      final editor = editors[i];

      // Ignore empty editors.
      // An empty editor between non-empty ones will cause an error at proof
      // creation.
      if (editor.isNotEmpty) {
        // Resolve difference again to be sure the expressionDifference is
        // up-to-date (if it already is no API request will be executed, see the
        // code).
        final diff = await editor.resolveDifference(editors[i - 1], db);
        if (diff != null && diff.resolved) {
          data.steps.add(diff);
        } else {
          throw new Exception('proof is broken');
        }
      }
    }

    return data;
  }

  void addRow() {
    DivElement editorContainer, resolveStatus;

    // Add resolve info elements.
    final row = container.append(div('.proof-row', c: [
      div('.proof-row-number')..text = (editors.length + 1).toString(),
      div('.proof-row-editor.editex.editex-align-left',
          store: (e) => editorContainer = e),
      div('.proof-row-status', store: (e) => resolveStatus = e)
    ]));

    final editor = new ExpressionEditor(
        editors.length, row, resolveStatus, editorContainer, interface);
    _addEditorEvents(editor);
    editors.add(editor);
  }

  /// Focus the editor at the given index. Index may be out of bounds.
  /// Values for [setCursor]:
  /// - `-1`: set cursor to start.
  /// - `1`: set cursor to end.
  void _focusEditor(int idx, [int setCursor = 0]) {
    if (idx >= 0 && idx < editors.length) {
      final editor = editors[idx];
      if (setCursor == -1) {
        editor.setCursor(0);
      } else if (setCursor == 1) {
        editor.setCursor(editor.content.length - 1);
      }

      editor.container.focus();
    }
  }

  void _addEditorEvents(ExpressionEditor editor) {
    editor.onLeftLeave.listen((_) => _focusEditor(editor.index - 1, 1));
    editor.onRightLeave.listen((_) => _focusEditor(editor.index + 1, -1));

    editor.container.onKeyDown.listen((e) {
      if (e.keyCode == KeyCode.UP) {
        _focusEditor(editor.index - 1, 0);
      } else if (e.keyCode == KeyCode.DOWN || e.keyCode == KeyCode.ENTER) {
        // If the next editor is empty, copy the expression from this editor.
        // It seems more intuitive to only do this when the enter key is used.
        if (e.keyCode == KeyCode.ENTER && editors[editor.index + 1].isEmpty) {
          editors[editor.index + 1]
            ..loadData(editor.getData())
            ..setCursor(editor.cursorPosition);
        }

        _focusEditor(editor.index + 1, 0);
      } else {
        return;
      }
      e.preventDefault();
    });

    /// Do automatic difference check when an editor is unfocussed.
    editor.container.onBlur.listen((_) {
      if (editor.index > 0) {
        editor.resolveDifference(editors[editor.index - 1], db);
      }
    });

    editor.container.onFocus.listen((_) {
      if (editor.index == editors.length - 1) {
        // Add new row when there are now rows left below the focussed editor.
        addRow();
      } else {
        // Remove empty rows from the bottom but leave one row after the current
        // focussed element.
        while (editor.index < editors.length - 2 &&
            editors.last.isEmpty &&
            editors[editors.length - 2].isEmpty) {
          editors.removeLast().parentRowNode.remove();
        }
      }
    });
  }
}

Future main() async {
  // Retrieve operators and functions.
  final db = new EqdbApi(new BrowserClient());
  final interface = new EqDBEdiTeXInterface();
  await interface.loadData(db);

  // Construct editors.
  final proofEditor =
      new ProofEditor(querySelector('#proof-editor'), db, interface);
  proofEditor.addRow();
  proofEditor.addRow();

  // Build form data on submit.
  final FormElement form = querySelector('form');
  final InputElement dataInput = querySelector('#data');
  form.onSubmit.listen((e) {
    e.preventDefault();
    submitForm(form, dataInput, proofEditor);
  });
}

Future<bool> submitForm(
    FormElement form, InputElement dataInput, ProofEditor proofEditor) async {
  try {
    dataInput.value = JSON.encode((await proofEditor.getData()).toJson());
    form.submit();
    return true;
  } catch (e) {
    window.alert(e.toString());
    return false;
  }
}
