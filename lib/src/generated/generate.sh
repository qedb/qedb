# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

#/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

cd "${0%/*}"

mustache data.yaml session_data.mustache > session_data.dart
mustache data.yaml tables.mustache > tables.dart
dartfmt -w *.dart
