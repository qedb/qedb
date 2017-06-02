// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

Future<db.LanguageRow> createLanguage(Session s, LanguageResource body) async {
  // Prevent primary key gaps for languages (I am a control freak).
  if (await s.exists(db.language, WHERE({'code': IS(body.code)}))) {
    throw new UnprocessableEntityError('language already exists');
  }
  return await s.insert(db.language, VALUES({'code': body.code}));
}

Future<List<db.LanguageRow>> listLanguages(Session s) {
  return s.select(db.language);
}

/// Return language IDs for the given language ISO codes.
/// Note that all languages should already be loaded.
List<int> getLanguageIds(Session s, List<String> languages) {
  final ids = new List<int>();
  for (final language in s.data.languageTable.values) {
    if (languages.contains(language.code)) {
      ids.add(language.id);
    }
  }
  return ids;
}

/// Get ID from the given language.
/// This assumes all languages are loaded into the session data.
int getLanguageId(Session s, LanguageResource language) {
  if (language.id == null) {
    return s.data.languageTable.values
        .singleWhere((r) => r.code == language.code)
        .id;
  } else {
    return language.id;
  }
}
