// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

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

    for (final Map testData in sheetTest['run']) {
      // Check if all required keys are present in the model.
      if (['apiMethod', 'httpMethod', 'request', 'response']
          .every((key) => testData.containsKey(key))) {
        // Send one API request for each row in the table.
        for (var idx = 1; idx < table.length; idx++) {
          final row = table[idx];

          // Process row.
          final requestData = process(columns, row, testData['request']);
          final expectedResponse = process(columns, row, testData['response']);

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

dynamic process(List<String> columns, List<dynamic> row, dynamic data) {
  if (data is Map) {
    final ret = new Map();
    for (final key in data.keys) {
      // Conditional key.
      if (key is String && key.startsWith('if:')) {
        var _key = key.substring('if:'.length);
        final nextColon = _key.indexOf(':');
        final condition = _key.substring(0, nextColon);
        final fieldName = _key.substring(nextColon + 1);

        // Check if condition is true.
        final conditionIndex = columns.indexOf(condition);
        if (conditionIndex != -1 && conditionIndex < row.length) {
          if (row[conditionIndex] == true) {
            ret[fieldName] = process(columns, row, data[key]);
          }
        } else {
          throw new Exception('conditional column "$condition" not found');
        }
      } else {
        ret[key] = process(columns, row, data[key]);
      }
    }
    return ret;
  } else if (data is List) {
    return new List.generate(
        data.length, (i) => process(columns, row, data[i]));
  } else if (data is String) {
    if (data.startsWith('column:')) {
      var columnName = data.substring('column:'.length);
      if (columnName.startsWith('[]')) {
        columnName = columnName.substring('[]'.length);
        final index = columns.indexOf(columnName);
        if (index < row.length) {
          final String value = row[index];
          return value.isEmpty ? [] : process(columns, row, value.split(','));
        } else {
          throw new Exception('column "$columnName" not found');
        }
      } else {
        final index = columns.indexOf(columnName);
        if (index != -1 && index < row.length) {
          return process(columns, row, row[index]);
        } else {
          throw new Exception('column "$columnName" not found');
        }
      }
    } else {
      if (data == 'FALSE') {
        return false;
      } else if (data == 'TRUE') {
        return true;
      } else {
        return data;
      }
    }
  } else {
    return data;
  }
}
