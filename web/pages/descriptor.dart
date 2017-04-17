// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createDescriptorPage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'descriptor', inputs: (data) {
        return [localeSelect(data), formInput('Translation', name: 'content')];
      });
    },
    onPost: (data) => {
          'translations': [
            {
              'locale': {'code': data['locale']},
              'content': data['content']
            }
          ]
        },
    additional: {'locales': 'locale/list'});

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
        tr([th('#'), th('Content'), th('Locale')])
      ]),
      tbody(data.data.translations.map((translation) {
        return tr([
          th((++translationNr).toString(), scope: 'row'),
          td(translation.content),
          td(code(translation.locale.code))
        ]);
      }).toList())
    ]),
    br(),
    a('.btn.btn-secondary', 'Add translation',
        href: '/descriptor/${data.data.id}/translation/create', role: 'button')
  ]);
});
