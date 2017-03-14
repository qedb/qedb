// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.LocaleRow> createLocale(Session s, LocaleResource body) async {
  // Prevent primary key gaps for locales (I am a control freak).
  final localeId = await localeHelper.getId(s, {'code': body.code});
  s.data.cache.localeIdToCode[localeId] = body.code;
  s.data.cache.localeCodeToId[body.code] = localeId;
  return new db.LocaleRow(localeId, body.code);
}

List<LocaleResource> listLocales(DbCache cache) {
  // Reconstruct from memory.
  final list = new List<LocaleResource>();
  cache.localeIdToCode.forEach((id, code) {
    list.add(new LocaleResource()
      ..id = id
      ..code = code);
  });
  return list;
}

/// Retrieve locale IDs from the given [cache] for the given [locales].
List<int> getLocaleIds(DbCache cache, List<String> locales) {
  final list = new List<int>();
  for (final localeCode in locales) {
    final id = cache.localeCodeToId[localeCode];
    if (id != null) {
      list.add(id);
    }
  }
  return list;
}
