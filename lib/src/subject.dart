// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.SubjectRow> createSubject(Session s, SubjectResource body) async {
  if (body.descriptor.id != null) {
    return subjectHelper.insert(s, {'descriptor_id': body.descriptor.id});
  } else {
    return subjectHelper.insert(
        s, {'descriptor_id': (await createDescriptor(s, body.descriptor)).id});
  }
}

Future<List<db.SubjectRow>> listSubjects(
    Session s, List<String> locales) async {
  final subjects = await subjectHelper.select(s, {});
  final descriptors = await descriptorHelper.selectIn(
      s, {'id': subjectHelper.ids(subjects, (row) => row.descriptorId)});

  // Select all translations.
  await translationHelper.selectIn(s, {
    'descriptor_id': getIds(descriptors),
    'locale_id': await getLocaleIds(s, locales)
  });

  return subjects;
}
