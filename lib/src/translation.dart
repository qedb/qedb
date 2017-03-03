// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.TranslationRow> createTranslation(
    Session s, int descriptorId, TranslationResource body) async {
  final localeId = s.data.cache.localeCodeToId[body.locale.code];
  if (localeId == null) {
    // On the fly creation of locales is purposefully not supported.
    throw new UnprocessableEntityError('unknown locale');
  }

  return await translationHelper.insert(s, {
    'descriptor_id': descriptorId,
    'locale_id': localeId,
    'content': body.content
  });
}

Future<List<db.TranslationRow>> listTranslations(Session s, int descriptorId) {
  return descriptorId == null
      ? translationHelper.select(s, {})
      : translationHelper.select(s, {'descriptor_id': descriptorId});
}
