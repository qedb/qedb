// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createDescriptorPage = new AdminPage(
    template: (data) {
      return createResourceTemplate(data, 'descriptor', inputs: (data) {
        return [
          localeSelect(data),
          div('.form-group', [
            label('Translation', _for: 'content'),
            input('#content.form-control', type: 'text', name: 'content')
          ])
        ];
      }, success: (data) {
        return [
          div('.alert.alert-success', 'Successfully created descriptor',
              role: 'alert'),
          a('.btn.btn-primary', 'Go to descriptors overview',
              href: '/descriptor/list', role: 'button'),
          ' ',
          a('.btn.btn-secondary', 'Go to created descriptor',
              href: '/descriptor/${data.data.id}/read', role: 'button'),
          ' ',
          a('.btn.btn-secondary', 'Create another descriptor',
              href: '/descriptor/create', role: 'button')
        ];
      });
    },
    postFormat: {
      'translations': [
        {
          'locale': {'code': 'locale'},
          'content': 'content'
        }
      ]
    },
    additional: {
      'locales': 'locale/list'
    });

final listDescriptorsPage = new AdminPage(template: (data) {
  return html([
    head([title('All descriptors'), defaultHead(data)]),
    body([
      breadcrumb(data),
      div('.container', [
        h3('All descriptors'),
        br(),
        table('.table', [
          thead([
            tr([th('ID'), th('Translation')])
          ]),
          tbody(data.data.map((descriptor) {
            return tr([
              th(
                  a(descriptor.id.toString(),
                      href: '/descriptor/${descriptor.id}/read'),
                  scope: 'row'),
              td(safe(() => descriptor.translations[0].content, ''))
            ]);
          }).toList())
        ]),
        br()
      ])
    ])
  ]);
});

final readDescriptorPage = new AdminPage(template: (data) {
  var translationNr = 0;
  return html([
    head(
        [title('Descriptor #${data.pathParameters['id']}'), defaultHead(data)]),
    body([
      breadcrumb(data),
      div('.container', [
        h3('Descriptor #${data.pathParameters['id']}'),
        br(),
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
            href:
                '/descriptor/${data.pathParameters['id']}/translations/create',
            role: 'button')
      ])
    ])
  ]);
});
