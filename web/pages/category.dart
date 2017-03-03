// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createCategoryPage = new AdminPage(
    template: (data) {
      return createResourceTemplate(data, 'category', inputs: (data) {
        return [
          input(type: 'hidden', name: 'locale', value: 'en_US'),
          localeSelect(data),
          div('.form-group', [
            label('Subject', _for: 'subject'),
            input('#subject.form-control', type: 'text', name: 'subject')
          ])
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Go to category overview',
              href: '/category/list', role: 'button'),
          ' ',
          a('.btn.btn-secondary', 'Go to created category',
              href: '/category/${data.data.id}/read', role: 'button')
        ];
      });
    },
    postFormat: {
      'subject': {
        'descriptor': {
          'translations': [
            {
              'locale': {'code': 'locale'},
              'content': 'subject'
            }
          ]
        }
      }
    },
    additional: {
      'locales': 'locale/list'
    });

final listCategoriesPage = new AdminPage(template: (data) {
  return listResourceTemplate(data, 'category', 'categories',
      tableHead: [th('ID'), th('Subject'), th('Parent')], row: (category) {
    return [
      th(category.id.toString()),
      td(
        safe(() {
          return a(category.subject.descriptor.translations[0].content,
              href: '/descriptor/${category.subject.descriptor.id}/read',
              scope: 'row');
        }, ''),
      ),
      td(
        safe(() {
          final parent =
              data.data.where((c) => c.id == category.parents.first).single;
          return parent.subject.descriptor.translations[0].content;
        }, ''),
      )
    ];
  });
});
