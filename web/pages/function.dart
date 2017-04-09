// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createFunctionPage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'function', inputs: (data) {
        return [
          input(type: 'hidden', name: 'locale', value: 'en_US'),
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
          div('.form-group', [
            label('Name'),
            div('.input-group', [
              input('.form-control', type: 'text', name: 'name'),
              localeSelect(data,
                  name: 'name-locale', customClass: '', inGroup: false)
            ])
          ]),
          div('.form-group', [
            label('Keyword'),
            div('.input-group', [
              input('.form-control', type: 'text', name: 'keyword'),
              select('.form-control', name: 'keyword-type', c: [
                option('Word', value: 'word'),
                option('Acronym', value: 'acronym'),
                option('Abbreviation', value: 'abbreviation'),
                option('Symbol', value: 'symbol'),
                option('LaTeX', value: 'latex')
              ])
            ])
          ]),
          formGroup('Argument count', 'argument-count', [
            input('#argument-count.form-control',
                name: 'argument-count', type: 'number', min: 0, step: 1)
          ]),
          formInput('LaTeX template', name: 'latex-template'),
          selectYesNo('Generic', name: 'generic'),
          selectYesNo('Rearrangeable', name: 'rearrangeable')
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Go to function overview',
              href: '/function/list', role: 'button')
        ];
      });
    },
    onPost: (data) => {
          'generic': data['generic'] == 'true',
          'rearrangeable': data['rearrangeable'] == 'true',
          'argumentCount': int.parse(data['argument-count']),
          'keyword': data['keyword'],
          'keywordType': data['keyword-type'],
          'latexTemplate': data['latex-template'],
          'category': {'id': int.parse(data['category'])},
          'descriptor': {
            'translations': [
              {
                'locale': {'code': data['name-locale']},
                'content': data['name']
              }
            ]
          }
        },
    additional: {
      'locales': 'locale/list',
      'categories': 'category/list?locale=en_US'
    });

final listFunctionsPage = new Page(template: (data) {
  return listResourceTemplate(data, 'function', 'functions', tableHead: [
    th('ID'),
    th('Category'),
    th('Descriptor'),
    th('Keyword'),
    th('LaTeX template'),
    th('Generic')
  ], row: (function) {
    return [
      td(function.id.toString()),
      td(a(function.category.id.toString(),
          href: '/category/${function.category.id}/read')),
      td(
        safe(() {
          return a(function.descriptor.translations[0].content,
              href: '/descriptor/${function.descriptor.id}/read', scope: 'row');
        }, ''),
      ),
      td(safe(() => function.keyword.toString(), '')),
      td(safe(() => span('.latex', function.latexTemplate))),
      td(function.generic ? 'yes' : 'no')
    ];
  }, customHeadTags: [
    stylesheet(data.settings['katex.css.href']),
    style('.katex-display { margin: 0 !important; text-align: left; }')
  ], customBodyTags: [
    script(src: data.settings['katex.js.src']),
    script(data.snippets['render-latex.js'])
  ]);
});
