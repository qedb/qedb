// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertCategory = '''
WITH path AS (SELECT path FROM category WHERE id = @parentId:int4)
INSERT INTO category VALUES (DEFAULT, path || @parentId:int4)
RETURNING id, unnest(path);''';

Future<table.Category> _createCategory(DbPool db, CreateCategory input) async {
  final result =
      await db.query(sqlInsertCategory, {'parentId': input.parentId});
  return new table.Category.from(result);
}

class CreateCategory {
  final int parentId;
  CreateCategory(this.parentId);
}
