// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';

typedef dynamic InlineHtmlBuilder(PageSessionData data);

/// SVG logo data.
final logoSvgContent = [
  '<path d="M2 2v9h6V9H7v1H3V7h2V6H3V3h4v1h1V2zm14 0v1h1v7h-1v1h3c2.479396 0 4-2.0206 4-4.5S21.479396 2 19 2h-1zm2 1h1c1.938956 0 3 1.5611 3 3.5 0 1.939-1.061044 3.5-3 3.5h-1zm6-1v9h3.5c1.37479 0 2.487405-1.1253 2.5-2.5.01105-1.2059-.757689-2.0327-1.618433-2.4006.271667-.2357.618432-.7799.618432-1.5994 0-1.3748-1.12521-2.5-2.5-2.5zm1 1h1.5c.834349 0 1.5.6657 1.5 1.5 0 .8344-.665651 1.5-1.5 1.5H25zm0 4h2.5c.834349 0 1.5.6657 1.5 1.5 0 .8344-.665651 1.5-1.5 1.5H25zM11 3.9992c-1.65093 0-3 1.3491-3 3 0 1.651 1.34907 3 3 3s3-1.349 3-3c0-1.6509-1.34907-3-3-3zm0 1c1.110494 0 2 .8895 2 2s-.889506 2-2 2-2-.8895-2-2 .889506-2 2-2z"></path>',
  '<path d="M13 3.9991v11.2598l4.197266-1.7988-.394532-.92L14 13.7413V3.9991h-1z"></path>'
].join();

/// Shorthand
String stylesheet(String href) => link(rel: 'stylesheet', href: href);

List editexStyles(PageSessionData data) => [
      style(data.snippets['editex.css']),
      stylesheet(data.settings['editex.css.href'])
    ];

List katexSource(PageSessionData data) => [
      stylesheet(data.settings['katex.css.href']),
      script(src: data.settings['katex.js.src'])
    ];

/// Bootstrap .form-group
String formGroup(String labelText, String id, List widget) {
  return div('.form-group', [label(labelText, _for: id), widget]);
}

/// Shortcut for [formGroup] with input.
String formInput(String labelText, {String name, String type: 'text'}) {
  return formGroup(
      labelText, name, [input('#$name.form-control', type: type, name: name)]);
}

/// Language language select form element.
String languageSelect(PageSessionData data,
    {String name: 'language',
    String customClass: '.custom-select',
    bool inGroup: true}) {
  final selectHtml = select('#$name$customClass.form-control',
      name: name,
      c: data.additional['languages'].map((language) {
        return option(language.code, value: language.code);
      }).toList());

  if (inGroup) {
    return formGroup('Language', name, [selectHtml]);
  } else {
    return selectHtml;
  }
}

/// Select with Yes/No options.
String selectYesNo(String label, {String name}) {
  return formGroup(label, name, [
    select('#$name.form-control', name: name, c: [
      option('No', value: 'false', selected: ''),
      option('Yes', value: 'true')
    ])
  ]);
}

/// Default HEAD parameters.
List defaultHead(PageSessionData data) => [
      meta(charset: 'utf-8'),
      meta(
          name: 'viewport',
          content: 'width=device-width,initial-scale=1,shrink-to-fit=no'),
      link(
          rel: 'stylesheet',
          href: data.settings['bootstrap.href'],
          integrity: data.settings['bootstrap.integrity'],
          crossorigin: 'anonymous')
    ];

/// Paths that can be linked in the breadcrumb.
/// Putting this in the global namespace is ugly. But this entire templating
/// thing is ugly, so who cares.
/// TODO: make cleaner mechanism for available links
final breadcrumbAvailableLinks = [];

/// Path breadcrumb.
dynamic breadcrumb(PageSessionData data) {
  return nav('.breadcrumb',
      style: 'word-spacing: .3em; margin-bottom: 2em;',
      c: [
        a('EqDB', href: '/'),
        span(' / '),
        new List.generate(data.path.length, (i) {
          final numberRegex = new RegExp(r'^[0-9]+$');
          final pathDir = data.path[i];

          if (i == data.path.length - 1) {
            return span(pathDir);
          } else {
            final suffixCommand =
                numberRegex.hasMatch(pathDir) ? 'read' : 'list';
            final href =
                '/${data.path.sublist(0, i + 1).join('/')}/$suffixCommand';
            final hrefPattern = href.replaceAll(new RegExp('[0-9]+'), '{id}');

            if (breadcrumbAvailableLinks.contains(hrefPattern)) {
              return [a(pathDir, href: href), ' / '];
            } else {
              return '$pathDir / ';
            }
          }
        })
      ]);
}

/// Template for every page.
String pageTemplate(PageSessionData data, String pageTitle,
    {InlineHtmlBuilder inputs,
    dynamic headTags,
    dynamic containerTags,
    dynamic bodyTags}) {
  return html([
    head([title(pageTitle), defaultHead(data), headTags]),
    body([
      breadcrumb(data),
      div('.container', [h3(pageTitle), br(), containerTags]),
      bodyTags
    ])
  ]);
}

/// Resource creation page.
String createResourceTemplate(PageSessionData data, String name,
    {InlineHtmlBuilder inputs,
    dynamic headTags,
    dynamic bodyTags,
    String overviewRoute}) {
  // Build form.
  dynamic containerTags;
  if (data.data.containsKey('id')) {
    containerTags = [
      div('.alert.alert-success', 'Successfully created $name', role: 'alert'),
      a('.btn.btn-primary', 'Return to $name overview',
          href: overviewRoute ?? data.relativeUrl('list'), role: 'button'),
      a('.btn', 'Create another $name',
          href: data.relativeUrl('create'), role: 'button')
    ];
    if (breadcrumbAvailableLinks.contains('/$name/{id}/read')) {
      containerTags.add(a('.btn', 'Go to created $name',
          href: '/$name/${data.data.id}/read', role: 'button'));
    }
  } else {
    containerTags = form(method: 'POST', c: [
      inputs(data),
      br(),
      button('.btn.btn-primary.btn-lg', 'Submit', type: 'submit')
    ]);
    if (data.data.containsKey('error')) {
      containerTags = [
        div('.alert.alert-warning', role: 'alert', c: [
          '${prettyPrintErrorMessage(data.data.error.message)} ',
          '<strong>(${data.data.error.code})</strong>'
        ]),
        containerTags
      ];
    }
  }

  return pageTemplate(data, 'Create $name',
      headTags: headTags, bodyTags: bodyTags, containerTags: containerTags);
}

typedef dynamic HtmlTableRowBuilder(dynamic data);

/// Resource listing page.
String listResourceTemplate(
    PageSessionData data, String nameSingular, String namePlural,
    {String customTitle,
    String customCreateButton,
    List tableHead,
    HtmlTableRowBuilder row,
    dynamic headTags,
    dynamic bodyTags}) {
  String createButton;
  if (breadcrumbAvailableLinks.contains('/${data.path.first}/create')) {
    createButton = p(a(
        '.btn.btn-primary', customCreateButton ?? 'Create new $nameSingular',
        href: 'create'));
  }

  return pageTemplate(data, customTitle ?? 'All $namePlural',
      headTags: headTags,
      bodyTags: bodyTags,
      containerTags: [
        createButton,
        br(),
        table('.table', [
          thead([tr(tableHead)]),
          tbody(data.data.map((resource) {
            return tr(row(resource));
          }).toList())
        ])
      ]);
}
