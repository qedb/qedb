// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createTranslationPage = new AdminPage(
    template: (data) {
      return createResourceTemplate(data, 'translation', inputs: (data) {
        return [
          input(
              type: 'hidden',
              name: 'descriptorId',
              value: data.pathParameters['id']),
          localeSelect(data),
          div('.form-group', [
            label('Translation', _for: 'content'),
            input('#content.form-control', type: 'text', name: 'content')
          ])
        ];
      }, success: (data) {
        return [
          div('.alert.alert-success', 'Successfully added translation',
              role: 'alert'),
          a('.btn.btn-primary', 'Return to descriptor',
              href: '/descriptor/${data.pathParameters['id']}/read',
              role: 'button')
        ];
      });
    },
    postFormat: {
      'descriptor': {'id': 'descriptorId'},
      'locale': {'code': 'locale'},
      'content': 'content'
    },
    additional: {
      'locales': 'locale/list'
    });
