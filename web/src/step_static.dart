// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

/// Static step editor
class StepStatic extends StepBase {
  final Expr expression;
  final String latex;
  final int initialStepId, initialRuleId;

  factory StepStatic(
      EdiTeXInterface interface,
      QedbApi db,
      Element root,
      StepBase prev,
      Expr expression,
      String latex,
      int initialStepId,
      int initialRuleId) {
    final container = ht.div('.proof-row-editor.proof-row-static.editex');
    final status = ht.div('.proof-row-status');
    final row = root.append(ht.div('.proof-row',
        c: [ht.div('.proof-row-number'), container, status]));

    // Render latex.
    final target = ht.div([]);
    container.append(target);
    katex.render(latex, target, new katex.RenderingOptions(displayMode: true));

    return new StepStatic._(interface, db, root, row, container, status, prev,
        expression, latex, initialStepId, initialRuleId);
  }

  StepStatic._(
      EdiTeXInterface interface,
      QedbApi db,
      Element root,
      Element r,
      Element c,
      Element s,
      StepBase prev,
      this.expression,
      this.latex,
      this.initialStepId,
      this.initialRuleId)
      : super(interface, db, root, r, c, s, prev) {
    setStatus('lock');
    ensureNext();
  }

  @override
  ExpressionData getExpression() =>
      new ExpressionData(expression, valid: true, empty: false);

  @override
  Future writeData(data) {
    data.initialStepId = initialStepId;
    data.initialRuleId = initialRuleId;
    return super.writeData(data);
  }

  @override
  void focus() {}

  @override
  void setCursor(position) {}

  @override
  bool get isEmpty => false;
}
