init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit
	# Install admin server dependencies.
	npm install pug

build-base-container:
	docker build -t qedb-postgres-base:latest ./tool/docker/qedb-postgres-base/

restart-database:
	./tool/restart-db.sh

stop-database:
	./tool/stop-db.sh

restart-api-server:
	export QEDb_TEST_LOG=''; ./tool/restart-api-server.sh

restart-api-server-log-tests:
	export QEDb_TEST_LOG='test/logs/main.txt'; ./tool/restart-api-server.sh

restart-web-server:
	./tool/kill-port.sh 8081
	export QEDb_WEB_PORT=8081; dart -c bin/web/server.dart > /dev/null 2>&1 &

dump-database:
	./tool/dump-database.sh dumps/main.sql

restore-database-dump:
	./tool/kill-port.sh 8080 force
	cat dumps/main.sql | docker exec -i qedb-postgres psql -U postgres
	export QEDb_TEST_LOG=''; ./tool/restart-api-server.sh

check:
	./tool/check.sh

build-dev-environment:	
	./tool/restart-db.sh
	./tool/restart-api-server.sh
	./tool/kill-port.sh 8081 force
	pub build
	export QEDb_WEB_PORT=8081; dart -c bin/web/server.dart > /dev/null 2>&1 &

build-tested-dev-environment: restart-web-server
	./tool/restart-db.sh
	./tool/run-test.sh ./test/run.sh
	./tool/restart-api-server.sh
	./tool/kill-port.sh 8081 force
	pub build
	export QEDb_WEB_PORT=8081; dart -c bin/web/server.dart > /dev/null 2>&1 &

generate-discovery-doc: restart-database restart-api-server
	mkdir -p doc
	curl http://localhost:8080/discovery/v1/apis/qedb/v0/rest > doc/discovery.json

generate-openapi-spec: restart-database restart-api-server
	sudo npm install -g api-spec-converter
	mkdir -p doc
	api-spec-converter http://localhost:8080/discovery/v1/apis/qedb/v0/rest \
	  --from google --to swagger_2 > doc/openapi.json

generate-dot-svg-schema: restart-database
	sleep 4
	PASSWORD=`cat dev_config.yaml | grep "DB_PASS" | awk '{print $2}'`
	postgresql_autodoc -d qedb -h 172.17.0.2 -p 5432 -u qedb --password=${PASSWORD} -t dot
	mkdir -p doc
	mv qedb.dot doc/schema.dot
	dot -Tsvg doc/schema.dot > doc/schema.svg

open-pgcli:
	./tool/open-pgcli.sh
