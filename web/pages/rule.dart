// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createRulePage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'rule', inputs: (_) {
        return [
          formGroup('First step of proof', 'first', [
            input('#first.form-control',
                type: 'text', name: 'first', maxlength: 6, pattern: '[0-9a-z]+')
          ]),
          formGroup('Last step of proof', 'last', [
            input('#last.form-control',
                type: 'text', name: 'last', maxlength: 6, pattern: '[0-9a-z]+')
          ])
        ];
      });
    },
    onPost: (data) => {
          'proof': {
            'firstStep': {'id': int.parse(data['first'], radix: 36)},
            'lastStep': {'id': int.parse(data['last'], radix: 36)}
          }
        });

final listRulesPage = new Page(template: (s) {
  return listResourceTemplate(s, 'rule', 'rules', tableHead: [
    th('ID'),
    th('Left', style: 'text-align: center;'),
    th(''),
    th('Right', style: 'text-align: center;')
  ], row: (rule) {
    return [
      td(rule.id.toString()),
      td(span('.latex', rule.leftExpression.latex)),
      td(span('.latex', r'\rightarrow')),
      td(span('.latex', rule.rightExpression.latex))
    ];
  }, bodyTags: [
    katexSource(s),
    style(s.snippets['latex-table.css']),
    script(s.snippets['render-latex.js'])
  ]);
});
