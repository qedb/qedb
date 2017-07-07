// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.utils;

import 'dart:io';

import 'package:rpc/rpc.dart';
import 'package:yaml/yaml.dart';

/// RPC exception for 422 status.
class UnprocessableEntityError extends RpcError {
  UnprocessableEntityError(String message)
      : super(422, 'Unprocessable Entity', message);
}

/// Check the given String is not null and not empty.
bool notEmpty(String str) => str != null && str.isNotEmpty;

/// Convert PostgreSQL integer array in [str] to List<int>.
/// If [str] is null this function will also return null.
List<int> pgIntArray(String str) {
  if (str == null) {
    return null;
  }

  // Remove '{}'.
  final values = str.substring(1, str.length - 1);

  if (values.isEmpty) {
    return [];
  }

  final parts = values.split(',');
  return new List<int>.generate(
      parts.length, (i) => int.parse(parts[i].trim()));
}

/// Remove newlines from base64 string to make it compatible with dart:convert.
String fixBase64(String data) {
  return data.replaceAll(new RegExp(r'\s'), '');
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

  /// Same as [string] but for booleans.
  bool boolean(String label, [bool dflt = false]) =>
      _yamlData.containsKey(label)
          ? _yamlData[label]
          : Platform.environment.containsKey('$envPrefix$label')
              ? Platform.environment['$envPrefix$label'] == 'true'
              : dflt;
}
