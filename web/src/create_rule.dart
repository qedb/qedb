// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:editex/editex.dart';
import 'package:qedb_client/qedb_client.dart';
import 'package:qedb_client/browser_client.dart';
import 'package:htgen/dynamic.dart' as ht;

import 'editex_interface.dart';

Future main() async {
  // Check if this is the GET request by checking if there are any .editex
  // elements.
  if (document.querySelectorAll('.editex').isEmpty) {
    return;
  }

  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  // Initialize static editors.
  for (final element in document.querySelectorAll('.editex')) {
    initializeEditor(element, interface);
  }

  // Initialize conditions editing.
  var conditionCount = 0;
  final cWrapper = querySelector('#conditions-wrapper');
  final conditionCountInput = new InputElement(type: 'hidden');
  conditionCountInput.name = 'condition-count';
  cWrapper.append(conditionCountInput);

  void setConditionCount(count) {
    conditionCount = count;
    conditionCountInput.value = conditionCount.toString();
  }

  setConditionCount(0);

  querySelector('#add-condition').onClick.listen((_) {
    final l = ht.div('.editex.editex-align-left.form-control');
    final r = ht.div('.editex.editex-align-left.form-control');
    cWrapper.append(ht.p('.subs-input', c: [l, ht.span('.subs-arrow'), r]));

    initializeEditor(l, interface, 'condition$conditionCount-left');
    initializeEditor(r, interface, 'condition$conditionCount-right');
    setConditionCount(conditionCount + 1);
  });

  querySelector('#remove-condition').onClick.listen((_) {
    if (conditionCount > 0) {
      cWrapper.children.last.remove();
      setConditionCount(conditionCount - 1);
    }
  });
}

void initializeEditor(Element element, QEDbEdiTeXInterface interface,
    [String name]) {
  // Create editor with hidden form input which value is continuously updated.
  final editor = new EdiTeX(element, interface);
  final input = new InputElement(type: 'hidden');
  input.name = name ?? element.dataset['name'];
  input.value = '';
  element.parent.append(input);

  editor.onUpdate.listen((_) {
    try {
      input.value = interface.parse(editor.getParsable()).toBase64();
    } on Exception {
      input.value = '';
    }
  });
}
