// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../common.dart';
import 'components.dart';

typedef dynamic InlineHtmlBuilder(PageData data);

String createResourceTemplate(PageData data, String name,
        {InlineHtmlBuilder inputs,
        InlineHtmlBuilder success,
        List headAppend: const []}) =>
    html([
      head([title('Create $name'), defaultHead(data), headAppend]),
      body([
        breadcrumb(data),
        div('.container', [
          h3('Create $name'),
          br(),
          safeIf(() => data.data.id != null)
              ? success(data)
              : [
                  safeIf(() => data.data.error != null)
                      ? [
                          div('.alert.alert-warning',
                              '${prettyPrintErrorMessage(data.data.error.message)} <strong>(${data.data.error.code})</strong>',
                              role: 'alert')
                        ]
                      : [],
                  form(method: 'POST', c: [
                    inputs(data),
                    button('.btn.btn-primary', 'Submit', type: 'submit')
                  ])
                ]
        ])
      ])
    ]);
