#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

OBSERVATORY_PORT=8000

# Kill API server here, since killing is async (only sends signal).
./tool/kill-port.sh 8080

# Restart database.
./tool/stop-db.sh
./tool/start-db.sh

# Wait before Postgres is up before starting server (because the API server
# will try to immedeatly create a connection pool).
echo 'Sleeping 4 seconds...'
sleep 4

# Start the API server.
truncate -s 0 testlog.txt
export EQPG_API_LOG='testlog.txt'
dart --checked --observe=$OBSERVATORY_PORT bin/server.dart > /dev/null 2>&1 &

# Wait untill server has started.
while [ -z "`cat testlog.txt | grep 'Listening at port 8080'`"  ]; do
  echo 'Waiting for API server to initialize...'
  sleep 0.3
done
echo 'API server is initialized.'

# Run the provided test command.
eval $1

if [ ! -z ${CODECOV_TOKEN+x} ];
then
  # Collect coverage.
  echo 'Collecting coverage...'
  pub global run coverage:collect_coverage\
  --uri=http://127.0.0.1:$OBSERVATORY_PORT/ --out $2

  # Format coverage into LCOV.
  echo 'Formatting coverage...'
  pub global run coverage:format_coverage --packages=./.packages\
  --report-on lib --in $2 --out $2.lcov --lcov
  rm $2
fi

# Log will not be removed on error because this script will also be terminated.
rm testlog.txt
./tool/kill-port.sh 8080
