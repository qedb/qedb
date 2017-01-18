// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:eqpg/eqpg.dart';
import 'package:yaml/yaml.dart';
import 'package:rpc/rpc.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/server_logging_handlers.dart';

import 'package:shelf_rpc/shelf_rpc.dart' as shelf_rpc;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_route/shelf_route.dart' as shelf_route;

// Server parameter names.
const keyServerLog = 'SERVER_LOG';
const keyApiPort = 'API_PORT';
const keyDbHost = 'DB_HOST';
const keyDbPort = 'DB_PORT';
const keyDbName = 'DB_NAME';
const keyDbUser = 'DB_USER';
const keyDbPass = 'DB_PASS';
const keyMaxConn = 'MAX_CONNECTIONS';

// Environment variable prefix.
const envPrefix = 'EQPG_';

Future main() async {
  // Read YAML file.
  final yamlConfigPath = env('EQPG_CONFIG_PATH', 'dev-config.yaml');
  final yamlFile = new File(yamlConfigPath);
  Map<String, dynamic> yamlData = {};
  if (await yamlFile.exists()) {
    yamlData = loadYaml(yamlFile.readAsStringSync());
  }

  // Read some configuration values.
  final logFile = getParam(yamlData, keyServerLog);
  final srvPort = getParamInt(yamlData, keyApiPort, 8080);
  final dbHost = getParam(yamlData, keyDbHost, '0.0.0.0');
  final dbPort = getParamInt(yamlData, keyDbPort, 5432);
  final dbName = getParam(yamlData, keyDbName, 'eqdb');
  final dbUser = getParam(yamlData, keyDbUser, 'eqpg');
  final dbPass = getParam(yamlData, keyDbPass, 'unconfigured');
  final maxConnections = getParamInt(yamlData, keyMaxConn, 100);

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

  // Gracefully handle SIGKILL signals.
  ProcessSignal.SIGINT.watch().listen((signal) async {
    Logger.root.info('Received SIGINT signal, terminating...');
    await server.close();
    exit(0);
  });
}

/// Read environment variable.
String env(String label, [String dflt = '']) =>
    Platform.environment.containsKey('$envPrefix$label')
        ? Platform.environment['$envPrefix$label']
        : dflt;

/// Read string parameter from yaml data > environment variable > default
String getParam(Map<String, dynamic> yaml, String label, [String dflt = '']) =>
    yaml.containsKey(label) ? yaml[label] : env(label, dflt);

/// Same as [getParam] but for integers.
int getParamInt(Map<String, dynamic> yaml, String label, [int dflt = 0]) =>
    yaml.containsKey(label)
        ? yaml[label]
        : Platform.environment.containsKey('$envPrefix$label')
            ? int.parse(Platform.environment[label])
            : dflt;
