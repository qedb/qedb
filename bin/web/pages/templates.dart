// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:htgen/static.dart';

import '../page.dart';

typedef dynamic InlineHtmlBuilder(PageSessionData s);

/// SVG logo data.
final logoPath =
    'M31 0v15h-2v-4h-2v3h-7V9h4V7h-4V2h7v3h2V0H18v14h-2c-.95 0-1.575-.202-2.145-.57C15.182 12 16 10.095 16 8c0-4.406-3.594-8-8-8-4.406 0-8 3.594-8 8 0 4.407 3.594 8 8 8 1.577 0 3.046-.468 4.287-1.262C13.24 15.468 14.444 16 16 16h29zM8 2c3.326 0 6 2.675 6 6 0 1.59-.615 3.026-1.617 4.098-.493-.537-1.023-1.153-1.676-1.805-1.775-1.775-4.045-2.08-5.87-1.94-1.38.103-2.29.4-2.76.57C2.033 8.62 2 8.314 2 8c0-3.325 2.674-6 6-6zm25 4l7 8h-7zM6.025 10.383c1.145.065 2.35.405 3.268 1.324.53.53 1 1.078 1.486 1.61C9.95 13.752 9.004 14 8 14c-2.3 0-4.288-1.28-5.295-3.172.476-.156 1.758-.534 3.32-.445z';
final logoSvgContent = '<path d="$logoPath"></path>';

/// Shorthand
String stylesheet(String href) => link(rel: 'stylesheet', href: href);

