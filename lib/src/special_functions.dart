// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

/// This enum is the same as the `special_function_type` enum in the database.
enum SpecialFunction { equals, add, subtract, multiply, negate, derrivative }

/// Map special function type string to enum value.
const _specialTypeStr2Enum = const {
  'equals': SpecialFunction.equals,
  'add': SpecialFunction.add,
  'subtract': SpecialFunction.subtract,
  'multiply': SpecialFunction.multiply,
  'negate': SpecialFunction.negate,
  'derrivative': SpecialFunction.derrivative
};

/// Retrieve all special function IDs (executed each session).
Future<Map<SpecialFunction, int>> getSpecialFunctions(Session s) async {
  final map = new Map<SpecialFunction, int>();
  final functions =
      await s.selectAndForget(db.function, SQL('WHERE special_type NOTNULL'));
  for (final fn in functions) {
    map[_specialTypeStr2Enum[fn.specialType]] = fn.id;
  }
  return map;
}
