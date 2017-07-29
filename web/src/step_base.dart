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
abstract class StepBase {
  final QEDbEdiTeXInterface interface;
  final QedbApi db;

  /// Reference to a list of free substitutions that is send to the server.
  /// The list snapshot is updated after every resolving cycle.
  final List<Subs> freeConditions, freeConditionsBackup = [];

  /// DOM element that contains all steps
  final Element root;

  /// DOM element of the row container
  final Element row;

  /// Other elements
  final Element container, status;

  /// Previous and next step
  StepBase prev, next;

  /// Pending resolve data
  Future<ResolveBranch> resolveBranch;

  /// Difference table
  TableElement difftable;

  /// Stream to be triggered by the implementation when the user is done with
  /// editing of any sort
  /// Important: the step implementation must call this.
  final afterUpdate = new StreamController<Null>.broadcast();

  /// Stream that is triggered when the difference between this step and the
  /// previous one is resolved. Called in [resolveStepDifference]. The value
  /// indicates if the resolving was successful.
  final afterResolve = new StreamController<bool>.broadcast();

  /// All subscriptions that must be cancelled on remove.
  final subscriptions = new List<StreamSubscription>();

  StepBase(this.interface, this.db, this.root, this.row, this.container,
      this.status, this.prev, this.freeConditions) {
    if (prev != null) {
      subscriptions.add(prev.afterResolve.stream.listen((v) {
        resolveStepDifference();
      }));

      subscriptions.add(afterUpdate.stream.listen((_) {
        resolveStepDifference();
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
      if (resolveBranch != null) {
        if (difftable != null) {
          difftable.remove();
          difftable = null;
        } else {
          // Insert difference table.
          final resolvedBranch = await resolveBranch;
          difftable = createDifferenceTable(interface, resolvedBranch);
          row.parent.insertBefore(difftable, row);
        }
      }
    });

    // Update difference table after step difference is resolved.
    subscriptions.add(afterResolve.stream.listen((resolved) async {
      if (difftable != null) {
        difftable.remove();

        if (resolveBranch != null) {
          // Await difference and use it to generate a table.
          final resolvedBranch = await resolveBranch;
          difftable = createDifferenceTable(interface, resolvedBranch);
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
    data.steps = new List<ResolveBranch>();
    await writeData(data);
    return data;
  }

  /// Write data in this step (and child steps) to [data].
  Future writeData(ProofData data) async {
    if (!isEmptyRecursive()) {
      if (prev != null) {
        final difference = await resolveStepDifference();
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
  Future<ResolveBranch> resolveStepDifference() async {
    final prevExpr = prev.getExpression();
    final thisExpr = getExpression();
    if (!thisExpr.valid) {
      setStatus('exclaim');
      resolveBranch = null;
      afterResolve.add(false);
      return null;
    } else if (!prevExpr.valid || thisExpr.empty || prevExpr.empty) {
      setStatus('valid');
      resolveBranch = null;
      afterResolve.add(false);
      return null;
    } else {
      setStatus('progress');
      final current = resolveBranch == null ? null : await resolveBranch;
      final target = new RpcSubs();
      target.left = prevExpr.expression.toBase64();
      target.right = thisExpr.expression.toBase64();

      // Check if difference resolving is neccesary.
      // It is neccesary when there is a difference with the current state, or
      // if the list of free conditions has changed.
      // TODO: skip if there is an unconflicting change in free conditions and
      //       the difference has already been resolved.
      if (current == null ||
          target.left != current.subs.left ||
          target.right != current.subs.right ||
          !(const ListEquality()
              .equals(freeConditions, freeConditionsBackup))) {
        // Construct difference resolving request data.
        final request = new ResolveRequest()
          ..target = target
          ..freeConditions = freeConditions
              .map((subs) => subs.left == null || subs.right == null
                  ? (new RpcSubs()
                    ..left = ''
                    ..right = '')
                  : subsToRpcSubs(subs))
              .toList();

        // Note: it is important that we assign the completer future here else
        // we open an infinite waiting loop.
        final completer = new Completer<ResolveBranch>();
        resolveBranch = completer.future;
        final result = await db.resolveSubstitution(request);

        // Update freeConditionsBackup.
        freeConditionsBackup
          ..clear()
          ..addAll(freeConditions);

        // Update status and trigger stream.
        setStatus(result.different && !result.resolved ? 'error' : 'resolved');
        afterResolve.add(result.resolved);
        completer.complete(result);
        return result;
      } else {
        setStatus(
            current.different && !current.resolved ? 'error' : 'resolved');
        afterResolve.add(current.resolved);
        return resolveBranch;
      }
    }
  }

  void ensureNext() {
    next ??= new StepEditor(interface, db, root, this, freeConditions);
  }
}

RpcSubs subsToRpcSubs(Subs subs) => new RpcSubs()
  ..left = subs.left.toBase64()
  ..right = subs.right.toBase64();
