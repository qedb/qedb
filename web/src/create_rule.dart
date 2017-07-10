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
  // Retrieve operators and functions.
  final db = new QedbApi(new BrowserClient());
  final interface = await createQEDbEdiTeXInterface(db);

  // Initialize static editors.
  for (final element in document.querySelectorAll('.editex')) {
    initializeEditor(element, interface);
  }

  // Initialize conditions editing.
  var conditionCount = 0;
  final conditionsWrapper = querySelector('#conditions-wrapper');
  final conditionCountInput = new InputElement(type: 'hidden');
  conditionCountInput.name = 'condition-count';
  conditionsWrapper.append(conditionCountInput);

  void setConditionCount(count) {
    conditionCount = count;
    conditionCountInput.value = conditionCount.toString();
  }

  setConditionCount(0);

  querySelector('#add-condition').onClick.listen((_) {
    final left = ht.div('.editex.editex-align-left.form-control');
    final right = ht.div('.editex.editex-align-left.form-control');
    conditionsWrapper
        .append(ht.p('.rule-input', c: [left, ht.span('.rule-arrow'), right]));

    initializeEditor(left, interface, 'condition$conditionCount-left');
    initializeEditor(right, interface, 'condition$conditionCount-right');
    setConditionCount(conditionCount + 1);
  });

  querySelector('#remove-condition').onClick.listen((_) {
    if (conditionCount > 0) {
      conditionsWrapper.children.last.remove();
      setConditionCount(conditionCount - 1);
    }
  });
}

void initializeEditor(Element element, QEDbEdiTeXInterface interface,
    [String name]) {
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
