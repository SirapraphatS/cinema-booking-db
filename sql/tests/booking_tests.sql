-- ============================================================================
-- tests: load after 01_schema.sql, 02_sample_data.sql, 03_booking_procedures.sql
--     insert fixtures: extra seats, coupons, a Monthly Pass member
--     clock T0 = 2026-11-05 13:01:00
--     showtime A = branch 1, theatre 1, 14:00;  showtime B = same theatre, 17:30
--     each check: run the call, compare with the expected value or error text
--     print PASS or FAIL per check; exit non-zero if any FAIL
-- ============================================================================

DROP TABLE IF EXISTS _test_result;
CREATE TABLE _test_result (
    test_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name     VARCHAR(200) NOT NULL,
    passed   BOOLEAN      NOT NULL,
    detail   VARCHAR(300)
);

-- helpers are functions: PERFORM accepts a subquery argument, CALL does not
CREATE OR REPLACE FUNCTION t_check(p_name VARCHAR, p_ok BOOLEAN) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO _test_result (name, passed) VALUES (p_name, COALESCE(p_ok, FALSE));
END $$;

-- run the statement; pass only if it raises exactly this message
CREATE OR REPLACE FUNCTION t_expect_error(p_name VARCHAR, p_sql TEXT, p_msg VARCHAR) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT := NULL;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    INSERT INTO _test_result (name, passed, detail)
    VALUES (p_name, COALESCE(v_msg = p_msg, FALSE),
            CASE WHEN v_msg = p_msg THEN NULL ELSE 'got: ' || COALESCE(v_msg, 'no error') END);
END $$;

-- ---------------------------------------------------------------- fixtures
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES
    (1,1,5,'A',5,'ACTIVE',1), (1,1,6,'A',6,'ACTIVE',1), (1,1,7,'A',7,'ACTIVE',1),
    (1,1,8,'A',8,'ACTIVE',1), (1,1,9,'A',9,'ACTIVE',3),   -- seat 9: Premium, no price row
    (2,3,2,'A',2,'ACTIVE',2);                              -- Pair seat at Pinklao
INSERT INTO ticket_price VALUES (2,1,2,1,2,'2026-01-01','9999-12-31',400);
INSERT INTO customer VALUES (5,'Somboon','Dee','somboon@example.test','0800000005','Bangkok','2002-05-05');
INSERT INTO register VALUES (6,5,1,'2026-10-31 18:00:00','COMPLETED');
INSERT INTO member VALUES (5,6,'2026-11-01','2026-12-01');
INSERT INTO monthly_pass_member VALUES (5);
INSERT INTO discount VALUES (2,NULL,'Expired 10%','PERCENT',10,'2026-01-01','2026-01-31',NULL,'OLD10',NULL,NULL);
INSERT INTO discount VALUES (3,NULL,'Pinklao only','AMOUNT',10,'2026-11-01','2026-11-30',NULL,'PINK10',NULL,NULL);
INSERT INTO discount VALUES (4,NULL,'One use only','AMOUNT',20,'2026-11-01','2026-11-30',NULL,'ONCE',1,NULL);
INSERT INTO discount_branch VALUES (2,1), (3,2), (4,1), (4,2);


DO $$
DECLARE
    t0 TIMESTAMP := '2026-11-05 13:01:00';
    amount1 NUMERIC;
    amount2 NUMERIC;
    amount3 NUMERIC;
    b1 INT;
    b2 INT;
    b3 INT;
    b4 INT;
    b5 INT;
    b6 INT;
    bookings_before INT;
    g1 INT;
    gamount NUMERIC;
    gp INT;
    m1 INT;
    m2 INT;
    m3 INT;
    m4 INT;
    mamount1 NUMERIC;
    mamount4 NUMERIC;
    mp1 INT;
    mp4 INT;
    n INT;
    pay1 INT;
    pay2 INT;
    pay3 INT;
    pl INT;
    points_before INT;
    released INT;
    x INT;
    y INT;
BEGIN
SELECT COUNT(*) INTO bookings_before FROM booking;

