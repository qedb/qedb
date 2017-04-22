// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.ExpressionRow> _createExpression(Session s, Expr expr,
    [OperatorConfig operatorConfig]) async {
  // Encode expression.
  final codecData = exprCodecEncode(expr);

  // Expression may not contain floating point numbers.
  if (codecData.containsFloats()) {
    throw new UnprocessableEntityError('rejected expression')
      ..errors.add(new RpcErrorDetail(
          reason: 'expression contains floating point numbers'));
  }

  if (codecData.functionIds.isNotEmpty) {
    final functions = await s.selectByIds(db.function, codecData.functionIds);
    for (final fn in functions) {
      // Validate function.
      final fnIdx = codecData.functionIds.indexOf(fn.id);
      if (codecData.functionArgcs[fnIdx] != fn.argumentCount ||
          codecData.inGenericRange(fnIdx) != fn.generic) {
        throw new UnprocessableEntityError(
            'expression not compatible with function table');
      }
    }
  }

  // Generate BASE64 data.
  final base64 = BASE64.encode(codecData.writeToBuffer().asUint8List());

  // Check if expression exists.
  final lookupResult = await s.select(
      db.expression,
      WHERE({
        'hash': IS(
            FUNCTION('digest', FUNCTION('decode', base64, 'base64'), 'sha256'))
      }));

  if (lookupResult.isNotEmpty) {
    return lookupResult.single;
  }

  // Make sure we have a valid operator configuration.
  final ops = operatorConfig ?? await _loadOperatorConfig(s);

  // Resolve expression node parameters.
  String nodeType;
  int nodeValue;
  List<int> nodeArguments;

  if (expr is NumberExpr) {
    nodeType = 'integer';
    nodeValue = expr.value;
    nodeArguments = [];
  } else if (expr is FunctionExpr) {
    nodeType = expr.isGeneric ? 'generic' : 'function';
    nodeValue = expr.id;

    // Get expression IDs for all arguments.
    nodeArguments = new List<int>();
    for (final arg in expr.arguments) {
      nodeArguments.add((await _createExpression(s, arg, ops)).id);
    }
  }

  assert(nodeType != null && nodeValue != null && nodeArguments != null);

  // Create expression node.
  return await s.insert(
      db.expression,
      VALUES({
        'data': DECODE(base64, 'base64'),
        'hash': DIGEST(DECODE(base64, 'base64'), 'sha256'),
        'latex': await _renderExpressionLaTeX(s, expr, ops),
        'functions': ARRAY(codecData.functionIds, 'integer'),
        'node_type': nodeType,
        'node_value': nodeValue,
        'node_arguments': ARRAY(nodeArguments, 'integer')
      }));
}

Future<List<db.ExpressionRow>> listExpressions(
    Session s, Iterable<int> ids) async {
  final expressions = await s.selectByIds(db.expression, ids);

  // Check if there are any NULL latex fields.
  final queue = new List<Future>();
  final ops = await _loadOperatorConfig(s);
  for (var i = 0; i < expressions.length; i++) {
    final expr = expressions[i];
    if (expr.latex == null) {
      final latex =
          _renderExpressionLaTeX(s, new Expr.fromBase64(expr.data), ops);
      queue.add(s
          .update(
              db.expression, WHERE({'id': IS(expr.id)}), SET({'latex': latex}))
          .then((rows) {
        expressions[i] = rows.single;
      }));
    }
  }
  await Future.wait(queue);

  return expressions;
}

Future<OperatorConfig> _loadOperatorConfig(Session s) async {
  // Load operators.
  final ops = new OperatorConfig();
  final operators = await listOperators(s);

  // Populate operator config.
  for (final op in operators) {
    ops.add(new Operator(
        op.id,
        op.precedenceLevel,
        op.associativity == 'ltr' ? Associativity.ltr : Associativity.rtl,
        op.character.runes.first,
        op.operatorType == 'infix'
            ? OperatorType.infix
            : op.operatorType == 'prefix'
                ? OperatorType.prefix
                : OperatorType.postfix));
  }

  // Add default setting for implicit multiplication.
  // (same precedence level as power operator).
  ops.add(new Operator(
      ops.implicitMultiplyId,
      ops.byId[ops.id('^')].precedenceLevel,
      Associativity.rtl,
      -1,
      OperatorType.infix));

  return ops;
}

/// Expression LaTeX rendering.
/// Internal function. Allows reuse of codec data for more efficient function ID
Future<String> _renderExpressionLaTeX(
    Session s, Expr expr, OperatorConfig ops) async {
  final printer = new LaTeXPrinter();

  // Retrieve latex templates and populate printer dictionary.
  var getLbl = (int id) => '\\#$id';
  final functionIds = expr.functionIds;
  if (functionIds.isNotEmpty) {
    final functions = await s.selectByIds(db.function, functionIds);

    // Create new LaTeX printer and populate dictionary.
    functions.forEach((row) {
      if (row.latexTemplate != null) {
        printer.dict[row.id] = row.latexTemplate;
      }
    });

    // Also look for fallback labels in function keywords.
    // A constraint ensures that either a template or a keyword is present.
    getLbl = (int id) => functions.singleWhere((r) => r.id == id).keyword;
  }

  // Print expression.
  return printer.render(expr, getLbl, ops);
}
