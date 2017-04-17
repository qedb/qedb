#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

OBSERVATORY_PORT=8000

# Start the API server.
./tool/restart-api-server.sh $OBSERVATORY_PORT

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

