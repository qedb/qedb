// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.utils;

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Check the given String is not null and not empty.
bool notEmpty(String str) => str != null && str.isNotEmpty;

/// Convert PostgreSQL integer array to List<int>.
List<int> pgIntArray(String str) {
  // Remove '{}'.
  final values = str.substring(1, str.length - 1);

  if (values.isEmpty) {
    return [];
  }

  final parts = values.split(',');
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

/// Evironment variables / YAML file configuration helper.
class EnvConfig {
  final String envPrefix;
  Map<String, dynamic> _yamlData;

  EnvConfig(this.envPrefix, String defaultConfigPath) {
    // Resolve YAML config path.
    final yamlPath = env('CONFIG_PATH', defaultConfigPath);
    final yamlFile = new File(yamlPath);
    if (yamlFile.existsSync()) {
      _yamlData = loadYaml(yamlFile.readAsStringSync());
    }
  }

  /// Read environment variable.
  String env(String label, [String dflt = '']) =>
      Platform.environment.containsKey('$envPrefix$label')
          ? Platform.environment['$envPrefix$label']
          : dflt;

  /// Read string parameter from yaml data > environment variable > default
  String string(String label, [String dflt = '']) =>
      _yamlData.containsKey(label) ? _yamlData[label] : env(label, dflt);

  /// Same as [string] but for integers.
  int integer(String label, [int dflt = 0]) => _yamlData.containsKey(label)
      ? _yamlData[label]
      : Platform.environment.containsKey('$envPrefix$label')
          ? int.parse(Platform.environment['$envPrefix$label'])
          : dflt;
}
