// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.utils;

/// Convert string with comma separated integers to List<int>.
List<int> intsFromString(String str) {
  if (str.trim().isEmpty) {
    return [];
  }

  final parts = str.split(',');
  return new List<int>.generate(
      parts.length, (i) => int.parse(parts[i].trim()));
}

/// Utility for parsing arrays of custom PostgreSQL types while using
/// `array_to_string(array, '')`.
List<List<String>> splitPgRowList(String str) {
  final parts = str.substring(1, str.length - 1).split(')(');
  return new List<List<String>>.generate(
      parts.length, (i) => parts[i].split(','));
}
