// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:editex/editex.dart';
import 'package:qedb_client/qedb_client.dart';
import 'package:qedb_client/browser_client.dart';

import 'editex_interface.dart';

Future main() async {
  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  document.querySelectorAll('div.editex').forEach((Element element) {
    final editor = new EdiTeX(element, interface);
    final input = new InputElement(type: 'hidden');
    input.name = element.dataset['name'];
    input.value = '';
    element.parent.append(input);

    editor.onUpdate.listen((_) {
      try {
        input.value = interface.parse(editor.getParsable()).toBase64();
      } catch (e) {
        input.value = '';
      }
    });
  });
}
