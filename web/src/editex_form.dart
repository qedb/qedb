// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';
import 'package:eqdb_client/browser_client.dart';

import 'editex_interface.dart';

Future main() async {
  CursorList.selectionColor = '#2aa198';

  // Retrieve operators and functions.
  final db = new EqdbApi(new BrowserClient());
  final interface = new EqDBEdiTeXInterface();
  await interface.loadData(db);

  document.querySelectorAll('div.editex').forEach((Element element) {
    final editor = new EdiTeX(element, interface);
    final input = new InputElement(type: 'hidden');
    input.name = element.dataset['name'];
    input.value = '';
    element.parent.append(input);

    editor.onUpdate.listen((_) {
      try {
        input.value = interface.parse(editor.getParsableContent()).toBase64();
      } catch (e) {
        input.value = '';
      }
    });
  });
}