-- ------------------------------------------------- 1. ticket price lookup
PERFORM t_check('price: Normal seat, Thursday 2D = 240', fn_ticket_price(1,1,'2026-11-05','14:00',2) = 240);
PERFORM t_check('price: Pair seat, Thursday 2D = 780', fn_ticket_price(1,1,'2026-11-05','14:00',21) = 780);
PERFORM t_expect_error('price: seat type without a price row is rejected', 'SELECT fn_ticket_price(1,1,''2026-11-05'',''14:00'',9)', 'No ticket price for this seat and showtime');
PERFORM t_check('showtime start: 00:30 show of business date 11-05 starts on 11-06',
    fn_showtime_start('2026-11-05','00:30') = '2026-11-06 00:30:00');

-- ------------------------------------------------- 2. hold seats
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','14:00', '5,6', t0, b1);
PERFORM t_check('hold: booking is PENDING', (SELECT booking_status FROM booking WHERE booking_id = b1) = 'PENDING');
PERFORM t_check('hold: booking code derives from id', (SELECT booking_code FROM booking WHERE booking_id = b1) = ('BK' || LPAD(b1::TEXT, 4, '0')));
PERFORM t_check('hold: expires after HOLD_MINUTES (15)', (SELECT booking_expire_datetime FROM booking WHERE booking_id = b1) = '2026-11-05 13:16:00');
PERFORM t_check('hold: phone copied from the customer account', (SELECT booking_phone_number FROM booking WHERE booking_id = b1) = '0800000001');
PERFORM t_check('hold: two tickets priced 240 each', (SELECT COUNT(*) FROM ticket WHERE booking_id = b1) = 2
    AND (SELECT SUM(ticket_sale_price) FROM ticket WHERE booking_id = b1) = 480);

-- ------------------------------------------------- 3. seats cannot be double-sold
SELECT COUNT(*) INTO n FROM booking;
PERFORM t_expect_error('hold: a held seat cannot be booked again', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''14:00'',''5'',''2026-11-05 13:01:00'', NULL)', 'Seat already taken for this showtime');
PERFORM t_expect_error('hold: a sold seat cannot be booked again', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''14:00'',''21'',''2026-11-05 13:01:00'', NULL)', 'Seat already taken for this showtime');
PERFORM t_expect_error('hold: a seat held by another unexpired booking is refused', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''14:00'',''2'',''2026-11-05 13:01:00'', NULL)', 'Seat already taken for this showtime');
PERFORM t_expect_error('hold: the same seat twice in one request is refused', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''17:30'',''7,7'',''2026-11-05 13:01:00'', NULL)', 'Seat already taken for this showtime');
PERFORM t_expect_error('hold: a removed seat is refused', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''17:30'',''1'',''2026-11-05 13:01:00'', NULL)', 'Seat not found or not available');
PERFORM t_expect_error('hold: one bad seat rejects the whole request', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''17:30'',''7,1'',''2026-11-05 13:01:00'', NULL)', 'Seat not found or not available');
PERFORM t_expect_error('hold: a seat without a price is refused', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''17:30'',''9'',''2026-11-05 13:01:00'', NULL)', 'No ticket price for this seat and showtime');
PERFORM t_check('hold: failed requests leave no booking and no ticket behind',
    (SELECT COUNT(*) FROM booking) = n
    AND (SELECT COUNT(*) FROM ticket WHERE showtime_time = '17:30' AND seat_id IN (7,9)) = 0);
PERFORM t_expect_error('hold: unknown showtime', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''11:00'',''5'',''2026-11-05 13:01:00'', NULL)', 'Showtime not found or not open');
PERFORM t_expect_error('hold: showtime already started', 'CALL sp_hold_seats(2, NULL, 1,1,''2026-11-05'',''14:00'',''7'',''2026-11-05 14:30:00'', NULL)', 'Showtime has already started');
PERFORM t_expect_error('hold: a guest must give a phone number', 'CALL sp_hold_seats(NULL, NULL, 1,1,''2026-11-05'',''17:30'',''7'',''2026-11-05 13:01:00'', NULL)', 'A contact phone number is required');

