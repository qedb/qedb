#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

CONTAINER=`docker ps | grep "eqpg-database" | awk '{print $1}'`
if [ -n "${CONTAINER}" ]
then
  docker stop --time=1 eqpg-database
  docker rm eqpg-database
fi
