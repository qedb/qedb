// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'csvtest/csvtest.dart';

Future main() async {
  final baseUrl = 'http://localhost:8080/eqdb/v0/';
  final pkey = new PrimaryKeyEmulator();

  // Descriptor
  await csvtest(baseUrl, 'data/data.0.csv', [
    // Create descriptor.
    route('POST', 'descriptor/create', request: {
      'translations': [
        {
          'locale': {'code': 'en_US'},
          'content': col('Translation (en_US)')
        }
      ]
    }, response: {
      'id': pkey.get('descriptor', col('Translation (en_US)')),
      'translations': [
        {
          'id': pkey.get('translation', col('Translation (en_US)')),
          'locale': {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'},
          'content': col('Translation (en_US)')
        }
      ]
    }),

    // Get descriptor translations.
    route('GET', 'descriptor/{id}/translations/list', url: {
      'id': col('ID')
    }, response: [
      {
        'id': pkey.get('translation', col('Translation (en_US)')),
        'locale': {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'},
        'content': col('Translation (en_US)')
      }
    ]),

    // Add Dutch translation to descriptor.
    route('POST', 'descriptor/{id}/translations/create', url: {
      'id': col('ID')
    }, request: {
      'locale': {'code': 'nl_NL'},
      'content': col('Translation (nl_NL)')
    }, response: {
      'id': pkey.get('translation', col('Translation (nl_NL)')),
      'locale': {'id': pkey.get('locale', 'nl_NL'), 'code': 'nl_NL'},
      'content': col('Translation (nl_NL)')
    }),

    // Get descriptor translations again.
    route('GET', 'descriptor/{id}/translations/list', url: {
      'id': col('ID')
    }, response: [
      {
        'id': pkey.get('translation', col('Translation (en_US)')),
        'locale': {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'},
        'content': col('Translation (en_US)')
      },
      {
        'id': pkey.get('translation', col('Translation (nl_NL)')),
        'locale': {'id': pkey.get('locale', 'nl_NL'), 'code': 'nl_NL'},
        'content': col('Translation (nl_NL)')
      }
    ]),

    // Create subject from descriptor.
    route('POST', 'subject/create', runIf: col('Subject'), request: {
      'descriptor': {'id': col('ID')}
    }, response: {
      'id': pkey.get('subject', col('ID')),
      'descriptor': {'id': col('ID')}
    })
  ]);

  // Category
  /*await csvtest(baseUrl, 'data/data.1.csv', [
    // Create category.
    route('POST', 'category/create', request: {
      'parentId': includeIf(not(empty(col('Parent ID'))), col('Parent ID')),
      'name': {'locale': 'en_US', 'content': col('Name')}
    }, response: {
      'subject': [
        {
          'id': pkey.get('subject', pkey.get('descriptor', col('Name'))),
          'descriptorId': pkey.get('descriptor', col('Name'))
        }
      ],
      'category': [
        {
          'id': pkey.get('category', col('Name')),
          'subjectId': pkey.get('subject', pkey.get('descriptor', col('Name'))),
          'parents': intlist(col('Parents'))
        }
      ]
    })
  ]);

  // Function
  await csvtest(baseUrl, 'data/data.2.csv', [
    // Create function.
    route('POST', 'function/create', request: {
      'categoryId': pkey.get('category', col('Category')),
      'argumentCount': col('ArgC'),
      'latexTemplate': col('LaTeX template'),
      'generic': col('Generic'),
      'name': ifNe('Name', {'locale': 'en_US', 'content': col('Name')}),
      'operator': ifNe('Pre.',
          {'precedenceLevel': col('Pre.'), 'associativity': col('Ass.')})
    }, response: {
      'descriptor':
          ifNor(empty(col('Name')), pkey.contains('translation', col('Name')), [
        {'id': pkey.get('descriptor', col('Name'))}
      ]),
      'translation':
          ifNor(empty(col('Name')), pkey.contains('translation', col('Name')), [
        {
          'id': pkey.get('translation', col('Name')),
          'descriptorId': pkey.get('descriptor', col('Name')),
          'localeId': pkey.get('locale', 'en_US'),
          'content': col('Name')
        }
      ]),
      'function': [
        {
          'id': col('ID'),
          'categoryId': pkey.get('category', col('Category')),
          'descriptorId': ifNe('Name', pkey.get('descriptor', col('Name'))),
          'argumentCount': col('ArgC'),
          'latexTemplate': col('LaTeX template'),
          'generic': col('Generic')
        }
      ],
      'operator': ifNe('Pre.', [
        {
          'id': pkey.get('operator', col('ID')),
          'functionId': col('ID'),
          'precedenceLevel': col('Pre.'),
          'associativity': col('Ass.')
        }
      ])
    })
  ]);*/
/*
  // Definition
  await csvtest(baseUrl, 'data/data.3.csv', [
  // Create definition.
  - route:                    definition/create
    method:                   POST
    request:
      categoryId:             column:cID
      left:                   eqlib:codec:column:Equation left
      right:                  eqlib:codec:column:Equation right
    response:
      rules:
      - id:                   column:rID
        categoryId:           column:cID
        0:leftExpressionId:   eqlib:index:column:Equation left
        1:rightExpressionId:  eqlib:index:column:Equation right
      definitions:
      - id:                   column:ID
        ruleId:               column:rID
      # expressions:            accect:anyList
      # functionReferences:     accect:anyList
      # integerReferences:      accect:anyList
    ignore:
    - expressions
    - functionReferences
    - integerReferences

  # Retrieve expression tree for left expression.
  - route:      expression/{id}/retrieveTree
    method:     GET
    url:
      id:       eqlib:index:column:Equation left
    response:
      id:       eqlib:index:column:Equation left
      rawData:  eqlib:codec:column:Equation left
    ignore:
    - reference

  # Retrieve expression tree for right expression.
  - route:      expression/{id}/retrieveTree
    method:     GET
    url:
      id:       eqlib:index:column:Equation right
    response:
      id:       eqlib:index:column:Equation right
      rawData:  eqlib:codec:column:Equation right
    ignore:
    - reference*/
}
