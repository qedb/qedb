// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:json_object/json_object.dart';

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

/// Helper for other pages.
String descriptorHyperlink(JsonObject getDescriptor()) {
  try {
    final descriptor = getDescriptor();
    return a(descriptor.translations[0].content,
        href: '/descriptor/${descriptor.id}/read', scope: 'row');
  } catch (e) {
    return span('.none');
  }
}

final listDescriptorsPage = new Page(template: (data) {
  return listResourceTemplate(data, 'descriptor', 'descriptors',
      tableHead: [th('ID'), th('Translation')], row: (descriptor) {
    return [
      th(a(descriptor.id.toString(), href: '/descriptor/${descriptor.id}/read'),
          scope: 'row'),
      td(safe(() => descriptor.translations[0].content, ''))
    ];
  });
});

final readDescriptorPage = new Page(template: (data) {
  var translationNr = 0;
  return pageTemplate(data, 'Descriptor #${data.data.id}', containerTags: [
    h4('Translations'),
    table('.table', [
      thead([
        tr([th('#'), th('Content'), th('Language')])
      ]),
      tbody(data.data.translations.map((translation) {
        return tr([
          th((++translationNr).toString(), scope: 'row'),
          td(translation.content),
          td(code(translation.language.code))
        ]);
      }).toList())
    ]),
    br(),
    a('.btn.btn-secondary', 'Add translation',
        href: '/descriptor/${data.data.id}/translation/create', role: 'button')
  ]);
});
