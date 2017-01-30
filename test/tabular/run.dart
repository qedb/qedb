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

const cliReset = '\x1B[0m';
const cliRed = '\x1B[38;5;9m';
const cliGreen = '\x1B[38;5;10m';
const cliYellow = '\x1B[38;5;11m';

abstract class Extension {
  void processTable(List<List> table, dynamic configuration) {}
  dynamic processParams(
      List<String> columns, List<dynamic> row, List<String> params);
}

// Register extensions (dirty, but easy).
Map<String, Extension> extensions = {
  'isEmpty': new IsEmptyExtension(),
  'column': new ColumnExtension(),
  'eqlib': new EqlibExtension(),
  'pkey': new PKeyExtension()
};

/// TODO: implement accept:any
Future<Null> main(List<String> files) async {
  // Load testing model.
  final model = loadYaml(await new File(files.first).readAsString());
  final baseUrl = model['baseUrl'];
  final List sheetTests = model['sheets'];

  // First read all CSV files because tests must be started synchronuously.
  final csvFiles = files.sublist(1);
  final csvTables = [];
  for (final file in csvFiles) {
    final table = const CsvToListConverter(eol: '\n')
        .convert(await new File(file).readAsString());
    // Convert boolean values.
    for (final row in table) {
      for (var i = 0; i < row.length; i++) {
        if (row[i] == 'TRUE') {
          row[i] = true;
        } else if (row[i] == 'FALSE') {
          row[i] = false;
        }
      }
    }
    csvTables.add(table);
  }

  // Loop through tables.
  for (var tablei = 0;
      tablei < csvFiles.length && tablei < sheetTests.length;
      tablei++) {
    final table = csvTables[tablei];

    // Process according to model.
    final sheetTest = sheetTests[tablei];
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

    const requiredKeys = const ['route', 'method', 'response'];
    final List<Map> tests = sheetTest['run'];

    // Send one API request for each row in the table.
    for (var rowi = 1; rowi < table.length; rowi++) {
      final row = table[rowi];

      for (var testi = 0; testi < tests.length; testi++) {
        final testData = tests[testi];

        // Check if all required keys are present in the model.
        if (requiredKeys.every((key) => testData.containsKey(key))) {
          // Skip if test is to be skipped.
          if (testData.containsKey('skip') && testData['skip'] == true) {
            print([
              '${cliYellow}skipped:  ${cliReset}table #${'${tablei + 1}'.padLeft(3, '0')}',
              'row #${'$rowi'.padLeft(3, '0')}',
              'test #${'${testi + 1}'.padLeft(3, '0')}',
            ].join(', '));
            continue;
          }
          // Skip test if condition is set.
          if (testData.containsKey('skipIf') &&
              processValue(columns, row, testData['skipIf']) == true) {
            continue;
          }

          // Tiny delay.
          // The database needs a bit of time sometimes to pick up new records.
          await new Future.delayed(new Duration(milliseconds: 50));

          // Process row.
          final requestBody = testData.containsKey('request')
              ? processValue(columns, row, testData['request'])
              : null;
          final expectedResponse =
              processValue(columns, row, testData['response']);

          // Process request route.
          String requestRoute = testData['route'];
          if (testData.containsKey('url')) {
            final Map<String, dynamic> urlParams = testData['url'];
            final regex = new RegExp(r'\{([a-z]+)\}');
            requestRoute = requestRoute.replaceAllMapped(regex, (match) {
              final key = match.group(1);
              if (urlParams.containsKey(key)) {
                return processValue(columns, row, urlParams[key]);
              } else {
                return key;
              }
            });
          }

          // Run test.
          // Note: it is not possible to use test() because the tests are not
          // isolated (state is stored in the database, misalignment between
          // tests in the async runner is dangerous).

          // Setup request object.
          final request = new http.Request(
              testData['method'], Uri.parse('$baseUrl$requestRoute'));

          // Add request body.
          if (requestBody != null) {
            request.headers['Content-Type'] = 'application/json';
            request.body = JSON.encode(requestBody);
          }

          // Execute request.
          final response = await request.send();
          final Map responseBody =
              JSON.decode(await response.stream.bytesToString());

          // Remove fields that are ignored.
          if (testData.containsKey('ignore')) {
            final ignored = new List<String>.from(testData['ignore']);
            for (final key in ignored) {
              responseBody.remove(key);
            }
          }

          // Compare.
          final matcher = equals(expectedResponse);
          final matchState = new Map();
          final matches = matcher.matches(responseBody, matchState);

          // Print test state.
          print([
            '${matches ? cliGreen : cliRed}${matches ? 'passed' : 'failed'}:   ${cliReset}table #${'${tablei + 1}'.padLeft(3, '0')}',
            'row #${'$rowi'.padLeft(3, '0')}',
            'test #${'${testi + 1}'.padLeft(3, '0')}',
          ].join(', '));

          if (!matches) {
            print('Request failed');
            print(request);
            print('Headers: ${request.headers}');
            print('Body: ${request.body}');

            // Describe mismatch.
            final mismatch = matcher.describeMismatch(
                responseBody, new StringDescription(), matchState, false);

            print('Expected: $expectedResponse');
            print('Actual: $responseBody');
            print('${cliYellow}Which: $mismatch$cliReset');

            // Terminate any further action.
            exit(1);
          }
        } else {
          final missingKeys = new Set<String>.from(requiredKeys)
              .difference(new Set<String>.from(testData.keys));
          throw new ArgumentError(
              'Sheet test misses required keys: $missingKeys');
        }
      }
    }
  }
}

/// Process value.
dynamic processValue(List<String> columns, List<dynamic> row, dynamic data) {
  if (data is Map) {
    final ret = new Map();
    final keys = data.keys.toList();

    // This enables sequential key processing.
    keys.sort();

    for (final key in keys) {
      final newKey = processKey(columns, row, key);
      if (newKey != null) {
        ret[newKey] = processValue(columns, row, data[key]);
      }
    }
    return ret;
  } else if (data is List) {
    return new List.generate(
        data.length, (i) => processValue(columns, row, data[i]));
  } else if (data is String) {
    return processStringValue(columns, row, data);
  } else {
    return data;
  }
}

/// Process string value (can contain an extension).
dynamic processStringValue(
    List<String> columns, List<dynamic> row, String str) {
  // Split value.
  final parts = str.split(':');

  if (parts.length > 1) {
    return processValueExtension(columns, row, parts);
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

/// Process a value field extension.
dynamic processValueExtension(
    List<String> columns, List<dynamic> row, List<String> params) {
  if (extensions.containsKey(params.first)) {
    return extensions[params.first]
        .processParams(columns, row, params.sublist(1));
  } else {
    return null;
  }
}

/// Process a key (can contain an extension).
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

    // Sequential key processing.
    if (parts.length == 2) {
      try {
        int.parse(parts.first);
        return parts.last;
      } on FormatException {
        return null;
      }
    }

    // Fallback
    return null;
  } else {
    return key; // default
  }
}