List katexSource(PageSessionData s) => [
      stylesheet('/external/katex.min.css'),
      script(src: '/external/katex.min.js')
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

/// Language select form element.
String languageSelect(PageSessionData s,
    {String name: 'language', bool inGroup: true}) {
  final options = s.additional['languages'].map((language) {
    return option(language.code, value: language.code);
  }).toList();
  if (options.isEmpty) {
    options.add(option('null', value: ''));
  }

  final selectHtml = select('#$name.form-control', name: name, c: options);

  if (inGroup) {
    return formGroup('Language', name, [selectHtml]);
  } else {
    return selectHtml;
  }
}

/// Subject select form element.
String subjectSelect(PageSessionData s,
    {String name: 'language', bool inGroup: true}) {
  final options = s.additional['subjects'].map((subject) {
    return option(safe(() => subject.descriptor.translations[0].content, ''),
        value: subject.id);
  }).toList();
  if (options.isEmpty) {
    options.add(option('null', value: '0'));
  }

  final selectHtml = select('#$name.form-control', name: name, c: options);

  if (inGroup) {
    return formGroup('Subject', name, [selectHtml]);
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
List defaultHead(PageSessionData s) => [
      meta(charset: 'utf-8'),
      meta(
          name: 'viewport',
          content: 'width=device-width,initial-scale=1,shrink-to-fit=no'),
      link(rel: 'stylesheet', href: '/external/bootstrap.min.css'),
      stylesheet('/snippets/common.css')
    ];

/// Path breadcrumb.
dynamic breadcrumb(PageSessionData s) {
  return nav('.breadcrumb',
      style: 'word-spacing: .3em; margin-bottom: 2em;',
      c: [
        a('QEDb', href: '/'),
        span(' / '),
        new List.generate(s.path.length, (i) {
          final numberRegex = new RegExp(r'^[0-9]+$');
          final pathDir = s.path[i];

          if (i == s.path.length - 1) {
            return span(pathDir);
          } else {
            final suffixCommand =
                numberRegex.hasMatch(pathDir) ? 'read' : 'list';
            final href =
                '/${s.path.sublist(0, i + 1).join('/')}/$suffixCommand';
            final hrefPattern = href.replaceAll(new RegExp('[0-9]+'), '{id}');

            if (s.allRoutes.contains(hrefPattern)) {
              return [a(pathDir, href: href), ' / '];
            } else {
              return '$pathDir / ';
            }
          }
        })
      ]);
}

/// Template for printing errors.
String errorAlert(PageSessionData s) {
  return div('.alert.alert-warning', role: 'alert', c: [
    '${prettyPrintErrorMessage(s.response.error.message)} ',
    '<strong>(${s.response.error.code})</strong>'
  ]);
}

/// Template for every page.
String pageTemplate(PageSessionData s, String pageTitle,
    {InlineHtmlBuilder inputs,
    dynamic headTags,
    dynamic containerTags,
    dynamic bodyTags}) {
  return html([
    head([title(pageTitle), defaultHead(s), headTags]),
    body([
      breadcrumb(s),
      div('.container', [h3(pageTitle), br(), containerTags]),
      bodyTags,
      br(),
      br()
    ])
  ]);
}

/// Resource creation page.
String createResourceTemplate(PageSessionData s, String name,
    {InlineHtmlBuilder inputs,
    dynamic headTags,
    dynamic bodyTags,
    String overviewRoute}) {
  // Build form.
  dynamic containerTags;
  if (s.response.containsKey('id')) {
    containerTags = [
      div('.alert.alert-success', 'Successfully created $name', role: 'alert'),
      a('.btn.btn-primary', 'Return to $name overview',
          href: overviewRoute ?? s.relativeUrl('list'), role: 'button'),
      a('.btn', 'Create another $name',
          href: s.relativeUrl('create'), role: 'button')
    ];
    if (s.allRoutes.contains('/$name/{id}/read')) {
      containerTags.add(a('.btn', 'Go to created $name',
          href: '/$name/${s.response.id}/read', role: 'button'));
    }
  } else {
    containerTags = form(method: 'POST', c: [
      inputs(s),
      br(),
      button('.btn.btn-primary.btn-lg', 'Submit', type: 'submit')
    ]);
    if (s.response.containsKey('error')) {
      containerTags = [errorAlert(s), containerTags];
    }
  }

  return pageTemplate(s, 'Create $name',
      headTags: headTags, bodyTags: bodyTags, containerTags: containerTags);
}

/// Resource update page.
String updateResourceTemplate(PageSessionData s, String name,
    {Map<String, InlineHtmlBuilder> fields,
    dynamic headTags,
    dynamic bodyTags}) {
  // Build form.
  final containerTags = new List();
  if (s.response.containsKey('id')) {
    containerTags.addAll([
      div('.alert.alert-success', 'Successfully updated $name', role: 'alert'),
      a('.btn.btn-primary', 'Return to $name overview',
          href: '/$name/list', role: 'button'),
      a('.btn', 'Update another field', href: 'update', role: 'button')
    ]);
  } else {
    if (s.response.containsKey('error')) {
      containerTags.add(errorAlert(s));
    }

    fields.forEach((label, field) {
      // Create for for each field.
      containerTags.add(form(method: 'POST', c: [
        formGroup(
            label, label.toLowerCase().replaceAll(new RegExp(r'\s'), '-'), [
          div('.input-group', [
            field(s),
            span('.input-group-btn',
                [button('.btn.btn-secondary', 'Submit', type: 'submit')])
          ])
        ])
      ]));
    });
  }

  return pageTemplate(s, 'Update $name #${s.pathParameters['id']}',
      headTags: headTags, bodyTags: bodyTags, containerTags: containerTags);
}

typedef dynamic HtmlTableRowBuilder(dynamic data);

/// Resource listing page.
String listResourceTemplate(
    PageSessionData s, String nameSingular, String namePlural,
    {String customTitle,
    String customCreateButton,
    List tableHead,
    HtmlTableRowBuilder row,
    dynamic headTags,
    dynamic bodyTags}) {
  String createButton;
  if (s.allRoutes.contains('/${s.path.first}/create')) {
    createButton = p(a(
        '.btn.btn-primary', customCreateButton ?? 'Create new $nameSingular',
        href: 'create'));
  }

  s.response.sort((a, b) => a.id - b.id);

  return pageTemplate(s, customTitle ?? 'All $namePlural',
      headTags: headTags,
      bodyTags: bodyTags,
      containerTags: [
        createButton,
        br(),
        table('.table', [
          thead([tr(tableHead)]),
          tbody(s.response.map((resource) {
            return tr(row(resource));
          }).toList())
        ])
      ]);
}

/// Resource deletion page.
String deleteResourceTemplate(PageSessionData s, String name) {
  final containerTags = new List();

  if (s.response.containsKey('id')) {
    containerTags.addAll([
      div('.alert.alert-success', 'Successfully deleted $name', role: 'alert'),
      a('.btn.btn-primary', 'Return to $name overview',
          href: '/$name/list', role: 'button')
    ]);
  } else if (s.response.containsKey('error')) {
    containerTags.add(errorAlert(s));
  }
  /* else {
    containerTags.add(form(method: 'GET', c: [
      p('Please confirm that you want to delete this $name.'),
      button('.btn.btn-primary.btn-lg', 'Delete', type: 'submit')
    ]));
  } */

  return pageTemplate(s, 'Delete $name #${s.pathParameters['id']}',
      containerTags: containerTags);
}
