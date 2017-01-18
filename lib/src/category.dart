// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertCategoryWithParents = '''
INSERT INTO category VALUES (DEFAULT, array_append(
  (SELECT parents FROM category WHERE id = @parentId:int4),
  @parentId:int4)::integer[])
RETURNING id, array_to_string(parents, ',')''';

const sqlInsertCategory = '''
INSERT INTO category VALUES (DEFAULT, ARRAY[]::integer[])
RETURNING id, array_to_string(parents, ',')''';

Future<table.Category> _createCategory(DbPool db, CreateCategory input) async {
  if (input.parentId != null) {
    // First check if parent exists.
    final result = await db.query(
        "SELECT id FROM category WHERE id = @parentId:int4",
        {'parentId': input.parentId});
    if (result.length == 1) {
      final result = await db
          .query(sqlInsertCategoryWithParents, {'parentId': input.parentId});
      return new table.Category.from(result.first);
    } else {
      throw new ArgumentError('parentId does not exist');
    }
  } else {
    final result = await db.query(sqlInsertCategory);
    return new table.Category.from(result.first);
  }
}

class CreateCategory {
  int parentId;
}
