// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:eqlib/eqlib.dart';

/// A small program to print some information about a Base64 EqLib code.
void main(List<String> args) {
  for (final code in args) {
    final header = new ExprCodecData.decodeHeader(
        new Uint8List.fromList(BASE64.decode(code)).buffer);
    print('Info for: $code');
    print('floating points: ${header.floatingPoints}');
    print('integers:        ${header.integers}');
    print('functions:       ${header.functionIds}');
    print('argument count:  ${header.functionArgcs}');
    print('generic count:   ${header.genericCount}');
  }
}
