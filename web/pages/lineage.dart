// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:convert';

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createLineagePage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'lineage', inputs: (data) {
        return [
          div('#lineage-editor'),
          input('#data', type: 'hidden', name: 'data')
        ];
      }, bodyTags: [
        katexSource(s),
        editexStyles(s),
        stylesheet(s.settings['lineagesrc'] + 'styles/main.css'),
        script(src: s.settings['lineagesrc'] + 'src/main.dart.js')
      ]);
    },
    onPost: (data) => JSON.decode(data['data']));

final readLineagePage = new Page(template: (s) {
  return pageTemplate(s, 'Lineage ${s.response.id}',
      containerTags: ol(
          '.lineage',
          s.response.steps
              .map((step) => li([
                    span('.latex', step.expression.latex),
                    ' ',
                    span('.stepid', step.id.toRadixString(36).padLeft(6, '0'))
                  ]))
              .toList()),
      bodyTags: [
        style(s.snippets['lineage.css']),
        katexSource(s),
        script(s.snippets['render-latex.js'])
      ]);
});

final listLineagesPage = new Page(template: (s) {
  return listResourceTemplate(s, 'lineage', 'lineages',
      tableHead: [th('ID'), th('First'), th('Last')], row: (lineage) {
    return [
      td(a(lineage.id.toString(), href: '/lineage/${lineage.id}/read')),
      td(span('.latex', lineage.steps.first.expression.latex)),
      td(span('.latex', lineage.steps.last.expression.latex))
    ];
  }, bodyTags: [
    style(s.snippets['latex-table.css']),
    katexSource(s),
    script(s.snippets['render-latex.js'])
  ]);
});
