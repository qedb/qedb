// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

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
  } else if (expr is SymbolExpr) {
    nodeType = expr.isGeneric ? 'generic' : 'function';
    nodeValue = expr.id;
    nodeArguments = [];
  } else if (expr is FunctionExpr) {
    nodeType = expr.isGeneric ? 'generic' : 'function';
    nodeValue = expr.id;

    // Get expression IDs for all arguments.
    nodeArguments = new List<int>();
    for (final arg in expr.args) {
      nodeArguments.add((await _createExpression(s, arg)).id);
    }
  }

  assert(nodeType != null && nodeValue != null && nodeArguments != null);

  // Create expression node.
  return await expressionHelper.insert(s, {
    'data': new Sql("decode(@data, 'base64')", {'data': base64}),
    'hash': new Sql("digest(decode(@data, 'base64') ,'sha256')"),
    'functions': new Sql('ARRAY[${codecData.functionId.join(',')}]::integer[]'),
    'node_type': nodeType,
    'node_value': nodeValue,
    'node_arguments': new Sql('ARRAY[${nodeArguments.join(',')}]::integer[]')
  });
}
