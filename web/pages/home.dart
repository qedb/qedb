// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'components.dart';

final allMethods = [
  ['locale/create', 'Create locale'],
  ['descriptor/create', 'Create descriptor'],
  ['category/create', 'Create category'],
  ['descriptor/list', 'List descriptors']
];

final homePage = new AdminPage(template: (data) {
  return html([
    head([title('EqDB admin'), defaultHead(data)]),
    body([
      div('.jumbotron', [
        div('.container', [h1('.display-3', 'EqDB admin')])
      ]),
      div('.container', [
        div('.list-group', [
          allMethods
              .map((method) => a(
                  '.list-group-item.justify-content-between.list-group-item-action',
                  method.last,
                  href: '/${method.first}'))
              .toList()
        ])
      ])
    ])
  ]);
});
