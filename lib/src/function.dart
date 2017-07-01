// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

Future<db.FunctionRow> createFunction(Session s, FunctionResource body) async {
  // Non-generic functions with >0 arguments must have a name (soft constraint).
  if (!body.generic && body.argumentCount > 0 && body.descriptor == null) {
    throw new UnprocessableEntityError(
        'non-generic functions with >0 arguments must have a descriptor');
  }

  // Insert function.
  final values = {
    'subject_id': body.subject.id,
    'generic': body.generic,
    'rearrangeable': body.rearrangeable,
    'argument_count': body.argumentCount
  };

  if (body.descriptor != null) {
    values['descriptor_id'] = (await _createDescriptor(s, body.descriptor)).id;
  }

  if (notEmpty(body.keyword) && body.keywordType != null) {
    values['keyword'] = body.keyword;
    values['keyword_type'] = body.keywordType;
  }

  if (notEmpty(body.latexTemplate)) {
    values['latex_template'] = body.latexTemplate;
  }

  if (notEmpty(body.specialType)) {
    values['special_type'] = body.specialType;
  }

  return await s.insert(db.function, VALUES(values));
}

Future<db.FunctionRow> updateFunction(
    Session s, int functionId, FunctionResource body) async {
  final setValues = new Map<String, dynamic>();
  if (body.subject != null) {
    setValues['subject_id'] = body.subject.id;
  }
  if (body.keyword != null) {
    setValues['keyword'] = body.keyword;
  }
  if (body.keywordType != null) {
    setValues['keyword_type'] = body.keywordType;
  }
  if (body.latexTemplate != null) {
    setValues['latex_template'] = body.latexTemplate;
  }
  if (setValues.isEmpty) {
    throw new UnprocessableEntityError(
        'body does not contain updatable fields');
  }

  return s.updateOne(
      db.function, SET(setValues), WHERE({'id': IS(functionId)}));
}

Future<List<db.FunctionRow>> listFunctions(Session s) async {
  final functions = await s.select(db.function);

  // Select all subjects and translations.
  final subjects =
      await s.selectByIds(db.subject, functions.map((row) => row.subjectId));

  // Get all descriptors.
  final descriptorIds = new List<int>();
  for (final fn in functions) {
    if (fn.descriptorId != null) {
      descriptorIds.add(fn.descriptorId);
    }
  }
  for (final subject in subjects) {
    descriptorIds.add(subject.descriptorId);
  }

  if (descriptorIds.isNotEmpty) {
    await s.select(
        db.translation,
        WHERE({
          'descriptor_id': IN(descriptorIds),
          'language_id': IN(s.languages)
        }));
  }

  return functions;
}
