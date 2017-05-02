// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

import 'package:eqdb/utils.dart';

final createRulePage = new Page(template: (s) {
  return createResourceTemplate(s, 'rule', inputs: (_) {
    return [
      h4('From definition'),
      formGroup('Left expression', 'left', [
        div('#left.editex.editex-align-left.form-control', data_name: 'left')
      ]),
      formGroup('Right expression', 'right', [
        div('#right.editex.editex-align-left.form-control', data_name: 'right')
      ]),
      h4('From proof'),
      formInput('Proof ID', name: 'proof'),
      h4('From connecting steps'),
      formGroup('First step ID', 'first', [
        input('#first.form-control',
            type: 'text', name: 'first', maxlength: 6, pattern: '[0-9a-z]+')
      ]),
      formGroup('Last step ID', 'last', [
        input('#last.form-control',
            type: 'text', name: 'last', maxlength: 6, pattern: '[0-9a-z]+')
      ]),
      h4('From derived rule expression'),
      formGroup('Step ID', 'last', [
        input('#last.form-control',
            type: 'text', name: 'step', maxlength: 6, pattern: '[0-9a-z]+')
      ])
    ];
  }, bodyTags: [
    katexSource(s),
    editexStyles(s),
    script(src: s.settings['editorsrc'] + 'src/editex_form.dart.js')
  ]);
}, onPost: (data) {
  if (notEmpty(data['left']) && notEmpty(data['right'])) {
    return {
      'isDefinition': true,
      'leftExpression': {'data': data['left']},
      'rightExpression': {'data': data['right']}
    };
  } else if (notEmpty(data['proof'])) {
    return {
      'proof': {'id': int.parse(data['proof'])}
    };
  } else if (notEmpty(data['first']) && notEmpty(data['last'])) {
    return {
      'proof': {
        'firstStep': {'id': int.parse(data['first'], radix: 36)},
        'lastStep': {'id': int.parse(data['last'], radix: 36)}
      }
    };
  } else if (notEmpty(data['step'])) {
    return {
      'step': {'id': int.parse(data['step'])}
    };
  } else {
    return {};
  }
});

final listRulesPage = new Page(template: (s) {
  return listResourceTemplate(s, 'rule', 'rules', tableHead: [
    th('ID'),
    th('Left', style: 'text-align: center;'),
    th(''),
    th('Right', style: 'text-align: center;'),
    th('Proof'),
    th('Actions', style: 'width: 1px;')
  ], row: (rule) {
    return [
      td(rule.id.toString()),
      td(span('.latex', rule.leftExpression.latex)),
      td(span('.latex', r'\rightarrow')),
      td(span('.latex', rule.rightExpression.latex)),
      td(safe(() => a('proof', href: '/proof/${rule.proof.id}/steps/list'),
          rule.containsKey('step') ? span('step') : span('.none.text-muted'))),
      td(div('.btn-group.btn-group-sm', role: 'group', c: [
        a('.btn.btn.btn-outline-secondary', 'Delete',
            href: '${rule.id}/delete'),
        a('.btn.btn.btn-outline-secondary', 'Derive rule',
            href: '/proof/create?initialrule=${rule.id}')
      ]))
    ];
  }, bodyTags: [
    katexSource(s),
    style(s.snippets['latex-table.css']),
    script(s.snippets['render-latex.js'])
  ]);
});

final deleteRulePage = new Page(template: (s) {
  return deleteResourceTemplate(s, 'rule');
});
