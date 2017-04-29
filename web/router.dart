// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_route/shelf_route.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:http/http.dart' as http;

import 'pages/home.dart';
import 'pages/language.dart';
import 'pages/descriptor.dart';
import 'pages/subject.dart';
import 'pages/translation.dart';
import 'pages/function.dart';
import 'pages/proof.dart';
import 'pages/rule.dart';

import 'page.dart';

/// All pages
Map<String, Page> pages = {
  '/': homePage,
  '/language/create': createLanguagePage,
  '/descriptor/{id}/read': readDescriptorPage,
  '/descriptor/{id}/translation/create': createTranslationPage,
  '/subject/create': createSubjectPage,
  '/subject/list': listSubjectsPage,
  '/function/create': createFunctionPage,
  '/function/{id}/update': updateFunctionPage,
  '/function/list': listFunctionsPage,
  '/rule/create': createRulePage,
  '/rule/list': listRulesPage,
  '/rule/{id}/delete': deleteRulePage,
  '/proof/create': createProofPage,
  '/proof/list': listProofsPage,
  '/proof/{id}/steps/list': listProofStepsPage
};

/// Entry point to create router.
Future<Null> setupRouter(String apiBase, Router router) async {
  // Read settings file.
  final settings = loadYaml(await new File('web/settings.yaml').readAsString());

  // Read all snippets.
  final entities = await new Directory('web/snippets').list().toList();
  final snippets = new Map<String, String>();
  for (final entity in entities) {
    final file = new File.fromUri(entity.uri);
    if (await file.exists()) {
      snippets[file.path.split('/').last] = await file.readAsString();
    }
  }

  // Serve favicon.
  final faviconData = new File('web/favicon.ico').readAsBytesSync();
  router.get('/favicon.ico', (_) {
    return new Response.ok(faviconData,
        headers: {'Content-Type': 'image/x-icon'});
  });

  // Serve static files.
  router.add('/static/', ['GET'], createStaticHandler('web/static'),
      exactMatch: false);

  // Add handlers for all pages.
  pages.forEach((path, page) {
    router.add(path, ['GET', 'POST'], (Request request) async {
      final data = new PageSessionData(settings, snippets, pages.keys.toSet());
      data.path = request.requestedUri.path.split('/');
      data.path.removeWhere((str) => str.isEmpty);
      data.pathParameters = getPathParameters(request);

      if (data.path.isEmpty) {
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      }

      // Load additional resources.
      for (final label in page.additional.keys) {
        final response = await http.get('$apiBase${page.additional[label]}');
        data.additional[label] = jsonify(JSON.decode(response.body));
      }

      if (request.method == 'POST' && page.onPost != null) {
        // Decode form data.
        final uri = new Uri(query: await request.readAsString());

        // Encode post data.
        data.request = jsonify(page.onPost(uri.queryParameters));

        // Get API response.
        final response = await http.post(
            '$apiBase${request.requestedUri.path.substring(1)}',
            headers: {'Content-Type': 'application/json'},
            body: JSON.encode(data.request));
        data.response = jsonify(JSON.decode(response.body));

        // Render page.
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      } else {
        // Do GET request if no postFormat is specified.
        if (page.onPost == null) {
          final response = await http
              .get('$apiBase${request.requestedUri.path.substring(1)}');
          data.response = jsonify(JSON.decode(response.body));
        }

        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      }
    });
  });
}
