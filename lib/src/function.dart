// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

Future<db.FunctionRow> createFunction(Session s, FunctionResource body) async {
  // Non-generic functions with >0 arguments must have a name (soft constraint).
  if (!body.generic && body.argumentCount > 0 && body.descriptor == null) {
    throw new UnprocessableEntityError(
        'non-generic functions with >0 arguments must have a descriptor');
  }

  // Insert function.
  final values = {
    'generic': body.generic,
    'rearrangeable': body.rearrangeable,
    'argument_count': body.argumentCount,
    'category_id': body.category.id
  };

  if (notEmpty(body.latexTemplate)) {
    values['latex_template'] = body.latexTemplate;
  }

  if (notEmpty(body.keyword) && body.keywordType != null) {
    values['keyword'] = body.keyword;
    values['keyword_type'] = body.keywordType;
  }

  // If a name is specified, add it to the insert parameters.
  if (body.descriptor != null) {
    // Use ID if provided.
    if (body.descriptor.id != null) {
      values['descriptor_id'] = body.descriptor.id;
    } else {
      // Create descriptor.
      values['descriptor_id'] = (await createDescriptor(s, body.descriptor)).id;
    }
  }

  return await s.insert(db.function, VALUES(values));
}

Future<List<db.FunctionRow>> listFunctions(
    Session s, List<String> locales, int categoryId) async {
  final functions = await s.select(db.function);

  // Select all translations.
  final descriptorIds = functions.map((row) => row.descriptorId);
  await s.select(
      db.translation,
      WHERE({
        'descriptor_id': IN(descriptorIds),
        'locale_id': IN(getLocaleIds(s, locales))
      }));

  return functions;
}
