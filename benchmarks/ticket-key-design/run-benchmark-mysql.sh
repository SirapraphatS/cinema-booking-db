#!/usr/bin/env bash
# requires SET GLOBAL local_infile=1 on the server
# create tables A, B, B2; load the CSV files from DATA_DIR (first argument)
# print table and index sizes, then the average time of 300 seat-map and 300 delete queries
set -euo pipefail
D="$(cd "${1:?usage: run-benchmark-mysql.sh DATA_DIR}" && pwd)"
: "${MYSQL_HOST:=127.0.0.1}" "${MYSQL_PORT:=3306}" "${MYSQL_USER:=root}"
export MYSQL_PWD="${MYSQL_PWD:-}"
M=(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" --local-infile=1)

"${M[@]}" -e "DROP DATABASE IF EXISTS bench; CREATE DATABASE bench" 2>/dev/null
"${M[@]}" bench 2>/dev/null <<'SQL'
CREATE TABLE ticket_a (branch_id INT NOT NULL, theatre_id INT NOT NULL, showtime_date DATE NOT NULL, showtime_time TIME NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (branch_id, theatre_id, showtime_date, showtime_time, seat_id), KEY idx_booking (booking_id));
CREATE TABLE ticket_b (showtime_id INT NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (showtime_id, seat_id), KEY idx_booking (booking_id));
CREATE TABLE ticket_b2 (showtime_id INT NOT NULL, branch_id INT NOT NULL, theatre_id INT NOT NULL, seat_id INT NOT NULL, booking_id INT NOT NULL, PRIMARY KEY (showtime_id, seat_id), KEY idx_booking (booking_id));
SQL
now() { date +%s.%N; }
for v in a b b2; do
    f=$(echo "$v" | tr a-z A-Z); s=$(now)
    "${M[@]}" bench -e "LOAD DATA LOCAL INFILE '$D/$f.csv' INTO TABLE ticket_$v FIELDS TERMINATED BY ','" 2>/dev/null
    echo "load $v: $(echo "$(now) - $s" | bc) s"
done
"${M[@]}" bench -e "ANALYZE TABLE ticket_a, ticket_b, ticket_b2" >/dev/null 2>&1
echo "table data_MB index_MB"
"${M[@]}" bench -N -e "SELECT table_name, ROUND(data_length/1048576,1), ROUND(index_length/1048576,1) FROM information_schema.tables WHERE table_schema='bench'" 2>/dev/null
for v in a b b2; do for q in map del; do
    s=$(now); "${M[@]}" bench -N < "$D/q${v}_$q.sql" > /dev/null 2>&1
    echo "$v $q: $(echo "($(now) - $s)*1000/300" | bc -l | cut -c1-6) ms per query"
done; done
