// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

class FreeConditionsEditor {
  final QEDbEdiTeXInterface interface;
  final fcEditData = new List<List<List>>();
  final freeConditions = new List<Subs>();
  final Function onUpdate;
  final Element fcWrapper;

  FreeConditionsEditor(this.interface, this.onUpdate, this.fcWrapper,
      Element addBtn, Element rmBtn) {
    addBtn.onClick.listen((_) {
      addFreeConditionEditor([], []);
    });

    rmBtn.onClick.listen((_) {
      fcWrapper.children.last.remove();
      freeConditions.removeLast();
      fcEditData.removeLast();
      onUpdate();
    });
  }

  /// Append free condition editor.
  void addFreeConditionEditor(List lData, List rData) {
    // Create HTML elements.
    final left = ht.div('.editex.editex-align-left');
    final right = ht.div('.editex.editex-align-left');
    final input = ht.p('.free-condition.subs-input',
        c: [left, ht.span('.subs-arrow'), right]);
    fcWrapper.append(input);

    // Setup variables.
    final valid = [true, true];
    final index = freeConditions.length;
    freeConditions.add(new Subs(null, null));
    fcEditData.add([lData, rData]);

    // Set validitiy style.
    void setValid() {
      input.classes.toggle('free-condition-invalid', valid.any((v) => !v));
    }

    // Create one of the two editors.
    void createEditor(Element container, int side,
        Subs update(Expr expr, Subs old), List data) {
      // Create editor and bind events.
      final editor = new EdiTeX(container, interface);
      editor.container.onBlur.listen((_) {
        try {
          final expr = interface.parse(editor.getParsable());
          freeConditions[index] = update(expr, freeConditions[index]);
          valid[side] = true;
        } on Exception {
          valid[side] = false;
        }

        fcEditData[index][side] = editor.getData();
        onUpdate();
        setValid();
      });

      // Load initial data.
      editor.loadData(data);

      // Update expression data.
      try {
        final expr = interface.parse(editor.getParsable());
        freeConditions[index] = update(expr, freeConditions[index]);
      } on Exception {
        valid[0] = false;
        setValid();
      }
    }

    createEditor(left, 0, (expr, subs) => new Subs(expr, subs.right), lData);
    createEditor(right, 1, (expr, subs) => new Subs(subs.left, expr), rData);
  }
}
