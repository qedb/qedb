// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertLineageTree = '''
WITH tree_id AS (
  INSERT INTO lineage_tree VALUES (DEFAULT) RETURNING id
) INSERT INTO lineage (tree, initial_category)
SELECT id, @category:int4 FROM tree_id
RETURNING *''';

const sqlInsertDefinedLineageExpressions = '''
INSERT INTO lineage_expression
VALUES (DEFAULT, @leftExpressionId:int4, @lineageId:int4, 0, 0);
INSERT INTO lineage_expression
VALUES (DEFAULT, @rightExpressionId:int4, @lineageId:int4, 1, 1);
''';

Future<table.LineageTree> _createLineageTree(
    PostgreSQLExecutionContext db, Eq initialEq, int category) async {
  // Create new tree.
  final result = await db
      .query(sqlInsertLineageTree, substitutionValues: {'category': category});
  final lineage = new table.Lineage.from(result.first);

  // Create two expressions.
  final leftExpr = await _createExpression(db, initialEq.left);
  final rightExpr = await _createExpression(db, initialEq.right);

  // Add expression to the lineage.
  await db.query(sqlInsertDefinedLineageExpressions, substitutionValues: {
    'lineageId': lineage.id,
    'leftExpressionId': leftExpr.id,
    'rightExpressionId': rightExpr.id
  });

  return new table.LineageTree(lineage.treeId);
}
