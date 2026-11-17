# Why the rules live in the database, and why PostgreSQL

The project has two stages ([project-story.md](project-story.md) tells the full path):

| Stage | Engine | Where |
|---|---|---|
| 1. Design: the 57-table design, sample data and queries from the database course | MySQL / MariaDB through phpMyAdmin on XAMPP (the stack taught in the course; MAMP is the macOS equivalent) | [`design-mysql/`](../design-mysql/) |
| 2. Implementation: the booking rules as stored procedures, tests and CI | PostgreSQL 16 | `sql/`, `scripts/` |

## A. Advantages of putting the rules in the database

1. One place enforces the rules for every client. The web app, an admin script and a future API all call the same `sp_hold_seats` and `sp_pay_booking`, so a bug in one client cannot sell a seat twice or spend points that do not exist.
2. Multi-step operations are atomic. Holding three seats, or paying (payment, booking status and points), either all happens or none of it does. The test `hold: one bad seat rejects the whole request` covers it.
3. Races are closed where they happen. The primary key of `ticket` and row locks (`FOR UPDATE` on booking, discount and member) sit next to the data, so two sessions cannot both pass a check-then-act test. `scripts/run-race-test.sh` runs simultaneous sessions to confirm it.
4. There are fewer round trips. One `CALL` replaces a dozen queries from the application, and other sessions never see a half-finished state.
5. The behaviour can be tested in plain SQL. 68 `PASS`/`FAIL` lines (`sql/tests/booking_tests.sql`) run in CI on every push without any application.
6. Time is reproducible. Every procedure takes the clock as `p_now`, so expiry, validity windows and "showtime already started" are deterministic in tests.
7. Privileges can be narrow. An application role can get `EXECUTE` on the procedures and no direct `INSERT` or `UPDATE` on `ticket`, `payment` or `point_log`, so even a compromised application cannot write inconsistent rows.

The costs:

* SQL logic is harder to version, review and debug than application code, and it needs its own deployment step (`03_booking_procedures.sql`).
* It uses the database server's CPU, which is harder to scale out than application servers.
* Rules end up split between the application and the database. We keep invariants in the database (no double sale, no negative points, one coupon per payment) and leave presentation and workflow to the application.
* It ties the rules to one engine (see section C).

## B. Why PostgreSQL for the implementation

We first wrote the logic for both MySQL 8 and PostgreSQL 16 with identical tests, then dropped the MySQL version before creating this repository. These are the differences that showed up:

| What we hit | MySQL 8 | PostgreSQL 16 |
|---|---|---|
| Transactions in procedures | a procedure had to own `START TRANSACTION` and `COMMIT`, which commits and breaks a caller's open transaction | runs in the caller's transaction; any exception undoes the whole call |
| Translating a duplicate-key error | `DECLARE EXIT HANDLER FOR 1062` plus a manual `ROLLBACK` | `BEGIN ... EXCEPTION WHEN unique_violation THEN RAISE ...` inside the procedure, earlier work intact |
| Race test (one seat, 10 to 12 sessions) | one winner every time, but in two of three runs one session of 12 got `ERROR 1213 deadlock found` instead of "seat taken" and had to retry | one winner, and every loser got `Seat already taken`, in every run |
| Reading a generated id | `LAST_INSERT_ID()` | `INSERT ... RETURNING ... INTO` in the same statement |
| Returning values from a procedure | `OUT` parameter and a session variable (`@booking`) | `INOUT` parameter; `CALL` returns a row |
| Splitting `'5,6'`, date arithmetic | `SUBSTRING_INDEX` loop, `INTERVAL ... MINUTE` | `string_to_array` with `FOREACH`, `make_interval` |
| Time zones and range | `TIMESTAMP` converts through the session time zone and ends in 2038, so we needed `DATETIME` | `TIMESTAMP` works |
| Wide primary keys (benchmark) | the clustered primary key is repeated in every secondary index: 106 MB with the 5-column key against 68 MB with an id | heap tables, so only the primary-key index grows: 164 MB against 59 MB |

PostgreSQL was less convenient in three places:

* It does not index foreign keys automatically, so `sql/01_schema.sql` carries 54 explicit indexes (MySQL creates them itself).
* `CALL` does not accept a subquery argument, so the test helpers are functions called with `PERFORM`.
* An exception undoes everything the call did, so "release the seats, then report the expired payment" cannot happen in one call (see `design-decisions.md`).

PostgreSQL also offers features we have not used yet:

* `CHECK` and exclusion constraints, for example making overlapping showtimes in one theatre impossible with `EXCLUDE USING gist` over a time range instead of relying on the application.
* Transactional DDL, so a schema migration applies fully or not at all.
* Deferrable constraints, partial and expression indexes, `SELECT ... FOR UPDATE SKIP LOCKED` for queue-style sweeps, extended statistics for correlated columns (branch and theatre), and row-level security.

## C. When MySQL is still a good choice

MySQL fits when an organisation already runs it, hosting only offers it, or the workload is read-heavy CRUD with little logic in the database. The course used it too: stage 1 runs on MySQL through phpMyAdmin on XAMPP ([`design-mysql/`](../design-mysql/)), which is the easiest way to explore a schema and run course queries. We moved only the implementation to PostgreSQL, where transactions, locking and error handling matter.
