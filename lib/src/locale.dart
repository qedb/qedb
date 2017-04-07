// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.LocaleRow> createLocale(Session s, LocaleResource body) async {
  // Prevent primary key gaps for locales (I am a control freak).
  if (await s.exists(db.locale, WHERE({'code': IS(body.code)}))) {
    throw new UnprocessableEntityError('locale already exists');
  }
  return await s.insert(db.locale, VALUES({'code': body.code}));
}

Future<List<db.LocaleRow>> listLocales(Session s) {
  return s.select(db.locale);
}

/// Return locale IDs for the given locale ISO codes.
/// Note that all locales should already be loaded.
List<int> getLocaleIds(Session s, List<String> locales) {
  final ids = new List<int>();
  for (final locale in s.data.localeTable.values) {
    if (locales.contains(locale.code)) {
      ids.add(locale.id);
    }
  }
  return ids;
}

/// Get ID from the given locale.
/// This assumes all locales are loaded into the session data.
int localeId(Session s, LocaleResource locale) {
  if (locale.id == null) {
    return s.data.localeTable.values
        .singleWhere((r) => r.code == locale.code)
        .id;
  } else {
    return locale.id;
  }
}
