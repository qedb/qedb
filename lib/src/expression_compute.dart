// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

/// Compute special functions.
num _exprCompute(Session s, int id, List<num> args) {
  // Only do operations that given two integers will always return an integer.
  if (id == s.specialFunctions[SpecialFunction.add]) {
    return args[0] + args[1];
  } else if (id == s.specialFunctions[SpecialFunction.subtract]) {
    return args[0] - args[1];
  } else if (id == s.specialFunctions[SpecialFunction.multiply]) {
    return args[0] * args[1];
  } else if (id == s.specialFunctions[SpecialFunction.negate]) {
    return -args[0];
  } else {
    return double.NAN;
  }
}
