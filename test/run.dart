// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'csvtest/csvtest.dart';

Future main() async {
  final baseUrl = 'http://localhost:8080/eqdb/v0/';
  final pkey = new PrimaryKeyEmulator();

  // Descriptors
  await csvtest(baseUrl, 'data/data.0.csv', [
    // Create descriptor.
    route('POST', 'descriptor/create', request: {
      'translations': [
        {'locale': 'en_US', 'content': column('Translation (en_US)')}
      ]
    }, response: {
      'descriptors': [
        {'id': pkey.get('descriptor', column('Translation (en_US)'))}
      ],
      'locales': [
        {'id': pkey.get('locale', 'en_US'), 'code': 'en_US'}
      ],
      'translations': [
        {
          'id': pkey.get('translation', column('Translation (en_US)')),
          'descriptorId': column('ID'),
          'localeId': pkey.get('locale', 'en_US'),
          'content': column('Translation (en_US)')
        }
      ]
    }),

    // Add Dutch translation to descriptor.
    route('POST', 'descriptor/{id}/translations/create', url: {
      'id': column('ID')
    }, request: {
      'locale': 'nl_NL',
      'content': column('Translation (nl_NL)')
    }, response: {
      'locales': [
        {'id': pkey.get('locale', 'nl_NL'), 'code': 'nl_NL'}
      ],
      'translations': [
        {
          'id': pkey.get('translation', column('Translation (nl_NL)')),
          'descriptorId': column('ID'),
          'localeId': pkey.get('locale', 'nl_NL'),
          'content': column('Translation (nl_NL)')
        }
      ]
    }),

    // Create subject from descriptor.
    route('POST', 'subject/create', runIf: column('Subject'), request: {
      'descriptorId': column('ID')
    }, response: {
      'subjects': [
        {'id': pkey.get('subject', column('ID')), 'descriptorId': column('ID')}
      ]
    })
  ]);

  // Categories
  await csvtest(baseUrl, 'data/data.1.csv', [
    route('POST', 'category/create', request: {
      'parentId': includeIfNotEmpty(column('Parent ID')),
      'name': {'locale': 'en_US', 'content': column('Name')}
    }, response: {
      'subjects': [
        {
          'id': pkey.get('subject', pkey.get('descriptor', column('Name'))),
          'descriptorId': pkey.get('descriptor', column('Name'))
        }
      ],
      'categories': [
        {
          'id': pkey.get('category', column('Name')),
          'subjectId':
              pkey.get('subject', pkey.get('descriptor', column('Name'))),
          'parents': intlist(column('Parents'))
        }
      ]
    })
  ]);
}
