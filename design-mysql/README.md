# Stage 1: the course design on MySQL

This folder is the first stage of the project: the 57-table cinema booking design, built and tested as a working database for a university database-systems course. It runs on MySQL or MariaDB through phpMyAdmin. The course used XAMPP, and MAMP is the macOS equivalent. It holds the schema, fictional sample data (209 rows) and the course queries. It has no stored logic: stage 2 (`../sql/`, PostgreSQL) added the booking rules, tests and CI.

| File | Purpose |
|---|---|
| `01_schema_design.sql` | the 57 tables as designed (original column types), for an empty database |
| `02_import_all_in_one.sql` | everything in one file: creates database `cinema_booking`, the 57 tables and the sample data (simplified types) |
| `03_example_queries.sql` | example queries: statistics, joins, price checks |
| `04_practice_questions.sql` | practice questions, most with a basic and an advanced version |
| `reset.sql` | drops all 57 tables so you can import again |

## Run it

Start Apache and MySQL in XAMPP (or MAMP), open phpMyAdmin, then:

1. Import tab > choose `02_import_all_in_one.sql` > Go
2. Select the `cinema_booking` database on the left
3. SQL tab > paste a query from `03_example_queries.sql` or `04_practice_questions.sql` > Go

| Stack | Platform | phpMyAdmin address |
|---|---|---|
| XAMPP | Windows / Linux (also macOS) | `http://localhost/phpmyadmin` |
| MAMP | macOS | `http://localhost:8888/phpMyAdmin` (or the Apache port you configured, e.g. 8889) |

MAMP-only tip: if phpMyAdmin shows *Internal Server Error*, switch MAMP's PHP version in its
preferences (7.4.33 worked here).

## Compatibility

XAMPP's database (labelled *MySQL* in its control panel) is MariaDB. Tested on MariaDB 10.11:
`02_import_all_in_one.sql` creates 57 tables and the sample rows (7 bookings, 4 customers);
`01_schema_design.sql` creates the 57 tables in an empty database; both query files run with no
errors; `reset.sql` followed by the import rebuilds everything. Nothing here needs MySQL 8
features: no stored routines, triggers, views or window functions. Importing the same file in
phpMyAdmin on MAMP (MySQL) also worked.

If the tables already exist, run `reset.sql` first. `02_import_all_in_one.sql` contains the data
already, so do not load it together with another file that inserts the same rows (duplicate-key errors).

## What this stage shows

The structure holds together: keys, relationships, price lookup, membership and points data, and plain SQL answers useful questions. This stage says nothing about what happens when two customers book the same seat at once or when a booking fails half-way. Stage 2 implements and tests that in PostgreSQL.
