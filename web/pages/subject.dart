// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createSubjectPage = new AdminPage(
    template: (data) {
      return createResourceTemplate(data, 'subject', inputs: (data) {
        return [
          localeSelect(data),
          div('.form-group', [
            label('Descriptor', _for: 'content'),
            input('#content.form-control', type: 'text', name: 'content')
          ])
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Go to subjects overview',
              href: '/subject/list', role: 'button')
        ];
      });
    },
    postFormat: {
      'descriptor': {
        'translations': [
          {
            'locale': {'code': 'locale'},
            'content': 'content'
          }
        ]
      }
    },
    additional: {
      'locales': 'locale/list'
    });

final listSubjectsPage = new AdminPage(template: (data) {
  return listResourceTemplate(data, 'subject', 'subjects',
      tableHead: [th('ID'), th('Descriptor ID'), th('Translation')],
      row: (subject) {
    return [
      th(subject.id.toString()),
      td(
          a(subject.descriptor.id.toString(),
              href: '/descriptor/${subject.descriptor.id}/read'),
          scope: 'row'),
      td(safe(() => subject.descriptor.translations[0].content, ''))
    ];
  });
});
