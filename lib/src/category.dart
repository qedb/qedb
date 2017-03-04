// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.CategoryRow> createCategory(
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
descriptor_id = (
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

Future<db.CategoryRow> readCategory(
    Session s, int id, List<String> locales) async {
  final category = await categoryHelper.selectOne(s, {'id': id});
  final subject = await subjectHelper.selectOne(s, {'id': category.subjectId});
  await translationHelper.selectIn(s, {
    'descriptor_id': [subject.descriptorId],
    'locale_id': getLocaleIds(s.data.cache, locales)
  });
  return category;
}

Future<List<db.CategoryRow>> listCategories(Session s, List<String> locales,
    [int parentId = -1]) async {
  final categories = parentId == -1
      ? await categoryHelper.select(s, {})
      : await categoryHelper.selectCustom(
          s,
          '''parents = array_append(
            (SELECT parents FROM category WHERE id = @parent_id), @parent_id)''',
          {'parent_id': parentId});

  if (categories.isEmpty) {
    return [];
  }

  // Select all subjects.
  final subjectIds = categoryHelper.ids(categories, (row) => row.subjectId);
  final subjects = await subjectHelper.selectIn(s, {'id': subjectIds});

  // Select all translations.
  final descriptorIds = subjectHelper.ids(subjects, (row) => row.descriptorId);
  await translationHelper.selectIn(s, {
    'descriptor_id': descriptorIds,
    'locale_id': getLocaleIds(s.data.cache, locales)
  });

  return categories;
}