-- ------------------------------------------------- 4. pay: coupon, points
CALL sp_pay_booking(b1, 2, 'CARD50', 'PromptPay', '2026-11-05 13:03:00', pay1, amount1);
PERFORM t_check('pay: 2 x 240 with 50% coupon = 240', amount1 = 240);
PERFORM t_check('pay: booking becomes PAID', (SELECT booking_status FROM booking WHERE booking_id = b1) = 'PAID');
PERFORM t_check('pay: payment row is SUCCESS and keeps the coupon',
    (SELECT payment_status FROM payment WHERE payment_id = pay1) = 'SUCCESS'
    AND (SELECT discount_id FROM payment WHERE payment_id = pay1) = 1);
PERFORM t_check('pay: 1 point per baht paid (EARN 240, expires in 12 months)',
    (SELECT point_log_amount FROM point_log WHERE payment_id = pay1 AND point_log_type = 'EARN') = 240
    AND (SELECT point_log_expired_date FROM point_log WHERE payment_id = pay1) = '2027-11-05');
PERFORM t_check('points: balance = 390 earned - 100 redeemed + 240 earned', fn_point_balance(2, '2026-11-05') = 530);
PERFORM t_expect_error('pay: paying twice is refused', 'CALL sp_pay_booking(' || b1 || ', 2, NULL, ''PromptPay'', ''2026-11-05 13:04:00'', NULL, NULL)', 'Booking is already paid');

-- ------------------------------------------------- 5. coupon and member rules
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','17:30','7', t0, b2);
PERFORM t_expect_error('pay: member of another customer is refused', 'CALL sp_pay_booking(' || b2 || ', 1, NULL, ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Member does not belong to the booking customer');
PERFORM t_expect_error('pay: expired membership is refused', 'CALL sp_pay_booking(' || b2 || ', 3, NULL, ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Member not found or membership not active');
PERFORM t_expect_error('coupon: unknown code', 'CALL sp_pay_booking(' || b2 || ', NULL, ''NOPE'', ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Discount code not found');
PERFORM t_expect_error('coupon: outside its dates', 'CALL sp_pay_booking(' || b2 || ', NULL, ''OLD10'', ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Discount is not valid today');
PERFORM t_expect_error('coupon: not valid at this branch', 'CALL sp_pay_booking(' || b2 || ', NULL, ''PINK10'', ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Discount is not valid at this branch');
PERFORM t_check('pay: failed payments leave the booking pending',
    (SELECT booking_status FROM booking WHERE booking_id = b2) = 'PENDING'
    AND (SELECT COUNT(*) FROM payment WHERE booking_id = b2) = 0);
