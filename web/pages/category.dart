// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createCategoryPage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'category', inputs: (data) {
        return [
          input(type: 'hidden', name: 'locale', value: 'en_US'),
          localeSelect(data),
          formInput('Subject', name: 'subject')
        ];
      });
    },
    onPost: (data) => {
          'subject': {
            'descriptor': {
              'translations': [
                {
                  'locale': {'code': data['locale']},
                  'content': data['subject']
                }
              ]
            }
          }
        },
    additional: {'locales': 'locale/list'});

final readCategoryPage = new Page(template: (data) {
  final name =
      safe(() => data.data.subject.descriptor.translations[0].content, '');
  return pageTemplate(data, '$name (#${data.data.id})', containerTags: [
    a('.btn.btn-secondary', 'Sub categories',
        href: '/category/${data.data.id}/category/list', role: 'button')
  ]);
});

final listCategoriesPage = new Page(template: (data) {
  return listResourceTemplate(data, 'category', 'categories',
      tableHead: [th('ID'), th('Subject'), th('Parent')], row: (category) {
    return [
      th(a(category.id.toString(), href: '/category/${category.id}/read')),
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
              data.data.where((c) => c.id == category.parents.last).single;
          return parent.subject.descriptor.translations[0].content;
        }, ''),
      )
    ];
  });
});

final listSubCategoriesPage = new Page(template: (data) {
  return listResourceTemplate(data, 'category', 'categories',
      customTitle: '#${data.pathParameters['id']} subcategories',
      customCreateButton: 'Create subcategory',
      tableHead: [th('ID'), th('Subject')], row: (category) {
    return [
      th(a(category.id.toString(), href: '/category/${category.id}/read')),
      td(
        safe(() {
          return a(category.subject.descriptor.translations[0].content,
              href: '/descriptor/${category.subject.descriptor.id}/read',
              scope: 'row');
        }, ''),
      )
    ];
  });
});
