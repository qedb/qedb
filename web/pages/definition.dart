// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
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
      }, headAppend: [
        link(
            rel: 'stylesheet',
            href:
                'https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.7.1/katex.min.css'),
        link(
            rel: 'stylesheet',
            href: 'http://0.0.0.0:8083/packages/editex/editex.css'),
        script(
            type: 'text/javascript',
            src:
                'https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.7.1/katex.min.js'),
        script(src: 'http://0.0.0.0:8083/notebook/src/editex_form.dart.js'),
        style('''
.editex {
  box-shadow: inset 0 0 3px rgba(0,0,0,.5);
  border: 1px solid #666;
  font-size: 1.7em;
}

.editex:focus {
  border-color: #2196F3;
  outline: none;
  box-shadow: inset 0 0 5px #2196F3;
}
''')
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
  }, customHeaderTags: [
    style('''
td, th {
  text-align: center;
  vertical-align: middle !important;
}
'''),
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
  katex.render(latex, span, {displayMode: true});
}
    ''',
        type: 'text/javascript')
  ]);
});
