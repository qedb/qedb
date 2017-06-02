// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

/// Interactive step editor
class StepEditor extends StepEditorBase {
  /// Editing component
  EdiTeX editor;

  factory StepEditor(EdiTeXInterface interface, QedbApi db, Element root,
      StepEditorBase prev) {
    final container = ht.div('.proof-row-editor.editex.editex-align-left');
    final status = ht.div('.proof-row-status');
    final row = root.append(ht.div('.proof-row',
        c: [ht.div('.proof-row-number'), container, status]));

    // Create editor.
    final editor = new EdiTeX(container, interface);

    return new StepEditor._(
        interface, db, root, row, container, status, editor, prev);
  }

  StepEditor._(EdiTeXInterface interface, QedbApi db, Element root, Element r,
      Element c, Element s, this.editor, StepEditorBase prev)
      : super(interface, db, root, r, c, s, prev) {
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
        if (next.isEmpty) {
          next.load(editor.getData());
          next.setCursor(editor.cursorIndex);
        }
        next.focus();
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
  ExpressionData getExpression() {
    final content = editor.getParsable();
    if (content.trim().isEmpty) {
      return new ExpressionData(null, valid: true, empty: true);
    } else {
      try {
        return new ExpressionData(interface.parse(content),
            valid: true, empty: false);
      } catch (e) {
        return new ExpressionData(null, valid: false, empty: false);
      }
    }
  }

  void focus() => editor.focus();

  void load(List data) => editor.loadData(data);

  void setCursor(int index) => editor.setCursor(index);

  bool get isEmpty => editor.isEmpty;
}

typedef void ProofDataModifier(ProofData data);

/// Static step editor
class StaticStepEditor extends StepEditorBase {
  final Expr expression;
  final ProofDataModifier modifier;

  factory StaticStepEditor(
      EdiTeXInterface interface,
      QedbApi db,
      Element root,
      StepEditorBase prev,
      Expr expression,
      String latex,
      ProofDataModifier modifier) {
    final container = ht.div('.proof-row-editor.editex.editex-align-left');
    final status = ht.div('.proof-row-status');
    final row = root.append(ht.div('.proof-row',
        c: [ht.div('.proof-row-number'), container, status]));

    // Render latex.
    final target = new DivElement();
    container.append(target);
    katex.render(latex, target);

    return new StaticStepEditor._(interface, db, root, row, container, status,
        prev, expression, modifier);
  }

  StaticStepEditor._(
      EdiTeXInterface interface,
      QedbApi db,
      Element root,
      Element r,
      Element c,
      Element s,
      StepEditorBase prev,
      this.expression,
      this.modifier)
      : super(interface, db, root, r, c, s, prev) {
    setStatus('lock');
    ensureNext();
  }

  ExpressionData getExpression() =>
      new ExpressionData(expression, valid: true, empty: false);

  Future writeData(data) {
    modifier(data);
    return super.writeData(data);
  }

  void focus() {}
  void setCursor(position) {}
  bool get isEmpty => false;
}
