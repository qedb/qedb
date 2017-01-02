// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:eqpg/eqpg.dart';
import 'package:rpc/rpc.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/server_logging_handlers.dart';

import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_route/shelf_route.dart' as shelf_route;

String env(String label, [String dflt = '']) =>
    Platform.environment.containsKey(label)
        ? Platform.environment[label]
        : dflt;

Future main() async {
  // Read some configuration values.
  final logFile = env('EQPG_SERVER_LOG');
  final srvPort = int.parse(env('EQPG_API_PORT', '8080'));
  final dbHost = env('EQPG_DB_HOST', '0.0.0.0');
  final dbPort = int.parse(env('EQPG_DB_PORT', '5432'));
  final dbName = env('EQPG_DB_NAME', 'eqdb');
  final dbUser = env('EQPG_DB_NAME', 'eqdb');
  final dbPass = env('EQPG_DB_NAME', 'eqdb');
  final maxConnections = int.parse(env('EQPG_MAX_CONNECTIONS', '100'));

  // Create connection object.
  final connection = new DbConnection(dbHost, dbPort, dbName, dbUser, dbPass);

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

  // Create RPC API server.
  final ApiServer apiServer = new ApiServer();
  apiServer.addApi(new EqDB(connection, maxConnections));
  apiServer.enableDiscoveryApi();

  // Create a Shelf handler for your RPC API.
  var apiHandler = shelf_rpc.createRpcHandler(apiServer);
  var apiRouter = shelf_route.router();
  apiRouter.add('', null, apiHandler, exactMatch: false);
  var handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(apiRouter.handler);

  var server = await shelf_io.serve(handler, '0.0.0.0', srvPort);
  Logger.root.info('Listening at port ${server.port}.');
}
