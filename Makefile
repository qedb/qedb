init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit
	# Install admin server dependencies.
	npm install pug

build-base-container:
	docker build -t eqdb-postgres-base:latest ./tool/docker/eqdb-postgres-base/

start-database:
	./tool/start-db.sh

stop-database:
	./tool/stop-db.sh

restart-database: stop-database start-database

restart-api-server:
	./tool/restart-api-server.sh

restart-web-server:
	./tool/kill-port.sh 8081
	export EQDB_WEB_PORT=8081; \
	dart web/server.dart > /dev/null 2>&1 &

check:
	./tool/check.sh

generate-discovery-doc: restart-database restart-api-server
	mkdir -p doc
	curl http://localhost:8080/discovery/v1/apis/eqdb/v0/rest > doc/discovery.json

generate-openapi-spec: restart-database restart-api-server
	sudo npm install -g api-spec-converter
	mkdir -p doc
	api-spec-converter http://localhost:8080/discovery/v1/apis/eqdb/v0/rest \
	  --from google --to swagger_2 > doc/openapi.json

generate-dot-svg-schema: restart-database
	sleep 4
	PASSWORD=`cat dev-config.yaml | grep "DB_PASS" | awk '{print $2}'`
	postgresql_autodoc -d eqdb -h 172.17.0.2 -p 5432 -u eqdb --password=${PASSWORD} -t dot
	mkdir -p doc
	mv eqdb.dot doc/schema.dot
	dot -Tsvg doc/schema.dot > doc/schema.svg
