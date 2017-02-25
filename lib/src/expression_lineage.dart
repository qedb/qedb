// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.ExpressionLineageRow> _createExpressionLineage(
    Session s, ExpressionLineageResource body) async {
  final lineage = await expressionLineageHelper.insert(s, {});

  /*for (final expression in body.expressions) {
    await _createLineageExpression(s, expression);
  }*/

  return lineage;
}

/*Future<db.LineageExpressionRow> _createLineageExpression(
    Session s, LineageExpressionResource body) async {
  // Decode expression.
  final header = _decodeCodecHeader(body.expression.data);

  // Compute category.
  final queryFindCategory = '''
WITH tmp AS (
  SELECT id, unnest(array_append(parents, 0)) FROM category WHERE id IN (
    SELECT category_id FROM function WHERE id IN (${header.functionId.join(',')})))
SELECT DISTINCT id FROM tmp WHERE id NOT IN (SELECT unnest FROM tmp)''';
  final parentCategory = new List<int>.from(
      await s.conn.query(queryFindCategory).map((r) => r[0]).toList());
  if (parentCategory.length > 1) {
    throw new UnprocessableEntityError(
        'expression depends on multiple isolated categories: $parentCategory');
  }

  // Insert expression.
  final expression = await _createExpression(s, exprCodecDecode(header));
}*/
