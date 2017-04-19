// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:eqlib/latex.dart';
import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqdb/utils.dart';
import 'package:eqdb/sqlbuilder.dart';
import 'package:eqdb/resources.dart';
import 'package:eqdb/schema.dart' as db;

part 'src/locale.dart';
part 'src/descriptor.dart';
part 'src/translation.dart';
part 'src/subject.dart';
part 'src/function.dart';
part 'src/operator.dart';
part 'src/expression.dart';
part 'src/rule.dart';
part 'src/definition.dart';
part 'src/expression_difference.dart';
part 'src/lineage_create.dart';
part 'src/lineage_read.dart';

final log = new Logger('eqdb');

class Session extends SessionState<db.SessionData> {
  Session(Connection conn, db.SessionData data) : super(conn, data);
}

class UnprocessableEntityError extends RpcError {
  UnprocessableEntityError(String message)
      : super(422, 'Unprocessable Entity', message);
}
