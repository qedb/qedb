// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb.web.proof_editor;

/// Expression information
class ExpressionData {
  final Expr expression;
  final bool empty, valid;
  ExpressionData(this.expression, {this.valid: false, this.empty: true});
}

/// Base API for any step editor
abstract class StepEditorBase {
  final EqDBEdiTeXInterface interface;
  final EqdbApi db;

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

  /// Stream to be triggered by the implementation when the user is done with
  /// editing of any sort
  /// Important: the step implementation must call this.
  final afterUpdate = new StreamController<Null>.broadcast();

  /// Stream that is triggered when the difference between this step and the
  /// previous one is successfully resolved. Called in [resolveDifference].
  final afterResolve = new StreamController<Null>.broadcast();

  StepEditorBase(this.interface, this.db, this.root, this.row, this.container,
      this.status, this.prev) {
    if (prev != null) {
      prev.afterResolve.stream.listen((_) {
        resolveDifference();
      });

      afterUpdate.stream.listen((_) {
        resolveDifference();
      });
    } else {
      afterUpdate.stream.listen((_) {
        // In other cases this is updated in [resolveDifference].
        setStatus(!getExpression().valid ? 'exclaim' : 'valid');
        afterResolve.add(null);
      });
    }
  }

  /// Remove from DOM.
  Future remove([bool self = true]) async {
    if (self == true) {
      row.remove();
      await afterUpdate.close();
      await afterResolve.close();
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

  /// Get expression value. May return null for an invalid expression. May throw
  /// an error when the expression cannot be retrieved.
  ExpressionData getExpression();

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

  /// Resolve difference.
  /// This function assumes that [prev] is defined.
  Future<DifferenceBranch> resolveDifference() async {
    final prevExpr = prev.getExpression();
    final thisExpr = getExpression();
    if (!thisExpr.valid) {
      setStatus('exclaim');
      return null;
    } else if (!prevExpr.valid || thisExpr.empty || prevExpr.empty) {
      setStatus('valid');
      return null;
    } else {
      setStatus('progress');
      final DifferenceBranch current =
          difference == null ? null : await difference;
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
        setStatus(result.different && !result.resolved ? 'error' : 'valid');
        if (result.different && result.resolved) {
          afterResolve.add(null);
        }

        completer.complete(result);
        return result;
      } else {
        setStatus(current.different && !current.resolved ? 'error' : 'valid');
        return difference;
      }
    }
  }

  void ensureNext() {
    if (next == null) {
      next = new StepEditor(interface, db, root, this);
    }
  }
}
