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
          div('#proof-editor.proof-editor'),
          input('#data', type: 'hidden', name: 'data')
        ];
      }, bodyTags: [
        katexSource(s),
        editexStyles(s),
        stylesheet(s.settings['editorsrc'] + 'styles/main.css'),
        script(src: s.settings['editorsrc'] + 'src/main.dart.js')
      ]);
    },
    onPost: (data) => JSON.decode(data['data']));

final listProofsPage = new Page(template: (s) {
  return listResourceTemplate(s, 'proof', 'proofs', tableHead: [
    th('ID'),
    th('First expression'),
    th('Last expression'),
    th('Actions', style: 'width: 1px;')
  ], row: (proof) {
    return [
      td(a(proof.id.toString(), href: '/proof/${proof.id}/steps/list')),
      td(span('.latex', proof.firstStep.expression.latex)),
      td(span('.latex', proof.lastStep.expression.latex)),
      td(div('.btn-group.btn-group-sm', role: 'group', c: [
        form('.btn-group.btn-group-sm',
            role: 'group',
            method: 'POST',
            action: '/rule/create',
            style: 'display: inline-block;',
            c: [
              button('.btn.btn-outline-secondary', 'To rule', type: 'submit'),
              input(type: 'hidden', name: 'proof', value: '${proof.id}')
            ]),
        a('.btn.btn-outline-secondary', 'Extend',
            href: '/proof/create?initialstep=${proof.lastStep.id}')
      ]))
    ];
  }, bodyTags: [
    style(s.snippets['latex-table.css']),
    katexSource(s),
    script(s.snippets['render-latex.js'])
  ]);
});

final listProofStepsPage = new Page(template: (s) {
  return pageTemplate(s, 'Proof #${s.pathParameters['id']} steps',
      containerTags: ol(
          '.proof',
          s.response
              .map((step) => li([
                    span('.latex', step.expression.latex),
                    ' ',
                    span([code(step.id.toRadixString(36).padLeft(6, '0'))]),
                  ]))
              .toList()),
      bodyTags: [
        style(s.snippets['proof.css']),
        katexSource(s),
        script(s.snippets['render-latex.js'])
      ]);
});
