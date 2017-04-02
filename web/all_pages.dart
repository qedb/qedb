// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_route/shelf_route.dart';
import 'package:json_object/json_object.dart';

import 'package:http/http.dart' as http;

import 'pages/home.dart';
import 'pages/locale.dart';
import 'pages/descriptor.dart';
import 'pages/subject.dart';
import 'pages/translation.dart';
import 'pages/category.dart';
import 'pages/function.dart';

import 'pages/templates.dart';
import 'common.dart';

/// All pages.
Map<String, AdminPage> pages = {
  '/': homePage,
  '/locale/create': createLocalePage,
  '/descriptor/create': createDescriptorPage,
  '/descriptor/list': listDescriptorsPage,
  '/descriptor/{id}/read': readDescriptorPage,
  '/descriptor/{id}/translation/create': createTranslationPage,
  '/subject/create': createSubjectPage,
  '/subject/list': listSubjectsPage,
  '/category/create': createCategoryPage,
  '/category/list': listCategoriesPage,
  '/category/{id}/read': readCategoryPage,
  '/category/{id}/category/create': createCategoryPage,
  '/category/{id}/category/list': listSubCategoriesPage,
  '/function/create': createFunctionPage,
  '/function/list': listFunctionsPage
};

/// Requests constants.
final Map<String, String> requestConstants = {
  'bootstrap.href':
      'https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css',
  'bootstrap.integrity':
      'sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ'
};

void routeAllPages(String apiBase, Router router) {
  // Make sure breadcrumb only points to existing pages.
  breadcrumbAvailableLinks.addAll(pages.keys);

  // Serve favicon.
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

      // Load additional resources.
      for (final label in page.additional.keys) {
        final response = await http.get('$apiBase${page.additional[label]}');
        data.additional[label] = new JsonObject.fromJsonString(response.body);
      }

      if (request.method == 'POST' && page.postFormat != null) {
        // Decode form data.
        final uri = new Uri(query: await request.readAsString());

        // Encode post data.
        data.request = encodePostData(page.postFormat, uri.queryParameters);

        // Get API response.
        final response = await http.post(
            '$apiBase${request.requestedUri.path.substring(1)}',
            headers: {'Content-Type': 'application/json'},
            body: JSON.encode(data.request));
        data.data = new JsonObject.fromJsonString(response.body);

        // Render page.
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      } else {
        // Do GET request if no postFormat is specified.
        if (page.postFormat == null) {
          final response =
              await http.get('$apiBase${request.requestedUri.path}');
          data.data = new JsonObject.fromJsonString(response.body);
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
    // Format may start with '$type:' to cast it.
    final parts = format.split(':');
    final targetName = parts.last;
    if (formData.containsKey(targetName)) {
      if (parts.first == 'int') {
        return int.parse(formData[targetName]);
      } else if (parts.first == 'bool') {
        return formData[targetName] == 'true';
      } else {
        return formData[targetName];
      }
    } else {
      return format;
    }
  } else {
    return format;
  }
}
