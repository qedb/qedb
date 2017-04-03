// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

/// Shortcut for decoding base64 codec headers.
ExprCodecData _decodeCodecHeader(String base64Data) =>
    new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(base64Data)).buffer);

Future<db.ExpressionRow> _createExpression(Session s, Expr expr) async {
  // Encode expression.
  final codecData = exprCodecEncode(expr);

  // Additional check for floating point numbers.
  if (codecData.float64Count > 0) {
    throw new UnprocessableEntityError('rejected expression')
      ..errors.add(new RpcErrorDetail(
          reason: 'expression contains floating point numbers'));
  }

  // Generate BASE64 data.
  final base64 = BASE64.encode(codecData.writeToBuffer().asUint8List());

  // Check if expression exists.
  final lookupResult = await expressionHelper.select(s, {
    'hash':
        new Sql("digest(decode(@data, 'base64'), 'sha256')", {'data': base64})
  });
  if (lookupResult.isNotEmpty) {
    return lookupResult.single;
  }

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
      nodeArguments.add((await _createExpression(s, arg)).id);
    }
  }

  assert(nodeType != null && nodeValue != null && nodeArguments != null);

  // Create expression node.
  return await expressionHelper.insert(s, {
    'data': new Sql("decode(@data, 'base64')", {'data': base64}),
    'hash': new Sql("digest(decode(@data, 'base64') ,'sha256')"),
    'latex': await _renderExpressionLaTeX(s, codecData.functionId, expr),
    'functions': intarray(codecData.functionId),
    'node_type': nodeType,
    'node_value': nodeValue,
    'node_arguments': intarray(nodeArguments)
  });
}

/// Expression LaTeX rendering.
/// Internal function. Allows reuse of codec data for more efficient function ID
///
Future<String> _renderExpressionLaTeX(
    Session s, List<int> functionsInExpr, Expr expr) async {
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

  final printer = new LaTeXPrinter();

  // Retrieve latex templates and populate printer dictionary.
  var getLbl = (int id) => '\\#$id';
  if (functionsInExpr.isNotEmpty) {
    final functions = await functionHelper.selectIn(s, {'id': functionsInExpr});

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
