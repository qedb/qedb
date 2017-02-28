// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../admin_page.dart';

/// Default HEAD parameters.
List defaultHead(PageData data) => [
      meta(charset: 'utf-8'),
      meta(
          name: 'viewport',
          content: 'width=device-width,initial-scale=1,shrink-to-fit=no'),
      link(
          rel: 'stylesheet',
          href: data.constants['bootstrap.href'],
          integrity: data.constants['bootstrap.integrity'],
          crossorigin: 'anonymous')
    ];

dynamic breadcrumb(PageData data) => nav('.breadcrumb', [
      a('.breadcrumb-item', 'Index', href: '/'),
      new List.generate(data.path.length, (i) {
        final numberRegex = new RegExp(r'^[0-9]+$');
        final pathDir = data.path[i];
        if (i == data.path.length - 1 || numberRegex.hasMatch(pathDir)) {
          return span('.breadcrumb-item.active', pathDir);
        } else {
          return a('.breadcrumb-item', pathDir,
              href: '/' + data.path.sublist(0, i + 1).join('/'));
        }
      })
    ]);

bool safeIf(Function fn) {
  try {
    return fn();
  } catch (e) {
    return false;
  }
}
