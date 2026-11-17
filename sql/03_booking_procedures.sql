-- load order: 01_schema.sql, 02_sample_data.sql, this file
--
-- every routine:
--     now = p_now (the caller passes now())
--     run inside the caller's transaction; any error undoes the whole call
--     out values come back as INOUT parameters (pass NULL)
--
-- fn_config(key)                  -> value from app_config
-- fn_showtime_start(date, time)   -> real start of a showtime
-- fn_ticket_price(showtime, seat) -> list price
-- fn_discounted_price(type, value, price)
-- fn_point_balance(member, date)  -> spendable points
-- sp_hold_seats                   book seats, PENDING
-- sp_pay_booking                  pay a booking; calls the three helpers below
--     sp_apply_monthly_pass       price the ticket with a Monthly Pass
--     sp_apply_coupon             price the tickets with a coupon
--     sp_earn_points              write the EARN row
-- sp_redeem_reward                spend points
-- sp_release_expired              free seats of expired holds
-- sp_cancel_booking               cancel a PENDING booking
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_config(p_key VARCHAR) RETURNS INT
LANGUAGE plpgsql STABLE AS $$
DECLARE v_value INT;
BEGIN
    SELECT config_value INTO v_value FROM app_config WHERE config_key = p_key;
    IF v_value IS NULL THEN
        RAISE EXCEPTION 'Missing app_config key';
    END IF;
    RETURN v_value;
END $$;

-- start = date + time
-- if hour(time) < BUSINESS_DAY_CUTOFF_HOUR: start = start + 1 day
CREATE OR REPLACE FUNCTION fn_showtime_start(p_date DATE, p_time TIME) RETURNS TIMESTAMP
LANGUAGE plpgsql STABLE AS $$
DECLARE v_start TIMESTAMP;
BEGIN
    v_start := p_date + p_time;
    IF EXTRACT(HOUR FROM p_time) < fn_config('BUSINESS_DAY_CUTOFF_HOUR') THEN
        v_start := v_start + INTERVAL '1 day';
    END IF;
    RETURN v_start;
END $$;

CREATE OR REPLACE FUNCTION fn_ticket_price(p_branch INT, p_theatre INT, p_date DATE, p_time TIME, p_seat INT)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE v_price NUMERIC(10,2);
BEGIN
    SELECT tp.ticket_price_amount INTO v_price
    FROM showtime st
    INNER JOIN theatre th ON th.branch_id = st.branch_id AND th.theatre_id = st.theatre_id
    INNER JOIN seat s ON s.branch_id = st.branch_id AND s.theatre_id = st.theatre_id AND s.seat_id = p_seat
    INNER JOIN ticket_price tp ON tp.branch_id = th.branch_id
        AND tp.theatre_type_id = th.theatre_type_id
        AND tp.seat_type_id = s.seat_type_id
        AND tp.showtime_dimension_id = st.showtime_dimension_id
        AND tp.price_period_id = st.price_period_id
        AND st.showtime_date BETWEEN tp.ticket_price_start_date AND tp.ticket_price_end_date
    WHERE st.branch_id = p_branch AND st.theatre_id = p_theatre
      AND st.showtime_date = p_date AND st.showtime_time = p_time;
    IF v_price IS NULL THEN
        RAISE EXCEPTION 'No ticket price for this seat and showtime';
    END IF;
    RETURN v_price;
END $$;

CREATE OR REPLACE FUNCTION fn_discounted_price(p_type VARCHAR, p_value NUMERIC, p_price NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_type = 'PERCENT' THEN
        RETURN ROUND(p_price - p_price * p_value / 100, 2);
    ELSIF p_type = 'AMOUNT' THEN
        RETURN GREATEST(p_price - p_value, 0);
    ELSIF p_type = 'FIXED_PRICE' THEN
        RETURN LEAST(p_price, p_value);
    END IF;
    RAISE EXCEPTION 'Unknown discount type';
END $$;

-- balance = sum(amount)
--           where amount < 0 or expired_date is null or expired_date >= on_date
CREATE OR REPLACE FUNCTION fn_point_balance(p_member INT, p_on DATE) RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(point_log_amount), 0)::INT
    FROM point_log
    WHERE member_id = p_member
      AND (point_log_amount < 0 OR point_log_expired_date IS NULL OR point_log_expired_date >= p_on);
