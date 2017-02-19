// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.CategoryRow> _createCategory(
    Session s, int parentId, CategoryResource body) async {
  // Get subject ID directly from request, or resolve first translation provided
  // in the descriptor.
  var subjectId = body.subject.id;
  if (body.subject.id == null) {
    final translation = body.subject.descriptor.translations.single;

    // Resolve subject ID.
    final result = await subjectHelper.selectCustom(
        s,
        '''
SELECT * FROM subject WHERE descriptor_id = (
  SELECT descriptor_id FROM translation
  WHERE content = @content AND locale_id = @locale_id)''',
        {
          'content': translation.content,
          'locale_id': translation.locale.getId(s.data)
        });

    // If no subject exists, raise an error.
    if (result.isEmpty) {
      throw new UnprocessableEntityError(
          'subject translation could not be resolved to a subject');
    }

    subjectId = result.single.id;
  }

  // Check if any function subject tag references this subject.
  if (await functionSubjectTagHelper.exists(s, {'subject_id': subjectId})) {
    throw new UnprocessableEntityError(
        'subject already used by function subject tag');
  }

  if (parentId > 0) {
    // First check if parent exists.
    if (await categoryHelper.exists(s, {'id': parentId})) {
      return await categoryHelper.insert(s, {
        'subject_id': subjectId,
        'parents': new Sql.arrayAppend(
            '(SELECT parents FROM category WHERE id = @parent_id)',
            '@parent_id',
            'integer[]',
            {'parent_id': parentId})
      });
    } else {
      throw new UnprocessableEntityError(
          'parentId not found in category table');
    }
  } else {
    return await categoryHelper.insert(
        s, {'subject_id': subjectId, 'parents': new Sql('ARRAY[]::integer[]')});
  }
}
