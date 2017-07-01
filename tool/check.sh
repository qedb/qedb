#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

if [ -z $1 ];
then
  # Regenerate generated files.
  ./lib/src/generated/generate.sh

  # Check formatting.
  dartfmt --dry-run --set-exit-if-changed ./

  # Run analyzer checks.
  dartanalyzer \
  --options analysis_options.yaml \
  --fatal-hints --fatal-warnings --fatal-lints ./
fi

# Restart database.
./tool/restart-db.sh

# Run tests.
export QEDb_TEST_LOG=''
./tool/run-test.sh ./test/run.sh coverage.json

# Run Perl algorithm tests.
perl -Ilib/pl -MDevel::Cover lib/pl/test.pl

# Upload coverage.
if [ ! -z ${CODECOV_TOKEN+x} ];
then
  bash <(curl -s https://codecov.io/bash)
fi

# Remove LCOV files.
rm -f *.lcov
