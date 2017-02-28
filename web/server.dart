// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:eqpg/eqpg.dart';
import 'package:eqpg/utils.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/server_logging_handlers.dart';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_route/shelf_route.dart' as route;

import 'all_pages.dart';

Future<Null> main() async {
  final log = new Logger('server');
  final conf = new EnvConfig('EQPG_', 'dev-config.yaml');

  // Read some configuration values.
  final logFile = conf.string('WEB_LOG');
  final srvPort = conf.integer('WEB_PORT', 8080);
  final dbHost = conf.string('DB_HOST', '0.0.0.0');
  final dbPort = conf.integer('DB_PORT', 5432);
  final dbName = conf.string('DB_NAME', 'eqdb');
  final dbUser = conf.string('DB_USER', 'eqpg');
  final dbPass = conf.string('DB_PASS', 'unconfigured');
  final minConnections = conf.integer('DB_MIN_CONNECTIONS', 2);
  final maxConnections = conf.integer('DB_MAX_CONNECTIONS', 100);
  final connectionUri = 'postgres://$dbUser:$dbPass@$dbHost:$dbPort/$dbName';

  // Setup file based logging.
  if (logFile.isNotEmpty) {
    Logger.root.onRecord.listen(new SyncFileLoggingHandler(logFile));
  }

  // Log to STDOUT.
  if (stdout.hasTerminal) {
    Logger.root.onRecord.listen(new LogPrintHandler());
  }

  // Create database API instance.
  final eqapi = new EqDB(connectionUri, minConnections, maxConnections);
  await eqapi.initialize();

  // Create router.
  final router = route.router();
  routeAllPages(
      conf.string('API_BASE', 'http://localhost:8080/eqdb/v0/'), router, eqapi);

  // Create shelf handler.
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests(
          logger: (msg, isError) => isError ? log.severe(msg) : log.info(msg)))
      .addHandler(router.handler);

  // Start server.
  final server = await io.serve(handler, '0.0.0.0', srvPort);
  log.info('Listening at port ${server.port}.');

  // Gracefully handle SIGINT signals.
  ProcessSignal.SIGINT.watch().listen((signal) async {
    log.info('Received $signal, terminating...');
    await eqapi.pool.stop();
    await server.close();
    exit(0);
  });
}
