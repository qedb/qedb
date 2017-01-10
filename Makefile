init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit

start-database:
	./tool/start-db.sh

stop-database:
	./tool/stop-db.sh

restart-database: stop-database start-database

check: restart-database
	./tool/kill-server.sh
	dart bin/server.dart > /dev/null &
	sleep 2
	dart test/run.dart
	./tool/kill-server.sh
