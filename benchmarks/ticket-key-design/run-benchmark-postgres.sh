#!/usr/bin/env bash
# PostgreSQL benchmark. Connection: PGHOST PGPORT PGUSER PGPASSWORD ; data directory = first argument.
set -euo pipefail
D="$(cd "${1:?usage: run-benchmark-postgres.sh DATA_DIR}" && pwd)"
: "${PGHOST:=127.0.0.1}" "${PGPORT:=5432}" "${PGUSER:=postgres}"
export PGHOST PGPORT PGUSER
P=(psql -q -v ON_ERROR_STOP=1)

"${P[@]}" -d postgres -c "DROP DATABASE IF EXISTS bench" -c "CREATE DATABASE bench" 2>/dev/null
"${P[@]}" -d bench <<'SQL'
CREATE TABLE ticket_a (branch_id INT NOT NULL, theatre_id INT NOT NULL, showtime_date DATE NOT NULL, showtime_time TIME NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (branch_id, theatre_id, showtime_date, showtime_time, seat_id));
CREATE INDEX idx_a_booking ON ticket_a (booking_id);
CREATE TABLE ticket_b (showtime_id INT NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (showtime_id, seat_id));
CREATE INDEX idx_b_booking ON ticket_b (booking_id);
CREATE TABLE ticket_b2 (showtime_id INT NOT NULL, branch_id INT NOT NULL, theatre_id INT NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (showtime_id, seat_id));
CREATE INDEX idx_b2_booking ON ticket_b2 (booking_id);
SQL
now() { date +%s.%N; }
for v in a b b2; do
    f=$(echo "$v" | tr a-z A-Z); s=$(now)
    "${P[@]}" -d bench -c "\\copy ticket_$v FROM '$D/$f.csv' CSV"
    echo "load $v: $(echo "$(now) - $s" | bc) s"
done
"${P[@]}" -d bench -c "ANALYZE" -c "VACUUM ticket_a, ticket_b, ticket_b2"
echo "table heap indexes"
"${P[@]}" -d bench -At -F' ' -c "SELECT relname, pg_size_pretty(pg_relation_size(oid)), pg_size_pretty(pg_indexes_size(oid)) FROM pg_class WHERE relname LIKE 'ticket_%' AND relkind='r' ORDER BY 1"
for v in a b b2; do for q in map del; do
    s=$(now); "${P[@]}" -d bench -At -f "$D/q${v}_$q.sql" > /dev/null 2>&1
    echo "$v $q: $(echo "($(now) - $s)*1000/300" | bc -l | cut -c1-6) ms per query"
done; done
