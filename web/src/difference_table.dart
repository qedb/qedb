// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

TableElement createDifferenceTable(
    QEDbEdiTeXInterface interface, DifferenceBranch difference) {
  // Create all cells recursively.
  final cells = _difftableBranch(interface, difference, new W<int>(0));

  // Insert cells into table.
  return ht.table('.proof-step-difference-table',
      c: cells.map((row) {
        return ht.tr(row);
      }).toList());
}

List<List<TableCellElement>> _difftableBranch(QEDbEdiTeXInterface interface,
    DifferenceBranch difference, W<int> colspan) {
  if (difference.arguments != null) {
    // Put all arguments next to each other.
    final arguments = difference.arguments.map((argument) {
      final argColspan = new W<int>(0);
      final result = _difftableBranch(interface, argument, argColspan);
      colspan.v += argColspan.v;
      return result;
    }).toList();

    // Collapse into single cell array.
    while (arguments.length > 1) {
      arguments.insert(
          0, _difftableCombine(arguments.removeAt(0), arguments.removeAt(0)));
    }

    final cells = arguments.single;

    // Get function label.
    final expr = new Expr.fromBase64(difference.leftExpression);
    final fnId = expr is FunctionExpr ? expr.id : 0;

    String label;
    try {
      label = interface.functionMap[fnId].descriptor.translations[0].content;
    } catch (e) {
      label = 'fn#$fnId';
    }

    // Add first and last row which contains branch function title.
    cells.insert(0, [
      ht.td(['.difftable-function', label], attrs: {'colspan': '${colspan.v}'})
    ]);
    cells.add([
      ht.td(['.difftable-function', label], attrs: {'colspan': '${colspan.v}'})
    ]);

    return cells;
  } else {
    // Branch is either:
    // - not different
    // - resolved by a rule
    // - by rearrangements
    // - unresolved

    // Return three stacked cells: left expression, resolved?, right expression.
    final leftExpression = ht.td('.difftable-latex');
    final rightExpression = ht.td('.difftable-latex');

    final base64ToLaTeX = (String base64) =>
        interface.printer.render(new Expr.fromBase64(base64));

    katex.render(base64ToLaTeX(difference.leftExpression), leftExpression);
    katex.render(base64ToLaTeX(difference.rightExpression), rightExpression);

    TableCellElement state;

    final unresolvedHtml = katex.renderToStringNoMathML(r'?');
    final rearrangeHtml = katex.renderToStringNoMathML(r'\leftrightharpoons');
    final nodifferenceHtml = katex.renderToStringNoMathML(r'\simeq');
    final katexSpan = (String html) =>
        ht.span('')..setInnerHtml(html, validator: EdiTeX.labelHtmlValidator);

    if (!difference.different) {
      state = ht.td(['.difftable-not-different', katexSpan(nodifferenceHtml)]);
    } else if (!difference.resolved) {
      state = ht.td(['.difftable-not-resolved', katexSpan(unresolvedHtml)]);
    } else if (difference.rearrangements.isNotEmpty) {
      state = ht.td(['.difftable-rearrange', katexSpan(rearrangeHtml)]);
    } else if (difference.rule != null) {
      state = ht.td(['.difftable-rule', '#${difference.rule.id}']);
    } else {
      state = ht.td('?');
    }

    assert(state != null);
    state.attributes['rowspan'] = '1';

    /// Add to max colspan.
    colspan.v++;
    return [
      [leftExpression],
      [state],
      [rightExpression]
    ];
  }
}

List<List<TableCellElement>> _difftableCombine(
    List<List<TableCellElement>> a, List<List<TableCellElement>> b) {
  final small = a.length < b.length ? a : b;
  final large = a.length < b.length ? b : a;
  final diff = large.length - small.length;

  // Add row difference to rowspan of all central cells. There can be found by
  // checking if a rowspan property already exists.
  small.forEach((row) => row
      .where((cell) => cell.attributes.containsKey('rowspan'))
      .forEach((cell) => cell.rowSpan += diff));

  // Copy small into large. To make sure the central cells end up in the right
  // spot, we copy rows to index i in this order: https://oeis.org/A130472.
  // A permutation of the integers: a(n) = (-1)^n * floor((n+1)/2).
  for (var n = 0; n < small.length; n++) {
    final int idx = pow(-1, n) * ((n + 1) / 2).floor();
    large[idx < 0 ? large.length + idx : idx]
        .addAll(small[idx < 0 ? small.length + idx : idx]);
  }

  return large;
}
