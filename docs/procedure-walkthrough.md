# Walkthrough: how the booking logic works

A guided tour of `sql/03_booking_procedures.sql`. Load a database first
(`make up`, or load `01_schema.sql`, `02_sample_data.sql`, `03_booking_procedures.sql` by hand with `psql -f`) so you can try every step.
The sample showtimes are on 2026-11-05, so the examples use a clock just before them.

## 0. The shape of every procedure

```
validate inputs  ->  lock what must not change  ->  write rows  ->  commit (or undo everything)
```

Business rules live in one place (`app_config`), and every procedure receives `p_now`, so you
can replay any moment in time.

```sql
SELECT * FROM app_config;   -- HOLD_MINUTES 15, POINTS_PER_BAHT 1, ...
```

## 1. `sp_hold_seats`: hold seats

1. Release expired holds first. A lapsed hold must never block a seat.
2. Validate the showtime: it exists, its status is `OPEN`, and it has not started
   (`fn_showtime_start` handles the 04:00 business-day cutoff: the `00:30` show of business date
   11-05 really starts on 11-06).
3. Insert the booking as `PENDING` with `expire = p_now + 15 minutes`; the booking code
   (`BK0008`) is derived from the generated id.
4. Insert one `ticket` per seat. The price comes from `fn_ticket_price`: join showtime ->
   theatre -> seat -> `ticket_price` on (branch, theatre type, seat type, dimension, price
   period, date range).
5. The primary key of `ticket` rejects a seat that is already held or sold. The procedure
   catches that duplicate-key error and re-raises it as `Seat already taken for this showtime`.

All-or-nothing: `'7,1'` fails on seat 1 (removed) and seat 7 is *not* left held.

Try it:

```sql
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','14:00','4','2026-11-05 13:01:00', NULL);  -- returns the booking id
CALL sp_hold_seats(2, NULL, 1,1,'2026-11-05','14:00','4','2026-11-05 13:02:00', NULL);  -- error: seat taken
```

Concepts: composite primary key as a business rule, transactions, deriving values from
generated ids.

## 2. `sp_pay_booking`: pay, coupon, Monthly Pass, points

In order:

1. `SELECT ... FOR UPDATE` on the booking: two payments of the same booking serialise, and the
   second sees `PAID` (`Booking is already paid`).
2. Refuse a booking that is not `PENDING` or whose hold has run out (`Hold has expired`).
3. Member checks: membership active on `p_now`, and the member belongs to the booking's
   customer (you cannot earn points on someone else's booking).
4. Monthly Pass (`p_method = 'Monthly Pass'`): exactly one ticket, once per movie, movie not excluded
   (country / genre from `member_type_condition`). Normal 2D seat -> ticket price 0; other seat
   types pay only the difference to the Normal 2D price. A row goes into `monthly_pass_usage`.
5. Coupon: code exists, valid on `p_now`, valid at every ticket's branch (`discount_branch`),
   usage limit not reached (the discount row is locked while counting). `PERCENT`, `AMOUNT` or
   `FIXED_PRICE` is applied to tickets only.
6. Amount = tickets after coupon + food (`booking_product`). Insert `payment`, set booking `PAID`.
7. Points = `FLOOR(ticket amount x POINTS_PER_BAHT)`, only for members, written as an
   `EARN` ledger row that expires in 12 months.

Check against the sample data: booking 2 has a 780 ticket and a 50% coupon -> 390 points. That
is why the rule is 1 point per baht paid.

Concepts: row locks, validation order (cheap checks first), money arithmetic with `DECIMAL`,
a ledger instead of a stored balance.

## 3. `sp_redeem_reward`: spend points

Lock the member row, read the reward's cost for that branch (`branch_reward`), compare with
`fn_point_balance`, then insert a negative `REDEEM` row.

```sql
SELECT fn_point_balance(2, '2026-11-06');           -- 390 earned - 100 redeemed = 290
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:00:00', NULL);
```

The lock is the important line: without it, two simultaneous redemptions could both read
"enough points" and both succeed.

Concepts: check-then-act races and how a row lock closes them.

## 4. `sp_release_expired` and `sp_cancel_booking`

* `sp_release_expired(p_now)`: delete the tickets of `PENDING` bookings whose expiry has passed
  and mark them `EXPIRED`. Run it from a scheduler (cron or `pg_cron`) or rely on
  `sp_hold_seats`, which calls it first.
* `sp_cancel_booking(id)`: only a `PENDING` booking can be cancelled; its tickets are deleted
  so the seats are free immediately. Paid bookings are never cancelled here.

## 5. PostgreSQL features used (and where)

| Feature | Where | Why |
|---|---|---|
| `CREATE PROCEDURE` / `CREATE FUNCTION` in PL/pgSQL | all of `03_booking_procedures.sql` | rules live next to the data |
| `RAISE EXCEPTION` | every validation | one clear message, the whole call is undone |
| `BEGIN ... EXCEPTION WHEN unique_violation` | `sp_hold_seats` | turns a duplicate-key error into `Seat already taken` without losing the earlier work |
| `INOUT` parameters and `CALL` returning a row | `sp_hold_seats`, `sp_pay_booking`, `sp_redeem_reward` | hand back the new ids and the amount |
| `INSERT ... RETURNING ... INTO` | booking, payment, point_log | read the generated id in the same statement |
| `GENERATED BY DEFAULT AS IDENTITY` | `01_schema.sql` | ids that cannot collide |
| `SELECT ... FOR UPDATE` | pay, cancel, redeem | row locks that close check-then-act races |
| `make_interval`, `string_to_array` + `FOREACH` | hold expiry, seat list | date arithmetic and splitting `'5,6'` |
| Tests as functions called with `PERFORM` | `booking_tests.sql` | `CALL` does not accept a subquery argument |

See `docs/why-postgresql.md` for the reasoning.

## 6. Read the tests like a spec

`booking_tests.sql` doubles as documentation of the behaviour: each line is a rule, written as an
assertion. Run it and read the output:

```
PASS hold: one bad seat rejects the whole request
PASS coupon: usage limit reached
PASS redeem: the balance never goes negative (50 left, cost 100)
```
