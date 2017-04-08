// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final allMethods = [
  ['locale/create', 'Create locale'],
  ['descriptor/create', 'Create descriptor'],
  ['subject/create', 'Create subject'],
  ['category/create', 'Create category'],
  ['function/create', 'Create function'],
  ['definition/create', 'Create definition'],
  ['descriptor/list', 'List descriptors'],
  ['subject/list', 'List subjects'],
  ['category/list', 'List categories'],
  ['function/list', 'List functions'],
  ['definition/list', 'List definitions']
];

final homePage = new Page(template: (data) {
  return html([
    head([title('EqDB Admin'), defaultHead(data)]),
    body([
      div('.jumbotron', style: 'background: linear-gradient(#ccc, #fff);', c: [
        div('.container', style: 'text-align: center;', c: [
          svg(logoSvgContent,
              style: 'max-width: 20em; vertical-align: middle;',
              xmlns: 'http://www.w3.org/2000/svg',
              viewBox: '0 0 31 16'),
          span('.display-4', 'Admin',
              style: buildStyle({
                'vertical-align': 'middle',
                'padding-left': '.3em',
                'font-family': "'Roboto'"
              }))
        ])
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
