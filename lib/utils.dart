// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.utils;

import 'dart:io';

import 'package:yaml/yaml.dart';

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
