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
          input('#data', type: 'hidden', name: 'data'),
          stylesheet(data.settings['katex.css.href']),
          stylesheet(data.settings['editex.css.href']),
          stylesheet(data.settings['pubserve.root'] + 'styles/main.css'),
          style(data.snippets['editex.css']),
          script(src: data.settings['katex.js.src']),
          script(src: data.settings['pubserve.root'] + 'src/main.dart.js')
        ];
      }, success: (data) {
        return [
          a('.btn.btn-primary', 'Back to lineage builder',
              href: '/lineage/create', role: 'button')
        ];
      });
    },
    onPost: (data) => JSON.decode(data['data']));
