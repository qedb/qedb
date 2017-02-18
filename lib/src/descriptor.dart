// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.DescriptorRow> _createDescriptor(
    Session s, DescriptorResource body) async {
  // Require at least one translation.
  if (body.translations.isEmpty) {
    throw new UnprocessableEntityError('submit at least one translation');
  }

  // Insert descriptor.
  final descriptor = await descriptorHelper.insert(s, {});

  // Insert translations.
  for (final translation in body.translations) {
    await _createTranslation(s, descriptor.id, translation);
  }

  return descriptor;
}

Future<db.TranslationRow> _createTranslation(
    Session s, int descriptorId, TranslationResource body) async {
  var localeId = s.data.cache.locales.inverse[body.locale.code];
  if (localeId == null) {
    // There should NOT be an existing record, but just to be sure, use getId.
    localeId = await localeHelper.getId(s, {'code': body.locale.code});
    s.data.cache.locales[localeId] = body.locale.code;
  }

  // Insert translation.
  return await translationHelper.insert(s, {
    'descriptor_id': descriptorId,
    'locale_id': localeId,
    'content': body.content
  });
}

Future<List<db.TranslationRow>> _listTranslations(Session s,
    [int descriptorId = -1]) {
  return descriptorId == -1
      ? translationHelper.select(s, {})
      : translationHelper.select(s, {'descriptor_id': descriptorId});
}

Future<db.SubjectRow> _createSubject(Session s, SubjectResource body) =>
    subjectHelper.insert(s, {'descriptor_id': body.descriptor.id});
