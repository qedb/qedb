// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb;

class LineageCreateData {
  List<ExpressionDifferenceResource> steps;
}

Future<LineageResource> createLineage(Session s, LineageCreateData body) async {
  /// TODO: Implement: validate, insert, return resource.
  return new LineageResource();
}
