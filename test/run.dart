// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

Future main() async {
  var doc = loadYaml(await new File('./test/tests.yaml').readAsString());
  var baseUrl = doc['baseUrl'];

  for (var i = 0; i < doc['methods'].length; i++) {
    var method = doc['methods'][i];
    var httpMethod = method['method'];
    var path = '$baseUrl${method['name']}';

    // Run all tests for this method.
    test(method['name'], () async {
      for (var j = 0; j < method['tests'].length; j++) {
        var test = method['tests'][j];

        // Execute request.
        if (httpMethod == 'POST') {
          final response = await http.post(path,
              headers: {'Content-Type': 'application/json'},
              body: JSON.encode(test['data']));

          // Compare expected and actual value.
          expect(JSON.decode(response.body), equals(test['response']));
        }
      }
    });
  }
}
