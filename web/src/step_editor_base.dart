// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.web.proof_editor;

/// Expression information
class ExpressionData {
  final Expr expression;
  final bool empty, valid;
  ExpressionData(this.expression, {this.valid: false, this.empty: true});
}

/// Base API for any step editor
abstract class StepEditorBase {
  final QEDbEdiTeXInterface interface;
  final QedbApi db;

  /// DOM element that contains all steps
  final Element root;

  /// DOM element of the row container
  final Element row;

  /// Other elements
  final Element container, status;

  /// Previous and next step
  StepEditorBase prev, next;

  /// Pending resolve data
  Future<DifferenceBranch> difference;

  /// Difference table
  TableElement difftable;

  /// Stream to be triggered by the implementation when the user is done with
  /// editing of any sort
  /// Important: the step implementation must call this.
  final afterUpdate = new StreamController<Null>.broadcast();

  /// Stream that is triggered when the difference between this step and the
  /// previous one is resolved. Called in [resolveDifference]. The value
  /// indicates if the resolving was successful.
  final afterResolve = new StreamController<bool>.broadcast();

  /// All subscriptions that must be cancelled on remove.
  final subscriptions = new List<StreamSubscription>();

  StepEditorBase(this.interface, this.db, this.root, this.row, this.container,
      this.status, this.prev) {
    if (prev != null) {
      subscriptions.add(prev.afterResolve.stream.listen((v) {
        resolveDifference();
      }));

      subscriptions.add(afterUpdate.stream.listen((_) {
        resolveDifference();
      }));
    } else {
      subscriptions.add(afterUpdate.stream.listen((_) {
        final valid = getExpression().valid;
        setStatus(valid ? 'valid' : 'exclaim');
        afterResolve.add(valid);
      }));
    }

    // When the status icon is clicked, show the current difference.
    status.onClick.listen((_) async {
      if (difference != null) {
        if (difftable != null) {
          difftable.remove();
          difftable = null;
        } else {
          // Insert difference table.
          final theDifference = await difference;
          difftable = createDifferenceTable(interface, theDifference);
          row.parent.insertBefore(difftable, row);
        }
      }
    });

    // Update difference table after expression difference is resolved.
    subscriptions.add(afterResolve.stream.listen((resolved) async {
      if (difftable != null) {
        difftable.remove();

        if (difference != null) {
          // Await difference and use it to generate a table.
          final theDifference = await difference;
          difftable = createDifferenceTable(interface, theDifference);
        } else {
          // Generate table with a question mark.
          final unresolvedHtml = katex.renderToStringNoMathML(r'?');
          difftable = ht.table([
            '.proof-step-difference-table',
            ht.tr(ht.td([
              '.difftable-not-resolved',
              ht.span('')
                ..setInnerHtml(unresolvedHtml,
                    validator: EdiTeX.labelHtmlValidator)
            ]))
          ]);
        }

        row.parent.insertBefore(difftable, row);
      }
    }));
  }

  /// Remove from DOM.
  Future remove([bool self = true]) async {
    if (self == true) {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await afterUpdate.close();
      await afterResolve.close();
      row.remove();

      if (difftable != null) {
        difftable.remove();
      }
    }
    if (next != null) {
      await next.remove();
      next = null;
    }
  }

  /// Focus this editor.
  void focus();

  /// Load editex edit data.
  void load(List data) {}

  /// Set editing cursor index.
  void setCursor(int index);

  /// Check if step is empty.
  bool get isEmpty;

  /// Check if step and all children are empty.
  bool isEmptyRecursive() {
    if (next != null) {
      return isEmpty && next.isEmptyRecursive();
    } else {
      return isEmpty;
    }
  }

  /// Set status for UI appearance.
  void setStatus(String statusName) {
    status.classes
      ..removeWhere((className) => className.startsWith('status-'))
      ..add('status-$statusName');
  }

  /// Get data for submission.
  Future<ProofData> getData() async {
    final data = new ProofData();
    data.steps = new List<DifferenceBranch>();
    await writeData(data);
    return data;
  }

  /// Write data in this step (and child steps) to [data].
  Future writeData(ProofData data) async {
    if (!isEmptyRecursive()) {
      if (prev != null) {
        final difference = await resolveDifference();
        if (difference != null) {
          data.steps.add(difference);
        } else {
          throw new Exception('some steps could not be resolved');
        }
      }
      if (next != null) {
        await next.writeData(data);
      }
    }
  }

  /// Get expression value. May return null for an invalid expression. May throw
  /// an error when the expression cannot be retrieved.
  ExpressionData getExpression();

  /// Resolve difference.
  /// This function assumes that [prev] is defined.
  Future<DifferenceBranch> resolveDifference() async {
    final prevExpr = prev.getExpression();
    final thisExpr = getExpression();
    if (!thisExpr.valid) {
      setStatus('exclaim');
      difference = null;
      afterResolve.add(false);
      return null;
    } else if (!prevExpr.valid || thisExpr.empty || prevExpr.empty) {
      setStatus('valid');
      difference = null;
      afterResolve.add(false);
      return null;
    } else {
      setStatus('progress');
      final current = difference == null ? null : await difference;
      final request = new DifferenceRequest()
        ..leftExpression = prevExpr.expression.toBase64()
        ..rightExpression = thisExpr.expression.toBase64();

      if (current == null ||
          request.leftExpression != current.leftExpression ||
          request.rightExpression != current.rightExpression) {
        // Note: it is important that we assign the completer future here else
        // we open an infinite waiting loop.
        final completer = new Completer<DifferenceBranch>();
        difference = completer.future;
        final result = await db.resolveExpressionDifference(request);

        // Update status and trigger stream.
        setStatus(result.different && !result.resolved ? 'error' : 'resolved');
        afterResolve.add(result.resolved);
        completer.complete(result);
        return result;
      } else {
        setStatus(
            current.different && !current.resolved ? 'error' : 'resolved');
        afterResolve.add(current.resolved);
        return difference;
      }
    }
  }

  void ensureNext() {
    next ??= new StepEditor(interface, db, root, this);
  }
}
