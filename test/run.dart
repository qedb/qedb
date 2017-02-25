// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'csvtest/csvtest.dart';

Future main() async {
  final baseUrl = 'http://localhost:8080/eqdb/v0/';
  final pkey = new PrimaryKeyEmulator();
  final eqlib = new EqlibHelper();

  // Load function keywords.
  await eqlib.loadKeywords('data/data.2.csv', 'ID', 'Keyword');

  // Descriptors
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

  // Categories
  await csvtest(baseUrl, 'data/data.1.csv', [
    // Create category.
    route('POST', 'category/create', runIf: empty(col('Parent ID')), request: {
      'subject': {
        'descriptor': {
          'translations': [
            {
              'locale': {'code': 'en_US'},
              'content': col('Name')
            }
          ]
        }
      }
    }, response: {
      'id': pkey.get('category', col('Name')),
      'subject': {
        'id': pkey.get('subject', pkey.get('descriptor', col('Name'))),
        'descriptor': 'any:map'
      },
      'parents': []
    }),

    // Create sub-category.
    route('POST', 'category/{id}/category/create',
        runIf: not(empty(col('Parent ID'))),
        url: {
          'id': col('Parent ID')
        },
        request: {
          'subject': {
            'descriptor': {
              'translations': [
                {
                  'locale': {'code': 'en_US'},
                  'content': col('Name')
                }
              ]
            }
          }
        },
        response: {
          'id': pkey.get('category', col('Name')),
          'subject': {
            'id': pkey.get('subject', pkey.get('descriptor', col('Name'))),
            'descriptor': 'any:map'
          },
          'parents': intlist(col('Parents'))
        })
  ]);

  // Functions
  await csvtest(baseUrl, 'data/data.2.csv', [
    // Create function.
    route('POST', 'function/create', request: {
      'category': {'id': pkey.get('category', col('Category'))},
      'descriptor': ifNe('Name', {
        'translations': [
          {
            'locale': {'code': 'en_US'},
            'content': col('Name')
          }
        ]
      }),
      'generic': col('Generic'),
      'argumentCount': col('ArgC'),
      'latexTemplate': col('LaTeX template')
    }, response: {
      'id': col('ID'),
      'category': {'id': pkey.get('category', col('Category'))},
      'descriptor': ifNe('Name', {
        'id': pkey.get('descriptor', col('Name')),
        'translations': [
          {
            'id': pkey.get('translation', col('Name')),
            'locale': {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'},
            'content': col('Name')
          }
        ]
      }),
      'generic': col('Generic'),
      'argumentCount': col('ArgC'),
      'latexTemplate': col('LaTeX template')
    }),

    // Create operator.
    route('POST', 'operator/create', runIf: not(empty(col('Pre.'))), request: {
      'precedenceLevel': col('Pre.'),
      'associativity': col('Ass.'),
      'function': {'id': col('ID')}
    }, response: {
      'id': pkey.get('operator', col('ID')),
      'precedenceLevel': col('Pre.'),
      'associativity': col('Ass.'),
      'function': {'id': col('ID')}
    })
  ]);

  // Definitions
  await csvtest(baseUrl, 'data/data.3.csv', [
    // Create definition.
    route('POST', 'definition/create', request: {
      'rule': {
        'category': {'id': pkey.get('category', col('Category'))},
        'leftExpression': {'data': eqlib.data(col('Expression left'))},
        'rightExpression': {'data': eqlib.data(col('Expression right'))}
      }
    }, response: {
      'id': pkey.get('definition', col('ID')),
      'rule': {
        'id': pkey.get('rule', col('ID')),
        'category': {'id': pkey.get('category', col('Category'))},
        'leftExpression': {
          'id': pkey.get('expression', col('Expression left')),
          'data': eqlib.data(col('Expression left')),
          'hash': eqlib.hash(col('Expression left')),
          'functions': eqlib.functionIds(col('Expression left'))
        },
        'rightExpression': {
          'id': pkey.get('expression', col('Expression right')),
          'data': eqlib.data(col('Expression right')),
          'hash': eqlib.hash(col('Expression right')),
          'functions': eqlib.functionIds(col('Expression right'))
        }
      }
    })
  ]);
}
