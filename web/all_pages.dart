// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:convert';

import 'package:eqpg/eqpg.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_route/shelf_route.dart';

import 'package:http/http.dart' as http;

import 'pages/home.dart';
import 'pages/descriptor.dart';
import 'pages/category.dart';
import 'admin_page.dart';

/// All pages.
Map<String, AdminPage> pages = {
  '/': homePage,
  '/descriptor/create': createDescriptorPage,
  '/descriptor/{id}/read': readDescriptorPage,
  '/category/create': createCategoryPage
};

/// Requests constants.
final Map<String, String> requestConstants = {
  'bootstrap.href':
      'https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css',
  'bootstrap.integrity':
      'sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ'
};

void routeAllPages(String apiBase, Router router, EqDB eqapi) {
  final faviconData = new File('web/favicon.ico').readAsBytesSync();
  router.get('/favicon.ico', (_) {
    return new Response.ok(faviconData,
        headers: {'Content-Type': 'image/x-icon'});
  });

  // Add handlers for all pages.
  pages.forEach((path, page) {
    router.add(path, ['GET', 'POST'], (Request request) async {
      final data = new PageData(requestConstants);
      data.path = request.requestedUri.path.split('/');
      data.path.removeWhere((str) => str.isEmpty);
      data.pathParameters = getPathParameters(request);

      if (request.method == 'POST' && page.postFormat != null) {
        // Decode form data.
        final uri = new Uri(query: await request.readAsString());

        // Encode post data.
        data.request = encodePostData(page.postFormat, uri.queryParameters);

        // Get API response.
        final response = await http.post('$apiBase$path',
            headers: {'Content-Type': 'application/json'},
            body: JSON.encode(data.request));
        data.data = JSON.decode(response.body);

        // Render page.
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      } else {
        // Do GET request if no postFormat is specified.
        if (page.postFormat == null) {
          final response =
              await http.get('$apiBase${request.requestedUri.path}');
          data.data = JSON.decode(response.body);
        }

        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      }
    });
  });
}

/// Generate API POST data from a data [format] and [formData].
dynamic encodePostData(dynamic format, Map<String, String> formData) {
  if (format is Map) {
    return new Map.fromIterable(format.keys,
        key: (key) => key,
        value: (key) => encodePostData(format[key], formData));
  } else if (format is List) {
    return new List.generate(
        format.length, (i) => encodePostData(format[i], formData));
  } else if (format is String) {
    return formData.containsKey(format) ? formData[format] : format;
  } else {
    return format;
  }
}
