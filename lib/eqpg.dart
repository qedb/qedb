// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqpg/dbutils.dart';
import 'package:eqpg/resources.dart';
import 'package:eqpg/schema.dart' as db;

part 'src/locale.dart';
part 'src/descriptor.dart';
part 'src/subject.dart';
part 'src/translation.dart';
part 'src/category.dart';
part 'src/function.dart';
part 'src/expression.dart';
part 'src/rule.dart';
part 'src/definition.dart';
part 'src/expression_lineage.dart';

class UnprocessableEntityError extends RpcError {
  UnprocessableEntityError(String message)
      : super(422, 'Unprocessable Entity', message);
}
