// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.SubjectRow> createSubject(Session s, SubjectResource body) async {
  return s.insert(
      db.subject,
      VALUES(
          {'descriptor_id': (await _createDescriptor(s, body.descriptor)).id}));
}

Future<List<db.SubjectRow>> listSubjects(Session s) async {
  final subjects = await s.select(db.subject);
  final descriptors = await s.selectByIds(
      db.descriptor, subjects.map((row) => row.descriptorId));

  // Select all translations.
  await s.select(
      db.translation,
      WHERE(
          {'descriptor_id': IN_IDS(descriptors), 'locale_id': IN(s.locales)}));

  return subjects;
}
