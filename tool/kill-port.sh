#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

PORT=$1
FORCE=$2
SERVER_PID=`lsof -n -i :$PORT | grep 'LISTEN' | awk '{print $2}'`
if [ -n "$SERVER_PID" ]
then
  echo "Killing server PID $SERVER_PID"

  if [ -z $FORCE ]
  then
    # Note that the server can handle SIGINT signals.
    kill -s SIGINT $SERVER_PID
  else
    kill $SERVER_PID
  fi
fi
