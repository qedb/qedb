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
  final base64 = BASE64.encode(codecData.writeToBuffer().asUint8List());

  // Check if expression exists.
  final lookupResult = await expressionHelper.select(s, {
    'hash':
        new Sql("digest(decode(@data, 'base64'), 'sha256')", {'data': base64})
  });
  if (lookupResult.isNotEmpty) {
    return lookupResult.single;
  }

  // Create expression node.
  return await expressionHelper.insert(s, {
    'data': new Sql("decode(@data, 'base64')", {'data': base64}),
    'hash': new Sql("digest(decode(@data, 'base64') ,'sha256')"),
    'functions': new Sql('ARRAY[${codecData.functionId.join(',')}]::integer[]')
  });
}
