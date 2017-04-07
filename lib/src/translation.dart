// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.TranslationRow> createTranslation(
    Session s, int descriptorId, TranslationResource body) {
  return s.insert(
      db.translation,
      VALUES({
        'descriptor_id': descriptorId,
        'locale_id': localeId(s, body.locale),
        'content': body.content
      }));
}

Future<List<db.TranslationRow>> listTranslations(Session s, int descriptorId) {
  return s.select(db.translation,
      descriptorId == null ? null : WHERE({'descriptor_id': IS(descriptorId)}));
}
