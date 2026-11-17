#!/usr/bin/env bash
# rebuild the database from sql/01..03 (no tests)
# start N sessions at once, each calling sp_hold_seats for the same seat
# pass only if: 1 session succeeds, N-1 get 'Seat already taken', 1 ticket row exists
# usage: scripts/run-race-test.sh [N]
set -uo pipefail
cd "$(dirname "$0")/.."
n="${1:-10}"
: "${PGHOST:=127.0.0.1}" "${PGPORT:=5432}" "${PGUSER:=postgres}" "${DB:=cinema_booking}"
export PGHOST PGPORT PGUSER
out="$(mktemp -d)"

psql -q -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
for f in sql/0*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" > /dev/null; done

attempt() {
    psql -q -A -t -d "$DB" -c "CALL sp_hold_seats(NULL, '0800000099', 1,1,'2026-11-05','14:00','4','2026-11-05 13:01:00', NULL)"
}
for i in $(seq 1 "$n"); do attempt > "$out/$i.out" 2>&1 & done
wait

winners=$(grep -L "ERROR" "$out"/*.out | wc -l)
taken=$(grep -l "Seat already taken" "$out"/*.out | wc -l)
tickets=$(psql -q -A -t -d "$DB" -c "SELECT COUNT(*) FROM ticket WHERE branch_id=1 AND theatre_id=1 AND showtime_date='2026-11-05' AND showtime_time='14:00' AND seat_id=4")
echo "sessions=$n winners=$winners seat-taken-errors=$taken ticket-rows=$tickets"
if [ "$winners" -eq 1 ] && [ "$tickets" -eq 1 ] && [ "$taken" -eq $((n - 1)) ]; then
    echo "PASS exactly one session got the seat"
else
    echo "FAIL"; grep -h ERROR "$out"/*.out | sort | uniq -c; exit 1
fi
