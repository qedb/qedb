// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

Future main(List<String> args) async {
  final doc = loadYaml(await new File(args.first).readAsString());
  final baseUrl = doc['baseUrl'];

  for (var i = 0; i < doc['methods'].length; i++) {
    var method = doc['methods'][i];
    var httpMethod = method['method'];
    var path = '$baseUrl${method['name']}';

    // Run all tests for this method.
    test(method['name'], () async {
      for (var j = 0; j < method['tests'].length; j++) {
        Map<String, dynamic> testData = method['tests'][j];

        // Execute request.
        if (httpMethod == 'POST') {
          if (testData.containsKey('data')) {
            // data/response testing
            final response = await http.post(path,
                headers: {'Content-Type': 'application/json'},
                body: JSON.encode(testData['data']));

            // Compare expected and actual value.
            final expectedResponse = new Map<String, dynamic>.from(
                testData.containsKey('response')
                    ? testData['response']
                    : testData['data']);

            if (testData.containsKey('responseAdd')) {
              expectedResponse.addAll(
                  new Map<String, dynamic>.from(testData['responseAdd']));
            }
            if (testData.containsKey('responseRemove')) {
              final toRemove =
                  new List<String>.from(testData['responseRemove']);
              toRemove.forEach((key) => expectedResponse.remove(key));
            }

            // Compare.
            expect(JSON.decode(response.body), equals(expectedResponse));
          }
        }
      }
    });
  }
}
