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
        {'locale': 'en_US', 'content': col('Translation (en_US)')}
      ]
    }, response: {
      'descriptor': [
        {'id': pkey.get('descriptor', col('Translation (en_US)'))}
      ],
      'locale': [
        {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'}
      ],
      'translation': [
        {
          'id': pkey.get('translation', col('Translation (en_US)')),
          'descriptorId': col('ID'),
          'localeId': pkey.get('locale', 'en_US'),
          'content': col('Translation (en_US)')
        }
      ]
    }),

    // Get descriptor translations.
    route('GET', 'descriptor/{id}/translations/list', url: {
      'id': col('ID')
    }, response: {
      'translation': [
        {
          'id': pkey.get('translation', col('Translation (en_US)')),
          'descriptorId': col('ID'),
          'localeId': pkey.get('locale', 'en_US'),
          'content': col('Translation (en_US)')
        }
      ]
    }),

    // Add Dutch translation to descriptor.
    route('POST', 'descriptor/{id}/translations/create', url: {
      'id': col('ID')
    }, request: {
      'locale': 'nl_NL',
      'content': col('Translation (nl_NL)')
    }, response: {
      'locale': [
        {'id': pkey.get('locale', 'nl_NL'), 'code': 'nl_NL'}
      ],
      'translation': [
        {
          'id': pkey.get('translation', col('Translation (nl_NL)')),
          'descriptorId': col('ID'),
          'localeId': pkey.get('locale', 'nl_NL'),
          'content': col('Translation (nl_NL)')
        }
      ]
    }),

    // Get descriptor translations again.
    route('GET', 'descriptor/{id}/translations/list', url: {
      'id': col('ID')
    }, response: {
      'translation': [
        {
          'id': pkey.get('translation', col('Translation (en_US)')),
          'descriptorId': col('ID'),
          'localeId': pkey.get('locale', 'en_US'),
          'content': col('Translation (en_US)')
        },
        {
          'id': pkey.get('translation', col('Translation (nl_NL)')),
          'descriptorId': col('ID'),
          'localeId': pkey.get('locale', 'nl_NL'),
          'content': col('Translation (nl_NL)')
        }
      ]
    }),

    // Create subject from descriptor.
    route('POST', 'subject/create', runIf: col('Subject'), request: {
      'descriptorId': col('ID')
    }, response: {
      'subject': [
        {'id': pkey.get('subject', col('ID')), 'descriptorId': col('ID')}
      ]
    })
  ]);

  // Category
  await csvtest(baseUrl, 'data/data.1.csv', [
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
  ]);
}
