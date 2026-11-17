-- ============================================================================
-- 04_practice_questions.sql: answers to 14 everyday questions
-- Import 02_import_all_in_one.sql first. SQL used:
--   SELECT, FROM, WHERE (= <> > < >= <=, AND, OR, NOT, LIKE, IN, BETWEEN),
--   ORDER BY (ASC, DESC), INNER / LEFT JOIN ... ON, and the aggregates COUNT, SUM with GROUP BY.
-- Q2 version 2 uses IS NULL. Version 1 of Q2 and Q4 lists the rows; version 2 lets the database count or add them.
-- Values used below all exist in 02_import_all_in_one.sql:
--   A = 'movie A'   B = branch 1, theatre_id 1   C = '2026-11-05' at '14:00'
--   D, E, F = seat_id 2, 3, 4   today = '2026-11-05'   X, Y = 'person A'   Z = member_id 2   booking BK0007 (a guest booking)
-- Change the value inside a query to ask another question.
-- ============================================================================


-- ============================================================================
-- Q1) Which theatres show movie A, and at what time?
-- ============================================================================
SELECT branch.branch_name, theatre.theatre_name, showtime.showtime_date,
       showtime.showtime_time, showtime.showtime_end_time, language.language_name
FROM movie_name
INNER JOIN movie_version ON movie_name.movie_id = movie_version.movie_id
INNER JOIN language ON movie_version.audio_language_id = language.language_id
INNER JOIN showtime ON movie_version.movie_id = showtime.movie_id AND movie_version.audio_language_id = showtime.audio_language_id
INNER JOIN theatre ON showtime.theatre_id = theatre.theatre_id AND showtime.branch_id = theatre.branch_id
INNER JOIN branch ON theatre.branch_id = branch.branch_id
WHERE movie_name.movie_name = 'Movie A'
ORDER BY showtime.showtime_date ASC, showtime.showtime_time ASC;


-- ============================================================================
-- Q2) movie A at theatre B on date/time C: which seats are left?
-- Two versions:
--   Version 1 (taught only): list every ACTIVE seat with its ticket's booking_id.
--     NULL = no ticket = the seat is free; a number = the seat is already booked or held.
--   Version 2 (uses IS NULL, beyond the basic course material): the database keeps only the free seats.
-- ============================================================================
-- Q2 version 1: no IS NULL
SELECT seat.seat_id, seat.seat_row, seat.seat_number, seat_type.seat_type_name, ticket.booking_id
FROM showtime
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
INNER JOIN seat ON showtime.theatre_id = seat.theatre_id AND showtime.branch_id = seat.branch_id
INNER JOIN seat_type ON seat.seat_type_id = seat_type.seat_type_id
LEFT JOIN ticket ON seat.theatre_id = ticket.theatre_id AND seat.branch_id = ticket.branch_id AND seat.seat_id = ticket.seat_id
                AND showtime.showtime_date = ticket.showtime_date AND showtime.showtime_time = ticket.showtime_time
WHERE movie_name.movie_name = 'Movie A' AND showtime.branch_id = 1 AND showtime.theatre_id = 1
  AND showtime.showtime_date = '2026-11-05' AND showtime.showtime_time = '14:00'
  AND seat.seat_status = 'ACTIVE'
ORDER BY seat.seat_row ASC, seat.seat_number ASC;

-- Q2 version 2: with IS NULL
SELECT seat.seat_id, seat.seat_row, seat.seat_number, seat_type.seat_type_name
FROM showtime
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
INNER JOIN seat ON showtime.theatre_id = seat.theatre_id AND showtime.branch_id = seat.branch_id
INNER JOIN seat_type ON seat.seat_type_id = seat_type.seat_type_id
LEFT JOIN ticket ON seat.theatre_id = ticket.theatre_id AND seat.branch_id = ticket.branch_id AND seat.seat_id = ticket.seat_id
                AND showtime.showtime_date = ticket.showtime_date AND showtime.showtime_time = ticket.showtime_time
WHERE movie_name.movie_name = 'Movie A' AND showtime.branch_id = 1 AND showtime.theatre_id = 1
  AND showtime.showtime_date = '2026-11-05' AND showtime.showtime_time = '14:00'
  AND seat.seat_status = 'ACTIVE' AND ticket.booking_id IS NULL
ORDER BY seat.seat_row ASC, seat.seat_number ASC;


