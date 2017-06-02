#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

./tool/kill-port.sh 8080 force

# Wait for kill (is async).
# If the old server is still listening the new server cannot bind.
sleep 4

# Empty the log file.
truncate -s 0 testlog.txt

# Set log file.
export QEDb_API_LOG='testlog.txt'

# Run server.
if [ ! -z $1 ];
then
  echo "Observe at :$1"
  dart --checked --observe=$1 bin/api/server.dart > /dev/null 2>&1 &
else
  dart --checked bin/api/server.dart > /dev/null 2>&1 &
fi

# Wait untill server has started.
while [ -z "`cat testlog.txt | grep 'Listening at port 8080'`"  ]; do
  echo 'Waiting for API server to initialize...'
  sleep 0.3
done
echo 'API server is initialized.'
