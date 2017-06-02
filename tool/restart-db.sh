#!/bin/bash

# Copyright (c) 2016, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Stop first, if still running.
./tool/stop-db.sh

# Generate password.
#export QEDb_DB_PASS=`< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-64}; echo;`
# A static password makes using SQL dumps easier.
export QEDb_DB_PASS='quod erat demonstrandum'

# Replace password in setup SQL.
sed "s/\$password/${QEDb_DB_PASS}/" < ./lib/schema.sql > ./tool/docker/qedb-postgres/setup.sql

# Copy Perl function.
cp ./lib/pl/expr.pgsql ./tool/docker/qedb-postgres/expr.sql

# Copy triggers.
cp ./lib/triggers.pgsql ./tool/docker/qedb-postgres/triggers.sql

# Build container.
docker build -t qedb-postgres:latest ./tool/docker/qedb-postgres/

# Run container.
docker run --name qedb-postgres -e POSTGRES_DB="qedb" -e POSTGRES_PASSWORD="$QEDb_DB_PASS" -d qedb-postgres

# Give container some time to setup.
IS_READY=`docker exec -u postgres qedb-postgres pg_isready`
while [ "${IS_READY}" != "/var/run/postgresql:5432 - accepting connections" ]; do
  sleep 0.1
  IS_READY=`docker exec -u postgres qedb-postgres pg_isready`
  echo $IS_READY
done

# Export access parameters.
export QEDb_DB_HOST=`docker inspect qedb-postgres | grep '"IPAddress"' | awk '{print $2}' | awk -F '"' '{print $2}' | head -n1`
export QEDb_DB_PORT="5432"
export QEDb_DB_NAME="qedb"
export QEDb_DB_USER="qedb"

# Write config file.
rm -f dev_config.yaml
touch dev_config.yaml
echo "DB_HOST: '${QEDb_DB_HOST}'" >> dev_config.yaml
echo "DB_PORT: ${QEDb_DB_PORT}" >> dev_config.yaml
echo "DB_NAME: ${QEDb_DB_NAME}" >> dev_config.yaml
echo "DB_USER: ${QEDb_DB_USER}" >> dev_config.yaml
echo "DB_PASS: ${QEDb_DB_PASS}" >> dev_config.yaml
cat dev_config.yaml