-- ============================================================================
-- Q3) movie A, theatre B, time C, seat D: how much is the price?
-- The price comes from ticket_price: same branch, theatre type, seat type and dimension, and the price period of the
-- showtime (showtime.price_period_id), with the show date between the start and end date of the price.
-- A seat that is already sold also has its price saved in ticket.ticket_sale_price.
-- ============================================================================
SELECT seat.seat_id, seat_type.seat_type_name, price_period.price_period_name, ticket_price.ticket_price_amount
FROM showtime
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
INNER JOIN theatre ON showtime.theatre_id = theatre.theatre_id AND showtime.branch_id = theatre.branch_id
INNER JOIN seat ON showtime.theatre_id = seat.theatre_id AND showtime.branch_id = seat.branch_id
INNER JOIN seat_type ON seat.seat_type_id = seat_type.seat_type_id
INNER JOIN price_period ON showtime.price_period_id = price_period.price_period_id
INNER JOIN ticket_price ON theatre.branch_id = ticket_price.branch_id
       AND theatre.theatre_type_id = ticket_price.theatre_type_id
       AND seat.seat_type_id = ticket_price.seat_type_id
       AND showtime.showtime_dimension_id = ticket_price.showtime_dimension_id
       AND showtime.price_period_id = ticket_price.price_period_id
       AND showtime.showtime_date BETWEEN ticket_price.ticket_price_start_date AND ticket_price.ticket_price_end_date
WHERE movie_name.movie_name = 'Movie A' AND showtime.branch_id = 1 AND showtime.theatre_id = 1
  AND showtime.showtime_date = '2026-11-05' AND showtime.showtime_time = '14:00'
  AND seat.seat_id = 2;

-- If the ticket has already been sold, the price it was sold at is saved in ticket:
SELECT ticket.seat_id, ticket.ticket_sale_price
FROM ticket
WHERE ticket.branch_id = 1 AND ticket.theatre_id = 1 AND ticket.showtime_date = '2026-11-05'
  AND ticket.showtime_time = '14:00' AND ticket.seat_id = 2;


-- ============================================================================
-- Q4) Same showtime, seats D, E, F (3 seats): the total price
-- Two versions:
--   Version 1 (taught only): list the price of each seat, add them by hand.
--   Version 2 (uses SUM, beyond the basic course material): the database adds them.
-- ----------------------------------------------------------------------------
-- Q4 version 1: no SUM. Sold tickets show the price they were sold at (ticket_sale_price):
-- ============================================================================
SELECT ticket.seat_id, ticket.ticket_sale_price
FROM ticket
WHERE ticket.branch_id = 1 AND ticket.theatre_id = 1 AND ticket.showtime_date = '2026-11-05'
  AND ticket.showtime_time = '14:00' AND ticket.seat_id IN (2, 3, 4)
ORDER BY ticket.seat_id ASC;

-- Seats that are not sold yet (here seat 4): price of every seat of the showtime from the price list
SELECT seat.seat_id, seat_type.seat_type_name, ticket_price.ticket_price_amount
FROM showtime
INNER JOIN theatre ON showtime.theatre_id = theatre.theatre_id AND showtime.branch_id = theatre.branch_id
INNER JOIN seat ON showtime.theatre_id = seat.theatre_id AND showtime.branch_id = seat.branch_id
INNER JOIN seat_type ON seat.seat_type_id = seat_type.seat_type_id
INNER JOIN ticket_price ON theatre.branch_id = ticket_price.branch_id
       AND theatre.theatre_type_id = ticket_price.theatre_type_id
       AND seat.seat_type_id = ticket_price.seat_type_id
       AND showtime.showtime_dimension_id = ticket_price.showtime_dimension_id
       AND showtime.price_period_id = ticket_price.price_period_id
       AND showtime.showtime_date BETWEEN ticket_price.ticket_price_start_date AND ticket_price.ticket_price_end_date
WHERE showtime.branch_id = 1 AND showtime.theatre_id = 1 AND showtime.showtime_date = '2026-11-05'
  AND showtime.showtime_time = '14:00' AND seat.seat_id IN (2, 3, 4)
ORDER BY seat.seat_id ASC;

