#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Generate password.
export EQDB_DB_PASS=`< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-64}; echo;`

# Replace password in setup SQL.
sed "s/\$password/${EQDB_DB_PASS}/" < ./lib/schema.sql > ./tool/docker/setup.sql

# Remove old container to not mess up dev environment.
docker rmi eqdb-database:latest

# Build container.
docker build -t eqdb-database:latest ./tool/docker/

# Run container.
docker run --name eqdb-database -e POSTGRES_DB="eqdb" -d eqdb-database

# Give container some time to setup.
IS_READY=`docker exec -u postgres eqdb-database pg_isready`
while [ "${IS_READY}" != "/var/run/postgresql:5432 - accepting connections" ]; do
  sleep 0.1
  IS_READY=`docker exec -u postgres eqdb-database pg_isready`
  echo $IS_READY
done

# Export access parameters.
export EQDB_DB_HOST=`docker inspect eqdb-database | grep '"IPAddress"' | awk '{print $2}' | awk -F '"' '{print $2}' | head -n1`
export EQDB_DB_PORT="5432"
export EQDB_DB_NAME="eqdb"
export EQDB_DB_USER="eqdb"

# Write config file.
rm -f dev-config.yaml
touch dev-config.yaml
echo "DB_HOST: '${EQDB_DB_HOST}'" >> dev-config.yaml
echo "DB_PORT: ${EQDB_DB_PORT}" >> dev-config.yaml
echo "DB_NAME: ${EQDB_DB_NAME}" >> dev-config.yaml
echo "DB_USER: ${EQDB_DB_USER}" >> dev-config.yaml
echo "DB_PASS: ${EQDB_DB_PASS}" >> dev-config.yaml
cat dev-config.yaml
