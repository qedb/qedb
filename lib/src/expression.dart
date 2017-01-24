// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class RetrieveTree {
  final int id;

  // Raw data constructed from the tree, NOT from the data field!
  final String rawData;

  final RetrieveTreeReference reference;

  RetrieveTree(this.id, this.rawData, this.reference);
}

class RetrieveTreeReference {
  final int id, functionId, value;
  final bool generic;
  final List<RetrieveTreeReference> arguments;
  RetrieveTreeReference(this.id,
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

/// Shortcut for decoding base64 codec headers.
ExprCodecData _decodeCodecHeader(String base64Data) =>
    new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(base64Data)).buffer);

Future<table.Expression> _createExpression(Connection db, Expr expr) async {
  // Encode expression.
  final String encodedData = expr.toBase64();

  // Check if expression exists.
  const queryLookupExpression = '''
SELECT id, (reference).key, (reference).type, encode(data, 'base64'), encode(hash, 'base64')
FROM expression WHERE hash = digest(decode(@data, 'base64'), 'sha256')''';
  final lookupResult = await db
      .query(queryLookupExpression, {'data': encodedData})
      .map(table.Expression.map)
      .toList();
  if (lookupResult.isNotEmpty) {
    return lookupResult.single;
  }

  // Create reference node.
  table.ExpressionReference reference;
  if (expr is NumberExpr) {
    reference = await _createIntegerReference(db, expr);
  } else if (expr is SymbolExpr) {
    reference = await _createSymbolReference(db, expr);
  } else if (expr is FunctionExpr) {
    reference = await _createFunctionReference(db, expr);
  }
  assert(reference != null);

  // Create expression node.
  const queryInsertExpression = '''
INSERT INTO expression
VALUES (DEFAULT, ROW(@referenceKey, @referenceType),
  decode(@data, 'base64'), digest(decode(@data, 'base64'), 'sha256'))
RETURNING id, (reference).key, (reference).type,
  encode(data, 'base64'), encode(hash, 'base64')
''';
  return await db
      .query(queryInsertExpression, {
        'referenceKey': reference.key,
        'referenceType': reference.type,
        'data': encodedData
      })
      .map(table.Expression.map)
      .single;
}

/// Create expression reference for number expression in integer_reference.
Future<table.ExpressionReference> _createIntegerReference(
    Connection db, NumberExpr expr) async {
  log.info('Creating number reference, value = ${expr.value}');

  // Insert reference.
  final integerReference = await db
      .query('INSERT INTO integer_reference VALUES (DEFAULT, @val) RETURNING *',
          {'val': expr.value.toInt()})
      .map(table.IntegerReference.map)
      .single;

  // Get linking data.
  return new table.ExpressionReference(integerReference.id, 'integer');
}

/// Create expression reference for symbol expression in function_reference.
Future<table.ExpressionReference> _createSymbolReference(
    Connection db, SymbolExpr expr) async {
  /// Symbol references are compressed into the reference key.
  return new table.ExpressionReference(expr.id, 'symbol');
}

String queryInsertFunctionReference(int argCount) {
  final args = new List<String>.generate(
      argCount, (i) => 'ROW(@referenceKey$i, @referenceType$i)',
      growable: false);
  return '''
INSERT INTO function_reference
VALUES (DEFAULT, @functionId, ARRAY[${args.join(', ')}]::expression_reference[])
RETURNING id, function_id, array_to_string(arguments, '')
''';
}

/// Create expression reference for function expression in function_reference.
Future<table.ExpressionReference> _createFunctionReference(
    Connection db, FunctionExpr expr) async {
  log.info(
      'Creating function references, functionId: ${expr.id}, argument count: ${expr.args.length}');

  // Create map of query data.
  final Map<String, dynamic> data = {'functionId': expr.id};
  for (var i = 0; i < expr.args.length; i++) {
    final arg = expr.args[i];
    final argExpr = await _createExpression(db, arg);
    data['referenceKey$i'] = argExpr.reference.key;
    data['referenceType$i'] = argExpr.reference.type;
  }

  // Insert reference.
  final functionReference = await db
      .query(queryInsertFunctionReference(expr.args.length), data)
      .map(table.FunctionReference.map)
      .single;

  // Get linking data.
  return new table.ExpressionReference(functionReference.id, 'function');
}

Future<RetrieveTree> _retrieveExpressionTree(Connection db, int id) async {
  const query = '''
SELECT id, (reference).key, (reference).type,
  encode(data, 'base64'), encode(hash, 'base64')
FROM expression WHERE id = @id''';
  final expression =
      await db.query(query, {'id': id}).map(table.Expression.map).single;
  final reference = await _retrieveExpressionTreeRef(db, expression.reference);
  final rawData = reference.buildExpression().toBase64();
  return new RetrieveTree(expression.id, rawData, reference);
}

Future<RetrieveTreeReference> _retrieveExpressionTreeRef(
    Connection db, table.ExpressionReference reference) async {
  assert(['symbol', 'function', 'integer'].contains(reference.type));

  // Symbol reference
  if (reference.type == 'symbol') {
    final row = await db.query('SELECT generic FROM function WHERE id = @id',
        {'id': reference.key}).single;
    return new RetrieveTreeReference(null,
        functionId: reference.key, generic: row.generic);
  }

  // Function reference.
  else if (reference.type == 'function') {
    const querySelectFunctionReference = '''
SELECT id, function_id, array_to_string(arguments, '')
FROM function_reference WHERE id = @id''';
    final functionRef = await db
        .query(querySelectFunctionReference, {'id': reference.key})
        .map(table.FunctionReference.map)
        .single;

    final row = await db.query('SELECT generic FROM function WHERE id = @id',
        {'id': functionRef.functionId}).single;

    final argumentsQueue = new List<Future<RetrieveTreeReference>>.generate(
        functionRef.arguments.length,
        (i) => _retrieveExpressionTreeRef(db, functionRef.arguments[i]));

    return new RetrieveTreeReference(functionRef.id,
        functionId: functionRef.functionId,
        generic: row.generic,
        arguments: await Future.wait(argumentsQueue));
  }

  // Integer reference
  else {
    final integerRef = await db
        .query('SELECT * FROM integer_reference WHERE id = @id',
            {'id': reference.key})
        .map(table.IntegerReference.map)
        .single;
    return new RetrieveTreeReference(integerRef.id, value: integerRef.value);
  }
}
