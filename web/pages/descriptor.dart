// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../admin_page.dart';
import 'components.dart';

final createDescriptorPage = new AdminPage(
    template: (data) {
      return html([
        head([title('Create descriptor'), defaultHead(data)]),
        body([
          breadcrumb(data),
          div('.container', [
            h3('Create descriptor'),
            br(),
            safeIf(() => data.data['id'] != null)
                ? [
                    div('.alert.alert-success',
                        'Successfully created descriptor',
                        role: 'alert'),
                    a('.btn.btn-primary', 'Return to descriptors overview',
                        href: '/descriptor/', role: 'button'),
                    ' ',
                    a('.btn.btn-secondary', 'Go to created descriptor',
                        href: '/descriptor/${data.data['id']}/read',
                        role: 'button'),
                    ' ',
                    a('.btn.btn-secondary', 'Create another descriptor',
                        href: '/descriptor/create', role: 'button')
                  ]
                : form(action: '/descriptor/create', method: 'POST', c: [
                    div('.form-group', [
                      input(type: 'hidden', name: 'locale', value: 'en_US'),
                      label('Translation', _for: 'content'),
                      input('#content.form-control',
                          type: 'text', name: 'content'),
                      small('#nameHelp.form-text.text-muted',
                          'Enter the English (en-US) translation for this descriptor.')
                    ]),
                    button('.btn.btn-primary', 'Submit', type: 'submit')
                  ])
          ])
        ])
      ]);
    },
    postFormat: {
      'translations': [
        {
          'locale': {'code': 'locale'},
          'content': 'content'
        }
      ]
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
          tbody(data.data['translations'].map((translation) {
            return tr([
              th((++translationNr).toString(), scope: 'row'),
              td(translation['content']),
              td(code(translation['locale']['code']))
            ]);
          }).toList())
        ])
      ])
    ])
  ]);
});
