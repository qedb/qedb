// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.TranslationRow> _createTranslation(
    Session s, int descriptorId, TranslationResource body) async {
  final localeId = s.data.cache.localeCodeToId[body.locale.code];
  if (localeId == null) {
    // Throw an error. On the fly creation of locales is purposefully not
    // supported.
    throw new UnprocessableEntityError('unknown locale');
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
