init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit

start-database:
	./tool/start-db.sh

stop-database:
	./tool/stop-db.sh

restart-database: stop-database start-database

restart-server:
	./tool/kill-server.sh
	dart bin/server.dart > /dev/null &

check:
	./tool/check.sh

generate-openapi-spec: restart-database
	sudo npm install -g api-spec-converter
	./tool/kill-server.sh
	dart bin/server.dart
	mkdir -p doc
	api-spec-converter http://localhost:8080/discovery/v1/apis/eqdb/v0/rest \
	  --from google --to swagger_2 > doc/openapi.json