-- ----------------------------------------------------------------------------
-- Q4 version 2: with SUM (one extra function beyond the basics)
-- (a) total of the prices already saved on the tickets (seats 2, 3 are sold)
SELECT SUM(ticket.ticket_sale_price)
FROM ticket
WHERE ticket.branch_id = 1 AND ticket.theatre_id = 1 AND ticket.showtime_date = '2026-11-05'
  AND ticket.showtime_time = '14:00' AND ticket.seat_id IN (2, 3, 4);

-- (b) total of the list prices of the 3 seats (an Monthly Pass ticket is charged only the difference, so this can be higher)
SELECT SUM(ticket_price.ticket_price_amount)
FROM showtime
INNER JOIN theatre ON showtime.theatre_id = theatre.theatre_id AND showtime.branch_id = theatre.branch_id
INNER JOIN seat ON showtime.theatre_id = seat.theatre_id AND showtime.branch_id = seat.branch_id
INNER JOIN ticket_price ON theatre.branch_id = ticket_price.branch_id
       AND theatre.theatre_type_id = ticket_price.theatre_type_id
       AND seat.seat_type_id = ticket_price.seat_type_id
       AND showtime.showtime_dimension_id = ticket_price.showtime_dimension_id
       AND showtime.price_period_id = ticket_price.price_period_id
       AND showtime.showtime_date BETWEEN ticket_price.ticket_price_start_date AND ticket_price.ticket_price_end_date
WHERE showtime.branch_id = 1 AND showtime.theatre_id = 1 AND showtime.showtime_date = '2026-11-05'
  AND showtime.showtime_time = '14:00' AND seat.seat_id IN (2, 3, 4);


-- ============================================================================
-- Q5) Today at theatre B: which movies, and at what times?
-- ============================================================================
SELECT showtime.showtime_time, showtime.showtime_end_time, movie_name.movie_name,
       language.language_name, showtime_dimension.showtime_dimension_name
FROM showtime
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
INNER JOIN language ON movie_version.audio_language_id = language.language_id
INNER JOIN showtime_dimension ON showtime.showtime_dimension_id = showtime_dimension.showtime_dimension_id
WHERE showtime.branch_id = 1 AND showtime.theatre_id = 1 AND showtime.showtime_date = '2026-11-05' AND movie_name.language_id = 1
ORDER BY showtime.showtime_time ASC;

-- Q5 version 2: the same question asked with names instead of ids (branch name contains 'Ratchayothin', theatre 'Theatre 1')
SELECT branch.branch_name, theatre.theatre_name, showtime.showtime_time, showtime.showtime_end_time, movie_name.movie_name
FROM showtime
INNER JOIN theatre ON showtime.theatre_id = theatre.theatre_id AND showtime.branch_id = theatre.branch_id
INNER JOIN branch ON theatre.branch_id = branch.branch_id
INNER JOIN movie_name ON showtime.movie_id = movie_name.movie_id AND showtime.audio_language_id = movie_name.language_id
WHERE branch.branch_name LIKE '%Ratchayothin%' AND theatre.theatre_name = 'Theatre 1' AND showtime.showtime_date = '2026-11-05'
ORDER BY showtime.showtime_time ASC;


-- ============================================================================
-- Q6) Which movies does actor X appear in?
-- ============================================================================
SELECT person.person_name, movie_name.movie_name
FROM person
INNER JOIN movie_credit ON person.person_id = movie_credit.person_id
INNER JOIN role ON movie_credit.role_id = role.role_id
INNER JOIN movie_name ON movie_credit.movie_id = movie_name.movie_id
WHERE person.person_name = 'Person A' AND role.role_name = 'Actor' AND movie_name.language_id = 1
ORDER BY movie_name.movie_name ASC;


-- ============================================================================
-- Q7) Which movies does director Y direct?
-- ============================================================================
SELECT person.person_name, movie_name.movie_name
FROM person
INNER JOIN movie_credit ON person.person_id = movie_credit.person_id
INNER JOIN role ON movie_credit.role_id = role.role_id
INNER JOIN movie_name ON movie_credit.movie_id = movie_name.movie_id
WHERE person.person_name = 'Person A' AND role.role_name = 'Director' AND movie_name.language_id = 1
ORDER BY movie_name.movie_name ASC;


