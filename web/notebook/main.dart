// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'package:editex/editex.dart';

void main() {
  // Retrieve operators and functions.

  // Construct editors.
  EdiTeX prev;
  for (final div in querySelectorAll('.editex')) {
    final editor = new EdiTeX(div);

    if (prev != null) {
      prev.onRightLeave.listen((_) {
        editor.cursorIdx = 0;
        editor.doUpdate = true;
        editor.container.focus();
      });

      final prevWrapper = prev;
      editor.onLeftLeave.listen((_) {
        prevWrapper.cursorIdx = prevWrapper.content.length - 1;
        prevWrapper.doUpdate = true;
        prevWrapper.container.focus();
      });
    }

    prev = editor;
  }
}
