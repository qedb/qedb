// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';

import 'package:shelf_route/shelf_route.dart' as route;

final log = new Logger('router');

const bootstrapSrc =
    'https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css';
const bootstrapSha =
    'sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ';

class PugRenderer {
  Process process;
  final queue = new List<Completer<String>>();

  Future<Null> initialize(String template) async {
    process = await Process.start('node', ['render.js', '$template.pug'],
        workingDirectory: '${Directory.current.path}/web/views');

    process.stderr.listen((data) {
      throw new Exception(
          'Pug renderer experienced an error: ${UTF8.decode(data)}');
    });

    // Listen on stdout.
    process.stdout.listen((data) {
      log.info('Rendered Pug template');
      queue.removeAt(0).complete(UTF8.decode(data));
    });
  }

  Future<String> render(dynamic locals) {
    log.info('Render Pug template');
    final input = JSON.encode(locals);
    final completer = new Completer<String>();
    queue.add(completer);
    process.stdin.writeln(input);
    return completer.future;
  }
}

class AdminRouter {
  final route.Router router;
  final indexTemplate = new PugRenderer();

  AdminRouter() : router = route.router();

  Future<Null> terminate() async {
    indexTemplate.process.kill();
  }

  Future<Null> intialize() async {
    await indexTemplate.initialize('index');
    router.get('/', getIndex);
  }

  Future<Response> getIndex(Request request) async {
    final html = await indexTemplate.render({
      'title': 'Index',
      'bootstrap': {'src': bootstrapSrc, 'sha': bootstrapSha},
      'methods': [
        {'name': 'List categories', 'route': 'categories/list', 'count': 10},
        {'name': 'Create category', 'route': 'categories/create'}
      ]
    });
    return new Response.ok(html, headers: {'Content-Type': 'text/html'});
  }
}
