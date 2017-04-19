// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:convert';

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createLineagePage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'lineage', inputs: (data) {
        return [
          div('#lineage-editor'),
          input('#data', type: 'hidden', name: 'data')
        ];
      }, bodyTags: [
        katexSource(data),
        editexStyles(data),
        stylesheet(data.settings['lineagesrc'] + 'styles/main.css'),
        script(src: data.settings['lineagesrc'] + 'src/main.dart.js')
      ]);
    },
    onPost: (data) => JSON.decode(data['data']));

final readLineagePage = new Page(template: (data) {
  return pageTemplate(data, 'Lineage ${data.data.id}',
      containerTags: ol(
          '.lineage',
          data.data.steps
              .map((step) => li([
                    span('.latex', step.expression.latex),
                    ' ',
                    span('.stepid', step.id.toRadixString(36).padLeft(6, '0'))
                  ]))
              .toList()),
      bodyTags: [
        style(data.snippets['lineage.css']),
        katexSource(data),
        script(data.snippets['render-latex.js'])
      ]);
});

final listLineagesPage = new Page(template: (data) {
  return listResourceTemplate(data, 'lineage', 'linaeges',
      tableHead: [th('ID'), th('First'), th('Last')], row: (lineage) {
    return [
      td(a(lineage.id.toString(), href: '/lineage/${lineage.id}/read')),
      td(span('.latex', lineage.steps.first.expression.latex)),
      td(span('.latex', lineage.steps.last.expression.latex))
    ];
  }, bodyTags: [
    style(data.snippets['latex-table.css']),
    katexSource(data),
    script(data.snippets['render-latex.js'])
  ]);
});
