// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

/// Shortcut for decoding base64 codec headers.
ExprCodecData _decodeCodecHeader(String base64Data) =>
    new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(base64Data)).buffer);

Future<table.Expression> _createExpression(Session s, Expr expr) async {
  // Encode expression.
  final codecData = exprCodecEncode(expr);
  final base64 = BASE64.encode(codecData.writeToBuffer().asUint8List());

  // Check if expression exists.
  final lookupResult = await expressionHelper.select(s, {
    'hash':
        new Sql("digest(decode(@data, 'base64'), 'sha256')", {'data': base64})
  });
  if (lookupResult.isNotEmpty) {
    return lookupResult.single;
  }

  // Create reference node.
  table.ExpressionReference reference;
  if (expr is NumberExpr) {
    reference = await _createIntegerReference(s, expr);
  } else if (expr is SymbolExpr) {
    reference = await _createSymbolReference(s, expr);
  } else if (expr is FunctionExpr) {
    reference = await _createFunctionReference(s, expr);
  }
  assert(reference != null);

  // Create expression node.
  return await expressionHelper.insert(s, {
    'reference': new Sql('ROW(@reference_key, @reference_type)',
        {'reference_key': reference.key, 'reference_type': reference.type}),
    'data': new Sql("decode(@data, 'base64')", {'data': base64}),
    'hash': new Sql("digest(decode(@data, 'base64') ,'sha256')"),
    'functions': new Sql('ARRAY[${codecData.functionId.join(',')}]::integer[]')
  });
}

/// Create expression reference for number expression in integer_reference.
Future<table.ExpressionReference> _createIntegerReference(
    Session s, NumberExpr expr) async {
  log.info('Creating number reference, value = ${expr.value}');

  // Insert reference.
  final integerReference =
      await integerReferenceHelper.insert(s, {'val': expr.value.toInt()});

  // Get linking data.
  return new table.ExpressionReference(integerReference.id, 'integer');
}

/// Create expression reference for symbol expression in function_reference.
Future<table.ExpressionReference> _createSymbolReference(
    Session s, SymbolExpr expr) async {
  /// Symbol references are compressed into the reference key.
  return new table.ExpressionReference(expr.id, 'symbol');
}

/// Create expression reference for function expression in function_reference.
Future<table.ExpressionReference> _createFunctionReference(
    Session s, FunctionExpr expr) async {
  log.info(
      'Creating function references, functionId: ${expr.id}, argument count: ${expr.args.length}');

  // Create map of query data.
  final Map<String, dynamic> argsData = {};
  for (var i = 0; i < expr.args.length; i++) {
    final arg = expr.args[i];
    final argExpr = await _createExpression(s, arg);
    argsData['reference_key_$i'] = argExpr.reference.key;
    argsData['reference_type_$i'] = argExpr.reference.type;
  }

  // Insert reference.
  final argRows = new List<String>.generate(
          expr.args.length, (i) => 'ROW(@reference_key_$i, @reference_type_$i)')
      .join(',');
  final functionReference = await functionReferenceHelper.insert(s, {
    'function_id': expr.id,
    'arguments': new Sql("ARRAY[$argRows]::expression_reference[]", argsData)
  });

  // Get linking data.
  return new table.ExpressionReference(functionReference.id, 'function');
}
