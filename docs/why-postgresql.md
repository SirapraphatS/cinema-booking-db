# Why the rules live in the database, and why PostgreSQL

This project has two stages:

| Stage | Engine | Where |
|---|---|---|
| **1. Design**: the 57-table design, sample data and queries from the database course | MySQL / MariaDB, used through phpMyAdmin on XAMPP (the stack taught in the course; MAMP is the macOS equivalent) | [`design-mysql/`](../design-mysql/) |
| **2. Implementation**: the booking rules as stored procedures, tests, CI | PostgreSQL 16 | `sql/`, `scripts/` |

## A. Advantages of implementing the rules in the database

1. **One place enforces the rules for every client.** The web app, an admin script and a future
   API all go through the same `sp_hold_seats` / `sp_pay_booking`. A bug in one client cannot
   sell a seat twice or spend points it does not have.
2. **Atomic multi-step operations.** Holding three seats, writing the booking and the tickets, or
   paying (payment + booking status + points) either all happens or none of it does. The test
   `hold: one bad seat rejects the whole request` shows it.
3. **Races are closed where they happen.** The primary key of `ticket` and row locks
   (`FOR UPDATE` on booking, discount, member) sit next to the data, so two sessions cannot both
   pass a "check, then act" test. `scripts/run-race-test.sh` proves it with simultaneous sessions.
4. **Fewer round trips.** One `CALL` replaces a dozen queries from the application, and no
   half-finished state is visible to other sessions in between.
5. **Testable in plain SQL.** The behaviour is a specification of 68 `PASS`/`FAIL` lines
   (`sql/tests/booking_tests.sql`) that runs in CI on every push, with no application needed.
6. **Reproducible time.** Every procedure takes the clock as `p_now`, so expiry, validity windows
   and "showtime already started" can be tested deterministically.
7. **Least privilege is possible.** An application role can be given `EXECUTE` on the procedures
   and no direct `INSERT`/`UPDATE` on `ticket`, `payment` or `point_log`, so even a compromised
   application cannot write inconsistent rows.

Trade-offs to be honest about:

* Logic in SQL is harder to version, review and debug than application code, and needs its own
  deployment step (`03_booking_procedures.sql`).
* It uses the database server's CPU, which is harder to scale out than application servers.
* Business rules end up split between application and database; the rule of thumb here is that the
  database owns **invariants** (no double sale, no negative points, one coupon per payment) and the
  application owns presentation and workflow.
* It ties the rules to one engine (see C).

## B. Why PostgreSQL for the implementation

The logic was first written for both MySQL 8 and PostgreSQL 16 with identical tests (the MySQL version of the logic was dropped before this repository was created). These are the differences that actually showed up:

| What we hit | MySQL 8 | PostgreSQL 16 |
|---|---|---|
| **Transactions in procedures** | a procedure had to own `START TRANSACTION` / `COMMIT`, which commits and breaks a caller's open transaction | runs in the caller's transaction; any exception undoes the whole call |
| **Translating a duplicate-key error** | `DECLARE EXIT HANDLER FOR 1062` plus a manual `ROLLBACK` | `BEGIN ... EXCEPTION WHEN unique_violation THEN RAISE ...` inside the procedure, earlier work intact |
| **Race test (one seat, 10-12 sessions)** | one winner every time, but occasionally one loser got `ERROR 1213 deadlock found` instead of "seat taken" (1 session of 12 in two of three runs) and must retry | one winner, every loser got `Seat already taken`, in every run |
| **Reading a generated id** | `LAST_INSERT_ID()` | `INSERT ... RETURNING ... INTO` in the same statement |
| **Returning values from a procedure** | `OUT` parameter and a session variable (`@booking`) | `INOUT` parameter, `CALL` returns a row |
| **Splitting `'5,6'`, date arithmetic** | `SUBSTRING_INDEX` loop, `INTERVAL ... MINUTE` | `string_to_array` + `FOREACH`, `make_interval` |
| **Time zones and range** | `TIMESTAMP` converts through the session time zone and ends in 2038, so `DATETIME` was needed | `TIMESTAMP` is fine |
| **Wide primary keys** (benchmark) | the clustered PK is repeated in every secondary index: 106 MB with the 5-column key vs 68 MB with an id | heap tables: only the PK index itself is larger (164 MB vs 59 MB) |

Where PostgreSQL was the less convenient one:

* It does **not** index foreign keys automatically, so `sql/01_schema.sql` carries 54 explicit
  indexes (MySQL creates them itself).
* `CALL` does not accept a subquery argument, so the test helpers are functions called with
  `PERFORM` instead of procedures.
* An exception undoes everything the call did, so "release the seats and then report the expired
  payment" cannot be done in one call (see `design-decisions.md`).

Things PostgreSQL offers that the project could use next (not used yet):

* `CHECK` constraints and **exclusion constraints**: for example make overlapping showtimes in one
  theatre impossible with `EXCLUDE USING gist` over a time range, instead of relying on the app.
* **Transactional DDL**: a schema migration either fully applies or not at all.
* **Deferrable constraints**, partial and expression indexes, `SELECT ... FOR UPDATE SKIP LOCKED`
  for job-queue style sweeps, extended statistics for correlated columns (branch + theatre), and
  row-level security.

## C. When MySQL is still the right choice

MySQL is a good fit when an organisation already runs it, hosting only offers it, or the workload
is plain read-heavy CRUD without much logic in the database. It is also what the course used: stage 1
runs on MySQL through phpMyAdmin on XAMPP ([`design-mysql/`](../design-mysql/)), which is the easiest
way to explore a schema and run course queries. Only the implementation work, where transactions,
locking and error handling matter, uses PostgreSQL.
