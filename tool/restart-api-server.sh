#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

./tool/kill-port.sh 8080

# Wait for kill (is async).
# If the old server is still listening the new server cannot bind.
sleep 2

# Empty theca log file.
truncate -s 0 testlog.txt

# Set log file.
export EQDB_API_LOG='testlog.txt'

# Run server.
dart bin/server.dart > /dev/null 2>&1 &

# Wait untill server has started.
while [ -z "`cat testlog.txt | grep 'Listening at port 8080'`"  ]; do
  echo 'Waiting for API server to initialize...'
  sleep 0.3
done
echo 'API server is initialized.'