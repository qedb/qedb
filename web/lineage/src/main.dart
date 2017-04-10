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

class ExpressionEditor extends EdiTeX {
  final int index;
  final Node parentRowNode;
  final DivElement resolveState;
  final EqDBEdiTeXInterface _interface;
  ExpressionDifferenceResource expressionDifference;
  Expr _previousExpression;

  ExpressionEditor(this.index, this.parentRowNode, this.resolveState,
      DivElement container, this._interface)
      : super(container, _interface) {
    resolveState.classes.add('status-none');
  }

  void setStatus(String statusName) {
    resolveState.classes
      ..removeWhere((className) => className.startsWith('status-'))
      ..add('status-$statusName');
  }

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

  Future resolveDifference(
      ExpressionEditor compareWith, EqdbApi db, EqDBEdiTeXInterface interface,
      [bool force = false]) async {
    if (compareWith.isNotEmpty && this.isNotEmpty) {
      final left = compareWith.updateState();
      final right = this.updateState();

      if (!left.valid || !right.valid) {
        setStatus('error');
      } else if (left.different || right.different || force) {
        setStatus('progress');

        // Evaluate both sides.
        final le = left.expression.evaluate(interface.compute);
        final re = right.expression.evaluate(interface.compute);

        // Resolve difference via API.
        try {
          expressionDifference = await db
              .resolveExpressionDifference(new ExpressionDifferenceResource()
                ..left = (new ExpressionResource()..data = le.toBase64())
                ..right = (new ExpressionResource()..data = re.toBase64()));

          final branch = expressionDifference.branch;
          setStatus(
              branch.different && !branch.resolved ? 'error' : 'resolved');
        } catch (e) {
          setStatus('error');
        }
      }
    } else {
      setStatus('empty');
    }
  }
}

class LineageEditor {
  final DivElement container;
  final EqDBEdiTeXInterface interface;
  final EqdbApi db;

  final editors = new List<ExpressionEditor>();

  LineageEditor(this.container, this.db, this.interface);

  LineageCreateData get data => new LineageCreateData()
    ..steps = (editors
        .sublist(1)
        .map((editor) => editor.expressionDifference)
        .toList()
          // Remove undefined differences.
          ..removeWhere((difference) => difference == null));

  void addRow() {
    DivElement editorContainer, resolveStatus;

    // Add resolve info elements.
    final row = container.append(div('.lineage-row', c: [
      div('.lineage-row-number')..text = (editors.length + 1).toString(),
      div('.lineage-row-editor.editex.editex-align-left',
          store: (e) => editorContainer = e),
      div('.lineage-row-status', store: (e) => resolveStatus = e)
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
        editor.resolveDifference(editors[editor.index - 1], db, interface);
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
  final lineageEditor =
      new LineageEditor(querySelector('#lineage-editor'), db, interface);
  lineageEditor.addRow();
  lineageEditor.addRow();

  // Build form data on submit.
  final FormElement form = querySelector('form');
  final InputElement dataInput = querySelector('#data');
  form.onSubmit.listen((e) {
    e.preventDefault();
    dataInput.value = JSON.encode(lineageEditor.data.toJson());
    form.submit();
  });
}
