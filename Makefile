init:
	# Create symlink for pre-commit hook.
	ln -sf ../../tool/pre-commit.sh .git/hooks/pre-commit

docker-start:
	./tool/docker-db-start.sh

docker-teardown:
	docker stop eqpg-database
	docker rm eqpg-database
