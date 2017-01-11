// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

String sqlInsersectFunctions(List<int> functionIds) => '''
SELECT id FROM function WHERE category_id IN (
  SELECT array_append(path, id) FROM category WHERE id = @categoryId:int4)
UNION
SELECT id FROM function WHERE id IN (${functionIds.join(',')})''';

Future<table.Definition> _createDefinition(
    DbPool db, CreateDefinition input) async {
  // Decode expression headers.
  final leftData = _decodeCodecHeader(input.left);
  final rightData = _decodeCodecHeader(input.right);

  // For now we only accept single byte signed integers in non-evaluated
  // expressions.
  if (leftData.float64Count > 0 || rightData.float64Count > 0) {
    throw new RpcError(400, 'reject_expr', 'contains float64');
  }

  final completer = new Completer<table.Definition>();

  db.transaction((db) async {
    // Retrieve all function IDs that are defined under this category.
    final allIds = leftData.functionId.toSet()..addAll(rightData.functionId);
    final intersectResult = await db.query(
        sqlInsersectFunctions(allIds.toList()),
        substitutionValues: {'categoryId': input.categoryId});

    // Validate if all functions are defined in the context category.
    if (intersectResult.length != allIds.length) {
      throw new RpcError(400, 'reject_expr', 'not all functions are known');
    }

    // Decode expressions.
    final leftExpr = exprCodecDecode(leftData);
    final rightExpr = exprCodecDecode(rightData);
    final initialEq = new Eq(leftExpr, rightExpr);

    // Create new lineage tree.
    final tree = await _createLineageTree(db, initialEq, input.categoryId);

    // Insert definition.
    final insertResult = await db.query(
        'INSERT INTO definition VALUES (DEFAULT, @treeId:int4) RETURNING *',
        substitutionValues: {'treeId': tree.id});
    completer.complete(new table.Definition.from(insertResult));
  }).catchError(completer.completeError);

  return completer.future;
}

class CreateDefinition {
  int id, categoryId;
  String left, right;
}
