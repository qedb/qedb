// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createDefinitionPage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'definition', inputs: (data) {
        return [
          formGroup('Category', 'category', [
            select('#category.custom-select.form-control',
                name: 'category',
                c: data.additional['categories'].map((category) {
                  return option(
                      safe(
                          () => category
                              .subject.descriptor.translations[0].content,
                          ''),
                      value: category.id);
                }).toList())
          ]),
          formGroup('Left expression', 'left',
              [div('#left.editex.editex-align-left', data_name: 'left')]),
          formGroup('Right expression', 'right',
              [div('#right.editex.editex-align-left', data_name: 'right')])
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Go to definition overview',
              href: '/definition/list', role: 'button')
        ];
      }, customHeadTags: [
        link(rel: 'stylesheet', href: data.settings['katex.css.href']),
        link(rel: 'stylesheet', href: data.settings['editex.css.href']),
        script(src: data.settings['katex.js.src']),
        script(src: data.settings['editex_form.dart.js.src']),
        style(data.snippets['editex.css'])
      ]);
    },
    onPost: (data) => {
          'rule': {
            'category': {'id': int.parse(data['category'])},
            'leftExpression': {'data': data['left']},
            'rightExpression': {'data': data['right']}
          }
        },
    additional: {'categories': 'category/list?locale=en_US'});

final listDefinitionsPage = new Page(template: (data) {
  return listResourceTemplate(data, 'definition', 'definitions', tableHead: [
    th('ID'),
    th('Left', style: 'text-align: center;'),
    th(''),
    th('Right', style: 'text-align: center;')
  ], row: (definition) {
    return [
      td(definition.id.toString()),
      td(span('.latex', definition.rule.leftExpression.latex)),
      td(span('.latex', '=')),
      td(span('.latex', definition.rule.rightExpression.latex))
    ];
  }, customHeadTags: [
    style(data.snippets['definition-table.css']),
    link(rel: 'stylesheet', href: data.settings['katex.css.href'])
  ], customBodyTags: [
    script(src: data.settings['katex.js.src']),
    script(data.snippets['render-latex.js'])
  ]);
});
