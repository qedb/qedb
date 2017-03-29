// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';
import 'package:eqdb_client/browser_client.dart';

import 'editex_interface.dart';

class ExpressionEditor extends EdiTeX {
  final int index;

  ExpressionEditor(this.index, DivElement container, EdiTeXInterface interface)
      : super(container, interface);
}

class LineageEditor {
  final DivElement container;
  final editors = new List<ExpressionEditor>();
  final EqDBEdiTeXInterface interface;
  final EqdbApi db;

  LineageEditor(this.container, this.db, this.interface);

  void addLineageRow() {
    final row = new DivElement()..classes.add('lineage-row');
    final leftDiv = new DivElement()
      ..classes.addAll(['lineage-row-left', 'editex', 'editex-align-right']);
    final rightDiv = new DivElement()
      ..classes.addAll(['lineage-row-right', 'editex', 'editex-align-left']);

    row.append(leftDiv);
    row.append(new DivElement()..classes.add('equals'));
    row.append(rightDiv);
    container.append(row);

    final left = new ExpressionEditor(editors.length, leftDiv, interface);
    _addEditorEvents(left);
    editors.add(left);
    final right = new ExpressionEditor(editors.length, rightDiv, interface);
    _addEditorEvents(right);
    editors.add(right);
  }

  /// Focus the editor at the given index. Index may be out of bounds.
  /// Values for [setCursor]:
  /// - `-1`: set cursor to start.
  /// - `1`: set cursor to end.
  void _focusEditor(int idx, [int setCursor = 0]) {
    if (idx >= 0 && idx < editors.length) {
      final editor = editors[idx];
      if (setCursor == -1) {
        editor.cursorIdx = 0;
      } else if (setCursor == 1) {
        editor.cursorIdx = editor.content.length - 1;
      }

      editor.doUpdate = true;
      editor.container.focus();
    }
  }

  void _addEditorEvents(ExpressionEditor editor) {
    editor.onLeftLeave.listen((_) => _focusEditor(editor.index - 1, 1));
    editor.onRightLeave.listen((_) => _focusEditor(editor.index + 1, -1));

    editor.container.onKeyDown.listen((e) {
      if (e.keyCode == KeyCode.UP) {
        _focusEditor(editor.index - 2, 0);
      } else if (e.keyCode == KeyCode.DOWN || e.keyCode == KeyCode.ENTER) {
        _focusEditor(editor.index + 2, 0);
      } else {
        return;
      }
      e.preventDefault();
    });

    /// Do automatic difference check when an editor is unfocussed.
    editor.container.onBlur.listen((_) async {
      // Find index of editor to compare with.
      final compareWith =
          editor.index < 2 ? 1 - editor.index : editor.index - 2;

      if (compareWith >= 0 &&
          editors[compareWith].isNotEmpty &&
          editor.isNotEmpty) {
        var left = interface.parse(editors[compareWith].getParsableContent());
        var right = interface.parse(editor.getParsableContent());

        // Special case where the sides have to be swapped.
        if (editor.index == 0) {
          final tmp = left;
          left = right;
          right = tmp;
        }

        // TODO: evaluate both sides of the equation before submitting.

        // Resolve difference via API.
        final result = await db
            .resolveExpressionDifference(new ExpressionDifferenceResource()
              ..left = (new ExpressionResource()..data = left.toBase64())
              ..right = (new ExpressionResource()..data = right.toBase64()));

        print(result.toJson());
      }
    });

    // Add new row when an editor in the bottom row is focussed.
    editor.container.onFocus.listen((_) {
      if (editors.length - editor.index <= 2) {
        addLineageRow();
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
  lineageEditor.addLineageRow();
  lineageEditor.addLineageRow();
}
