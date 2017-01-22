// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

// Cannot seelect link.id, link.ref directly!!!!
const sqlSelectExprLookup = '''
SELECT id, (reference).id, (reference).type, encode(data, 'base64'), encode(hash, 'base64')
FROM expression WHERE hash = digest(decode(@data, 'base64'), 'sha256')
''';

const sqlInsertExpr = '''
INSERT INTO expression
VALUES (DEFAULT, ROW(@referenceId, @referenceType),
  decode(@data, 'base64'), digest(decode(@data, 'base64'), 'sha256'))
RETURNING id, (reference).id, (reference).type,
  encode(data, 'base64'), encode(hash, 'base64')
''';

String sqlInsertFunctionRef(int argCount) {
  final args = new List<String>.generate(
      argCount, (i) => 'ROW(@referenceId$i, @referenceType$i)',
      growable: false);
  return '''
INSERT INTO function_reference
VALUES (DEFAULT, @functionId, ARRAY[${args.join(', ')}]::expression_reference[])
RETURNING id, function_id, array_to_string(arguments, '')
''';
}

/// Shortcut for decoding base64 codec headers.
ExprCodecData _decodeCodecHeader(String base64Data) =>
    new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(base64Data)).buffer);

Future<table.Expression> _createExpression(Connection db, Expr expr) async {
  // Encode expression.
  final String encodedData = expr.toBase64();

  // Check if expression exists.
  final lookupResult = await db
      .query(sqlSelectExprLookup, {'data': encodedData})
      .map(table.Expression.map)
      .toList();
  if (lookupResult.isNotEmpty) {
    return lookupResult.first;
  }

  // Create reference node.
  table.ExpressionReference reference;
  if (expr is NumberExpr) {
    reference = await _createNumberReference(db, expr);
  } else if (expr is SymbolExpr) {
    reference = await _createSymbolReference(db, expr);
  } else if (expr is FunctionExpr) {
    reference = await _createFunctionReference(db, expr);
  } else {
    throw new UnsupportedError('unsupported expression type');
  }

  // Create expression node.
  return await db
      .query(sqlInsertExpr, {
        'referenceId': reference.id,
        'referenceType': 'function',
        'data': encodedData
      })
      .map(table.Expression.map)
      .first;
}

/// Create expression reference for number expression in integer_reference.
Future<table.ExpressionReference> _createNumberReference(
    Connection db, NumberExpr expr) async {
  log.info('Creating number reference, value = ${expr.value}');

  // Insert reference.
  final intRef = await db
      .query('INSERT INTO integer_reference VALUES (DEFAULT, @val) RETURNING *',
          {'val': expr.value.toInt()})
      .map(table.IntegerReference.map)
      .first;

  // Get linking data.
  return new table.ExpressionReference(intRef.id, 'integer');
}

/// Create expression reference for symbol expression in function_reference.
Future<table.ExpressionReference> _createSymbolReference(
    Connection db, SymbolExpr expr) async {
  log.info('Creating symbol reference, id = ${expr.id}');

  // Insert reference.
  final functionRef = await db
      .query(sqlInsertFunctionRef(0), {'functionId': expr.id})
      .map(table.FunctionReference.map)
      .first;

  // Get linking data.
  return new table.ExpressionReference(functionRef.id, 'function');
}

/// Create expression reference for function expression in function_reference.
Future<table.ExpressionReference> _createFunctionReference(
    Connection db, FunctionExpr expr) async {
  log.info(
      'Creating function references, id = ${expr.id}, argument count = ${expr.args.length}');

  // Create map of query data.
  Map<String, dynamic> data = {'functionId': expr.id};
  for (var i = 0; i < expr.args.length; i++) {
    final arg = expr.args[i];
    final argExpr = await _createExpression(db, arg);
    data['referenceId$i'] = argExpr.reference.id;
    data['referenceType$i'] = argExpr.reference.type;
  }

  // Insert reference.
  final functionRef = await db
      .query(sqlInsertFunctionRef(expr.args.length), data)
      .map(table.FunctionReference.map)
      .first;

  // Get linking data.
  return new table.ExpressionReference(functionRef.id, 'function');
}
