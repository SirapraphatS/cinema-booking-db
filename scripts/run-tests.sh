#!/usr/bin/env bash
# Rebuilds the database from scratch and runs the PostgreSQL tests.
# Connection comes from the standard libpq variables (defaults suit a local server):
#   PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=<password> DB=cinema_booking
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
