// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:convert';

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createProofPage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'proof', inputs: (data) {
        return [
          div('#proof-editor'),
          input('#data', type: 'hidden', name: 'data')
        ];
      }, bodyTags: [
        katexSource(s),
        editexStyles(s),
        stylesheet(s.settings['proofsrc'] + 'styles/main.css'),
        script(src: s.settings['proofsrc'] + 'src/main.dart.js')
      ]);
    },
    onPost: (data) => JSON.decode(data['data']));

final readProofPage = new Page(template: (s) {
  return pageTemplate(s, 'Proof ${s.response.id}',
      containerTags: ol(
          '.proof',
          s.response.steps
              .map((step) => li([
                    span('.latex', step.expression.latex),
                    ' ',
                    span('.stepid', step.id.toRadixString(36).padLeft(6, '0'))
                  ]))
              .toList()),
      bodyTags: [
        style(s.snippets['proof.css']),
        katexSource(s),
        script(s.snippets['render-latex.js'])
      ]);
});

final listProofsPage = new Page(template: (s) {
  return listResourceTemplate(s, 'proof', 'proofs',
      tableHead: [th('ID'), th('First'), th('Last')], row: (proof) {
    return [
      td(a(proof.id.toString(), href: '/proof/${proof.id}/read')),
      td(span('.latex', proof.steps.first.expression.latex)),
      td(span('.latex', proof.steps.last.expression.latex))
    ];
  }, bodyTags: [
    style(s.snippets['latex-table.css']),
    katexSource(s),
    script(s.snippets['render-latex.js'])
  ]);
});
