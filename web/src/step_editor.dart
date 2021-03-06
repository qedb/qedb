// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

/// Interactive step editor
class StepEditor extends StepBase {
  /// Editing component
  EdiTeX editor;

  factory StepEditor(EdiTeXInterface interface, QedbApi db, Element root,
      StepBase prev, List<Subs> freeConditions) {
    final container = ht.div('.proof-row-editor.editex.editex-align-left');
    final status = ht.div('.proof-row-status');
    final row = root.append(ht.div('.proof-row',
        c: [ht.div('.proof-row-number'), container, status]));

    // Create editor.
    final editor = new EdiTeX(container, interface);

    return new StepEditor._(interface, db, root, row, container, status, editor,
        prev, freeConditions);
  }

  StepEditor._(
      EdiTeXInterface interface,
      QedbApi db,
      Element root,
      Element r,
      Element c,
      Element s,
      this.editor,
      StepBase prev,
      List<Subs> freeConditions)
      : super(interface, db, root, r, c, s, prev, freeConditions) {
    editor.onIdleKeyDown.listen((e) {
      if (e.keyCode == KeyCode.UP) {
        if (prev != null) {
          prev.focus();
        }
      } else if (e.keyCode == KeyCode.DOWN) {
        ensureNext();
        next.focus();
      } else if (e.keyCode == KeyCode.ENTER) {
        ensureNext();

        // First focus, so that the difference is resolved and the next editor
        // is triggered before we copy the expression.
        next.focus();

        if (next.isEmpty) {
          // Wait until the next editor afterResolve is triggered before copying
          // the expression.
          StreamSubscription sub;
          sub = next.afterResolve.stream.listen((_) {
            next.load(editor.getData());
            next.setCursor(editor.cursorIndex);
            sub.cancel();
          });
        }
      } else {
        return;
      }
      e.preventDefault();
    });

    editor.container.onFocus.listen((_) {
      ensureNext();
      if (next.isEmptyRecursive()) {
        next.remove(false);
      }
    });

    subscriptions.add(editor.container.onBlur.listen((_) {
      afterUpdate.add(null);
    }));

    editor.onLeftLeave.listen((_) {
      if (prev != null) {
        prev.focus();
        prev.setCursor(-1);
      }
    });

    editor.onRightLeave.listen((_) {
      ensureNext();
      next.focus();
      next.setCursor(0);
    });
  }

  @override
  Future remove([bool self = true]) async {
    if (self) {
      await editor.destruct();
      editor = null;
    }
    await super.remove(self);
  }

  /// Note that the state is already updated by the base class.
  @override
  ExpressionData getExpression() {
    final content = editor.getParsable();
    if (content.trim().isEmpty) {
      return new ExpressionData(null, valid: true, empty: true);
    } else {
      try {
        return new ExpressionData(interface.parse(content),
            valid: true, empty: false);
      } on Exception {
        return new ExpressionData(null, valid: false, empty: false);
      }
    }
  }

  @override
  void focus() => editor.focus();

  @override
  void load(List data) => editor.loadData(data);

  @override
  void setCursor(int index) => editor.setCursor(index);

  @override
  bool get isEmpty => editor.isEmpty;
}