-- ============================================================================
-- Q8) Which movies has member Z watched since the membership start date?
-- A movie is watched when a PAID booking of this member has a ticket for a showtime
-- from member_start_date up to today. Part 1 lists the movies; part 2 counts them.
-- ============================================================================
SELECT member.member_id, member.member_start_date, movie_name.movie_name, showtime.showtime_date
FROM member
INNER JOIN payment ON member.member_id = payment.member_id
INNER JOIN booking ON payment.booking_id = booking.booking_id
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
INNER JOIN showtime ON ticket.theatre_id = showtime.theatre_id AND ticket.branch_id = showtime.branch_id AND ticket.showtime_date = showtime.showtime_date
                   AND ticket.showtime_time = showtime.showtime_time
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
WHERE member.member_id = 2 AND booking.booking_status = 'PAID' AND movie_name.language_id = 1
  AND showtime.showtime_date >= member.member_start_date AND showtime.showtime_date <= '2026-11-05'
ORDER BY showtime.showtime_date ASC;

-- Q8 part 2: how many different movies
SELECT member.member_id, COUNT(DISTINCT movie_name.movie_id) AS movies_watched
FROM member
INNER JOIN payment ON member.member_id = payment.member_id
INNER JOIN booking ON payment.booking_id = booking.booking_id
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
INNER JOIN showtime ON ticket.theatre_id = showtime.theatre_id AND ticket.branch_id = showtime.branch_id AND ticket.showtime_date = showtime.showtime_date
                   AND ticket.showtime_time = showtime.showtime_time
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
WHERE member.member_id = 2 AND booking.booking_status = 'PAID' AND movie_name.language_id = 1
  AND showtime.showtime_date >= member.member_start_date AND showtime.showtime_date <= '2026-11-05'
GROUP BY member.member_id;


-- ============================================================================
-- Q9) Membership history of customer Z: which member types, how many times, when?
-- Every subscription starts with a row of register (who, which type, when) and gives a row of member (the card).
-- Part 1 lists the subscriptions; part 2 counts them per member type.
-- ============================================================================
SELECT customer.customer_id, member.member_id, member_type.member_type_name,
       member.member_start_date, member.member_end_date
FROM customer
INNER JOIN register ON customer.customer_id = register.customer_id
INNER JOIN member ON register.register_id = member.register_id
INNER JOIN member_type ON register.member_type_id = member_type.member_type_id
WHERE customer.customer_id = 2
ORDER BY member.member_start_date ASC;

-- Q9 part 2: how many times each member type
SELECT member_type.member_type_name, COUNT(member.member_id) AS subscriptions
FROM customer
INNER JOIN register ON customer.customer_id = register.customer_id
INNER JOIN member ON register.register_id = member.register_id
INNER JOIN member_type ON register.member_type_id = member_type.member_type_id
WHERE customer.customer_id = 2
GROUP BY member_type.member_type_id, member_type.member_type_name
ORDER BY subscriptions DESC;


-- ============================================================================
-- Q10) Which subtitle languages does a showtime have? (one showtime can show several subtitles at once)
-- Values: B = branch 1, theatre_id 1   date '2026-11-05'   time '17:30' (this showtime has 2 subtitles)
-- Part 1 lists the subtitle languages; part 2 counts them for every showtime.
-- ============================================================================
SELECT showtime_subtitle.showtime_date, showtime_subtitle.showtime_time, language.language_name AS subtitle_language
FROM showtime_subtitle
INNER JOIN language ON showtime_subtitle.subtitle_language_id = language.language_id
WHERE showtime_subtitle.branch_id = 1 AND showtime_subtitle.theatre_id = 1
  AND showtime_subtitle.showtime_date = '2026-11-05' AND showtime_subtitle.showtime_time = '17:30'
ORDER BY language.language_name ASC;

-- Q10 part 2: number of subtitle languages of each showtime (a showtime with no subtitle has no row, so it is not listed)
SELECT showtime_subtitle.branch_id, showtime_subtitle.theatre_id, showtime_subtitle.showtime_date, showtime_subtitle.showtime_time,
       COUNT(showtime_subtitle.subtitle_language_id) AS subtitle_languages
FROM showtime_subtitle
GROUP BY showtime_subtitle.branch_id, showtime_subtitle.theatre_id, showtime_subtitle.showtime_date, showtime_subtitle.showtime_time
ORDER BY subtitle_languages DESC, showtime_subtitle.showtime_date ASC, showtime_subtitle.showtime_time ASC;