-- food price is not reduced by the coupon
INSERT INTO booking_product VALUES (2, b2, 1, 1, 1, 125, NULL);
CALL sp_pay_booking(b2, 2, 'ONCE', 'PromptPay', '2026-11-05 13:02:00', pay2, amount2);
PERFORM t_check('pay: coupon reduces tickets only (240 - 20 + 125 food = 345)', amount2 = 345);
PERFORM t_check('pay: points ignore food (EARN 220)',
    (SELECT point_log_amount FROM point_log WHERE payment_id = pay2) = 220);
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','17:30','8', t0, b3);
PERFORM t_expect_error('coupon: usage limit reached', 'CALL sp_pay_booking(' || b3 || ', NULL, ''ONCE'', ''PromptPay'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Discount usage limit reached');
SELECT COUNT(*) INTO points_before FROM point_log;
CALL sp_pay_booking(b3, NULL, NULL, 'Banking App', '2026-11-05 13:02:00', pay3, amount3);
PERFORM t_check('pay: non-member without coupon pays full price and earns nothing',
    amount3 = 240 AND (SELECT COUNT(*) FROM point_log) = points_before);

-- ------------------------------------------------- 6. expiry and cancel
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','17:30','5', t0, b4);
CALL sp_release_expired('2026-11-05 13:20:00', released);
PERFORM t_check('expire: holds past their time are released (booking 1 and this one)', released = 2);
PERFORM t_check('expire: booking is EXPIRED and its tickets are gone',
    (SELECT booking_status FROM booking WHERE booking_id = b4) = 'EXPIRED'
    AND (SELECT COUNT(*) FROM ticket WHERE booking_id = b4) = 0);
PERFORM t_check('expire: paid bookings are untouched', (SELECT booking_status FROM booking WHERE booking_id = b1) = 'PAID');
CALL sp_hold_seats(1, NULL, 1,1,'2026-11-05','17:30','5', '2026-11-05 13:20:00', b5);
PERFORM t_check('expire: a released seat can be booked again', b5 IS NOT NULL);
PERFORM t_expect_error('expire: paying after the hold ran out is refused', 'CALL sp_pay_booking(' || b5 || ', NULL, NULL, ''PromptPay'', ''2026-11-05 13:40:00'', NULL, NULL)', 'Hold has expired');
PERFORM t_check('expire: the refused payment changes nothing',
    (SELECT booking_status FROM booking WHERE booking_id = b5) = 'PENDING'
    AND (SELECT COUNT(*) FROM payment WHERE booking_id = b5) = 0);
CALL sp_hold_seats(2, NULL, 1,1,'2026-11-05','17:30','5', '2026-11-05 13:50:00', b6);
PERFORM t_check('hold: a booking releases expired holds of the same seat by itself',
    (SELECT booking_status FROM booking WHERE booking_id = b5) = 'EXPIRED' AND b6 IS NOT NULL);
CALL sp_cancel_booking(b6);
PERFORM t_check('cancel: pending booking becomes CANCELLED and frees its seats',
    (SELECT booking_status FROM booking WHERE booking_id = b6) = 'CANCELLED'
    AND (SELECT COUNT(*) FROM ticket WHERE booking_id = b6) = 0);
PERFORM t_expect_error('cancel: a cancelled booking cannot be cancelled again', 'CALL sp_cancel_booking(' || b6 || ')', 'Only a pending booking can be cancelled');
PERFORM t_expect_error('cancel: a paid booking cannot be cancelled', 'CALL sp_cancel_booking(' || b1 || ')', 'Only a pending booking can be cancelled');
PERFORM t_expect_error('cancel: unknown booking', 'CALL sp_cancel_booking(999999)', 'Booking not found');

-- ------------------------------------------------- 7. redeem points
PERFORM t_check('points: balance before redeeming = 530 + 220', fn_point_balance(2, '2026-11-06') = 750);
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:00:00', pl);
PERFORM t_check('redeem: a REDEEM row of -100 is written',
    (SELECT point_log_amount FROM point_log WHERE point_log_id = pl) = -100
    AND (SELECT point_log_type FROM point_log WHERE point_log_id = pl) = 'REDEEM');
PERFORM t_check('redeem: balance drops by the reward cost', fn_point_balance(2, '2026-11-06') = 650);
PERFORM t_expect_error('redeem: reward not sold at this branch', 'CALL sp_redeem_reward(2, 1, 2, ''2026-11-06 10:00:00'', NULL)', 'Reward is not available at this branch');
PERFORM t_expect_error('redeem: a member without points is refused', 'CALL sp_redeem_reward(1, 1, 1, ''2026-11-06 10:00:00'', NULL)', 'Not enough points');
PERFORM t_expect_error('redeem: an inactive member is refused', 'CALL sp_redeem_reward(3, 1, 1, ''2026-11-06 10:00:00'', NULL)', 'Member not found or membership not active');
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:01:00', x); CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:02:00', x);
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:03:00', x); CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:04:00', x);
CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:05:00', x); CALL sp_redeem_reward(2, 1, 1, '2026-11-06 10:06:00', x);
PERFORM t_expect_error('redeem: the balance never goes negative (50 left, cost 100)', 'CALL sp_redeem_reward(2, 1, 1, ''2026-11-06 10:07:00'', NULL)', 'Not enough points');
PERFORM t_check('redeem: balance stays at 50', fn_point_balance(2, '2026-11-06') = 50);

