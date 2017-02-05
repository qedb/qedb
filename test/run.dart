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
        {'id': column('ID')}
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
    })
  ]);
}
