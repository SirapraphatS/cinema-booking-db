-- ============================================================================
-- 03_example_queries.sql: more queries on the sample data (SELECT only)
-- Import 02_import_all_in_one.sql first. SQL used:
--   SELECT, FROM, WHERE (= <> > < >= <=, AND, OR, NOT, LIKE, IN, BETWEEN),
--   ORDER BY (ASC, DESC), INNER / LEFT JOIN ... ON,
--   and the aggregates COUNT, SUM with GROUP BY (a later topic of the course).
--   Small helper functions: DATE(), SUBSTR() to cut a date out of a datetime, COALESCE() to turn NULL into 0.
-- Only bookings with booking_status = 'PAID' are counted.
-- ============================================================================


-- ============================================================================
-- Part A: the 4 statistics
-- ============================================================================

-- A1) Bookings per day: number of bookings, tickets and revenue per day
SELECT DATE(booking.booking_datetime) AS booking_day,
       COUNT(DISTINCT booking.booking_id) AS bookings,
       COUNT(ticket.seat_id) AS tickets,
       SUM(ticket.ticket_sale_price) AS revenue
FROM booking
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
WHERE booking.booking_status = 'PAID'
GROUP BY DATE(booking.booking_datetime)
ORDER BY booking_day ASC;

-- A2) Usage by member type: tickets and revenue of members, per member type
--     (LEFT JOIN keeps member types with no ticket: tickets = 0, revenue = NULL)
SELECT member_type.member_type_name,
       COUNT(ticket.seat_id) AS tickets,
       SUM(ticket.ticket_sale_price) AS revenue
FROM member_type
LEFT JOIN register ON member_type.member_type_id = register.member_type_id
LEFT JOIN member ON register.register_id = member.register_id
LEFT JOIN payment ON member.member_id = payment.member_id
LEFT JOIN booking ON payment.booking_id = booking.booking_id AND booking.booking_status = 'PAID'
LEFT JOIN ticket ON booking.booking_id = ticket.booking_id
GROUP BY member_type.member_type_id, member_type.member_type_name
ORDER BY member_type.member_type_name ASC;

-- A3) Best-selling theatre types: tickets and revenue per theatre type, best first
SELECT theatre_type.theatre_type_name,
       COUNT(ticket.seat_id) AS tickets,
       SUM(ticket.ticket_sale_price) AS revenue
FROM ticket
INNER JOIN booking ON ticket.booking_id = booking.booking_id
INNER JOIN theatre ON ticket.theatre_id = theatre.theatre_id AND ticket.branch_id = theatre.branch_id
INNER JOIN theatre_type ON theatre.theatre_type_id = theatre_type.theatre_type_id
WHERE booking.booking_status = 'PAID'
GROUP BY theatre_type.theatre_type_id, theatre_type.theatre_type_name
ORDER BY tickets DESC;

-- A4) Monthly movie ranking: tickets per movie in each month, best first
SELECT SUBSTR(booking.booking_datetime, 1, 7) AS booking_month, movie_name.movie_name,
       COUNT(ticket.seat_id) AS tickets
FROM ticket
INNER JOIN booking ON ticket.booking_id = booking.booking_id
INNER JOIN showtime ON ticket.theatre_id = showtime.theatre_id AND ticket.branch_id = showtime.branch_id AND ticket.showtime_date = showtime.showtime_date
                   AND ticket.showtime_time = showtime.showtime_time
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN movie_name ON movie_version.movie_id = movie_name.movie_id
WHERE booking.booking_status = 'PAID' AND movie_name.language_id = 1
GROUP BY SUBSTR(booking.booking_datetime, 1, 7), movie_name.movie_id, movie_name.movie_name
ORDER BY booking_month ASC, tickets DESC;


-- ============================================================================
-- Part B: movies and people
-- ============================================================================

-- B1) All credits of "person A" (one table answers both directing and acting)
SELECT person.person_name, movie_name.movie_name, role.role_name
FROM movie_credit
INNER JOIN person ON movie_credit.person_id = person.person_id
INNER JOIN role ON movie_credit.role_id = role.role_id
INNER JOIN movie_name ON movie_credit.movie_id = movie_name.movie_id
WHERE person.person_id = 1 AND movie_name.language_id = 1;

