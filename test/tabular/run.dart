// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.test.tabular;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:eqlib/eqlib.dart';
import 'package:http/http.dart' as http;

part 'extensions.dart';

abstract class Extension {
  void processTable(List<List> table, dynamic configuration) {}
  dynamic processValue(
      List<String> columns, List<dynamic> row, List<String> params);
}

// Register extensions (dirty, but easy).
Map<String, Extension> extensions = {
  'column': new ColumnExtension(),
  'eqlibCodec': new EqlibCodecExtension()
};

Future main(List<String> files) async {
  // Load testing model.
  final model = loadYaml(await new File(files.first).readAsString());
  final baseUrl = model['baseUrl'];
  final List sheetTests = model['sheets'];

  // First read all CSV files because tests must be started synchronuously.
  final csvFiles = files.sublist(1);
  final csvTables = [];
  for (final file in csvFiles) {
    csvTables.add(const CsvToListConverter(eol: '\n')
        .convert(await new File(file).readAsString()));
  }

  // Loop through tables.
  for (var i = 0; i < csvFiles.length && i < sheetTests.length; i++) {
    final table = csvTables[i];

    // Process according to model.
    final sheetTest = sheetTests[i];
    if (!sheetTest.containsKey('run')) {
      continue;
    }

    // Column headers.
    final List<String> columns = new List<String>.from(table.first);

    // If table extensions are specified, run them.
    if (sheetTest.containsKey('extensions')) {
      for (final Map extension in sheetTest['extensions']) {
        // Should have a single key, else skip.
        if (extension.keys.length == 1) {
          final extensionName = extension.keys.first;
          if (extensions.containsKey(extensionName)) {
            extensions[extensionName]
                .processTable(table, extension[extensionName]);
          }
        }
      }
    }

    for (final Map testData in sheetTest['run']) {
      // Check if all required keys are present in the model.
      if (['apiMethod', 'httpMethod', 'request', 'response']
          .every((key) => testData.containsKey(key))) {
        // Send one API request for each row in the table.
        for (var idx = 1; idx < table.length; idx++) {
          final row = table[idx];

          // Process row.
          final requestData =
              globalProcessValue(columns, row, testData['request']);
          final expectedResponse =
              globalProcessValue(columns, row, testData['response']);

          // Run test.
          test('table #$i, row #$idx', () async {
            if (testData['httpMethod'] == 'POST') {
              // Execute POST request.
              final response = await http.post(
                  '$baseUrl${testData['apiMethod']}',
                  headers: {'Content-Type': 'application/json'},
                  body: JSON.encode(requestData));

              // Compare.
              expect(JSON.decode(response.body), equals(expectedResponse));
            }
          });
        }
      }
    }
  }
}

dynamic globalProcessValue(
    List<String> columns, List<dynamic> row, dynamic data) {
  if (data is Map) {
    final ret = new Map();
    for (final key in data.keys) {
      final result = processKey(columns, row, key);
      if (result != null) {
        ret[result] = globalProcessValue(columns, row, data[key]);
      }
    }
    return ret;
  } else if (data is List) {
    return new List.generate(
        data.length, (i) => globalProcessValue(columns, row, data[i]));
  } else if (data is String) {
    return processStringValue(columns, row, data);
  } else {
    return data;
  }
}

dynamic processStringValue(
    List<String> columns, List<dynamic> row, String str) {
  // Split value.
  final parts = str.split(':');

  if (parts.length > 1) {
    return processValueExtension(columns, row, parts);
  } else {
    // Match with Gnumeric's strings for boolean values.
    if (str == 'TRUE') {
      return true;
    } else if (str == 'FALSE') {
      return false;
    } else {
      // Try to parse as number (when a comma separated list is splitted it is
      // possible for stringified numbers to exist)
      try {
        return num.parse(str);
      } on FormatException {
        return str;
      }
    }
  }
}

dynamic processValueExtension(
    List<String> columns, List<dynamic> row, List<String> params) {
  if (extensions.containsKey(params.first)) {
    return extensions[params.first]
        .processValue(columns, row, params.sublist(1));
  } else {
    return null;
  }
}

String processKey(List<String> columns, List<dynamic> row, String key) {
  // Split key.
  final parts = key.split(':');
  if (parts.length > 1) {
    // Conditional key.
    if (parts[0] == 'if') {
      final conditionalColumn = parts[1];
      final fieldName = parts[2];

      // Check if condition is true.
      final conditionIndex = columns.indexOf(conditionalColumn);
      if (conditionIndex != -1 && conditionIndex < row.length) {
        if (row[conditionIndex] == true) {
          return fieldName;
        }
      } else {
        throw new Exception(
            'conditional column "$conditionalColumn" not found');
      }
    }

    // Not yet returned: return null.
    return null;
  } else {
    return key; // default
  }
}
