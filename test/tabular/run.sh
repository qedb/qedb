#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e
cd "${0%/*}"

# Only reconvert if ssconvert is installed. Installing ssconvert on Travis-CI is
# painful and I could not find a suitable alternative program.
if [ ! -z `command -v ssconvert` ];
then
  echo 'Converting data.gnumeric to CSV...'
  mkdir -p data/data
  rm -f data/data.*.csv
  ssconvert -S data.gnumeric data/data.csv
  rename -v 's/data.csv.([0-9]+)/data.$1.csv/' data/data.csv.*
fi

dart run.dart model.yaml data/data.*.csv
