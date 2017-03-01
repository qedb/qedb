// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.SubjectRow> _createSubject(Session s, SubjectResource body) async {
  if (body.descriptor.id != null) {
    return subjectHelper.insert(s, {'descriptor_id': body.descriptor.id});
  } else {
    return subjectHelper.insert(
        s, {'descriptor_id': (await _createDescriptor(s, body.descriptor)).id});
  }
}

Future<List<db.SubjectRow>> _listSubjects(Session s,
    {String locale: ''}) async {
  final descriptors = await descriptorHelper.selectCustom(s,
      'SELECT * FROM descriptor WHERE id IN (SELECT descriptor_id FROM subject)');
  final localeId = s.data.cache.localeCodeToId[locale];

  if (localeId != null && descriptors.isNotEmpty) {
    // Select all translations.
    final descriptorIds =
        new List<int>.generate(descriptors.length, (i) => descriptors[i].id);
    await translationHelper.selectIn(s, {
      'descriptor_id': descriptorIds,
      'locale_id': [localeId]
    });
  }

  return await subjectHelper.select(s, {});
}
