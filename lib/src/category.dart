// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CategoryResource {
  final DbPool pool;

  CategoryResource(this.pool);

  @ApiMethod(path: 'createCategory', method: 'POST')
  CreatedCategory create(CreateCategory data) {
    pool.query('INSERT INTO category VALUES (NULL)');
    return new CreatedCategory();
  }
}

class CreatedCategory {}

class CreateCategory {}
