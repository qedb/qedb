// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

Future<db.DescriptorRow> createDescriptor(
    Session s, DescriptorResource body) async {
  // You must submit at least one translation.
  if (body.translations.isEmpty) {
    throw new UnprocessableEntityError(
        'descriptors must at least have one translation');
  }

  // First check if a descriptor with any of the given translations exists.
  final translations = new List<String>.generate(body.translations.length, (i) {
    final t = body.translations[i];
    return ['(', t.locale.getId(s.data), ',', encodeString(t.content), ')']
        .join();
  });
  final existingTranslations = await translationHelper.selectCustom(s,
      'SELECT * FROM translation WHERE (locale_id, content) IN (${translations.join(',')})');

  // If none of the specified translations is in the database, we can create
  // a new descriptor record.
  if (existingTranslations.isEmpty) {
    // Insert descriptor.
    final descriptor = await descriptorHelper.insert(s, {});

    // Insert translations.
    for (final translation in body.translations) {
      await createTranslation(s, descriptor.id, translation);
    }

    return descriptor;
  } else {
    // Check if all existing translations refer to the same descriptor.
    final descriptorId = existingTranslations.first.descriptorId;

    if (existingTranslations.every((r) => r.descriptorId == descriptorId)) {
      // Insert remaining translations.
      for (final translation in body.translations.where((r1) =>
          existingTranslations
              .where((r2) =>
                  r2.localeId == r1.locale.getId(s.data) &&
                  r2.content == r1.content)
              .isEmpty)) {
        await createTranslation(s, descriptorId, translation);
      }

      return new db.DescriptorRow(descriptorId);
    } else {
      throw new UnprocessableEntityError(
          'contains existing translations with different parent descriptors');
    }
  }
}

Future<List<db.DescriptorRow>> listDescriptors(
    Session s, List<String> locales) async {
  final descriptors = await descriptorHelper.select(s, {});

  // Select all translations.
  await translationHelper.selectIn(s, {
    'descriptor_id': getIds(descriptors),
    'locale_id': getLocaleIds(s.data.cache, locales)
  });

  return descriptors;
}
