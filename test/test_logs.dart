// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;

/// Open logs/main.txt and run all described requests.
Future main() async {
  final baseUrl = 'http://localhost:8080/';
  final lines = await new File('logs/main.txt').readAsLines();

  for (var i = 0; i < lines.length;) {
    // Read data.
    final method = lines[i++];
    final path = lines[i++];
    final requestData = method == 'GET' ? '' : lines[i++];
    final responseData = lines[i++];

    // Create request.
    final httpRequest = new http.Request(method, Uri.parse('$baseUrl$path'));
    if (method == 'POST') {
      httpRequest.headers['Content-Type'] = 'application/json';
      httpRequest.body = requestData;
    }

    // Validate response.
    final httpResponse =
        await (await httpRequest.send()).stream.bytesToString();
    if (httpResponse != responseData) {
      print('Request failed:');
      print('Method:   $method');
      print('Path:     $path');
      print('Request:  $requestData');
      print('Response: $responseData');

      exit(1);
    } else {
      print('.');
    }
  }

  print('All requests match!');
}
