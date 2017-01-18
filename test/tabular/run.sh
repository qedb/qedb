# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

set -e

ssconvert -S ./test/tabular/data.gnumeric ./test/tabular/data.csv
dart ./test/tabular/run.dart ./test/tabular/model.yaml ./test/tabular/data.csv.*
rm ./test/tabular/data.csv.*
