// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../admin_page.dart';
import 'components.dart';

final createCategoryPage = new AdminPage(
    template: (data) {
      return html([
        head([
          title('Create category'),
          defaultHead(data),
          //style(include('../../styles/treeselect.css')),
        ]),
        body([
          breadcrumb(data),
          div('.container', [
            h3('Create category'),
            br(),
            form(action: '/category/create', method: 'POST', c: [
              div('.form-group', [
                input(type: 'hidden', name: 'locale', value: 'en_US'),
                label('Name', _for: 'content'),
                input('#content.form-control', type: 'text', name: 'content'),
                small('#nameHelp.form-text.text-muted',
                    'Enter the English (en-US) name for the category.')
              ])
            ])
          ])
        ])
      ]);
    },
    postFormat: {
      'subject': {
        'descriptor': {
          'locale': {'code': 'locale'},
          'content': 'content'
        }
      }
    });
