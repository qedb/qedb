// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'package:shelf/shelf.dart';

abstract class RequestController {
  Future<Response> process(Request request) async {
    if (request.method == 'GET') {
      return get(request.url.queryParameters);
    } else if (request.method == 'POST') {
      if (request.headers['Content-Type']
          .contains('application/x-www-form-urlencoded')) {
        final bodyUri = new Uri(query: await request.readAsString());
        return post(bodyUri.queryParameters, request.url.queryParameters);
      } else {
        return new Response(422, body: 'Unprocessable Content-Type');
      }
    } else {
      return new Response.notFound('No such method');
    }
  }

  Response get(Map<String, String> urlQuery) {
    return new Response.notFound('No such method');
  }

  Response post(Map<String, String> postData, Map<String, String> urlQuery) {
    return new Response.notFound('No such method');
  }
}