-- ============================================================================
-- Q11) One booking, its tickets and its payment: booking BK0007 is a guest booking (no login, no customer) with 2 tickets
-- A booking has many tickets (ticket.booking_id) and is paid by payment (payment.booking_id).
-- A guest types a phone number (booking_phone_number); a logged-in buyer is not asked: the app copies the account phone. So every booking has a contact phone.
-- ============================================================================
SELECT booking.booking_code, booking.booking_phone_number, ticket.seat_id, ticket.showtime_date, ticket.showtime_time,
       ticket.ticket_sale_price, payment.payment_id, payment.payment_method
FROM booking
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
LEFT JOIN payment ON booking.booking_id = payment.booking_id
WHERE booking.booking_code = 'BK0007'
ORDER BY ticket.seat_id ASC;

-- Q11 part 2: the amount to pay is not stored. List the tickets and products of booking BK0002, then add them up (the coupon CARD50 = 50% off reduces only the tickets)
SELECT booking.booking_code, payment.payment_id, discount.discount_code, discount.discount_type, discount.discount_value, ticket.ticket_sale_price
FROM booking
INNER JOIN payment ON booking.booking_id = payment.booking_id
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
LEFT JOIN discount ON payment.discount_id = discount.discount_id
WHERE booking.booking_code = 'BK0002';

SELECT booking.booking_code, booking_product.booking_product_quantity, booking_product.booking_product_sale_price
FROM booking
INNER JOIN booking_product ON booking.booking_id = booking_product.booking_id
WHERE booking.booking_code = 'BK0002';

-- Q11 part 3: number of tickets and total ticket price of every booking (uses COUNT and SUM)
SELECT booking.booking_code, booking.booking_status, COUNT(ticket.seat_id) AS tickets, SUM(ticket.ticket_sale_price) AS ticket_total
FROM booking
LEFT JOIN ticket ON booking.booking_id = ticket.booking_id
GROUP BY booking.booking_id, booking.booking_code, booking.booking_status
ORDER BY booking.booking_code ASC;


-- ============================================================================
-- Q12) Is each customer registered, and as which member type?
--   no row in register          = the customer never registered (NULL in the register columns)
--   register, but no row in member = registered, waiting (register_status PENDING)
--   row in member               = a member of that type, with the start and end date
-- One customer can have several rows (several registrations over time).
-- ============================================================================
SELECT customer.customer_id, customer.customer_first_name, register.register_status, member_type.member_type_name,
       member.member_start_date, member.member_end_date
FROM customer
LEFT JOIN register ON customer.customer_id = register.customer_id
LEFT JOIN member_type ON register.member_type_id = member_type.member_type_id
LEFT JOIN member ON register.register_id = member.register_id
ORDER BY customer.customer_id ASC, register.register_datetime ASC;


-- ============================================================================
-- Q13) Every payment: who paid, and which membership was used (NULL = no customer / no membership used)
-- booking.customer_id is empty for a guest booking (no login); payment.member_id is empty when no membership is used.
-- LEFT JOIN customer keeps the guest bookings in the result.
-- ============================================================================
SELECT payment.payment_id, booking.booking_code, customer.customer_first_name, member_type.member_type_name
FROM payment
INNER JOIN booking ON payment.booking_id = booking.booking_id
LEFT JOIN customer ON booking.customer_id = customer.customer_id
LEFT JOIN member ON payment.member_id = member.member_id
LEFT JOIN register ON member.register_id = register.register_id
LEFT JOIN member_type ON register.member_type_id = member_type.member_type_id
ORDER BY payment.payment_id ASC;


-- ============================================================================
-- Q14) Monthly Pass members valid on 2026-11-05, and the movies each has already used (one movie only once)
-- monthly_pass_member lists the Monthly Pass members, and monthly_pass_usage can only point to them. A member with no used movie shows NULL.
-- ============================================================================
SELECT member.member_id, customer.customer_first_name, member.member_start_date, member.member_end_date, monthly_pass_usage.movie_id
FROM monthly_pass_member
INNER JOIN member ON monthly_pass_member.member_id = member.member_id
INNER JOIN register ON member.register_id = register.register_id
INNER JOIN customer ON register.customer_id = customer.customer_id
LEFT JOIN monthly_pass_usage ON monthly_pass_member.member_id = monthly_pass_usage.member_id
WHERE member.member_start_date <= '2026-11-05' AND member.member_end_date >= '2026-11-05'
ORDER BY member.member_id ASC;
