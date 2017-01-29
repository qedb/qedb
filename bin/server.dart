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

Future<Null> main() async {
  final log = new Logger('server');

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
  final eqdbApi = new EqDB(connectionUri, 2, maxConnections);
  await eqdbApi.pool.start();
  apiServer.addApi(eqdbApi);
  apiServer.enableDiscoveryApi();

  // Create a Shelf handler.
  final apiHandler = shelf_rpc.createRpcHandler(apiServer);
  final apiRouter = shelf_route.router();
  apiRouter.add('', null, apiHandler, exactMatch: false);
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests(
          logger: (msg, isError) => isError ? log.severe(msg) : log.info(msg)))
      .addHandler(apiRouter.handler);

  final server = await shelf_io.serve(handler, '0.0.0.0', srvPort);
  log.info('Listening at port ${server.port}.');

  // Gracefully handle SIGINT signals.
  ProcessSignal.SIGINT.watch().listen((signal) async {
    log.info('Received $signal, terminating...');
    await eqdbApi.pool.stop();
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
