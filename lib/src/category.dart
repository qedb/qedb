// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateCategory {
  int parentId;
}

Future<table.Category> _createCategory(Session s, CreateCategory body) async {
  if (body.parentId != null) {
    // First check if parent exists.
    if (await categoryHelper.exists(s, {'id': body.parentId})) {
      return await categoryHelper.insert(s, {
        'parents': new Sql.arrayAppend(
            '(SELECT parents FROM category WHERE id = @parent_id)',
            '@parent_id',
            'integer[]',
            {'parent_id': body.parentId})
      });
    } else {
      throw new UnprocessableEntityError(
          'parentId not found in category table');
    }
  } else {
    return await categoryHelper
        .insert(s, {'parents': new Sql('ARRAY[]::integer[]')});
  }
}