$$;

-- delete tickets of PENDING bookings whose expiry < now
-- mark those bookings EXPIRED, return how many
CREATE OR REPLACE PROCEDURE sp_release_expired(p_now TIMESTAMP, INOUT p_released INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM ticket t USING booking b
    WHERE b.booking_id = t.booking_id
      AND b.booking_status = 'PENDING' AND b.booking_expire_datetime < p_now;
    UPDATE booking SET booking_status = 'EXPIRED'
    WHERE booking_status = 'PENDING' AND booking_expire_datetime < p_now;
    GET DIAGNOSTICS p_released = ROW_COUNT;
END $$;

-- sp_hold_seats(customer, phone, showtime, seat ids as an int array, now):
--     release expired holds
--     require showtime OPEN and start > now
--     phone = phone or customer's phone; require a phone
--     booking = new PENDING booking, expires now + HOLD_MINUTES
--     for each seat:
--         require seat ACTIVE
--         insert ticket at fn_ticket_price   (duplicate key -> 'Seat already taken')
--     require at least one seat
--     any failure undoes the booking and every ticket
CREATE OR REPLACE PROCEDURE sp_hold_seats(
    p_customer_id INT, p_phone VARCHAR,
    p_branch INT, p_theatre INT, p_date DATE, p_time TIME,
    p_seat_ids INT[], p_now TIMESTAMP,
    INOUT p_booking_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_seat INT;
    v_count INT;
    v_seats INT := 0;
    v_phone VARCHAR;
    v_released INT;
BEGIN
    p_booking_id := NULL;
    CALL sp_release_expired(p_now, v_released);

    SELECT COUNT(*) INTO v_count
    FROM showtime st
    INNER JOIN showtime_status ss ON ss.showtime_status_id = st.showtime_status_id
    WHERE st.branch_id = p_branch AND st.theatre_id = p_theatre
      AND st.showtime_date = p_date AND st.showtime_time = p_time
      AND ss.showtime_status_name = 'OPEN';
    IF v_count = 0 THEN
        RAISE EXCEPTION 'Showtime not found or not open';
    END IF;
    IF fn_showtime_start(p_date, p_time) <= p_now THEN
        RAISE EXCEPTION 'Showtime has already started';
    END IF;

    v_phone := p_phone;
    IF v_phone IS NULL AND p_customer_id IS NOT NULL THEN
        SELECT customer_phone_number INTO v_phone FROM customer WHERE customer_id = p_customer_id;
    END IF;
    IF v_phone IS NULL THEN
        RAISE EXCEPTION 'A contact phone number is required';
    END IF;

    INSERT INTO booking (customer_id, booking_phone_number, booking_datetime,
                         booking_expire_datetime, booking_status)
    VALUES (p_customer_id, v_phone, p_now,
            p_now + make_interval(mins => fn_config('HOLD_MINUTES')), 'PENDING')
    RETURNING booking_id INTO p_booking_id;
    UPDATE booking SET booking_code = 'BK' || LPAD(p_booking_id::TEXT, 4, '0')
    WHERE booking_id = p_booking_id;

    FOREACH v_seat IN ARRAY COALESCE(p_seat_ids, ARRAY[]::INT[])
    LOOP
        SELECT COUNT(*) INTO v_count FROM seat
        WHERE branch_id = p_branch AND theatre_id = p_theatre
          AND seat_id = v_seat AND seat_status = 'ACTIVE';
        IF v_count = 0 THEN
            RAISE EXCEPTION 'Seat not found or not available';
        END IF;
        -- primary key of ticket rejects a held or sold seat
        BEGIN
            INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time,
                                seat_id, booking_id, ticket_sale_price)
            VALUES (p_branch, p_theatre, p_date, p_time, v_seat, p_booking_id,
                    fn_ticket_price(p_branch, p_theatre, p_date, p_time, v_seat));
        EXCEPTION WHEN unique_violation THEN
            RAISE EXCEPTION 'Seat already taken for this showtime';
        END;
        v_seats := v_seats + 1;
    END LOOP;
    IF v_seats = 0 THEN
        RAISE EXCEPTION 'No seats given';
    END IF;
END $$;

-- sp_cancel_booking(booking):
--     lock the booking; require it exists and is PENDING
--     delete its tickets; mark it CANCELLED
CREATE OR REPLACE PROCEDURE sp_cancel_booking(p_booking_id INT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
BEGIN
    SELECT booking_status INTO v_status FROM booking WHERE booking_id = p_booking_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Booking not found';
    END IF;
    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Only a pending booking can be cancelled';
    END IF;
    DELETE FROM ticket WHERE booking_id = p_booking_id;
    UPDATE booking SET booking_status = 'CANCELLED' WHERE booking_id = p_booking_id;
END $$;

-- sp_apply_monthly_pass(booking, member, member type, now) -> ticket total:
--     require a pass member and exactly one ticket
--     require movie not excluded (country, genre) and not used before
--     ticket price = 0 if seat type and dimension qualify, else list - base price
--     update the ticket price; insert monthly_pass_usage
CREATE OR REPLACE PROCEDURE sp_apply_monthly_pass(
    p_booking_id INT, p_member_id INT, p_member_type INT, p_now TIMESTAMP,
    INOUT p_ticket_total NUMERIC DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_count INT;
    v_tickets INT;
    v_branch INT; v_theatre INT; v_date DATE; v_time TIME; v_seat INT;
    v_list NUMERIC(10,2);
    v_movie INT; v_seat_type INT; v_dimension INT; v_period INT; v_theatre_type INT;
    v_cond_seat_type INT; v_cond_dimension INT; v_cond_max INT;
    v_country VARCHAR;
    v_base NUMERIC(10,2);
BEGIN
    SELECT COUNT(*) INTO v_count FROM monthly_pass_member WHERE member_id = p_member_id;
    IF v_count = 0 THEN
        RAISE EXCEPTION 'Member does not hold a Monthly Pass';
    END IF;
    SELECT COUNT(*) INTO v_tickets FROM ticket WHERE booking_id = p_booking_id;
    IF v_tickets <> 1 THEN
        RAISE EXCEPTION 'Monthly Pass covers exactly one ticket per booking';
    END IF;

    SELECT t.branch_id, t.theatre_id, t.showtime_date, t.showtime_time, t.seat_id, t.ticket_sale_price,
           st.movie_id, s.seat_type_id, st.showtime_dimension_id, st.price_period_id, th.theatre_type_id
      INTO v_branch, v_theatre, v_date, v_time, v_seat, v_list,
           v_movie, v_seat_type, v_dimension, v_period, v_theatre_type
    FROM ticket t
    INNER JOIN showtime st ON st.branch_id = t.branch_id AND st.theatre_id = t.theatre_id
        AND st.showtime_date = t.showtime_date AND st.showtime_time = t.showtime_time
    INNER JOIN seat s ON s.branch_id = t.branch_id AND s.theatre_id = t.theatre_id AND s.seat_id = t.seat_id
    INNER JOIN theatre th ON th.branch_id = t.branch_id AND th.theatre_id = t.theatre_id
    WHERE t.booking_id = p_booking_id;

    -- excluded country or genre -> reject
    SELECT movie_country INTO v_country FROM movie WHERE movie_id = v_movie;
    SELECT COUNT(*) INTO v_count FROM member_type_condition
    WHERE member_type_id = p_member_type AND member_type_condition_type = 'EXCLUDED_COUNTRY'
      AND member_type_condition_value = v_country;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'This movie is not covered by Monthly Pass';
    END IF;
    SELECT COUNT(*) INTO v_count
    FROM member_type_condition c INNER JOIN movie_genre g ON g.genre_id = c.member_type_condition_value::INT
    WHERE c.member_type_id = p_member_type AND c.member_type_condition_type = 'EXCLUDED_GENRE_ID'
      AND g.movie_id = v_movie;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'This movie is not covered by Monthly Pass';
    END IF;

    -- uses of this movie >= MAX_PER_MOVIE -> reject
    SELECT member_type_condition_value::INT INTO v_cond_max FROM member_type_condition
    WHERE member_type_id = p_member_type AND member_type_condition_type = 'MAX_PER_MOVIE' LIMIT 1;
    SELECT COUNT(*) INTO v_count FROM monthly_pass_usage WHERE member_id = p_member_id AND movie_id = v_movie;
    IF v_count >= COALESCE(v_cond_max, 1) THEN
        RAISE EXCEPTION 'Monthly Pass already used for this movie';
    END IF;

    -- qualifying seat type and dimension -> free; else price = list - base
    SELECT member_type_condition_value::INT INTO v_cond_seat_type FROM member_type_condition
    WHERE member_type_id = p_member_type AND member_type_condition_type = 'SEAT_TYPE_ID' LIMIT 1;
    SELECT member_type_condition_value::INT INTO v_cond_dimension FROM member_type_condition
    WHERE member_type_id = p_member_type AND member_type_condition_type = 'DIMENSION_ID' LIMIT 1;
    IF (v_cond_seat_type IS NULL OR v_cond_seat_type = v_seat_type)
       AND (v_cond_dimension IS NULL OR v_cond_dimension = v_dimension) THEN
        p_ticket_total := 0;
    ELSE
        SELECT ticket_price_amount INTO v_base FROM ticket_price
        WHERE branch_id = v_branch AND theatre_type_id = v_theatre_type
          AND seat_type_id = COALESCE(v_cond_seat_type, v_seat_type)
          AND showtime_dimension_id = COALESCE(v_cond_dimension, v_dimension)
          AND price_period_id = v_period
          AND v_date BETWEEN ticket_price_start_date AND ticket_price_end_date;
        p_ticket_total := GREATEST(v_list - COALESCE(v_base, 0), 0);
    END IF;
    UPDATE ticket SET ticket_sale_price = p_ticket_total
    WHERE branch_id = v_branch AND theatre_id = v_theatre AND showtime_date = v_date
      AND showtime_time = v_time AND seat_id = v_seat;
    INSERT INTO monthly_pass_usage (member_id, movie_id, branch_id, theatre_id, showtime_date,
                                    showtime_time, seat_id, monthly_pass_usage_datetime)
    VALUES (p_member_id, v_movie, v_branch, v_theatre, v_date, v_time, v_seat, p_now);
END $$;

-- sp_apply_coupon(booking, code, now) -> coupon id, ticket total after the coupon:
--     lock the coupon row; require code exists and valid today
--     require valid at the branch of every ticket and under its usage limit
--     ticket total = sum(fn_discounted_price(ticket price))
CREATE OR REPLACE PROCEDURE sp_apply_coupon(
    p_booking_id INT, p_code VARCHAR, p_now TIMESTAMP,
    INOUT p_discount_id INT DEFAULT NULL, INOUT p_ticket_total NUMERIC DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_count INT;
    v_dtype VARCHAR;
    v_dvalue NUMERIC;
    v_dstart DATE;
    v_dend DATE;
    v_dlimit INT;
BEGIN
    SELECT discount_id, discount_type, discount_value, discount_start_date,
           discount_end_date, discount_usage_limit
      INTO p_discount_id, v_dtype, v_dvalue, v_dstart, v_dend, v_dlimit
    FROM discount WHERE discount_code = p_code FOR UPDATE;
    IF p_discount_id IS NULL THEN
        RAISE EXCEPTION 'Discount code not found';
    END IF;
    IF (v_dstart IS NOT NULL AND p_now::DATE < v_dstart) OR (v_dend IS NOT NULL AND p_now::DATE > v_dend) THEN
        RAISE EXCEPTION 'Discount is not valid today';
    END IF;
    SELECT COUNT(*) INTO v_count FROM ticket t
    WHERE t.booking_id = p_booking_id
      AND NOT EXISTS (SELECT 1 FROM discount_branch db
                      WHERE db.discount_id = p_discount_id AND db.branch_id = t.branch_id);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Discount is not valid at this branch';
    END IF;
    IF v_dlimit IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count FROM payment
        WHERE discount_id = p_discount_id AND payment_status = 'SUCCESS';
        IF v_count >= v_dlimit THEN
            RAISE EXCEPTION 'Discount usage limit reached';
        END IF;
    END IF;
    SELECT COALESCE(SUM(fn_discounted_price(v_dtype, v_dvalue, ticket_sale_price)), 0)
      INTO p_ticket_total FROM ticket WHERE booking_id = p_booking_id;
END $$;

-- sp_earn_points(member, payment, ticket total, now):
--     points = floor(ticket total * POINTS_PER_BAHT)     food excluded
--     points > 0 -> insert EARN row expiring in POINT_EXPIRY_MONTHS
CREATE OR REPLACE PROCEDURE sp_earn_points(
    p_member_id INT, p_payment_id INT, p_ticket_total NUMERIC, p_now TIMESTAMP)
LANGUAGE plpgsql AS $$
DECLARE v_points INT;
BEGIN
    v_points := FLOOR(p_ticket_total * fn_config('POINTS_PER_BAHT'));
    IF v_points > 0 THEN
        INSERT INTO point_log (member_id, payment_id, reward_id, branch_id, point_log_amount,
                               point_log_type, point_log_datetime, point_log_expired_date)
        VALUES (p_member_id, p_payment_id, NULL, NULL, v_points, 'EARN', p_now,
                (p_now::DATE + make_interval(months => fn_config('POINT_EXPIRY_MONTHS')))::DATE);
    END IF;
END $$;

-- sp_pay_booking(booking, member or NULL, coupon code or NULL, method, now):
--     lock the booking; require PENDING and not expired
--     ticket total = sum(ticket prices)
--     member given: require active on now and owned by the booking's customer
--     method 'Monthly Pass': require member and no coupon; sp_apply_monthly_pass
--     coupon given: sp_apply_coupon
--     amount = ticket total + sum(food quantity * sale price)
--     insert payment; booking = PAID
--     member given: sp_earn_points
CREATE OR REPLACE PROCEDURE sp_pay_booking(
    p_booking_id INT, p_member_id INT, p_discount_code VARCHAR,
    p_method VARCHAR, p_now TIMESTAMP,
    INOUT p_payment_id INT DEFAULT NULL, INOUT p_amount NUMERIC DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_expire TIMESTAMP;
    v_customer INT;
    v_member_customer INT;
    v_member_type INT;
    v_discount_id INT;
    v_ticket_total NUMERIC(10,2);
    v_product_total NUMERIC(10,2);
BEGIN
    p_payment_id := NULL;
    p_amount := NULL;

    SELECT booking_status, booking_expire_datetime, customer_id
      INTO v_status, v_expire, v_customer
    FROM booking WHERE booking_id = p_booking_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Booking not found';
    END IF;
    IF v_status = 'PAID' THEN
        RAISE EXCEPTION 'Booking is already paid';
    END IF;
    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Booking is not pending';
    END IF;
    IF v_expire < p_now THEN
        -- seats are freed by the next sp_release_expired or sp_hold_seats
        RAISE EXCEPTION 'Hold has expired';
    END IF;

    SELECT COALESCE(SUM(ticket_sale_price), 0) INTO v_ticket_total
    FROM ticket WHERE booking_id = p_booking_id;

    IF p_member_id IS NOT NULL THEN
        SELECT r.customer_id, r.member_type_id INTO v_member_customer, v_member_type
        FROM member m INNER JOIN register r ON r.register_id = m.register_id
        WHERE m.member_id = p_member_id
          AND m.member_start_date <= p_now::DATE
          AND (m.member_end_date IS NULL OR m.member_end_date >= p_now::DATE);
        IF v_member_customer IS NULL THEN
            RAISE EXCEPTION 'Member not found or membership not active';
        END IF;
        IF v_customer IS NULL OR v_customer <> v_member_customer THEN
            RAISE EXCEPTION 'Member does not belong to the booking customer';
        END IF;
    END IF;

    IF p_method = 'Monthly Pass' THEN
        IF p_member_id IS NULL THEN
            RAISE EXCEPTION 'Monthly Pass needs a member';
        END IF;
        IF p_discount_code IS NOT NULL THEN
            RAISE EXCEPTION 'A coupon cannot be combined with Monthly Pass';
        END IF;
        CALL sp_apply_monthly_pass(p_booking_id, p_member_id, v_member_type, p_now, v_ticket_total);
    END IF;

    IF p_discount_code IS NOT NULL THEN
        CALL sp_apply_coupon(p_booking_id, p_discount_code, p_now, v_discount_id, v_ticket_total);
    END IF;

    SELECT COALESCE(SUM(booking_product_quantity * booking_product_sale_price), 0)
      INTO v_product_total FROM booking_product WHERE booking_id = p_booking_id;

    p_amount := v_ticket_total + v_product_total;
    INSERT INTO payment (booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method)
    VALUES (p_booking_id, p_member_id, v_discount_id, p_now, 'SUCCESS', p_method)
    RETURNING payment_id INTO p_payment_id;
    UPDATE booking SET booking_status = 'PAID' WHERE booking_id = p_booking_id;

    IF p_member_id IS NOT NULL THEN
        CALL sp_earn_points(p_member_id, p_payment_id, v_ticket_total, p_now);
    END IF;
END $$;

-- sp_redeem_reward(member, reward, branch, now):
--     lock the member row; require active on now
--     cost = branch_reward cost; require the reward at this branch
--     require fn_point_balance(member, today) >= cost
--     insert REDEEM row of -cost
CREATE OR REPLACE PROCEDURE sp_redeem_reward(
    p_member_id INT, p_reward_id INT, p_branch_id INT, p_now TIMESTAMP,
    INOUT p_point_log_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_member INT;
    v_cost INT;
BEGIN
    p_point_log_id := NULL;
    -- lock: two redemptions of one member take turns
    SELECT member_id INTO v_member FROM member
    WHERE member_id = p_member_id
      AND member_start_date <= p_now::DATE
      AND (member_end_date IS NULL OR member_end_date >= p_now::DATE)
    FOR UPDATE;
    IF v_member IS NULL THEN
        RAISE EXCEPTION 'Member not found or membership not active';
    END IF;
    SELECT branch_reward_point_cost INTO v_cost FROM branch_reward
    WHERE reward_id = p_reward_id AND branch_id = p_branch_id;
    IF v_cost IS NULL THEN
        RAISE EXCEPTION 'Reward is not available at this branch';
    END IF;
    IF fn_point_balance(p_member_id, p_now::DATE) < v_cost THEN
        RAISE EXCEPTION 'Not enough points';
    END IF;
    INSERT INTO point_log (member_id, payment_id, reward_id, branch_id, point_log_amount,
                           point_log_type, point_log_datetime, point_log_expired_date)
    VALUES (p_member_id, NULL, p_reward_id, p_branch_id, -v_cost, 'REDEEM', p_now, NULL)
    RETURNING point_log_id INTO p_point_log_id;
END $$;
