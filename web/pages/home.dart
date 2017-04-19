// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:math';

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final allMethods = [
  ['language/create', 'Create language'],
  ['subject/create', 'Create subject'],
  ['function/create', 'Create function'],
  ['definition/create', 'Create definition'],
  ['lineage/create', 'Create lineage'],
  ['descriptor/list', 'List descriptors'],
  ['subject/list', 'List subjects'],
  ['function/list', 'List functions'],
  ['definition/list', 'List definitions'],
  ['lineage/list', 'List lineages']
];

final homePage = new Page(template: (s) {
  final randomShade = () => new Random().nextBool() ? 'f' : 'd';
  var gradientStart = '#${randomShade()}${randomShade()}${randomShade()}';
  gradientStart = gradientStart == '#fff' ? '#ddd' : gradientStart;

  return html([
    head([title('EqDB Admin'), defaultHead(s)]),
    body([
      div('.jumbotron',
          style: 'background: linear-gradient($gradientStart, #fff);',
          c: [
            div('.container', style: 'text-align: center;', c: [
              svg([
                svgDefs([
                  svgLinearGradient([
                    svgStop(offset: '5%', stop_color: '#333'),
                    svgStop(offset: '95%', stop_color: '#666')
                  ], id: 'logo-gradient', gradientTransform: 'rotate(90)')
                ]),
                logoSvgContent
              ],
                  style: buildStyle({
                    'max-width': '20em',
                    'vertical-align': 'middle',
                    'fill': 'url(#logo-gradient)'
                  }),
                  xmlns: 'http://www.w3.org/2000/svg',
                  viewBox: '0 0 31 16'),
              span('.display-4', 'Admin',
                  style: buildStyle({
                    'vertical-align': 'middle',
                    'padding-left': '.3em',
                    'font-family': "'Roboto'",
                    'background': '-webkit-linear-gradient(#666, #999)',
                    '-webkit-background-clip': 'text',
                    '-webkit-text-fill-color': 'transparent'
                  }))
            ])
          ]),
      div('.container', [
        ul('.list-group', [
          allMethods
              .map((method) => li(
                  '.list-group-item', a(method.last, href: '/${method.first}')))
              .toList()
        ]),
        br(),
        br()
      ])
    ])
  ]);
});
