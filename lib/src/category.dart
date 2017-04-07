// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.CategoryRow> createCategory(
    Session s, int parentId, CategoryResource body) async {
  // Get subject ID directly from request, or resolve first translation provided
  // in the descriptor.
  var subjectId = body.subject.id;
  if (body.subject.id == null) {
    final translation = body.subject.descriptor.translations.single;

    // Resolve subject ID.
    final result = await s.select(
        db.subject,
        WHERE({
          'descriptor_id': IS(SUBQUERY(
              SQL('SELECT descriptor_id FROM translation'),
              WHERE({
                'content': IS(translation.content),
                'locale_id': IS(localeId(s, translation.locale))
              })))
        }));

    // If no subject exists, raise an error.
    if (result.isEmpty) {
      throw new UnprocessableEntityError(
          'subject translation could not be resolved to a subject');
    }

    subjectId = result.single.id;
  }

  // Check if any function subject tag references this subject.
  if (await s.exists(
      db.functionSubjectTag, WHERE({'subject_id': IS(subjectId)}))) {
    throw new UnprocessableEntityError(
        'subject already used by function subject tag');
  }

  if (parentId > 0) {
    // First check if parent exists.
    if (await s.exists(db.category, WHERE({'id': IS(parentId)}))) {
      return await s.insert(
          db.category,
          VALUES({
            'subject_id': subjectId,
            'parents': FUNCTION(
                'array_append::integer[]',
                SUBQUERY(SQL('SELECT parents FROM category'),
                    WHERE({'id': IS(parentId)})),
                parentId)
          }));
    } else {
      throw new UnprocessableEntityError(
          'parentId not found in category table');
    }
  } else {
    return await s.insert(
        db.category,
        VALUES(
            {'subject_id': subjectId, 'parents': SQL('ARRAY[]::integer[]')}));
  }
}

Future<db.CategoryRow> readCategory(
    Session s, int id, List<String> locales) async {
  final category = await s.selectFirst(db.category, WHERE({'id': IS(id)}));
  final subject =
      await s.selectFirst(db.subject, WHERE({'id': IS(category.subjectId)}));

  await s.select(
      db.translation,
      WHERE({
        'descriptor_id': IS(subject.descriptorId),
        'locale_id': IN(getLocaleIds(s, locales))
      }));

  return category;
}

Future<List<db.CategoryRow>> listCategories(Session s, List<String> locales,
    [int parentId = 0]) async {
  final categories = parentId == 0
      ? await s.select(db.category)
      : await s.select(
          db.category,
          WHERE({
            'parents': IS(FUNCTION(
                'array_append',
                SUBQUERY(SQL('SELECT parents FROM category'),
                    WHERE({'id': IS(parentId)})),
                parentId))
          }));

  if (categories.isEmpty) {
    return [];
  }

  // Select all subjects.
  final subjects = await s.select(
      db.subject, WHERE({'id': IN(categories.map((row) => row.subjectId))}));

  // Select all translations.
  await s.select(
      db.translation,
      WHERE({
        'descriptor_id': IN(subjects.map((row) => row.descriptorId)),
        'locale_id': IN(getLocaleIds(s, locales))
      }));

  return categories;
}
