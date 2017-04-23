// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';
import 'descriptor.dart';

final createFunctionPage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'function', inputs: (_) {
        return [
          input(type: 'hidden', name: 'language', value: 'en_US'),
          formGroup('Subject', 'subject', [
            select('#subject.custom-select.form-control',
                name: 'subject',
                c: s.additional['subjects'].map((subject) {
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
              languageSelect(s,
                  name: 'descriptor-language', customClass: '', inGroup: false)
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
      return updateResourceTemplate(s, 'function', inputs: (_) {
        return [
          formGroup('Subject', 'subject', [
            select('#subject.custom-select.form-control',
                name: 'subject',
                c: s.additional['subjects'].map((subject) {
                  return option(
                      safe(
                          () => subject.descriptor.translations[0].content, ''),
                      value: subject.id);
                }).toList()
                  ..insert(0, option(' ', value: '')))
          ]),
          formInput('Keyword', name: 'keyword'),
          formGroup('Keyword type', 'keyword-type', [
            select('.form-control', name: 'keyword-type', c: [
              option(' ', value: ''),
              option('Word', value: 'word'),
              option('Acronym', value: 'acronym'),
              option('Abbreviation', value: 'abbreviation'),
              option('Symbol', value: 'symbol'),
              option('LaTeX', value: 'latex')
            ])
          ]),
          formInput('LaTeX template', name: 'latex-template')
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
        'keyword': data['keyword'].isNotEmpty ? data['keyword'] : null,
        'keywordType': data['keyword-type'].trim().isNotEmpty
            ? data['keyword-type']
            : null,
        'latexTemplate':
            data['latex-template'].isNotEmpty ? data['latex-template'] : null
      };
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
    th('Actions')
  ], row: (function) {
    return [
      td(function.id.toString()),
      td(descriptorHyperlink(() => function.subject.descriptor)),
      td(descriptorHyperlink(() => function.descriptor)),
      td(safe(() => function.keyword.toString(), span('.none'))),
      td(safe(() => function.keywordType.toString(), span('.none'))),
      td(safe(() => span('.latex', function.latexTemplate), span('.none'))),
      td(function.generic ? 'yes' : 'no'),
      td([a('Update', href: '${function.id}/update')])
    ];
  }, headTags: [
    style(
        '.katex-display { margin: 0 !important; text-align: left !important; }'
        'tr { line-height: 3em; }')
  ], bodyTags: [
    katexSource(s),
    script(s.snippets['render-latex.js'])
  ]);
});
