// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateLineage {
  @ApiProperty(required: true)
  String firstExpression;
}

Future<table.Lineage> _createLineage(Connection db, CreateLineage input) async {
  // Decode expression.
  final header = _decodeCodecHeader(input.firstExpression);

  // Compute category.
  final queryFindCategory = '''
WITH tmp AS (
  SELECT id, unnest(array_append(parents, 0)) FROM category WHERE id IN (
    SELECT category_id FROM function WHERE id IN (${header.functionId.join(',')})))
SELECT DISTINCT id FROM tmp WHERE id NOT IN (SELECT unnest FROM tmp)''';
  final parentCategory = new List<int>.from(
      await db.query(queryFindCategory).map((r) => r[0]).toList());
  if (parentCategory.length > 1) {
    throw new UnprocessableEntityError(
        'expression depends on multiple isolated categories: $parentCategory');
  }

  // Insert expression.
  final expression = await _createExpression(db, exprCodecDecode(header));

  // Insert lineage.
  const queryInsertLineage = '''
WITH tree_id AS (
  INSERT INTO lineage_tree VALUES (DEFAULT) RETURNING id
) INSERT INTO lineage (tree_id, initial_category_id, first_expression_id)
SELECT id, @categoryId, @expressionId FROM tree_id
RETURNING *''';
  return await db
      .query(queryInsertLineage,
          {'categoryId': parentCategory.first, 'expressionId': expression.id})
      .map(table.Lineage.map)
      .single;
}
