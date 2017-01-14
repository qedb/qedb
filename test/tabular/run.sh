# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

ssconvert -S ./test/tabular/data.gnumeric ./test/tabular/data.csv
dart ./test/tabular/run.dart
rm ./test/tabular/data.csv.*
