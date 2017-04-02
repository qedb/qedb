// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:eqlib/eqlib.dart';
import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';
import 'package:eqdb_client/browser_client.dart';

import 'utils.dart';
import 'editex_interface.dart';

class ExpressionEditor extends EdiTeX {
  final int index;
  final DivElement arrow, ellipsis, infoPane;
  Expr oldExpression;

  ExpressionEditor(this.index, this.arrow, this.ellipsis, this.infoPane,
      DivElement container, EdiTeXInterface interface)
      : super(container, interface) {
    hideResolveInfo();
  }

  void hideResolveInfo() {
    arrow.style.opacity = '0';
    ellipsis.hidden = true;
    infoPane.children.clear();
  }

  /// TODO: solve this using a Stream based approach?
  Future resolveDifference(ExpressionEditor previous, EqdbApi db,
      EqDBEdiTeXInterface interface) async {
    if (previous.isNotEmpty && this.isNotEmpty) {
      // TODO: evaluate both sides of the equation.
      final left = interface.parse(previous.getParsableContent());
      final right = interface.parse(this.getParsableContent());

      if (right == oldExpression || left == previous.oldExpression) {
        return;
      } else {
        // TODO: Split into method.
        oldExpression = right;
        previous.oldExpression = left;
      }

      // TODO: use a stream based approach?, something like a state stream.
      arrow.style.opacity = '1';
      ellipsis.hidden = false;
      ellipsis.classes.add('animated');
      infoPane.children.clear();

      // Resolve difference via API.
      final result = await db
          .resolveExpressionDifference(new ExpressionDifferenceResource()
            ..left = (new ExpressionResource()..data = left.toBase64())
            ..right = (new ExpressionResource()..data = right.toBase64()));

      ellipsis.hidden = true;
      if (!result.difference.resolved) {
        infoPane.append(div('.error-badge'));
      }
    } else {
      hideResolveInfo();
    }
  }
}

class LineageEditor {
  final DivElement container;
  final editors = new List<ExpressionEditor>();
  final EqDBEdiTeXInterface interface;
  final EqdbApi db;

  LineageEditor(this.container, this.db, this.interface);

  void addLineageRow() {
    DivElement leftArrow, leftEllipsis, leftInfoPane, leftContainer;
    DivElement rightArrow, rightEllipsis, rightInfoPane, rightContainer;

    // Add resolve info elements.
    container.append(div('.resolve-info-row', c: [
      div('.resolve-info-left', c: [
        div('.arrow-left', store: (e) => leftArrow = e),
        div('.ellipsis', store: (e) => leftEllipsis = e, c: [
          span('.ellipsis-dot1'),
          span('.ellipsis-dot2'),
          span('.ellipsis-dot3')
        ]),
        div('.resolve-info-pane', store: (e) => leftInfoPane = e)
      ]),
      div('.resolve-info-separator'),
      div('.resolve-info-right', c: [
        div('.arrow-right', store: (e) => rightArrow = e),
        div('.ellipsis', store: (e) => rightEllipsis = e, c: [
          span('.ellipsis-dot1'),
          span('.ellipsis-dot2'),
          span('.ellipsis-dot3')
        ]),
        div('.resolve-info-pane', store: (e) => rightInfoPane = e)
      ])
    ]));

    // Add editor containers.
    container.append(div('.lineage-row', c: [
      div('.lineage-row-left.editex.editex-align-right',
          store: (e) => leftContainer = e),
      div('.equals'),
      div('.lineage-row-right.editex.editex-align-left',
          store: (e) => rightContainer = e)
    ]));

    final left = new ExpressionEditor(editors.length, leftArrow, leftEllipsis,
        leftInfoPane, leftContainer, interface);
    _addEditorEvents(left);
    editors.add(left);
    final right = new ExpressionEditor(editors.length, rightArrow,
        rightEllipsis, rightInfoPane, rightContainer, interface);
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
    editor.container.onBlur.listen((_) {
      if (editor.index == 0) {
        editors[1].resolveDifference(editor, db, interface);
      } else if (editor.index == 1) {
        editor.resolveDifference(editors[0], db, interface);
      } else {
        editor.resolveDifference(editors[editor.index - 2], db, interface);
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