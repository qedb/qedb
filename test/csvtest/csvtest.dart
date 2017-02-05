// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.test.csvtest;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

part 'resolvers.dart';

const cliReset = '\x1B[0m';
const cliRed = '\x1B[38;5;9m';
const cliGreen = '\x1B[38;5;10m';
const cliYellow = '\x1B[38;5;11m';

enum TestState { passed, failed, skipped, silentSkip }
final testStateText = {
  TestState.passed: 'passed',
  TestState.failed: 'failed',
  TestState.skipped: 'skipped'
};
final testStateColor = {
  TestState.passed: cliGreen,
  TestState.failed: cliRed,
  TestState.skipped: cliYellow
};

typedef Future<TestState> CsvTest(Row row, String baseUrl);
typedef T ValueResolver<T>(Row row);

/// Process a CSV file using csvtest.
Future csvtest(String baseUrl, String csvPath, List<CsvTest> tests) async {
  // Load CSV file.
  final table = const CsvToListConverter(eol: '\n')
      .convert(await new File(csvPath).readAsString());

  // Convert boolean values to actual booleans (this is Gnumeric specific).
  for (final row in table) {
    for (var i = 0; i < row.length; i++) {
      if (row[i] == 'TRUE') {
        row[i] = true;
      } else if (row[i] == 'FALSE') {
        row[i] = false;
      }
    }
  }

  // Iterate through table rows.
  final columns = new List<String>.from(table.first);
  for (var i = 1; i < table.length; i++) {
    final row = new Row(columns, table[i]);

    // Iterate through tests.
    for (var j = 0; j < tests.length; j++) {
      // Run test.
      final state = await tests[j](row, baseUrl);

      // Print test state.
      if (state != TestState.silentSkip) {
        print([
          csvPath,
          'row #${'$i'.padLeft(3, '0')}',
          'test #${'${j + 1}'.padLeft(3, '0')}',
          [testStateColor[state], testStateText[state], cliReset].join()
        ].join(', '));
      }

      // If the state is failed, exit the program immedeatly.
      if (state == TestState.failed) {
        exit(1);
      }

      // Tiny delay.
      // It turns out the database needs a bit of time to pick up new records.
      await new Future.delayed(new Duration(milliseconds: 50));
    }
  }
}

/// Utility class for representing a row.
class Row {
  final List<String> columns;
  final List<dynamic> data;

  Row(this.columns, this.data);

  dynamic getColumn(String column) {
    final idx = columns.indexOf(column);
    if (idx != -1) {
      return data[idx];
    } else {
      throw new Exception("column '$column' does not exist");
    }
  }
}

/// API route test.
CsvTest route(String method, String path,
        {Map<String, ValueResolver> url: const {},
        Map<String, dynamic> request: const {},
        Map<String, dynamic> response: const {},
        bool skip: false,
        ValueResolver runIf: resolveTrue}) =>
    (row, baseUrl) async {
      // Skip if this test is to be skipped.
      if (skip) {
        return TestState.skipped;
      }

      // Silent skip.
      if (runIf(row) == false) {
        return TestState.silentSkip;
      }

      // Process request route.
      final regex = new RegExp(r'\{([a-z]+)\}');
      final requestPath = path.replaceAllMapped(regex, (match) {
        final key = match.group(1);
        if (url.containsKey(key)) {
          return url[key](row);
        } else {
          return key;
        }
      });

      // Setup request object.
      final httpRequest =
          new http.Request(method, Uri.parse('$baseUrl$requestPath'));

      // Add request body.
      final requestBody = evaluate(request, row);
      if (request.isNotEmpty) {
        httpRequest.headers['Content-Type'] = 'application/json';
        httpRequest.body = JSON.encode(requestBody);
      }

      // Retrieve response.
      final httpResponse = await httpRequest.send();
      final responseBody =
          JSON.decode(await httpResponse.stream.bytesToString());

      // Compare response body with expected response.
      final expectedResponseBody = evaluate(response, row);
      try {
        compare(expectedResponseBody, responseBody);
        return TestState.passed;
      } catch (e) {
        // Print error details.
        print('Request failed');
        print(httpRequest);
        print('Headers: ${httpRequest.headers}');
        print('Body: $requestBody');
        print('Expected: $expectedResponseBody');
        print('Actual: $responseBody');
        print('Where: ${e.message.trim()}');

        return TestState.failed;
      }
    };

/// Evaluate into a new object.
dynamic evaluate(dynamic obj, Row row) {
  if (obj is Map) {
    final map = new Map();
    for (final key in obj.keys) {
      final value = evaluate(obj[key], row);
      if (!(value is _RemoveMe)) {
        map[key] = value;
      }
    }
    return map;
  } else if (obj is List) {
    final list = new List();
    for (final value in obj) {
      final v = evaluate(value, row);
      if (!(v is _RemoveMe)) {
        list.add(v);
      }
    }
    return list;
  } else if (obj is ValueResolver) {
    return obj(row);
  } else {
    return obj;
  }
}

void compare(dynamic src, dynamic dst, [String path = '']) {
  if (src is Map) {
    if (dst is Map) {
      // Compare all elements.
      for (final key in src.keys) {
        if (!dst.containsKey(key)) {
          throw new Exception("$path does not contain key '$key'");
        }

        compare(src[key], dst[key], path.isEmpty ? key : '$path.$key');
      }
    } else {
      throw new Exception('$path is not a map');
    }
  } else if (src is List) {
    if (dst is List) {
      if (dst.length != src.length) {
        throw new Exception('$path has a different length');
      }

      // Compare all elements.
      for (var i = 0; i < src.length; i++) {
        compare(src[i], dst[i], '$path[$i]');
      }
    } else {
      throw new Exception('$path is not a list');
    }
  } else if (src is String) {
    if (src.startsWith(_acceptPrefix)) {
      final type = src.split(':').last;
      if (type == 'map') {
        if (!(dst is Map)) {
          throw new Exception('$path is not a map');
        }
      } else if (type == 'list') {
        if (!(dst is List)) {
          throw new Exception('$path is not a list');
        }
      } else if (type == 'string') {
        if (!(dst is String)) {
          throw new Exception('$path is not a string');
        }
      } else if (type == 'number') {
        if (!(dst is num)) {
          throw new Exception('$path is not a number');
        }
      } else if (type == 'boolean') {
        if (!(dst is bool)) {
          throw new Exception('$path is not a boolean');
        }
      } else {
        throw new Exception('$path has unknown accept type');
      }
    }
  }
}

const _acceptPrefix = r'$any';

enum AcceptType { map, list, string, number, boolean }
final _acceptTypeText = {
  AcceptType.map: 'map',
  AcceptType.list: 'list',
  AcceptType.string: 'string',
  AcceptType.number: 'number',
  AcceptType.boolean: 'boolean'
};

ValueResolver accept(AcceptType type) =>
    (_) => '$_acceptPrefix:${_acceptTypeText[type]}';

/// Dummy class for item removal.
class _RemoveMe {}

/// Only include this item if the given value is not empty.
ValueResolver includeIfNotEmpty(ValueResolver value) => (row) {
      final v = value(row);
      if (v == null || (v is String && v.isEmpty)) {
        return new _RemoveMe();
      } else {
        return v;
      }
    };
