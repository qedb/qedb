// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:shelf/shelf.dart';

/// Map with all previous API responses
/// This map is used to prevent duplication of some fundamental requests.
final _requestMap = new Map<String, String>();

/// Read existing responses.
void readRequestLog(File file) {
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length;) {
    if (lines[i++] == 'GET') {
      _requestMap[lines[i++]] = lines[i++];
    } else {
      i += 3;
    }
  }
}

/// Log all requests/responses content to a file.
/// Each entry in the file has this structure:
///
///     GET/POST
///     target URL
///     request body (omitted in case of GET)
///     response body
///
Middleware logRequestData(File file) {
  return (innerHandler) {
    return (request) async {
      final method = request.method;
      final requestStr = (await request.readAsString()).trim();
      final requestCopy = request.change(body: requestStr);
      return new Future.sync(() => innerHandler(requestCopy))
          .then((response) async {
        final responseStr = (await response.readAsString()).trim();
        var path = request.url.path;
        if (request.url.query.isNotEmpty) {
          path += '?${request.url.query}';
        }

        // Write request data.
        if (method == 'GET' && _requestMap[path] != responseStr) {
          _requestMap[path] = responseStr;
          await file.writeAsString('GET\n$path\n$responseStr\n',
              mode: FileMode.APPEND);
        } else if (method == 'POST') {
          await file.writeAsString('POST\n$path\n$requestStr\n$responseStr\n',
              mode: FileMode.APPEND);
        }

        return response.change(body: responseStr);
      });
    };
  };
}
