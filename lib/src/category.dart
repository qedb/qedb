// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertCategoryWithParents = '''
INSERT INTO category VALUES (DEFAULT, array_append(
  (SELECT parents FROM category WHERE id = @parentId), @parentId)::integer[])
RETURNING category.id, array_to_string(category.parents, ',')''';

const sqlInsertCategory = '''
INSERT INTO category VALUES (DEFAULT, ARRAY[]::integer[])
RETURNING id, array_to_string(parents, ',')''';

Future<table.Category> _createCategory(
    Connection db, CreateCategory input) async {
  if (input.parentId != null) {
    // First check if parent exists.
    final result = await db.query(
        "SELECT id FROM category WHERE id = @parentId",
        {'parentId': input.parentId}).toList();

    if (result.length == 1) {
      return await db
          .query(sqlInsertCategoryWithParents, {'parentId': input.parentId})
          .map(table.Category.map)
          .first;
    } else {
      // TODO: replace with proper error reporting.
      throw new ArgumentError('parentId does not exist');
    }
  } else {
    return await db.query(sqlInsertCategory).map(table.Category.map).first;
  }
}

class CreateCategory {
  int parentId;
}