-- B2) movie titles and genres
SELECT movie_name.movie_name, genre.genre_name
FROM movie_genre
INNER JOIN genre ON movie_genre.genre_id = genre.genre_id
INNER JOIN movie_name ON movie_genre.movie_id = movie_name.movie_id
WHERE movie_name.language_id = 1
ORDER BY movie_name.movie_name ASC, genre.genre_name ASC;

-- B3) movie titles that start with "movie A" (LIKE)
SELECT movie_name.movie_id, movie_name.movie_name
FROM movie_name
WHERE movie_name.movie_name LIKE 'Movie A%';


-- ============================================================================
-- Part C: showtimes, seats, prices
-- ============================================================================

-- C1) Showtimes with audio language and subtitle language (a showtime with 2 subtitles appears in 2 rows; NULL = no subtitle)
SELECT showtime.branch_id, showtime.theatre_id, showtime.showtime_date, showtime.showtime_time, showtime.showtime_end_time,
       language.language_name, showtime_subtitle.subtitle_language_id
FROM showtime
INNER JOIN movie_version ON showtime.movie_id = movie_version.movie_id AND showtime.audio_language_id = movie_version.audio_language_id
INNER JOIN language ON movie_version.audio_language_id = language.language_id
LEFT JOIN showtime_subtitle ON showtime.branch_id = showtime_subtitle.branch_id AND showtime.theatre_id = showtime_subtitle.theatre_id
      AND showtime.showtime_date = showtime_subtitle.showtime_date AND showtime.showtime_time = showtime_subtitle.showtime_time
ORDER BY showtime.showtime_date ASC, showtime.theatre_id ASC, showtime.showtime_time ASC, showtime_subtitle.subtitle_language_id ASC;

-- C2) ticket price check: each ticket with the price period of its showtime and the price it was sold at
--     (ticket_sale_price is stored in ticket when it is sold; the period tells which row of ticket_price was used)
SELECT ticket.branch_id, ticket.theatre_id, ticket.showtime_date, ticket.showtime_time, ticket.seat_id,
       price_period.price_period_name, ticket.ticket_sale_price
FROM ticket
INNER JOIN showtime ON ticket.branch_id = showtime.branch_id AND ticket.theatre_id = showtime.theatre_id
      AND ticket.showtime_date = showtime.showtime_date AND ticket.showtime_time = showtime.showtime_time
INNER JOIN price_period ON showtime.price_period_id = price_period.price_period_id
ORDER BY ticket.showtime_date ASC, ticket.theatre_id ASC, ticket.showtime_time ASC, ticket.seat_id ASC;

-- C3) Showtimes that start between 12:00 and 18:00 (BETWEEN)
SELECT showtime.branch_id, showtime.theatre_id, showtime.showtime_date, showtime.showtime_time
FROM showtime
WHERE showtime.showtime_time BETWEEN '12:00' AND '18:00'
ORDER BY showtime.showtime_time ASC;


-- ============================================================================
-- Part D: bookings, members, points, products
-- ============================================================================

-- D1) Held tickets (PENDING) and their expiry time
SELECT booking.booking_id, booking.booking_status, booking.booking_expire_datetime, ticket.seat_id
FROM booking
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
WHERE booking.booking_status = 'PENDING';

-- D2) Point balance of each member (EARN is positive, REDEEM is negative)
SELECT member.member_id, customer.customer_first_name, SUM(point_log.point_log_amount) AS point_balance
FROM member
INNER JOIN register ON member.register_id = register.register_id
INNER JOIN customer ON register.customer_id = customer.customer_id
INNER JOIN point_log ON member.member_id = point_log.member_id
GROUP BY member.member_id, customer.customer_first_name
ORDER BY member.member_id ASC;

-- D3) Monthly Pass benefits already used
SELECT monthly_pass_usage.member_id, movie_name.movie_name, monthly_pass_usage.showtime_date, monthly_pass_usage.showtime_time,
       monthly_pass_usage.seat_id, monthly_pass_usage.monthly_pass_usage_datetime
