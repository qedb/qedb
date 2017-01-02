// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

const sqlInsertCategory =
    'INSERT INTO category (id, parent) VALUES (DEFAULT, @parent:int4) RETURNING id, parent';

class CategoryResource {
  final DbPool pool;

  CategoryResource(this.pool);

  @ApiMethod(path: 'createCategory', method: 'POST')
  Future<CreatedCategory> create(CreateCategory data) async {
    final result = await pool.query(sqlInsertCategory, {'parent': data.parent});
    return new CreatedCategory.from(result.first);
  }
}

class CreatedCategory {
  final int id, parent;
  CreatedCategory(this.id, this.parent);
  factory CreatedCategory.from(List data) =>
      new CreatedCategory(data[0], data[1]);
}

class CreateCategory {
  int parent;
}
