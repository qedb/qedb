#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

CONTAINER=`docker ps -a --filter='name=qedb-postgres' | grep "qedb-postgres" | awk '{print $1}'`
IMAGE=`docker images qedb-postgres | grep "qedb-postgres" | awk '{print $3}'`
if [ -n "${CONTAINER}" ]; then
  docker stop --time=1 qedb-postgres
  docker rm qedb-postgres
fi
if [ -n "${IMAGE}" ]; then
  docker rmi qedb-postgres
fi
