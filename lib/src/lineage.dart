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
