// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:rpc/rpc.dart';
import 'package:eqdb/api.dart';
import 'package:eqdb/utils.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/server_logging_handlers.dart';

import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_route/shelf_route.dart' as shelf_route;

import 'middleware.dart';

Future<Null> main() async {
  final log = new Logger('server');
  final conf = new EnvConfig('EQDB_', 'dev-config.yaml');

  // Read some configuration values.
  final logFile = conf.string('API_LOG');
  final srvPort = conf.integer('API_PORT', 8080);
  final dbHost = conf.string('DB_HOST', '0.0.0.0');
  final dbPort = conf.integer('DB_PORT', 5432);
  final dbName = conf.string('DB_NAME', 'eqdb');
  final dbUser = conf.string('DB_USER', 'eqdb');
  final dbPass = conf.string('DB_PASS', 'unconfigured');
  final minConnections = conf.integer('DB_MIN_CONNECTIONS', 2);
  final maxConnections = conf.integer('DB_MAX_CONNECTIONS', 100);
  final connectionUri = 'postgres://$dbUser:$dbPass@$dbHost:$dbPort/$dbName';

  // Log everything
  Logger.root.level = Level.ALL;

  // Setup file based logging.
  if (logFile.isNotEmpty) {
    Logger.root.onRecord.listen(new SyncFileLoggingHandler(logFile));
  }

  // Log to STDOUT.
  if (stdout.hasTerminal) {
    Logger.root.onRecord.listen(new LogPrintHandler());
  }

  // Create RPC API handler.
  final ApiServer apiServer = new ApiServer();

  final eqapi = new EqDB(connectionUri, minConnections, maxConnections);
  await eqapi.initialize();

  apiServer.addApi(eqapi);
  apiServer.enableDiscoveryApi();

  // Create a Shelf handler.
  final apiHandler = shelf_rpc.createRpcHandler(apiServer);
  final apiRouter = shelf_route.router();
  apiRouter.add('', null, apiHandler, exactMatch: false);

  // Construct pipeline.
  var pipeline = const shelf.Pipeline();
  pipeline = pipeline.addMiddleware(shelf.logRequests(
      logger: (msg, isError) => isError ? log.severe(msg) : log.info(msg)));

  // Log all requests for testing.
  final testLogFile = new File(conf.string('TEST_LOG'));
  if (await testLogFile.exists()) {
    readRequestLog(testLogFile);
    pipeline = pipeline.addMiddleware(logRequestData(testLogFile));
  }

  final handler = pipeline.addHandler(apiRouter.handler);
  final server = await shelf_io.serve(handler, '0.0.0.0', srvPort);
  log.info('Listening at port ${server.port}.');

  // Gracefully handle SIGINT signals.
  ProcessSignal.SIGINT.watch().listen((signal) async {
    log.info('Received $signal, terminating...');
    await eqapi.pool.stop();
    await server.close();
    exit(0);
  });
}
