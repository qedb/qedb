// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

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

  final functionRow = await functionHelper.insert(s, insertParameters);

  // Insert LaTeX templates.
  var templatePriority = 0;
  for (final template in body.latexTemplates) {
    await createFunctionTemplate(
        s, functionRow.id, ++templatePriority, template);
  }

  return functionRow;
}

Future<db.FunctionLaTeXTemplateRow> createFunctionTemplate(
    Session s, int functionId, int priority, String template) {
  return functionLaTeXTemplateHelper.insert(s,
      {'function_id': functionId, 'priority': priority, 'template': template});
}
