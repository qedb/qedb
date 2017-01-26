// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:logging/logging.dart';
import 'package:logging_handlers/server_logging_handlers.dart';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;

import 'router.dart';

const envLogFile = 'EQPG_ADMIN_WEBSITE_LOG_FILE';
const envPort = 'EQPG_ADMIN_WEBSITE_PORT';

Future main() async {
  final log = new Logger('server');

  // Setup file based logging.
  if (Platform.environment.containsKey(envLogFile)) {
    Logger.root.onRecord
        .listen(new SyncFileLoggingHandler((Platform.environment[envLogFile])));
  }

  // Log to STDOUT.
  if (stdout.hasTerminal) {
    Logger.root.onRecord.listen(new LogPrintHandler());
  }

  // Create router.
  final adminRouter = new AdminRouter();
  await adminRouter.intialize();

  // Create shelf handler.
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests(
          logger: (msg, isError) => isError ? log.severe(msg) : log.info(msg)))
      .addHandler(adminRouter.router.handler);

  // Get server port.
  final port = Platform.environment.containsKey(envPort)
      ? int.parse(Platform.environment[envPort])
      : 8080;

  // Start server.
  final server = await io.serve(handler, '0.0.0.0', port);
  log.info('Listening at port ${server.port}.');

  // Gracefully handle SIGINT signals.
  ProcessSignal.SIGINT.watch().listen((signal) async {
    log.info('Received $signal, terminating...');
    await server.close();
    await adminRouter.terminate();
    exit(0);
  });
}
