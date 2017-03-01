// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final createCategoryPage = new AdminPage(
    template: (data) {
      return createResourceTemplate(data, 'category', inputs: (data) {
        return [
          input(type: 'hidden', name: 'locale', value: 'en_US'),
          label('Name', _for: 'content'),
          input('#content.form-control', type: 'text', name: 'content'),
          small('#nameHelp.form-text.text-muted',
              'Enter the English (en-US) name for the category.')
        ];
      });
    },
    postFormat: {
      'subject': {
        'descriptor': {
          'locale': {'code': 'locale'},
          'content': 'content'
        }
      }
    });
