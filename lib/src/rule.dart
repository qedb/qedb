// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<table.Rule> _createRule(PostgreSQLExecutionContext db,
    int leftExpressionId, int rightExpressionId) async {
  final result = await db.query(
      'INSERT INTO rule VALUES (DEFAULT, @leftId:int4, @rightId:int4) RETURNING *',
      substitutionValues: {
        'leftId': leftExpressionId,
        'rightId': rightExpressionId
      });
  return new table.Rule.from(result);
}
