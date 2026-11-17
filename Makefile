# Requires Docker (compose v2) and the psql command-line client.
PG_ENV = PGHOST=127.0.0.1 PGPORT=5433 PGUSER=postgres PGPASSWORD=dev

.PHONY: up down test race

up:            ## start PostgreSQL (schema + data + logic loaded)
	docker compose up -d --wait

down:          ## stop and delete the database
	docker compose down -v

test: up       ## rebuild the database and run the 68 tests
	$(PG_ENV) scripts/run-tests.sh

race: up       ## 10 sessions fight for one seat: exactly one wins
	$(PG_ENV) scripts/run-race-test.sh 10
