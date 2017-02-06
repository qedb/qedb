// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateCategory {
  @ApiProperty(required: false)
  int parentId;

  @ApiProperty(required: true)
  CreateTranslation name;
}

Future<db.CategoryTable> _createCategory(Session s, CreateCategory body) async {
  // Resolve subject ID.
  final result = await subjectHelper.selectCustom(
      s,
      '''
SELECT * FROM subject WHERE descriptor_id = (
  SELECT descriptor_id FROM translation
  WHERE content = @content AND locale_id = (
    SELECT id FROM locale WHERE code = @locale))''',
      {'content': body.name.content, 'locale': body.name.locale});

  // If no subject exists, raise an error.
  if (result.isEmpty) {
    throw new UnprocessableEntityError(
        'name could not be identified as subject');
  }

  final subject = result.single;

  // Check if any function subject tag references this subject.
  if (await functionSubjectTagHelper.exists(s, {'subject_id': subject.id})) {
    throw new UnprocessableEntityError(
        'subject already used by function subject tag');
  }

  if (body.parentId != null) {
    // First check if parent exists.
    if (await categoryHelper.exists(s, {'id': body.parentId})) {
      return await categoryHelper.insert(s, {
        'subject_id': subject.id,
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
    return await categoryHelper.insert(s,
        {'subject_id': subject.id, 'parents': new Sql('ARRAY[]::integer[]')});
  }
}
