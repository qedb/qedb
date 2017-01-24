// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<table.Rule> _createRule(
    Connection db, int leftExpressionId, int rightExpressionId) async {
  return await db
      .query('INSERT INTO rule VALUES (DEFAULT, @leftId, @rightId) RETURNING *',
          {'leftId': leftExpressionId, 'rightId': rightExpressionId})
      .map(table.Rule.map)
      .single;
}
