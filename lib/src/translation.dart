// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.TranslationRow> createTranslation(
    Session s, int descriptorId, TranslationResource body) {
  return translationHelper.insert(s, {
    'descriptor_id': descriptorId,
    'locale_id': localeId(s, body.locale),
    'content': body.content
  });
}

Future<List<db.TranslationRow>> listTranslations(Session s, int descriptorId) {
  return descriptorId == null
      ? translationHelper.select(s, {})
      : translationHelper.select(s, {'descriptor_id': descriptorId});
}
