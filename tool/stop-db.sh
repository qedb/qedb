#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

CONTAINER=`docker ps | grep "eqdb-database" | awk '{print $1}'`
IMAGE=`docker images | grep "eqdb-database" | awk '{print $3}'`
if [ -n "${CONTAINER}" ]
then
  docker stop --time=1 eqdb-database
fi
if [ -n "${IMAGE}" ]
then
  docker rm eqdb-database
fi
