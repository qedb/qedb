// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:htgen/static.dart';

import '../page.dart';
import 'templates.dart';
import 'descriptor.dart';

String keywordTypeSelect({String name}) {
  return select('.form-control', name: name, c: [
    option('Word', value: 'word'),
    option('Acronym', value: 'acronym'),
    option('Abbreviation', value: 'abbreviation'),
    option('Symbol', value: 'symbol'),
    option('LaTeX', value: 'latex')
  ]);
}

final createFunctionPage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'function', inputs: (_) {
        return [
          input(type: 'hidden', name: 'language', value: 'en_US'),
          subjectSelect(s, name: 'subject'),
          div('.form-group', [
            label('Name'),
            div('.input-group', [
              input('.form-control', type: 'text', name: 'descriptor'),
              languageSelect(s, name: 'descriptor-language', inGroup: false)
            ])
          ]),
          div('.form-group', [
            label('Keyword'),
            div('.input-group', [
              input('.form-control', type: 'text', name: 'keyword'),
              keywordTypeSelect(name: 'keyword-type')
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
      });
    },
    onPost: (data) {
      final subjectId = unsafe(() => int.parse(data['subject']), null);
      return {
        'subject': subjectId != null ? {'id': subjectId} : null,
        'descriptor': {
          'translations': [
            {
              'language': {'code': data['descriptor-language']},
              'content': data['descriptor']
            }
          ]
        },
        'generic': data['generic'] == 'true',
        'rearrangeable': data['rearrangeable'] == 'true',
        'argumentCount': int.parse(data['argument-count'], onError: (_) => 0),
        'keyword': data['keyword'],
        'keywordType': data['keyword-type'],
        'latexTemplate': data['latex-template']
      };
    },
    additional: {
      'languages': 'language/list',
      'subjects': 'subject/list?language=en_US'
    });

final updateFunctionPage = new Page(
    template: (s) {
      return updateResourceTemplate(s, 'function', fields: {
        'Subject': (s) => subjectSelect(s, name: 'subject', inGroup: false),
        'Keyword': (s) => input('#keyword.form-control', name: 'keyword'),
        'Keyword type': (s) => keywordTypeSelect(name: 'keyword-type'),
        'LaTeX template': (s) =>
            input('#latex-template.form-control', name: 'latex-template')
      });
    },
    onPost: (data) {
      final map = new Map<String, dynamic>();
      if (data.containsKey('subject')) {
        map['subject'] = {'id': int.parse(data['subject'])};
      }
      if (data.containsKey('keyword')) {
        map['keyword'] = data['keyword'];
      }
      if (data.containsKey('keyword-type')) {
        map['keywordType'] = data['keyword-type'];
      }
      if (data.containsKey('latex-template')) {
        map['latexTemplate'] = data['latex-template'];
      }
      return map;
    },
    additional: {'subjects': 'subject/list?language=en_US'});

final listFunctionsPage = new Page(template: (s) {
  return listResourceTemplate(s, 'function', 'functions', tableHead: [
    th('ID'),
    th('Subject'),
    th('Descriptor'),
    th('Keyword'),
    th('Keyword type'),
    th('LaTeX template'),
    th('Generic'),
    th('Actions', style: 'width: 1px;')
  ], row: (function) {
    return [
      td(function.id.toString()),
      td(descriptorHyperlink(() => function.subject.descriptor)),
      td(descriptorHyperlink(() => function.descriptor)),
      td(unsafe(() => function.keyword.toString(), span('.none'))),
      td(unsafe(() => function.keywordType.toString(), span('.none'))),
      td(unsafe(
          () => span('.latex', function.latexTemplate,
              title: function.latexTemplate),
          span('.none'))),
      td(function.generic ? 'yes' : 'no'),
      td([
        a('.btn.btn-outline-secondary.btn-sm', 'Update',
            href: '${function.id}/update')
      ])
    ];
  }, headTags: [
    style(
        '.katex-display { margin: 0 !important; text-align: left !important; }'
        'tr { line-height: 3em; }')
  ], bodyTags: [
    katexSource(s),
    script(src: '/snippets/render_latex.js')
  ]);
});
