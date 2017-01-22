#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Generate password.
export EQPG_DB_PASS=`< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-64}; echo;`

# Replace password in setup SQL.
sed "s/\$password/${EQPG_DB_PASS}/" < ./lib/schema.sql > ./tool/docker/setup.sql

# Build container.
docker build -t eqpg-database ./tool/docker/

# Run container.
docker run --name eqpg-database -e POSTGRES_DB="eqdb" -d eqpg-database

# Give container some time to setup.
IS_READY=`docker exec -u postgres eqpg-database pg_isready`
while [ "${IS_READY}" != "/var/run/postgresql:5432 - accepting connections" ]; do
  sleep 0.1
  IS_READY=`docker exec -u postgres eqpg-database pg_isready`
  echo $IS_READY
done

# Export access parameters.
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
