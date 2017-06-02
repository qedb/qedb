#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Note that this removes carriage returns using sed or else they will
# accumulate over time.
docker exec -t qedb-postgres pg_dumpall -c -U postgres | sed 's/\r$//' > $1
