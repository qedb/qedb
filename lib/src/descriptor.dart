// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class CreateDescriptor {
  @ApiProperty(required: true)
  List<CreateTranslation> translations;

  CreateDescriptor();
  CreateDescriptor.fromTranslations(this.translations);
}

class CreateSubject {
  @ApiProperty(required: true)
  int descriptorId;
}

class CreateTranslation {
  @ApiProperty(required: true)
  String locale;

  @ApiProperty(required: true)
  String content;
}

Future<db.DescriptorTable> _createDescriptor(
    Session s, CreateDescriptor body) async {
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

Future<db.SubjectTable> _createSubject(Session s, CreateSubject body) async {
  // Insert translation.
  return await subjectHelper.insert(s, {'descriptor_id': body.descriptorId});
}

Future<db.TranslationTable> _createTranslation(
    Session s, int descriptorId, CreateTranslation body) async {
  // Insert translation.
  return await translationHelper.insert(s, {
    'descriptor_id': descriptorId,
    'locale_id': await localeHelper.getId(s, {'code': body.locale}),
    'content': body.content
  });
}

Future<List<db.TranslationTable>> _listTranslations(Session s,
    [int descriptorId = -1]) {
  return descriptorId == -1
      ? translationHelper.select(s, {})
      : translationHelper.select(s, {'descriptor_id': descriptorId});
}
