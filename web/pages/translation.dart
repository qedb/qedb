// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../htgen/htgen.dart';
import '../page.dart';
import 'templates.dart';

final createTranslationPage = new Page(
    template: (s) {
      return createResourceTemplate(s, 'translation',
          overviewRoute: s.relativeUrl('../read'), inputs: (data) {
        return [
          input(
              type: 'hidden',
              name: 'descriptor-id',
              value: data.pathParameters['id']),
          languageSelect(data),
          formInput('Translation', name: 'content')
        ];
      });
    },
    onPost: (data) => {
          'descriptor': {'id': data['descriptor-id']},
          'language': {'code': data['language']},
          'content': data['content']
        },
    additional: {'languages': 'language/list'});
