#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

PATTERN=$1
SERVER_PID=`pgrep -fo "^$PATTERN$"`
if [ -n "$SERVER_PID" ]
then
  echo "Killing server PID $SERVER_PID"
  # Note that the server can handle SIGINT signals.
  kill -s SIGINT $SERVER_PID
fi
