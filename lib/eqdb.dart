// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb;

import 'dart:async';
import 'dart:convert';

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:eqlib/latex.dart';
import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqdb/utils.dart';
import 'package:eqdb/sqlbuilder.dart';
import 'package:eqdb/resources.dart';
import 'package:eqdb/schema.dart' as db;

part 'src/language.dart';
part 'src/descriptor.dart';
part 'src/translation.dart';
part 'src/subject.dart';
part 'src/function.dart';
part 'src/operator.dart';
part 'src/expression.dart';
part 'src/rule.dart';
part 'src/expression_difference.dart';
part 'src/proof_create.dart';
part 'src/proof_read.dart';

final log = new Logger('eqdb');

class Session extends SessionState<db.SessionData> {
  // Targeted languages.
  final List<int> languages;

  Session(Connection conn, db.SessionData data, this.languages)
      : super(conn, data);
}
