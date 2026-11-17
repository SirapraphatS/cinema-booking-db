#!/usr/bin/env bash
# drop and create the database
# load sql/01..03 in name order, then sql/tests/booking_tests.sql
# connection: PGHOST PGPORT PGUSER PGPASSWORD, database name in DB
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PGHOST:=127.0.0.1}" "${PGPORT:=5432}" "${PGUSER:=postgres}" "${DB:=cinema_booking}"
export PGHOST PGPORT PGUSER
run() { psql -q -v ON_ERROR_STOP=1 "$@"; }

run -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
# sql/01_schema.sql, 02_sample_data.sql, 03_booking_procedures.sql load in name order, then the tests
for f in sql/0*.sql sql/tests/booking_tests.sql; do
    run -d "$DB" -f "$f"
done
