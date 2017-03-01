// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';

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

/// Paths that should not be linked in the breadcrumb.
/// Putting this in the global namespace is ugly. But this entire templating
/// thing is ugly, so who cares.
final breadcrumbAvailableLinks = [];

/// Path breadcrumb.
dynamic breadcrumb(PageData data) {
  return nav('.breadcrumb', [
    a('.breadcrumb-item', 'Index', href: '/'),
    new List.generate(data.path.length, (i) {
      final numberRegex = new RegExp(r'^[0-9]+$');
      final pathDir = data.path[i];

      if (i == data.path.length - 1) {
        return span('.breadcrumb-item.active', pathDir);
      } else {
        final suffixCommand = numberRegex.hasMatch(pathDir) ? 'read' : 'list';
        final href = '/${data.path.sublist(0, i + 1).join('/')}/$suffixCommand';
        final hrefPattern = href.replaceAll(new RegExp('[0-9]+'), '{id}');

        if (breadcrumbAvailableLinks.contains(hrefPattern)) {
          return a('.breadcrumb-item', pathDir, href: href);
        } else {
          return span('.breadcrumb-item.active', pathDir);
        }
      }
    })
  ]);
}

/// Language locale select form element.
dynamic localeSelect(PageData data, [String name = 'locale']) =>
    div('.form-group', [
      label('Locale', _for: name),
      select('#$name.custom-select.form-control',
          name: name,
          c: data.additional['locales'].map((locale) {
            return option(locale.code, value: locale.code);
          }).toList())
    ]);

bool safeIf(Function fn) {
  try {
    return fn();
  } catch (e) {
    return false;
  }
}
