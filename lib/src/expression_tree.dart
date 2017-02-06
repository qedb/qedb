// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class ExpressionTree {
  final int id;
  final ExpressionTreeReference reference;

  /// Raw Base64 data constructed from the tree, NOT from the data field!
  final String rawData;

  ExpressionTree(this.id, this.rawData, this.reference);
}

class ExpressionTreeReference {
  final int id, functionId, value;
  final bool generic;
  final List<ExpressionTreeReference> arguments;

  ExpressionTreeReference(this.id,
      {this.functionId, this.value, this.generic, this.arguments});

  /// Build Expr instance from this reference.
  Expr buildExpression() {
    if (value != null) {
      return new NumberExpr(value);
    } else if (arguments == null) {
      return new SymbolExpr(functionId, generic);
    } else {
      return new FunctionExpr(
          functionId,
          new List<Expr>.generate(
              arguments.length, (i) => arguments[i].buildExpression()),
          generic);
    }
  }
}

Future<ExpressionTree> _retrieveExpressionTree(Session s, int id) async {
  final result = await expressionHelper.select(s, {'id': id});
  if (result.isNotEmpty) {
    final expr = result.single;
    final reference = await _retrieveExpressionTreeRef(s, expr.reference);
    final rawData = reference.buildExpression().toBase64();

    /// Return an expression tree.
    return new ExpressionTree(expr.id, rawData, reference);
  } else {
    throw new NotFoundError('expression #$id could not be found');
  }
}

Future<ExpressionTreeReference> _retrieveExpressionTreeRef(
    Session s, db.ExpressionReference reference) async {
  assert(['symbol', 'function', 'integer'].contains(reference.type));

  // Symbol reference
  if (reference.type == 'symbol') {
    final function = await functionHelper.selectOne(s, {'id': reference.key});
    return new ExpressionTreeReference(null,
        functionId: reference.key, generic: function.generic);
  }

  // Function reference.
  else if (reference.type == 'function') {
    final functionRef =
        await functionReferenceHelper.selectOne(s, {'id': reference.key});
    final function =
        await functionHelper.selectOne(s, {'id': functionRef.functionId});

    final argumentsQueue = new List<Future<ExpressionTreeReference>>.generate(
        functionRef.arguments.length,
        (i) => _retrieveExpressionTreeRef(s, functionRef.arguments[i]));

    return new ExpressionTreeReference(functionRef.id,
        functionId: functionRef.functionId,
        generic: function.generic,
        arguments: await Future.wait(argumentsQueue));
  }

  // Integer reference
  else {
    final integerRef =
        await integerReferenceHelper.selectOne(s, {'id': reference.key});
    return new ExpressionTreeReference(integerRef.id, value: integerRef.value);
  }
}
