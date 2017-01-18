#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

# Restart database and kill the API server if still running.
./tool/stop-db.sh
./tool/start-db.sh
./tool/kill-server.sh

# Empty the log file.
truncate -s 0 testlog.txt

# Start the API server and redirect logging to testlog.txt
export EQPG_SERVER_LOG='testlog.txt'
dart bin/server.dart > /dev/null &

# Sleep 4 secs or postgres will reject connections.
echo 'Sleeping 4 seconds...'
sleep 4

# Run the provided test command.
eval $1

# Log will not be removed on error.
rm testlog.txt
./tool/kill-server.sh
