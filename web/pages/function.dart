// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createFunctionPage = new AdminPage(
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
          formGroup('Generic', 'generic', [
            select('#generic.form-control', name: 'generic', c: [
              option('No', value: 'false', selected: ''),
              option('Yes', value: 'true')
            ])
          ])
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Go to function overview',
              href: '/function/list', role: 'button')
        ];
      });
    },
    postFormat: {
      'generic': 'bool:generic',
      'argumentCount': 'int:argument-count',
      'keyword': 'keyword',
      'keywordType': 'keyword-type',
      'latexTemplate': 'latex-template',
      'category': {'id': 'int:category'},
      'descriptor': {
        'translations': [
          {
            'locale': {'code': 'name-locale'},
            'content': 'name'
          }
        ]
      }
    },
    additional: {
      'locales': 'locale/list',
      'categories': 'category/list?locale=en_US'
    });

final listFunctionsPage = new AdminPage(template: (data) {
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
  }, customHeaderTags: [
    link(
        rel: 'stylesheet',
        href:
            'https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.7.1/katex.min.css')
  ], customBodyTags: [
    script(
        type: 'text/javascript',
        src: 'https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.7.1/katex.min.js'),
    script(
        r'''
var spans = document.getElementsByClassName('latex');
for (var i = 0; i < spans.length; i++) {
  var span = spans[i];
  var latex = span.innerText;
  latex = latex.replace(/\$([0-9]+)/g, function(match, p1) {
    return '\\textsf{\\$}' + p1;
  });
  katex.render(latex, span, {displayMode: false});
}
    ''',
        type: 'text/javascript')
  ]);
});
