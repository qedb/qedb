// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'templates.dart';

final allMethods = [
  ['locale/create', 'Create locale'],
  ['descriptor/create', 'Create descriptor'],
  ['subject/create', 'Create subject'],
  ['category/create', 'Create category'],
  ['descriptor/list', 'List descriptors'],
  ['subject/list', 'List subjects']
];

final homePage = new AdminPage(template: (data) {
  return html([
    head([title('EqDB admin'), defaultHead(data)]),
    body([
      div('.jumbotron', [
        div('.container', [h1('.display-3', 'EqDB admin')])
      ]),
      div('.container', [
        ul('.list-group', [
          allMethods
              .map((method) => li(
                  '.list-group-item', a(method.last, href: '/${method.first}')))
              .toList()
        ])
      ])
    ])
  ]);
});
