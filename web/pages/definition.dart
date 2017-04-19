// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createDefinitionPage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'definition', inputs: (_) {
        return [
          formGroup('Left expression', 'left',
              [div('#left.editex.editex-align-left', data_name: 'left')]),
          formGroup('Right expression', 'right',
              [div('#right.editex.editex-align-left', data_name: 'right')]),
        ];
      }, bodyTags: [
        katexSource(s),
        editexStyles(s),
        script(src: s.settings['lineagesrc'] + 'src/editex_form.dart.js')
      ]);
    },
    onPost: (data) => {
          'rule': {
            'leftExpression': {'data': data['left']},
            'rightExpression': {'data': data['right']}
          }
        });

final listDefinitionsPage = new Page(template: (s) {
  return listResourceTemplate(s, 'definition', 'definitions', tableHead: [
    th('ID'),
    th('Left', style: 'text-align: center;'),
    th(''),
    th('Right', style: 'text-align: center;')
  ], row: (definition) {
    return [
      td(definition.id.toString()),
      td(span('.latex', definition.rule.leftExpression.latex)),
      td(span('.latex', r'\rightarrow')),
      td(span('.latex', definition.rule.rightExpression.latex))
    ];
  }, bodyTags: [
    katexSource(s),
    style(s.snippets['latex-table.css']),
    script(s.snippets['render-latex.js'])
  ]);
});
