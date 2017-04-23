#!/bin/bash

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

DB_HOST=`cat dev-config.yaml | grep HOST | awk '{print $2}' | sed 's/^.\(.*\).$/\1/'`
DB_PORT=`cat dev-config.yaml | grep PORT | awk '{print $2}'`
DB_NAME=`cat dev-config.yaml | grep NAME | awk '{print $2}'`
DB_USER=`cat dev-config.yaml | grep USER | awk '{print $2}'`
DB_PASS=`cat dev-config.yaml | grep PASS | cut -d\  -f2-`

echo "postgres://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME"
pgcli "postgres://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME"
