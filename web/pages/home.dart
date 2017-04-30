// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final homePage = new Page(template: (s) {
  // Generate action list from available routes.
  final actions = s.allRoutes
      .map((str) => str.split('/').sublist(1))
      .where((parts) =>
          parts.length == 2 && ['create', 'list'].contains(parts.last))
      .map((parts) => [
            parts.join('/'),
            ucfirst(parts.reversed.join(' ')) +
                (parts.last == 'list' ? 's' : '')
          ]);

  return html([
    head([title('EqDB Admin'), defaultHead(s)]),
    body([
      div('.jumbotron', c: [
        div('.container', style: 'text-align: center;', c: [
          svg([
            svgDefs([
              svgLinearGradient([
                svgStop(offset: '5%', stop_color: '#aaa'),
                svgStop(offset: '95%', stop_color: '#fff')
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
          span('.display-4', 'Builder',
              style: buildStyle({
                'vertical-align': 'middle',
                'padding-left': '.3em',
                'font-family': "'Roboto'",
                'background': '-webkit-linear-gradient(#aaa, #ddd)',
                '-webkit-background-clip': 'text',
                '-webkit-text-fill-color': 'transparent'
              }))
        ])
      ]),
      div('.container', [
        ul('.list-group', [
          actions
              .map((action) => li(
                  '.list-group-item', a(action.last, href: '/${action.first}')))
              .toList()
        ]),
        br(),
        br()
      ])
    ])
  ]);
});
