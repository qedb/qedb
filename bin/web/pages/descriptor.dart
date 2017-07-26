// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:htgen/static.dart';

import '../page.dart';
import 'templates.dart';

/// Helper for other pages.
String descriptorHyperlink(dynamic getDescriptor()) {
  return unsafe(() {
    final descriptor = getDescriptor();
    return a(descriptor.translations[0].content,
        href: '/descriptor/${descriptor.id}/read', scope: 'row');
  }, span('.none'));
}

final readDescriptorPage = new Page(template: (s) {
  var translationNr = 0;
  return pageTemplate(s, 'Descriptor #${s.response.id}', containerTags: [
    h4('Translations'),
    table('.table', [
      thead([
        tr([th('#'), th('Content'), th('Language')])
      ]),
      tbody(s.response.translations.map((translation) {
        return tr([
          th((++translationNr).toString(), scope: 'row'),
          td(translation.content),
          td(code(translation.language.code))
        ]);
      }).toList())
    ]),
    br(),
    a('.btn.btn-secondary', 'Add translation',
        href: '/descriptor/${s.response.id}/translation/create', role: 'button')
  ]);
});
