#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Generate password.
EQPG_DATABASE_PASS=`< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32}; echo;`

# Setup Postgres database using Docker.
docker run --name eqpg-database -e POSTGRES_PASSWORD="${EQPG_DATABASE_PASS}" -d postgres:alpine

# Give container some time to setup.
IS_READY=`docker exec -u postgres eqpg-database pg_isready`
while [ "${IS_READY}" != "/tmp:5432 - accepting connections" ]; do
  sleep 0.1
  IS_READY=`docker exec -u postgres eqpg-database pg_isready`
  echo $IS_READY
done

# Create new database.
docker exec -u postgres eqpg-database createdb eqdb

# Copy setup SQL.
docker cp ./lib/setup.sql eqpg-database:/docker-entrypoint-initdb.d/setup.sql

# Run setup SQL.
docker exec -u postgres eqpg-database psql eqdb postgres -f docker-entrypoint-initdb.d/setup.sql

# Get database host address and store in environment variable.
EQPG_DATABASE_HOST=`docker inspect eqpg-database | grep '"IPAddress"' | awk '{print $2}' | awk -F '"' '{print $2}' | head -n1`

# Print details.
echo "Host: ${EQPG_DATABASE_HOST}"
echo "User: postgres"
echo "Pass: ${EQPG_DATABASE_PASS}"

# Run API server.
#dart bin/server.dart

# Collect database dump.
#docker exec -t eqpg-database pg_dumpall -c -U postgres > dev-dump.sql
