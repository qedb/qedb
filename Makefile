init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit
	# Install admin server dependencies.
	npm install pug

start-database:
	./tool/start-db.sh

stop-database:
	./tool/stop-db.sh

restart-database: stop-database start-database

restart-server:
	./tool/kill-port.sh 8080
	dart bin/server.dart > /dev/null 2>&1 &

restart-admin-website:
	./tool/kill-port.sh 8081
	node web/server.js > /dev/null 2>&1 &

check:
	./tool/check.sh

generate-openapi-spec: restart-database restart-server
	sudo npm install -g api-spec-converter
	mkdir -p doc
	api-spec-converter http://localhost:8080/discovery/v1/apis/eqdb/v0/rest \
	  --from google --to swagger_2 > doc/openapi.json

generate-dot-svg-schema: restart-database
	sleep 4
	PASSWORD=`cat dev-config.yaml | grep "DB_PASS" | awk '{print $2}'`
	postgresql_autodoc -d eqdb -h 172.17.0.2 -p 5432 -u eqpg --password=${PASSWORD} -t dot
	mkdir -p doc
	mv eqdb.dot doc/schema.dot
	dot -Tsvg doc/schema.dot > doc/schema.svg
