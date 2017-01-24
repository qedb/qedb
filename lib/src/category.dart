// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<table.Category> _createCategory(
    Connection db, CreateCategory input) async {
  if (input.parentId != null) {
    // First check if parent exists.
    const query = 'SELECT id FROM category WHERE id = @parentId';
    final result = await db.query(query, {'parentId': input.parentId}).toList();

    if (result.length == 1) {
      const query = '''
INSERT INTO category VALUES (DEFAULT, array_append(
  (SELECT parents FROM category WHERE id = @parentId), @parentId)::integer[])
RETURNING category.id, array_to_string(category.parents, ',')''';

      return await db
          .query(query, {'parentId': input.parentId})
          .map(table.Category.map)
          .single;
    } else {
      throw new UnprocessableEntityError(
          'parentId not found in category table');
    }
  } else {
    const query = '''
INSERT INTO category VALUES (DEFAULT, ARRAY[]::integer[])
RETURNING id, array_to_string(parents, ',')''';

    return await db.query(query).map(table.Category.map).single;
  }
}

class CreateCategory {
  int parentId;
}
