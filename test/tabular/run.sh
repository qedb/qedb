# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

# Only reconvert if ssconvert is installed. Installing ssconvert on Travis-CI is
# painful and I could not find a suitable alternative program.
if [ -n `command -v ssconvert` ];
then
  mkdir -p ./test/tabular/data/data
  ssconvert -S ./test/tabular/data.gnumeric ./test/tabular/data/data.csv
fi

dart ./test/tabular/run.dart ./test/tabular/model.yaml ./test/tabular/data/data.csv.*
