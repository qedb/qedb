// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:htgen/static.dart';

import '../page.dart';
import 'templates.dart';

import 'package:qedb/utils.dart';

final createRulePage = new Page(template: (s) {
  return createResourceTemplate(s, 'rule', inputs: (_) {
    return [
      h4('From definition'),
      formGroup('Definition', 'definition', [
        div('.rule-input', [
          div('#left.editex.editex-align-left.form-control', data_name: 'left'),
          span('.rule-arrow'),
          div('#right.editex.editex-align-left.form-control',
              data_name: 'right')
        ])
      ]),
      formGroup('Conditions', 'conditions', [
        div([
          div('#conditions-wrapper'),
          p(div('.btn-group', rule: 'group', c: [
            button('#add-condition.btn.btn-secondary', 'Add condition',
                type: 'button'),
            button(
                '#remove-condition.btn.btn-secondary', 'Remove last condition',
                type: 'button')
          ]))
        ])
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
    stylesheet('/snippets/rule.css'),
    stylesheet('/snippets/editex.css'),
    script(src: '/src/create_rule.dart.js')
  ]);
}, onPost: (data) {
  if (notEmpty(data['left']) && notEmpty(data['right'])) {
    // Find condition count.
    final conditionCount = int.parse(data['condition-count']);

    return {
      'isDefinition': true,
      'substitution': {
        'leftExpression': {'data': data['left']},
        'rightExpression': {'data': data['right']}
      },
      'conditions': new List.generate(conditionCount, (i) {
        return {
          'leftExpression': {'data': data['condition$i-left']},
          'rightExpression': {'data': data['condition$i-right']}
        };
      })
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
      'step': {'id': int.parse(data['step'], radix: 36)}
    };
  } else {
    return {};
  }
});

final readRulePage = new Page(template: (s) {
  final data = s.response;
  final ruleLatex = //
      '${data.substitution.leftExpression.latex}'
      r'\leftrightharpoons '
      '${data.substitution.rightExpression.latex}';

  return pageTemplate(s, 'Rule #${data.id}', containerTags: [
    br(),
    p(span('.latex', ruleLatex)),
    br(),
    h4('Conditions'),
    table('.table', [
      thead([
        tr([th('#'), th('Left'), th(''), th('Right')])
      ]),
      tbody(data.conditions.map((condition) {
        return tr([
          th(condition.id.toString(), scope: 'row'),
          td(span('.latex', condition.leftExpression.latex)),
          td(span('.rule-arrow')),
          td(span('.latex', condition.rightExpression.latex))
        ]);
      }).toList())
    ]),
  ], bodyTags: [
    katexSource(s),
    stylesheet('/snippets/rule.css'),
    stylesheet('/snippets/latex_table.css'),
    script(src: '/snippets/render_latex.js')
  ]);
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
      td(a(rule.id.toString(), href: '/rule/${rule.id}/read')),
      td(span('.latex', rule.substitution.leftExpression.latex)),
      td(span('.rule-arrow')),
      td(span('.latex', rule.substitution.rightExpression.latex)),
      td(unsafe(() => a('proof', href: '/proof/${rule.proof.id}/steps/list'),
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
    stylesheet('/snippets/rule.css'),
    stylesheet('/snippets/latex_table.css'),
    script(src: '/snippets/render_latex.js')
  ]);
});

final deleteRulePage = new Page(template: (s) {
  return deleteResourceTemplate(s, 'rule');
});
