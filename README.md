# Cinema Booking Database

[![tests](https://github.com/SirapraphatS/cinema-booking-db/actions/workflows/test.yml/badge.svg)](https://github.com/SirapraphatS/cinema-booking-db/actions/workflows/test.yml)
![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

A cinema booking database for PostgreSQL. Stored procedures enforce the business rules (seat holds, payment, coupons, Monthly Pass, loyalty points) inside the database, and automated tests check them.

## Table of contents

- [About](#about)
- [Features](#features)
- [Two stages: design on MySQL, implementation on PostgreSQL](#two-stages-design-on-mysql-implementation-on-postgresql)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Data model](#data-model)
- [The five flows](#the-five-flows)
- [Business rules](#business-rules)
- [Tests](#tests)
- [Challenges and what we learned](#challenges-and-what-we-learned)
- [Limits and roadmap](#limits-and-roadmap)
- [Diagrams](#diagrams)
- [Project structure](#project-structure)
- [More documentation](#more-documentation)
- [Credits and license](#credits-and-license)

## About

It is a 57-table relational design for a cinema chain (movies, branches, theatres, showtimes, seats, ticket prices, members, coupons, bookings, payments, points, food) plus the procedures that make bookings safe.

The design began as a group project for a university database-systems course. We first built and tested it as a working MySQL database with sample data and queries, run in phpMyAdmin (see [`design-mysql/`](design-mysql/)). That showed the structure holds together. It did not show what happens when two people try to buy the same seat, when points could go negative, or when a booking fails half-way and leaves junk behind, so we implemented the rules in PostgreSQL and tested them.

One place now enforces the rules for every client (app, script, future API), multi-row operations are all-or-nothing, and races are closed next to the data. The behaviour is written as `PASS`/`FAIL` checks that run in CI, a race test sends simultaneous sessions at one seat, and the main design decisions (database choice, composite versus surrogate keys, indexing) come with measurements.

## Features

- Hold seats for 15 minutes without ever selling a seat twice
- Pay with a coupon (percent, amount or fixed price; date, branch and usage-limit checks) or a Monthly Pass
- Earn loyalty points on tickets (1 point per baht paid, 12-month expiry) and redeem them for rewards
  without the balance going negative
- Automatic release of expired holds, and cancellation of pending bookings
- Guest bookings (no account) and food items on the same booking
- Reproducible time: every procedure takes the clock as a parameter

## Two stages: design on MySQL, implementation on PostgreSQL

![From coursework to implementation: stage 1 on MySQL, the gap, stage 2 on PostgreSQL](docs/diagrams/01-two-stages.png)

| | Stage 1: design | Stage 2: implementation |
|---|---|---|
| Folder | [`design-mysql/`](design-mysql/) | [`sql/`](sql/) |
| Engine | MySQL / MariaDB (XAMPP or MAMP + phpMyAdmin) | PostgreSQL 16 |
| Contains | 57-table schema, sample data, example queries, practice questions | schema, sample data, stored procedures, tests, race test, CI |
| Business rules | not enforced by the database | enforced inside the database |
| Run it | import `design-mysql/02_import_all_in_one.sql` in phpMyAdmin | `make test` (see Quick start) |

The tables are the same in both stages, plus generated ids, an `app_config` table and indexes in stage 2. [docs/project-story.md](docs/project-story.md) tells the whole path: the course toolbox and its limits, why each table exists, and why we implemented. [docs/why-postgresql.md](docs/why-postgresql.md) explains the move to PostgreSQL, and [design-mysql/README.md](design-mysql/README.md) covers stage 1 setup.

## Quick start

Needs Docker and the `psql` client.

```bash
git clone https://github.com/SirapraphatS/cinema-booking-db.git
cd cinema-booking-db
make test    # starts PostgreSQL 16, rebuilds the database, runs the tests
```

Other commands: `make race` (10 sessions fight for one seat), `make up` / `make down`.
Without Docker, point the scripts at any PostgreSQL 16 server:

```bash
PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=secret scripts/run-tests.sh
```

or load `sql/01_schema.sql`, `02_sample_data.sql`, `03_booking_procedures.sql` (then `sql/tests/booking_tests.sql` on a fresh database) with
`psql -f`. Docker connection used by `make`: `localhost:5433`, user `postgres`, password `dev`,
database `cinema_booking`. The password is for local development only.

## Usage

Every procedure takes the current time as `p_now`, so behaviour is deterministic and testable; a real
application passes `now()`. The sample showtimes are dated 2026-11-05, so the examples use a fixed
clock shortly before them. OUT values are `INOUT` parameters: pass `NULL`, the result comes back as a row.

```sql
-- hold seat 4 for customer 1 at the 14:00 show of theatre 1, branch 1
CALL sp_hold_seats(1, NULL, 1, 1, '2026-11-05', '14:00', ARRAY[4], '2026-11-05 13:01:00', NULL);
--  p_booking_id
-- --------------
--             8

-- pay it as member 2 with coupon CARD50 (50% off the ticket)
CALL sp_pay_booking(8, 2, 'CARD50', 'PromptPay', '2026-11-05 13:03:00', NULL, NULL);
--  p_payment_id | p_amount
-- --------------+----------
--             7 |   120.00

-- spend 100 points on reward 1 at branch 1
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:00:00', NULL);
```

A second customer trying seat 4 for the same show gets `Seat already taken for this showtime`.

## Data model

57 tables in four zones: movies, locations/showtimes/prices, customers/members/promotions, and
bookings/tickets/payments/points/food (plus `app_config` for the rule constants). The booking core:

![The booking core of the data model: entities coloured by zone, with 1 / M cardinalities](docs/diagrams/03-booking-core-er.png)

Design points worth knowing:

* `ticket` has a 5-column primary key (branch, theatre, showtime date, showtime time, seat), so the
  same seat in the same showtime can never be sold twice, and the database enforces that itself.
* A held seat is simply a `ticket` row of a `PENDING` booking with an expiry time.
* Prices come from `ticket_price` by branch + theatre type + seat type + dimension + price period
  + date range; the price paid is copied into `ticket.ticket_sale_price` at sale time.
* Loyalty points are a ledger (`EARN` positive, `REDEEM` negative); the balance is the sum, never
  stored twice.

## The five flows

| Flow | Procedure | What it does |
|---|---|---|
| Hold seats | `sp_hold_seats` | Validates showtime and seats, creates a `PENDING` booking (15 min hold), looks up prices, all-or-nothing |
| Pay | `sp_pay_booking` | Checks member, coupon or Monthly Pass; writes the payment, marks the booking `PAID`, earns points |
| Redeem points | `sp_redeem_reward` | Spends points on a branch reward; the balance can never go negative |
| Free expired holds | `sp_release_expired` | Deletes tickets of `PENDING` bookings past their expiry, marks them `EXPIRED` |
| Cancel | `sp_cancel_booking` | Cancels a `PENDING` booking and frees its seats |

Helpers: `fn_ticket_price`, `fn_discounted_price`, `fn_point_balance`, `fn_showtime_start`, `fn_config`.

## Business rules

Constants live in the `app_config` table.

* A hold lasts `HOLD_MINUTES` = 15.
* 1 point per baht actually paid on tickets after the coupon (food does not earn points); points
  expire after 12 months.
* One coupon per payment; it only reduces ticket prices (food is paid in full).
* Monthly Pass: one ticket per booking, once per movie; Normal 2D seats are free, other seats pay only the
  difference to the Normal 2D price; country and genre exclusions come from `member_type_condition`.
* Showtimes starting before 04:00 belong to the previous business day.

## Tests

`sql/tests/booking_tests.sql` prints one `PASS`/`FAIL` line per check and exits non-zero on any failure:

```
PASS price: Normal seat, Thursday 2D = 240
PASS hold: a seat held by another unexpired booking is refused
PASS hold: one bad seat rejects the whole request
PASS pay: coupon reduces tickets only (240 - 20 + 125 food = 345)
PASS coupon: usage limit reached
PASS redeem: the balance never goes negative (50 left, cost 100)
PASS Monthly Pass: the same movie cannot be watched twice
...
71 passed, 0 failed
```

It covers price lookup, double-selling a seat, atomic rollback of a half-failed request, hold expiry
and cancellation, coupon rules (unknown, expired, wrong branch, usage limit), member checks, points
earned and redeemed, Monthly Pass rules, guests and food. `scripts/run-race-test.sh` starts N
simultaneous sessions on one seat and checks for exactly one winner. Both run in GitHub Actions on
every push.

## Challenges and what we learned

* Races: check-then-act logic fails when two sessions run at once. A constraint (the `ticket` key) plus row locks (`FOR UPDATE`) fix it, and the race test checks it.
* Atomicity and errors: PostgreSQL procedures run in the caller's transaction, and an exception undoes the call. A sub-transaction (`BEGIN ... EXCEPTION`) turns a duplicate-key error into a clear message. We first built the same logic on MySQL 8 and chose PostgreSQL for this and other reasons, listed in [docs/why-postgresql.md](docs/why-postgresql.md).
* Indexing: PostgreSQL does not index foreign keys automatically. A catalog query found the missing ones, and we added them (a test now fails if one is missing).
* Composite keys versus a surrogate id: we measured both on 2.8 million tickets. An id shrinks the indexes a lot, the hot queries run equally fast, and a bare id would lose a guarantee the composite key gives for free. Details in [benchmarks/](benchmarks/ticket-key-design/README.md).
* Testing time: passing the clock as a parameter made expiry and validity windows testable.

## Limits and roadmap

Known limits:

* Points are a ledger, not first-in-first-out lots: a redemption never uses up a specific earned batch.
* Monthly Pass `MIN_GAP_MINUTES` (shows at least 2 hours apart) is stored in the data but not enforced.
* A showtime that already has tickets cannot be rescheduled (its date and time are part of its key).
* There is no application or API layer, only the database.

Ideas for next steps:

* Prevent overlapping showtimes in one theatre with an exclusion constraint
* Give an application role `EXECUTE` on the procedures only (no direct table writes)
* Schedule `sp_release_expired` with `pg_cron`
* Allow rescheduling with `ON UPDATE CASCADE` or a `showtime_id`

## Diagrams

The pictures in this repository were drawn in [Excalidraw](https://excalidraw.com). Each PNG in
[docs/diagrams/](docs/diagrams/) has an editable `.excalidraw` file next to it: open it on
excalidraw.com (File > Open) to change it.

## Project structure

```
design-mysql/
  README.md                     stage 1: how to run the MySQL course design (XAMPP / phpMyAdmin)
  01_schema_design.sql          the 57 tables as designed
  02_import_all_in_one.sql      database + tables + sample data in one file for phpMyAdmin
  03_example_queries.sql        example queries
  04_practice_questions.sql     practice questions
  reset.sql                     drop all tables
sql/
  01_schema.sql                 57 tables + app_config + indexes
  02_sample_data.sql            fictional sample data
  03_booking_procedures.sql     the five flows and their helper functions
  tests/booking_tests.sql       the checks
scripts/
  run-tests.sh                  rebuild the database and run the tests
  run-race-test.sh              simultaneous sessions fight for one seat
benchmarks/ticket-key-design/   composite key vs surrogate id, measured on 2.8 M tickets
docs/diagrams/                  the pictures used in the docs (PNG + editable .excalidraw)
docs/                           project-story.md, why-postgresql.md, procedure-walkthrough.md, design-decisions.md
docker-compose.yml, Makefile, .github/workflows/test.yml
```

## More documentation

- [design-mysql/README.md](design-mysql/README.md): stage 1, the MySQL course design, and how to run it on XAMPP
- [docs/project-story.md](docs/project-story.md): the project from coursework to implementation, told as scenes
- [docs/why-postgresql.md](docs/why-postgresql.md): advantages of database-side rules, and why PostgreSQL
- [docs/procedure-walkthrough.md](docs/procedure-walkthrough.md): how each procedure works and why
- [docs/design-decisions.md](docs/design-decisions.md): schema differences, locks, trade-offs, known limits

## Credits and license

Group project for a university database-systems course; the implementation, tests and documentation
were extended by [@SirapraphatS](https://github.com/SirapraphatS). Movie and people data are
fictional. This is a portfolio project and is not open for contributions.

Released under the MIT License, see [LICENSE](LICENSE).
