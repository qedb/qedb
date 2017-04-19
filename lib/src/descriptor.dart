// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

/// Design choice: never call this directly from the API. Create descriptor
/// should be called when a descriptor is created for another record. This is
/// always a new record. All subject/function/lineage titles should be distinct.
Future<db.DescriptorRow> _createDescriptor(
    Session s, DescriptorResource body) async {
  // You must submit at least one translation.
  if (body.translations.isEmpty) {
    throw new UnprocessableEntityError(
        'descriptors must at least have one translation');
  }

  // Insert descriptor.
  final descriptor = await s.insert(db.descriptor, SQL('DEFAULT VALUES'));

  // Insert translations.
  for (final translation in body.translations) {
    await createTranslation(s, descriptor.id, translation);
  }

  return descriptor;
}

Future<List<db.DescriptorRow>> listDescriptors(Session s) async {
  final descriptors = await s.select(db.descriptor);

  // Select all translations.
  await s.select(
      db.translation,
      WHERE(
          {'descriptor_id': IN_IDS(descriptors), 'locale_id': IN(s.locales)}));

  return descriptors;
}