FROM monthly_pass_usage
INNER JOIN movie_name ON monthly_pass_usage.movie_id = movie_name.movie_id
WHERE movie_name.language_id = 1;

-- D4) Items inside each product set (set_product_id 3 = Combo Set L)
SELECT product_set.set_product_id, product_set.item_product_id, product.product_name, product_set.product_set_quantity
FROM product_set
INNER JOIN product ON product_set.item_product_id = product.product_id;

-- D5) Rules of each member type, one row per condition (the app reads these before it books)
SELECT member_type.member_type_name, member_type_condition.member_type_condition_type,
       member_type_condition.member_type_condition_value, member_type_condition.member_type_condition_detail
FROM member_type
INNER JOIN member_type_condition ON member_type.member_type_id = member_type_condition.member_type_id
ORDER BY member_type.member_type_id ASC, member_type_condition.member_type_condition_id ASC;

-- D6) Rule "shows at least 2 hours apart" (MIN_GAP_MINUTES = 120): all tickets of member 1 in date and time order.
--     Compare showtime_end_time of one row with showtime_time of the next row by hand (time arithmetic is not taught).
SELECT member.member_id, ticket.showtime_date, ticket.showtime_time, showtime.showtime_end_time, ticket.seat_id
FROM member
INNER JOIN payment ON member.member_id = payment.member_id
INNER JOIN booking ON payment.booking_id = booking.booking_id
INNER JOIN ticket ON booking.booking_id = ticket.booking_id
INNER JOIN showtime ON ticket.theatre_id = showtime.theatre_id AND ticket.branch_id = showtime.branch_id AND ticket.showtime_date = showtime.showtime_date
                   AND ticket.showtime_time = showtime.showtime_time
WHERE member.member_id = 1
ORDER BY ticket.showtime_date ASC, ticket.showtime_time ASC;

-- D7) Sold price versus the price list: for each ticket, the price it was sold at and the price in ticket_price
--     for the same conditions on the show date (they differ when the ticket was sold at a special price, e.g. an Monthly Pass ticket)
SELECT ticket.branch_id, ticket.theatre_id, ticket.showtime_date, ticket.showtime_time, ticket.seat_id,
       ticket.ticket_sale_price, ticket_price.ticket_price_amount
FROM ticket
INNER JOIN showtime ON ticket.branch_id = showtime.branch_id AND ticket.theatre_id = showtime.theatre_id
       AND ticket.showtime_date = showtime.showtime_date AND ticket.showtime_time = showtime.showtime_time
INNER JOIN theatre ON ticket.branch_id = theatre.branch_id AND ticket.theatre_id = theatre.theatre_id
INNER JOIN seat ON ticket.branch_id = seat.branch_id AND ticket.theatre_id = seat.theatre_id AND ticket.seat_id = seat.seat_id
INNER JOIN ticket_price ON ticket_price.branch_id = ticket.branch_id
       AND ticket_price.theatre_type_id = theatre.theatre_type_id AND ticket_price.seat_type_id = seat.seat_type_id
       AND ticket_price.showtime_dimension_id = showtime.showtime_dimension_id AND ticket_price.price_period_id = showtime.price_period_id
       AND showtime.showtime_date BETWEEN ticket_price.ticket_price_start_date AND ticket_price.ticket_price_end_date
ORDER BY ticket.showtime_date ASC, ticket.showtime_time ASC, ticket.theatre_id ASC, ticket.seat_id ASC;

-- D8) Rewards tied to a movie (a reward with no row in movie_reward is a generic reward, e.g. a ticket or popcorn)
SELECT reward.reward_id, reward.reward_name, movie_name.movie_name, branch_reward.branch_id, branch_reward.branch_reward_point_cost
FROM reward
INNER JOIN movie_reward ON reward.reward_id = movie_reward.reward_id
INNER JOIN movie_name ON movie_reward.movie_id = movie_name.movie_id
INNER JOIN branch_reward ON reward.reward_id = branch_reward.reward_id
WHERE movie_name.language_id = 1
ORDER BY reward.reward_id ASC, movie_name.movie_name ASC;
