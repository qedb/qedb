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
  final category = await s.selectById(db.category, id);
  final subject = await s.selectById(db.subject, category.subjectId);

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
  final subjects =
      await s.selectByIds(db.subject, categories.map((row) => row.subjectId));

  // Select all translations.
  await s.select(
      db.translation,
      WHERE({
        'descriptor_id': IN(subjects.map((row) => row.descriptorId)),
        'locale_id': IN(getLocaleIds(s, locales))
      }));

  return categories;
}

/// Find category lineage for [functionIds].
/// Returns empty list if the functions are not part of a common lineage.
Future<List<int>> findCategoryLineage(Session s, List<int> functionIds) async {
  final functions = await s.selectByIds(db.function, functionIds);
  final categoryIds = functions.map((fn) => fn.categoryId).toList();
  final categories = await s.selectByIds(db.category, categoryIds);

  // Find common category inheritance line.
  final parents = _categoryLineageFor(categories.first);
  for (final category in categories.sublist(1)) {
    final _parents = _categoryLineageFor(category);
    // If this category is in the same lineage, [_parents] is either a subset or
    // a superset of [parents].
    for (var i = 0; i < _parents.length; i++) {
      // Compare with, or extend parents.
      if (i < parents.length) {
        if (parents[i] != _parents[i]) {
          return [];
        }
      } else {
        parents.add(_parents[i]);
      }
    }
  }

  return parents;
}

/// Returns copy of all parent IDs + own ID of the given [category].
List<int> _categoryLineageFor(db.CategoryRow category) {
  return new List<int>.from(category.parents)..add(category.id);
}

/// Get lowest level category of the two specified categories. Returns 0 if
/// the given categories do not share the same category lineage.
Future<int> getLowestCategory(Session s, int a, int b) async {
  // Retrieve parents of both categories.
  final aParents = _categoryLineageFor(await s.selectById(db.category, a));
  final bParents = _categoryLineageFor(await s.selectById(db.category, b));

  // The last ID in a must be in b, or the other way around.
  if (aParents.length > bParents.length) {
    if (aParents.contains(bParents.last)) {
      return aParents.last;
    }
  } else {
    if (bParents.contains(aParents.last)) {
      return bParents.last;
    }
  }

  return 0;
}