-- ------------------------------------------------- 8. Monthly Pass
CALL sp_hold_seats(5, NULL, 1,1,'2026-11-05','17:30','6', t0, m1);
PERFORM t_expect_error('Monthly Pass: needs a member', 'CALL sp_pay_booking(' || m1 || ', NULL, NULL, ''Monthly Pass'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Monthly Pass needs a member');
PERFORM t_expect_error('Monthly Pass: cannot be combined with a coupon', 'CALL sp_pay_booking(' || m1 || ', 5, ''CARD50'', ''Monthly Pass'', ''2026-11-05 13:02:00'', NULL, NULL)', 'A coupon cannot be combined with Monthly Pass');
PERFORM t_expect_error('Monthly Pass: a member of another customer is refused', 'CALL sp_pay_booking(' || m1 || ', 2, NULL, ''Monthly Pass'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Member does not belong to the booking customer');
CALL sp_pay_booking(m1, 5, NULL, 'Monthly Pass', '2026-11-05 13:02:00', mp1, mamount1);
PERFORM t_check('Monthly Pass: a Normal 2D seat is free', mamount1 = 0
    AND (SELECT ticket_sale_price FROM ticket WHERE booking_id = m1) = 0);
PERFORM t_check('Monthly Pass: usage is recorded for member 5 / movie 1',
    (SELECT COUNT(*) FROM monthly_pass_usage WHERE member_id = 5 AND movie_id = 1) = 1);
PERFORM t_check('Monthly Pass: a free ticket earns no points', (SELECT COUNT(*) FROM point_log WHERE member_id = 5) = 0);
CALL sp_hold_seats(5, NULL, 1,1,'2026-11-05','00:30','3,4', t0, m2);
PERFORM t_expect_error('Monthly Pass: exactly one ticket per booking', 'CALL sp_pay_booking(' || m2 || ', 5, NULL, ''Monthly Pass'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Monthly Pass covers exactly one ticket per booking');
CALL sp_cancel_booking(m2);
CALL sp_hold_seats(5, NULL, 1,1,'2026-11-05','00:30','3', t0, m3);
PERFORM t_expect_error('Monthly Pass: the same movie cannot be watched twice', 'CALL sp_pay_booking(' || m3 || ', 5, NULL, ''Monthly Pass'', ''2026-11-05 13:02:00'', NULL, NULL)', 'Monthly Pass already used for this movie');
CALL sp_cancel_booking(m3);
CALL sp_hold_seats(5, NULL, 2,3,'2026-11-05','19:00','2', t0, m4);
CALL sp_pay_booking(m4, 5, NULL, 'Monthly Pass', '2026-11-05 13:02:00', mp4, mamount4);
PERFORM t_check('Monthly Pass: a non-Normal seat pays only the difference (400 - 160 = 240)', mamount4 = 240);
PERFORM t_check('Monthly Pass: the difference earns points (240)', (SELECT SUM(point_log_amount) FROM point_log WHERE member_id = 5) = 240);

-- ------------------------------------------------- 9. guests and customers
CALL sp_hold_seats(NULL, '0899999999', 2,3,'2026-12-03','19:00','2', t0, g1);
PERFORM t_check('guest: booking without customer keeps the phone number',
    (SELECT customer_id FROM booking WHERE booking_id = g1) IS NULL
    AND (SELECT booking_phone_number FROM booking WHERE booking_id = g1) = '0899999999');
CALL sp_pay_booking(g1, NULL, NULL, 'PromptPay', '2026-11-05 13:05:00', gp, gamount);
PERFORM t_check('guest: pays the list price (Pair seat at Pinklao = 400)', gamount = 400);

-- ------------------------------------------------- 10. nothing changed by failures
PERFORM t_check('data: failed requests added no bookings (11 successful holds in this file)', (SELECT COUNT(*) FROM booking) = bookings_before + 11);
END $$;

SELECT CASE WHEN passed THEN 'PASS ' ELSE 'FAIL ' END || name || COALESCE('  [' || detail || ']', '') AS result
FROM _test_result ORDER BY test_id;
SELECT COUNT(*) FILTER (WHERE passed) || ' passed, ' || COUNT(*) FILTER (WHERE NOT passed) || ' failed' AS summary
FROM _test_result;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM _test_result WHERE NOT passed) THEN
        RAISE EXCEPTION 'Some tests failed';
    END IF;
END $$;
