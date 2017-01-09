#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Generate password.
export EQPG_DB_PASS=`< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32}; echo;`

# Setup Postgres database using Docker.
docker run --name eqpg-database -e POSTGRES_PASSWORD="${EQPG_DB_PASS}" -d postgres:alpine

# Give container some time to setup.
IS_READY=`docker exec -u postgres eqpg-database pg_isready`
while [ "${IS_READY}" != "/tmp:5432 - accepting connections" ]; do
  sleep 0.1
  IS_READY=`docker exec -u postgres eqpg-database pg_isready`
  echo $IS_READY
done

# Create new database.
docker exec -u postgres eqpg-database createdb eqdb

# Replace '$password' in SQL with random password.
sed "s/\$password/${EQPG_DB_PASS}/" < lib/setup.pgsql > tmp.pgsql

# Copy setup SQL.
docker cp ./tmp.pgsql eqpg-database:/docker-entrypoint-initdb.d/setup.pgsql
rm -f tmp.pgsql

# Run setup SQL.
docker exec -u postgres eqpg-database psql eqdb postgres -f docker-entrypoint-initdb.d/setup.pgsql

# Get database host address and store in environment variable.
export EQPG_DB_HOST=`docker inspect eqpg-database | grep '"IPAddress"' | awk '{print $2}' | awk -F '"' '{print $2}' | head -n1`
export EQPG_DB_PORT="5432"
export EQPG_DB_NAME="eqdb"
export EQPG_DB_USER="eqpg"

# Write config file.
rm -f dev-config.yaml
touch dev-config.yaml
echo "DB_HOST: '${EQPG_DB_HOST}'" >> dev-config.yaml
echo "DB_PORT: ${EQPG_DB_PORT}" >> dev-config.yaml
echo "DB_NAME: ${EQPG_DB_NAME}" >> dev-config.yaml
echo "DB_USER: ${EQPG_DB_USER}" >> dev-config.yaml
echo "DB_PASS: ${EQPG_DB_PASS}" >> dev-config.yaml
cat dev-config.yaml
