// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlSelectExprLookup = '''
SELECT id, link.id, link.ref, encode(data, 'base64'), encode(data, 'base64')
FROM expression WHERE hash = digest(decode(@data:text, 'base64'), 'sha256')
''';

const sqlInsertExpr = '''
INSERT INTO expression
VALUES (DEFAULT, (@referenceId:int4, @referenceType:text)::expression_reference,
  decode(@data:text, 'base64'), digest(decode(@data:text, 'base64'), 'sha256'))
RETURNING id, reference.id, reference.type,
  encode(data, 'base64'), encode(hash, 'base64')
''';

const sqlInsertSymbolFunctionRef = '''
INSERT INTO function_reference
VALUES (DEFAULT, @functionId:int4, ARRAY[])
RETURNING *''';

String sqlInsertFunctionRef(int argCount) {
  final args = new List<String>.generate(
      argCount, (i) => 'ROW(@referenceId$i:int4, @referenceType$i:text)');
  return '''
INSERT INTO function_reference
VALUES (DEFAULT, @functionId:int4, ARRAY[${args.join(', ')}])
RETURNING id, fn, args;
''';
}

/// Shortcut for decoding base64 codec headers.
ExprCodecData _decodeCodecHeader(String base64Data) =>
    new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(base64Data)).buffer);

Future<table.Expression> _createExpression(
    PostgreSQLExecutionContext db, Expr expr) async {
  // Encode expression.
  final encodedData = expr.toBase64();

  // Check if expression exists.
  final lookupResult = await db
      .query(sqlSelectExprLookup, substitutionValues: {'data': encodedData});
  if (lookupResult.isNotEmpty) {
    return new table.Expression.from(lookupResult);
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
  final insertResult = await db.query(sqlInsertExpr, substitutionValues: {
    'referenceId': reference.id,
    'referenceType': reference.referenceType,
    'data': encodedData
  });
  return new table.Expression.from(insertResult);
}

/// Create expression reference for number expression in integer_reference.
Future<table.ExpressionReference> _createNumberReference(
    PostgreSQLExecutionContext db, NumberExpr expr) async {
  // Insert record.
  final result = await db.query(
      'INSERT INTO integer_reference VALUES (DEFAULT, @val:int4) RETURNING *',
      substitutionValues: {'val': expr.value.toInt()});

  // Get linking data.
  final intRef = new table.IntegerReference.from(result.first);
  return new table.ExpressionReference(intRef.id, 'integer');
}

/// Create expression reference for symbol expression in function_reference.
Future<table.ExpressionReference> _createSymbolReference(
    PostgreSQLExecutionContext db, SymbolExpr expr) async {
  final result = await db.query(sqlInsertSymbolFunctionRef,
      substitutionValues: {'functionId': expr.id});

  // Get linking data.
  final functionRef = new table.FunctionReference.from(result);
  return new table.ExpressionReference(functionRef.id, 'function');
}

/// Create expression reference for function expression in function_reference.
Future<table.ExpressionReference> _createFunctionReference(
    PostgreSQLExecutionContext db, FunctionExpr expr) async {
  // Create map of query data.
  Map<String, dynamic> data = {'functionId': expr.id};
  for (var i = 0; i < expr.args.length; i++) {
    final arg = expr.args[i];
    final argExpr = await _createExpression(db, arg);
    data['referenceId$i'] = argExpr.reference.id;
    data['referenceType$i'] = argExpr.reference.referenceType;
  }

  // Insert record.
  final result = await db.query(sqlInsertFunctionRef(expr.args.length),
      substitutionValues: data);

  // Get linking data.
  final funcRef = new table.FunctionReference.from(result);
  return new table.ExpressionReference(funcRef.id, 'function');
}
