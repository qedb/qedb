// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';
import 'descriptor.dart';

final createFunctionPage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'function', inputs: (data) {
        return [
          input(type: 'hidden', name: 'locale', value: 'en_US'),
          formGroup('Subject', 'subject', [
            select('#subject.custom-select.form-control',
                name: 'subject',
                c: data.additional['subjects'].map((subject) {
                  return option(
                      safe(
                          () => subject.descriptor.translations[0].content, ''),
                      value: subject.id);
                }).toList())
          ]),
          div('.form-group', [
            label('Name'),
            div('.input-group', [
              input('.form-control', type: 'text', name: 'descriptor'),
              localeSelect(data,
                  name: 'descriptor-locale', customClass: '', inGroup: false)
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
      });
    },
    onPost: (data) {
      int subjectId;
      try {
        subjectId = int.parse(data['subject']);
      } catch (e) {
        subjectId = null;
      }
      return {
        'subject': subjectId != null ? {'id': subjectId} : null,
        'descriptor': {
          'translations': [
            {
              'locale': {'code': data['descriptor-locale']},
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
      'locales': 'locale/list',
      'subjects': 'subject/list?locale=en_US'
    });

final listFunctionsPage = new Page(template: (data) {
  return listResourceTemplate(data, 'function', 'functions', tableHead: [
    th('ID'),
    th('Subject'),
    th('Descriptor'),
    th('Keyword'),
    th('LaTeX template'),
    th('Generic')
  ], row: (function) {
    return [
      td(function.id.toString()),
      td(descriptorHyperlink(() => function.subject.descriptor)),
      td(descriptorHyperlink(() => function.descriptor)),
      td(safe(() => function.keyword.toString(), '')),
      td(safe(() => span('.latex', function.latexTemplate))),
      td(function.generic ? 'yes' : 'no')
    ];
  }, headTags: [
    style('.katex-display { margin: 0 !important; text-align: left; }'
        'tr { line-height: 3em; }')
  ], bodyTags: [
    katexSource(data),
    script(data.snippets['render-latex.js'])
  ]);
});
