# Benchmark: composite key vs surrogate `showtime_id` for `ticket`

The implementation of this project uses PostgreSQL only. We measured the MySQL numbers below before dropping the MySQL port and kept them to show how InnoDB (clustered primary key) behaves differently. `run-benchmark-mysql.sh` is still here so they can be reproduced.

The question: if the 5-column primary key of `ticket` `(branch_id, theatre_id, showtime_date, showtime_time, seat_id)` is replaced by a `showtime_id`, do size or speed change?

| Variant | `ticket` columns | Primary key |
|---|---|---|
| A composite (current design) | branch, theatre, date, time, seat, booking | all five key columns |
| B lean surrogate | showtime_id, seat, booking | `(showtime_id, seat_id)` |
| B2 surrogate + integrity columns | showtime_id, branch, theatre, seat, booking | `(showtime_id, seat_id)` |

B2 keeps `branch_id`/`theatre_id` in the row because the current design guarantees, through the
shared key columns, that a ticket's seat belongs to the theatre of its showtime. With a bare
`showtime_id` (B) the database can no longer enforce that (see `docs/design-decisions.md`).

Data: 2.8 million tickets in 1.17 million bookings, 20,000 showtimes (20 theatres x 250 days x 4),
200 seats per theatre, 70% sold. Every variant also has a secondary index on `booking_id`
(the foreign-key index used by cancel/expire).

```bash
python3 generate-data.py /tmp/bench-data
MYSQL_USER=root MYSQL_PWD=... ./run-benchmark-mysql.sh /tmp/bench-data       # needs local_infile=1
PGUSER=postgres PGPASSWORD=... ./run-benchmark-postgres.sh /tmp/bench-data
```

## Results (MySQL 8.0.46 and PostgreSQL 16.15, one small cloud VM, buffer pool/cache warm)

Sizes were stable between runs.

| | A composite | B lean | B2 integrity |
|---|---|---|---|
| MySQL table data (clustered) | 234 MB | 169 MB | 213 MB |
| MySQL secondary indexes | 106 MB | 68 MB | 68 MB |
| PostgreSQL heap | 161 MB | 118 MB | 139 MB |
| PostgreSQL primary-key index | 164 MB | 59 MB | 59 MB |
| PostgreSQL all indexes (PK + booking_id) | 210 MB | 104 MB | 104 MB |
| bulk load, MySQL / PostgreSQL | 20 s / 6 s | 15 s / 4 s | 16 s / 5 s |

Latency per query (300 queries each, one client, average of two runs; the run-to-run spread was
about +-0.1 ms, larger than any difference between variants):

| Query | A | B | B2 |
|---|---|---|---|
| seat map of one showtime, MySQL | ~0.3 ms | ~0.23 ms | ~0.23 ms |
| seat map of one showtime, PostgreSQL | ~0.24 ms | ~0.25 ms | ~0.2 ms |
| delete tickets of one booking, MySQL | ~0.8 ms | ~0.9 ms | ~1.0 ms |
| delete tickets of one booking, PostgreSQL | ~0.44 ms | ~0.41 ms | ~0.37 ms |

## What it shows

* Size: a surrogate id shrinks the primary-key index by about 64% on PostgreSQL and the secondary indexes by about 36% on MySQL (InnoDB repeats the primary key in every secondary index). Variant B2 gives back part of the table-size saving because the extra columns stay.
* Speed: no consistent difference for the two hot queries. The composite key already makes the seat map a short range scan on the key prefix, so it is as fast as the id version.
* Not measured: a cold cache (data larger than memory), concurrent load, writes under contention, and planner behaviour in multi-way joins. At this size everything fits in memory.
