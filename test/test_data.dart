// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'csvtest/csvtest.dart';

Future main() async {
  final baseUrl = 'http://localhost:8080/eqdb/v0/';
  final pkey = new PrimaryKeyEmulator();
  final eqlib = new EqlibHelper();

  final languagesFile = 'data/data.0.csv';
  final subjectsFile = 'data/data.1.csv';
  final functionsFile = 'data/data.2.csv';
  final translationsFile = 'data/data.3.csv';
  final definitionsFile = 'data/data.4.csv';

  // Load function keywords.
  await eqlib.loadKeywords(functionsFile,
      id: 'ID',
      keyword: 'Keyword',
      precedenceLevel: 'Pre.',
      associativity: 'Ass.',
      character: 'Char(1)',
      type: 'Type');

  // Languages
  await csvtest(baseUrl, languagesFile, [
    // Create languages.
    route('POST', 'language/create', request: {
      'code': col('Language code')
    }, response: {
      'id': pkey.get('language', col('Language code')),
      'code': col('Language code')
    })
  ]);

  // Subjects
  await csvtest(baseUrl, subjectsFile, [
    // Create subject.
    route('POST', 'subject/create', request: {
      'descriptor': {
        'translations': [
          {
            'language': {'code': 'en_US'},
            'content': col('Subject')
          }
        ]
      }
    }, response: {
      'id': col('ID'),
      'descriptor': {
        'id': pkey.get('descriptor', col('Subject')),
        'translations': [
          {
            'id': pkey.get('translation', col('Subject'), 'en_US'),
            'language': {'id': pkey.get('language', 'en_US'), 'code': 'en_US'},
            'content': col('Subject')
          }
        ]
      }
    }),
  ]);

  // Functions
  await csvtest(baseUrl, functionsFile, [
    // Create function.
    route('POST', 'function/create', request: {
      'subject': {'id': pkey.get('subject', col('Subject'))},
      'descriptor': ifNe('Name', {
        'translations': [
          {
            'language': {'code': 'en_US'},
            'content': col('Name')
          }
        ]
      }),
      'generic': col('Generic'),
      'rearrangeable': col('Arr.'),
      'argumentCount': col('ArgC'),
      'keyword': ifNe('Keyword', col('Keyword')),
      'keywordType': ifNe('Keyword type', col('Keyword type')),
      'latexTemplate': ifNe('LaTeX template', col('LaTeX template'))
    }, response: {
      'id': col('ID'),
      'subject': {'id': pkey.get('subject', col('Subject'))},
      'descriptor': ifNe('Name', {
        'id': pkey.get('descriptor', col('Name')),
        'translations': [
          {
            'id': pkey.get('translation', col('Name'), 'en_US'),
            'language': {'id': pkey.get('language', 'en_US'), 'code': 'en_US'},
            'content': col('Name')
          }
        ]
      }),
      'generic': col('Generic'),
      'rearrangeable': col('Arr.'),
      'argumentCount': col('ArgC'),
      'keyword': ifNe('Keyword', col('Keyword')),
      'keywordType': ifNe('Keyword type', col('Keyword type')),
      'latexTemplate': ifNe('LaTeX template', col('LaTeX template'))
    }),

    // Create operator.
    route('POST', 'operator/create', runIf: not(empty(col('Pre.'))), request: {
      'function': {'id': col('ID')},
      'precedenceLevel': col('Pre.'),
      'associativity': col('Ass.'),
      'operatorType': col('Type'),
      'character': col('Char(1)'),
      'editorTemplate': col('Editor')
    }, response: {
      'id': pkey.get('operator', col('ID')),
      'function': {'id': col('ID')},
      'precedenceLevel': col('Pre.'),
      'associativity': col('Ass.'),
      'operatorType': col('Type'),
      'character': col('Char(1)'),
      'editorTemplate': col('Editor')
    })
  ]);

  // Translations
  await csvtest(baseUrl, translationsFile, [
    // Create Dutch translation.
    route('POST', 'descriptor/{id}/translation/create', url: {
      'id': pkey.get('descriptor', col('Translation (en_US)'))
    }, request: {
      'language': {'code': 'nl_NL'},
      'content': col('Translation (nl_NL)')
    }, response: {
      'id': pkey.get('translation', col('Translation (nl_NL)'), 'nl_NL'),
      'language': {'id': pkey.get('language', 'nl_NL'), 'code': 'nl_NL'},
      'content': col('Translation (nl_NL)')
    }),
  ]);

  // Definitions
  await csvtest(baseUrl, definitionsFile, [
    // Create definition.
    route('POST', 'rule/create', request: {
      'isDefinition': true,
      'leftExpression': {'data': eqlib.data(col('Expression left'))},
      'rightExpression': {'data': eqlib.data(col('Expression right'))}
    }, response: {
      'id': col('ID'),
      'isDefinition': true,
      'leftExpression': {
        'id': pkey.get('expression', col('Expression left')),
        'data': eqlib.data(col('Expression left')),
        'hash': eqlib.hash(col('Expression left')),
        'latex': accept(AcceptType.string),
        'functions': eqlib.functionIds(col('Expression left'))
      },
      'rightExpression': {
        'id': pkey.get('expression', col('Expression right')),
        'data': eqlib.data(col('Expression right')),
        'hash': eqlib.hash(col('Expression right')),
        'latex': accept(AcceptType.string),
        'functions': eqlib.functionIds(col('Expression right'))
      }
    })
  ]);
}
