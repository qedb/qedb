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
  final insertParameters = {
    'category_id': body.category.id,
    'argument_count': body.argumentCount,
    'generic': body.generic
  };

  if (body.latexTemplate != null) {
    insertParameters['latex_template'] = body.latexTemplate;
  }

  if (body.keyword != null && body.keywordType != null) {
    insertParameters['keyword'] = body.keyword;
    insertParameters['keyword_type'] = body.keywordType;
  }

  // If a name is specified, add it to the insert parameters.
  if (body.descriptor != null) {
    // Use ID if provided.
    if (body.descriptor.id != null) {
      insertParameters['descriptor_id'] = body.descriptor.id;
    } else {
      // Create descriptor.
      insertParameters['descriptor_id'] =
          (await createDescriptor(s, body.descriptor)).id;
    }
  }

  return await functionHelper.insert(s, insertParameters);
}

Future<List<db.FunctionRow>> listFunctions(
    Session s, List<String> locales, int categoryId) async {
  final functions = await functionHelper.select(s, {});

  // Select all translations.
  final descriptorIds =
      functionHelper.ids(functions, (row) => row.descriptorId);
  await translationHelper.selectIn(s, {
    'descriptor_id': descriptorIds,
    'locale_id': await getLocaleIds(s, locales)
  });

  return functions;
}
