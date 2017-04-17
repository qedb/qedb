// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import '../page.dart';
import 'templates.dart';

final createLocalePage = new Page(
    template: (data) {
      return createResourceTemplate(data, 'locale', inputs: (data) {
        return [formInput('Locale ISO code', name: 'code')];
      });
    },
    onPost: (data) => {'code': data['code']});
