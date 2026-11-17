-- ============================================================================
-- 02_import_all_in_one.sql: one-file import for phpMyAdmin (MySQL 5.7 / 8.0, MariaDB 10.x)
-- Creates the database cinema_booking, the 57 tables of the course design and the
-- sample data (fictional people and movies).
-- How to use: phpMyAdmin > Import > choose this file > Go.
-- If the tables already exist, run reset.sql first.
-- Simplified types for the demo: VARCHAR, INT and DATE only. Time = 'HH:MM',
-- date-time = 'YYYY-MM-DD HH:MM:SS', money = whole baht.
-- Only basic building blocks: PRIMARY KEY, FOREIGN KEY, NOT NULL (and one UNIQUE on the
-- monthly-pass usage table). Create referenced tables first, then the tables that reference them.
-- ============================================================================
CREATE DATABASE IF NOT EXISTS cinema_booking CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cinema_booking;
SET NAMES utf8mb4;

-- ============================================================================
-- Zone 1: movies (14 entities)
-- ============================================================================

CREATE TABLE language (
    language_id    INT          NOT NULL,
    language_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (language_id)
);

CREATE TABLE rate (
    rate_id    INT          NOT NULL,
    rate_name  VARCHAR(50)  NOT NULL,
    PRIMARY KEY (rate_id)
);

CREATE TABLE genre (
    genre_id    INT          NOT NULL,
    genre_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (genre_id)
);

CREATE TABLE person (
    person_id     INT          NOT NULL,
    person_name   VARCHAR(150) NOT NULL,
    person_image  VARCHAR(255),
    PRIMARY KEY (person_id)
);

CREATE TABLE role (
    role_id    INT          NOT NULL,
    role_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (role_id)
);

CREATE TABLE media_format (
    media_format_id    INT          NOT NULL,
    media_format_name  VARCHAR(50)  NOT NULL,   -- image, video
    PRIMARY KEY (media_format_id)
);

CREATE TABLE media (
    media_id         INT          NOT NULL,
    media_format_id  INT          NOT NULL,
    media_name       VARCHAR(255) NOT NULL,
    PRIMARY KEY (media_id),
    FOREIGN KEY (media_format_id) REFERENCES media_format (media_format_id)
);

CREATE TABLE movie (
    movie_id            INT          NOT NULL,
    rate_id             INT          NOT NULL,
    movie_country       VARCHAR(100),
    movie_release_date  DATE,
    movie_synopsis      VARCHAR(1000),
    poster_media_id     INT,
    banner_media_id     INT,
    PRIMARY KEY (movie_id),
    FOREIGN KEY (rate_id) REFERENCES rate (rate_id),
    FOREIGN KEY (poster_media_id) REFERENCES media (media_id),
    FOREIGN KEY (banner_media_id) REFERENCES media (media_id)
);

-- One screening version = 1 movie + 1 audio language (a movie can have several versions by audio language; subtitles are per showtime: showtime_subtitle)
CREATE TABLE movie_version (
    movie_id             INT          NOT NULL,
    audio_language_id    INT          NOT NULL,   -- audio language
    movie_runtime        INT          NOT NULL,   -- minutes (differs by audio language)
    PRIMARY KEY (movie_id, audio_language_id),
    FOREIGN KEY (movie_id)             REFERENCES movie (movie_id),
    FOREIGN KEY (audio_language_id)    REFERENCES language (language_id)
);

CREATE TABLE movie_media (
    movie_id  INT NOT NULL,
    media_id  INT NOT NULL,
    PRIMARY KEY (movie_id, media_id),
    FOREIGN KEY (movie_id) REFERENCES movie (movie_id),
    FOREIGN KEY (media_id) REFERENCES media (media_id)
);

CREATE TABLE movie_genre (
    movie_id  INT NOT NULL,
    genre_id  INT NOT NULL,
    PRIMARY KEY (movie_id, genre_id),
    FOREIGN KEY (movie_id) REFERENCES movie (movie_id),
    FOREIGN KEY (genre_id) REFERENCES genre (genre_id)
);

-- One person can have several roles in one movie (director + actor) because role_id is part of the key
CREATE TABLE movie_credit (
    movie_id   INT NOT NULL,
    person_id  INT NOT NULL,
    role_id    INT NOT NULL,
    PRIMARY KEY (movie_id, person_id, role_id),
    FOREIGN KEY (movie_id)  REFERENCES movie (movie_id),
    FOREIGN KEY (person_id) REFERENCES person (person_id),
    FOREIGN KEY (role_id)   REFERENCES role (role_id)
);

CREATE TABLE movie_name (
    movie_id     INT          NOT NULL,
    language_id  INT          NOT NULL,
    movie_name   VARCHAR(255) NOT NULL,
    PRIMARY KEY (movie_id, language_id),
    FOREIGN KEY (movie_id)    REFERENCES movie (movie_id),
    FOREIGN KEY (language_id) REFERENCES language (language_id)
);

CREATE TABLE movie_rerelease (
    movie_id         INT NOT NULL,
    movie_rerelease_number     INT NOT NULL,
    movie_rerelease_date   DATE,
    movie_rerelease_note   VARCHAR(255),
    PRIMARY KEY (movie_id, movie_rerelease_number),
    FOREIGN KEY (movie_id) REFERENCES movie (movie_id)
);

-- ============================================================================
-- Zone 2: places, showtimes and prices (13 entities)
-- ============================================================================

CREATE TABLE branch (
    branch_id         INT          NOT NULL,
    branch_name       VARCHAR(150) NOT NULL,
    branch_address    VARCHAR(255),
    branch_latitude   VARCHAR(20),
    branch_longitude  VARCHAR(20),
    branch_logo       VARCHAR(255),
    PRIMARY KEY (branch_id)
);

CREATE TABLE theatre_type (
    theatre_type_id      INT          NOT NULL,
    theatre_type_name    VARCHAR(100) NOT NULL,
    theatre_type_logo    VARCHAR(255),
    PRIMARY KEY (theatre_type_id)
);

CREATE TABLE sound_system (
    sound_id    INT          NOT NULL,
    sound_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (sound_id)
);

CREATE TABLE screen_format (
    screen_id    INT          NOT NULL,
    screen_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (screen_id)
);

CREATE TABLE theatre (
    theatre_id       INT          NOT NULL,
    branch_id        INT          NOT NULL,
    theatre_type_id  INT          NOT NULL,
    sound_id         INT          NOT NULL,
    screen_id        INT          NOT NULL,
    theatre_name     VARCHAR(100) NOT NULL,
    PRIMARY KEY (branch_id, theatre_id),
    FOREIGN KEY (branch_id)       REFERENCES branch (branch_id),
    FOREIGN KEY (theatre_type_id) REFERENCES theatre_type (theatre_type_id),
    FOREIGN KEY (sound_id)        REFERENCES sound_system (sound_id),
    FOREIGN KEY (screen_id)       REFERENCES screen_format (screen_id)
);

CREATE TABLE seat_type (
    seat_type_id        INT          NOT NULL,
    seat_type_name      VARCHAR(100) NOT NULL,
    seat_type_capacity  INT          NOT NULL,   -- people per seat (pair sofa = 2)
    PRIMARY KEY (seat_type_id)
);

-- seat_id is a running number inside the theatre (theatre 1 and 2 can both start at 1)
-- Changing the seat layout: never delete, never overwrite, never reuse an id
-- add a seat = add a new row, remove a seat = change seat_status,
-- change type = retire the old row and add a new row at the same position
CREATE TABLE seat (
    branch_id      INT           NOT NULL,
    theatre_id    INT         NOT NULL,
    seat_id       INT         NOT NULL,
    seat_row      VARCHAR(5)  NOT NULL,
    seat_number   INT         NOT NULL,
    seat_status   VARCHAR(30) NOT NULL,
    seat_type_id  INT         NOT NULL,
    PRIMARY KEY (branch_id, theatre_id, seat_id),
    FOREIGN KEY (branch_id, theatre_id) REFERENCES theatre (branch_id, theatre_id),
    FOREIGN KEY (seat_type_id) REFERENCES seat_type (seat_type_id)
);

CREATE TABLE showtime_status (
    showtime_status_id    INT          NOT NULL,
    showtime_status_name  VARCHAR(50)  NOT NULL,
    PRIMARY KEY (showtime_status_id)
);

-- Projection dimension, e.g. 2D, 3D
CREATE TABLE showtime_dimension (
    showtime_dimension_id    INT         NOT NULL,
    showtime_dimension_name  VARCHAR(20) NOT NULL,
    PRIMARY KEY (showtime_dimension_id)
);

-- Price period: a group of "day type + time of day" with its own ticket prices, e.g. Thursday or late night.
-- The app picks the period for each showtime when the showtime is created (stored in showtime.price_period_id). Periods must not overlap.
-- day_type: 'THU' = Thursday, 'OTHER' = any other day (uses the business date of the showtime)
CREATE TABLE price_period (
    price_period_id          INT           NOT NULL,
    price_period_name        VARCHAR(100)  NOT NULL,
    price_period_day_type    VARCHAR(20)   NOT NULL,
    price_period_start_time  VARCHAR(8)    NOT NULL,
    price_period_end_time    VARCHAR(8)    NOT NULL,
    PRIMARY KEY (price_period_id)
);

-- showtime_date = business date (a show that starts after midnight but before the cut-off, e.g. 04:00, belongs to the previous day)
-- showtime_end_time = time the theatre is ready for the next show (includes ads, trailers,
-- anthem, intermission if any, and cleaning time); set by the theatre
CREATE TABLE showtime (
    branch_id      INT           NOT NULL,
    theatre_id             INT         NOT NULL,
    showtime_date          DATE        NOT NULL,
    showtime_time          VARCHAR(8)        NOT NULL,
    showtime_end_time      VARCHAR(8)        NOT NULL,
    movie_id               INT         NOT NULL,
    audio_language_id            INT         NOT NULL,   -- audio language of the version shown
    showtime_dimension_id  INT         NOT NULL,
    showtime_status_id     INT         NOT NULL,
    price_period_id        INT         NOT NULL,
    PRIMARY KEY (branch_id, theatre_id, showtime_date, showtime_time),
    FOREIGN KEY (branch_id, theatre_id) REFERENCES theatre (branch_id, theatre_id),
    FOREIGN KEY (movie_id, audio_language_id)
        REFERENCES movie_version (movie_id, audio_language_id),
    FOREIGN KEY (showtime_dimension_id) REFERENCES showtime_dimension (showtime_dimension_id),
    FOREIGN KEY (showtime_status_id)    REFERENCES showtime_status (showtime_status_id),
    FOREIGN KEY (price_period_id)       REFERENCES price_period (price_period_id)
);

-- Subtitles of a showtime: 0 to many languages per showtime (no row = no subtitle)
CREATE TABLE showtime_subtitle (
    branch_id             INT  NOT NULL,
    theatre_id            INT  NOT NULL,
    showtime_date         DATE NOT NULL,
    showtime_time         VARCHAR(8) NOT NULL,
    subtitle_language_id  INT  NOT NULL,
    PRIMARY KEY (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id),
    FOREIGN KEY (branch_id, theatre_id, showtime_date, showtime_time)
        REFERENCES showtime (branch_id, theatre_id, showtime_date, showtime_time),
    FOREIGN KEY (subtitle_language_id) REFERENCES language (language_id)
);

-- Ticket price per seat: branch + theatre type + seat type + showtime dimension + price period.
-- 1 row = one price for one set of conditions in one date range. To change a price, add a new row with a new start date (ticket_price_end_date '9999-12-31' = no end).
-- To find the price of a showtime: use that showtime's price_period_id and a show date between start_date and end_date.
CREATE TABLE ticket_price (
    branch_id                INT           NOT NULL,
    theatre_type_id          INT           NOT NULL,
    seat_type_id             INT           NOT NULL,
    showtime_dimension_id    INT           NOT NULL,
    price_period_id          INT           NOT NULL,
    ticket_price_start_date  DATE          NOT NULL,
    ticket_price_end_date    DATE          NOT NULL,
    ticket_price_amount      INT           NOT NULL,
    PRIMARY KEY (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id,
                 ticket_price_start_date),
    FOREIGN KEY (branch_id)             REFERENCES branch (branch_id),
    FOREIGN KEY (theatre_type_id)       REFERENCES theatre_type (theatre_type_id),
    FOREIGN KEY (seat_type_id)          REFERENCES seat_type (seat_type_id),
    FOREIGN KEY (showtime_dimension_id) REFERENCES showtime_dimension (showtime_dimension_id),
    FOREIGN KEY (price_period_id)       REFERENCES price_period (price_period_id)
);

-- ============================================================================
-- Zone 3: customers, members and promotions (17 entities)
-- ============================================================================

CREATE TABLE customer (
    customer_id             INT          NOT NULL,
    customer_first_name     VARCHAR(100) NOT NULL,
    customer_last_name      VARCHAR(100) NOT NULL,
    customer_email          VARCHAR(150),
    customer_phone_number       VARCHAR(20) NOT NULL,
    customer_address        VARCHAR(255),
    customer_date_of_birth  DATE,
    PRIMARY KEY (customer_id)
);

CREATE TABLE favorite_branch (
    customer_id  INT NOT NULL,
    branch_id    INT NOT NULL,
    PRIMARY KEY (customer_id, branch_id),
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
    FOREIGN KEY (branch_id)   REFERENCES branch (branch_id)
);

CREATE TABLE member_type (
    member_type_id             INT           NOT NULL,
    member_type_name           VARCHAR(100)  NOT NULL,
    member_type_class          VARCHAR(50),
    member_type_price          INT,
    member_type_duration       INT,
    PRIMARY KEY (member_type_id)
);

CREATE TABLE member_type_condition (
    member_type_condition_id      INT          NOT NULL,
    member_type_id                INT          NOT NULL,
    member_type_condition_type    VARCHAR(50)  NOT NULL,   -- MAX_PER_MOVIE, MIN_GAP_MINUTES, SEAT_TYPE_ID, DIMENSION_ID
    member_type_condition_value   VARCHAR(50)  NOT NULL,
    member_type_condition_detail  VARCHAR(255),
    PRIMARY KEY (member_type_condition_id),
    FOREIGN KEY (member_type_id) REFERENCES member_type (member_type_id)
);

CREATE TABLE register (
    register_id        INT         NOT NULL,
    customer_id        INT         NOT NULL,
    member_type_id     INT         NOT NULL,
    register_datetime  VARCHAR(19) NOT NULL,
    register_status    VARCHAR(30) NOT NULL,
    PRIMARY KEY (register_id),
    FOREIGN KEY (customer_id)    REFERENCES customer (customer_id),
    FOREIGN KEY (member_type_id) REFERENCES member_type (member_type_id)
);

CREATE TABLE member (
    member_id          INT   NOT NULL,
    register_id        INT   NOT NULL,
    member_start_date  DATE  NOT NULL,
    member_end_date    DATE,
    PRIMARY KEY (member_id),
    FOREIGN KEY (register_id) REFERENCES register (register_id)
);

-- Monthly Pass members (a specialization of member): member_id is both the PK and a FK to member.
-- monthly_pass_usage points here, so an Monthly Pass benefit can only be saved for a member listed here (the app adds the row when Monthly Pass is approved).
CREATE TABLE monthly_pass_member (
    member_id  INT NOT NULL,
    PRIMARY KEY (member_id),
    FOREIGN KEY (member_id) REFERENCES member (member_id)
);

-- Issued membership cards: one member can have several cards over time (lost card, reissue; every card number is kept)
-- no row = app-only member - member_card_status: ACTIVE = the card in use, CANCELLED = cancelled (lost or replaced)
CREATE TABLE member_card (
    member_id               INT         NOT NULL,
    member_card_issue_date  DATE        NOT NULL,
    member_card_no          VARCHAR(30) NOT NULL,
    member_card_status      VARCHAR(20) NOT NULL,
    PRIMARY KEY (member_id, member_card_issue_date),
    FOREIGN KEY (member_id) REFERENCES member (member_id)
);

CREATE TABLE reward (
    reward_id    INT          NOT NULL,
    reward_name  VARCHAR(150) NOT NULL,
    reward_type  VARCHAR(50),
    PRIMARY KEY (reward_id)
);

CREATE TABLE branch_reward (
    reward_id                 INT NOT NULL,
    branch_id                 INT NOT NULL,
    branch_reward_point_cost  INT NOT NULL,
    PRIMARY KEY (reward_id, branch_id),
    FOREIGN KEY (reward_id) REFERENCES reward (reward_id),
    FOREIGN KEY (branch_id) REFERENCES branch (branch_id)
);

-- Rewards tied to specific movies (generic rewards such as tickets or popcorn have no row here)
CREATE TABLE movie_reward (
    reward_id  INT NOT NULL,
    movie_id   INT NOT NULL,
    PRIMARY KEY (reward_id, movie_id),
    FOREIGN KEY (reward_id) REFERENCES reward (reward_id),
    FOREIGN KEY (movie_id)  REFERENCES movie (movie_id)
);

CREATE TABLE partner (
    partner_id    INT          NOT NULL,
    partner_name  VARCHAR(150) NOT NULL,
    partner_logo  VARCHAR(255),
    PRIMARY KEY (partner_id)
);

CREATE TABLE discount (
    discount_id            INT           NOT NULL,
    partner_id             INT,
    discount_name          VARCHAR(150)  NOT NULL,
    discount_type          VARCHAR(20)   NOT NULL,
    discount_value         INT  NOT NULL,
    discount_start_date    DATE,
    discount_end_date  DATE,
    discount_detail        VARCHAR(1000),
    discount_code          VARCHAR(50),
    discount_usage_limit   INT,
    discount_image         VARCHAR(255),
    PRIMARY KEY (discount_id),
    FOREIGN KEY (partner_id) REFERENCES partner (partner_id)
);

CREATE TABLE discount_branch (
    discount_id  INT NOT NULL,
    branch_id    INT NOT NULL,
    PRIMARY KEY (discount_id, branch_id),
    FOREIGN KEY (discount_id) REFERENCES discount (discount_id),
    FOREIGN KEY (branch_id)   REFERENCES branch (branch_id)
);

CREATE TABLE news (
    news_id                     INT          NOT NULL,
    news_name                   VARCHAR(200) NOT NULL,
    news_type                   VARCHAR(50),
    news_detail                 VARCHAR(1000),
    news_image                  VARCHAR(255),
    news_start_date             DATE,
    news_end_date               DATE,
    news_participation_limit    INT,
    PRIMARY KEY (news_id)
);

CREATE TABLE discount_news (
    news_id      INT NOT NULL,
    discount_id  INT NOT NULL,
    PRIMARY KEY (news_id, discount_id),
    FOREIGN KEY (news_id)     REFERENCES news (news_id),
    FOREIGN KEY (discount_id) REFERENCES discount (discount_id)
);

-- branch_id may be empty (news not tied to a branch)
CREATE TABLE customer_news (
    customer_news_id        INT         NOT NULL,
    customer_id             INT         NOT NULL,
    news_id                 INT         NOT NULL,
    branch_id               INT,
    customer_news_datetime  VARCHAR(19)   NOT NULL,
    customer_news_result    VARCHAR(100),
    PRIMARY KEY (customer_news_id),
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
    FOREIGN KEY (news_id)     REFERENCES news (news_id),
    FOREIGN KEY (branch_id)   REFERENCES branch (branch_id)
);

-- ============================================================================
-- Zone 4: bookings, tickets, payments, points and products (13 entities)
-- ============================================================================

-- Hold ticket: a held ticket is a ticket row of a booking whose booking_status = PENDING
-- after booking_expire_datetime, if still unpaid, the app deletes the ticket to free the seat
-- A guest booking (no login) has no customer: customer_id may be empty, the phone number typed at booking time is in booking_phone_number.
-- A logged-in buyer: customer_id points to the account and is not asked for a phone; the app copies the account phone into booking_phone_number (every booking has a contact phone).
CREATE TABLE booking (
    booking_id               INT         NOT NULL,
    customer_id              INT,
    booking_phone_number      VARCHAR(20) NOT NULL,
    booking_datetime         VARCHAR(19)   NOT NULL,
    booking_expire_datetime  VARCHAR(19),
    booking_status           VARCHAR(30) NOT NULL,
    booking_code             VARCHAR(30),
    PRIMARY KEY (booking_id),
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
);

-- 4-column PK: the same seat of the same showtime cannot be sold twice
-- one theatre_id is shared by the FK to showtime and the FK to seat
-- so a seat of another theatre cannot be booked for this showtime
CREATE TABLE ticket (
    branch_id      INT           NOT NULL,
    theatre_id     INT           NOT NULL,
    showtime_date  DATE          NOT NULL,
    showtime_time  VARCHAR(8)          NOT NULL,
    seat_id        INT           NOT NULL,
    booking_id     INT           NOT NULL,
    -- ticket price at the time of sale (the app finds it in ticket_price by the showtime's price period; for an Monthly Pass ticket the app charges only the difference, Normal 2D seat = 0)
    ticket_sale_price  INT           NOT NULL,
    PRIMARY KEY (branch_id, theatre_id, showtime_date, showtime_time, seat_id),
    FOREIGN KEY (branch_id, theatre_id, showtime_date, showtime_time)
        REFERENCES showtime (branch_id, theatre_id, showtime_date, showtime_time),
    FOREIGN KEY (branch_id, theatre_id, seat_id)
        REFERENCES seat (branch_id, theatre_id, seat_id),
    FOREIGN KEY (booking_id) REFERENCES booking (booking_id)
);

-- Monthly Pass benefit: a member cannot use it twice for the same movie (PK = member + movie)
CREATE TABLE monthly_pass_usage (
    member_id             INT       NOT NULL,
    movie_id              INT       NOT NULL,
    branch_id             INT       NOT NULL,
    theatre_id            INT       NOT NULL,
    showtime_date         DATE      NOT NULL,
    showtime_time         VARCHAR(8)      NOT NULL,
    seat_id               INT       NOT NULL,
    monthly_pass_usage_datetime  VARCHAR(19) NOT NULL,
    PRIMARY KEY (member_id, movie_id),
    FOREIGN KEY (member_id) REFERENCES monthly_pass_member (member_id),
    FOREIGN KEY (movie_id)  REFERENCES movie (movie_id),
    UNIQUE (branch_id, theatre_id, showtime_date, showtime_time, seat_id),   -- one ticket can use the monthly-pass benefit at most once
    FOREIGN KEY (branch_id, theatre_id, showtime_date, showtime_time, seat_id)
        REFERENCES ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id)
);

-- member_id and discount_id may be empty (buyer is not a member / no discount used)
CREATE TABLE payment (
    payment_id           INT           NOT NULL,
    booking_id           INT           NOT NULL,
    member_id            INT,
    discount_id          INT,
    payment_datetime     VARCHAR(19)     NOT NULL,
    payment_status       VARCHAR(30)   NOT NULL,
    payment_method       VARCHAR(50),
    PRIMARY KEY (payment_id),
    FOREIGN KEY (booking_id)  REFERENCES booking (booking_id),
    FOREIGN KEY (member_id)   REFERENCES member (member_id),
    FOREIGN KEY (discount_id) REFERENCES discount (discount_id)
);

-- branch_id and reward_id may be empty together (points not related to a reward)
CREATE TABLE point_log (
    point_log_id            INT         NOT NULL,
    member_id               INT         NOT NULL,
    payment_id              INT,
    reward_id               INT,
    branch_id               INT,
    point_log_amount        INT         NOT NULL,
    point_log_type          VARCHAR(30) NOT NULL,
    point_log_datetime      VARCHAR(19)   NOT NULL,
    point_log_expired_date  DATE,
    PRIMARY KEY (point_log_id),
    FOREIGN KEY (member_id)  REFERENCES member (member_id),
    FOREIGN KEY (payment_id) REFERENCES payment (payment_id),
    FOREIGN KEY (reward_id, branch_id)
        REFERENCES branch_reward (reward_id, branch_id)
);

CREATE TABLE size (
    size_id      INT NOT NULL,
    size_amount  VARCHAR(50) NOT NULL,
    PRIMARY KEY (size_id)
);

CREATE TABLE flavor (
    flavor_id    INT          NOT NULL,
    flavor_name  VARCHAR(100) NOT NULL,
    PRIMARY KEY (flavor_id)
);

-- size_id may be empty (products without a size)
CREATE TABLE product (
    product_id     INT          NOT NULL,
    size_id        INT,
    product_name   VARCHAR(150) NOT NULL,
    product_type   VARCHAR(50),
    product_image  VARCHAR(255),
    PRIMARY KEY (product_id),
    FOREIGN KEY (size_id) REFERENCES size (size_id)
);

-- product set (recursive M:N): one set contains several products
CREATE TABLE product_set (
    set_product_id        INT NOT NULL,
    item_product_id       INT NOT NULL,
    product_set_quantity  INT NOT NULL,
    PRIMARY KEY (set_product_id, item_product_id),
    FOREIGN KEY (set_product_id)  REFERENCES product (product_id),
    FOREIGN KEY (item_product_id) REFERENCES product (product_id)
);

CREATE TABLE product_flavor (
    product_id                  INT           NOT NULL,
    flavor_id                   INT           NOT NULL,
    product_flavor_extra_price  INT,
    PRIMARY KEY (product_id, flavor_id),
    FOREIGN KEY (product_id) REFERENCES product (product_id),
    FOREIGN KEY (flavor_id)  REFERENCES flavor (flavor_id)
);

CREATE TABLE product_price (
    product_id            INT           NOT NULL,
    branch_id             INT           NOT NULL,
    product_price_start_date  DATE          NOT NULL,
    product_price_end_date    DATE          NOT NULL,
    product_price_amount      INT           NOT NULL,
    PRIMARY KEY (product_id, branch_id, product_price_start_date),
    FOREIGN KEY (product_id) REFERENCES product (product_id),
    FOREIGN KEY (branch_id)  REFERENCES branch (branch_id)
);

CREATE TABLE booking_product (
    booking_product_id          INT           NOT NULL,
    booking_id                  INT           NOT NULL,
    product_id                  INT           NOT NULL,
    branch_id                   INT           NOT NULL,
    booking_product_quantity    INT           NOT NULL,
    -- price per item at the time of the order = product_price_amount of the branch + the flavor extras (the app calculates it when the order is made)
    booking_product_sale_price  INT           NOT NULL,
    booking_product_note        VARCHAR(255),
    PRIMARY KEY (booking_product_id),
    FOREIGN KEY (booking_id) REFERENCES booking (booking_id),
    FOREIGN KEY (product_id) REFERENCES product (product_id),
    FOREIGN KEY (branch_id)  REFERENCES branch (branch_id)
);

CREATE TABLE booking_product_flavor (
    booking_product_id  INT NOT NULL,
    flavor_id           INT NOT NULL,
    PRIMARY KEY (booking_product_id, flavor_id),
    FOREIGN KEY (booking_product_id) REFERENCES booking_product (booking_product_id),
    FOREIGN KEY (flavor_id)          REFERENCES flavor (flavor_id)
);


-- ============================================================================
-- Sample data for every table (fictional, for explanation only)
-- In the same order as the table creation
-- ============================================================================

-- ---------- movies ----------
INSERT INTO language (language_id, language_name) VALUES (1,'Thai');
INSERT INTO language (language_id, language_name) VALUES (2,'English');
INSERT INTO language (language_id, language_name) VALUES (3,'Korean');
INSERT INTO rate (rate_id, rate_name) VALUES (1,'G');
INSERT INTO rate (rate_id, rate_name) VALUES (2,'13+');
INSERT INTO rate (rate_id, rate_name) VALUES (3,'15+');
INSERT INTO rate (rate_id, rate_name) VALUES (4,'18+');
INSERT INTO genre (genre_id, genre_name) VALUES (1,'Action');
INSERT INTO genre (genre_id, genre_name) VALUES (2,'Sci-Fi');
INSERT INTO genre (genre_id, genre_name) VALUES (3,'Drama');
INSERT INTO genre (genre_id, genre_name) VALUES (4,'Romance');
INSERT INTO genre (genre_id, genre_name) VALUES (5,'Documentary');
INSERT INTO genre (genre_id, genre_name) VALUES (6,'Concert');
INSERT INTO person (person_id, person_name, person_image) VALUES (1,'Person A','p1.jpg');
INSERT INTO person (person_id, person_name, person_image) VALUES (2,'Person B','p2.jpg');
INSERT INTO person (person_id, person_name, person_image) VALUES (3,'Person C','p3.jpg');
INSERT INTO role (role_id, role_name) VALUES (1,'Director');
INSERT INTO role (role_id, role_name) VALUES (2,'Actor');
INSERT INTO media_format (media_format_id, media_format_name) VALUES (1,'image');
INSERT INTO media_format (media_format_id, media_format_name) VALUES (2,'video');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (1,1,'a_poster.jpg');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (2,1,'a_banner.jpg');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (3,1,'b_poster.jpg');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (4,1,'b_banner.jpg');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (5,2,'A_trailer.mp4');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (6,2,'B_trailer.mp4');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (7,1,'A_still1.jpg');
INSERT INTO media (media_id, media_format_id, media_name) VALUES (8,1,'B_still1.jpg');
INSERT INTO movie (movie_id, rate_id, movie_country, movie_release_date, movie_synopsis, poster_media_id, banner_media_id) VALUES (1,2,'USA','2026-11-01','Synopsis of Movie A',1,2);
INSERT INTO movie (movie_id, rate_id, movie_country, movie_release_date, movie_synopsis, poster_media_id, banner_media_id) VALUES (2,3,'Korea','2026-11-08','Synopsis of Movie B',3,4);
-- movie A: v1 English audio no subtitle / v2 English audio Thai subtitle / v3 Thai dub.   movie B: v4 Korean audio Thai subtitle
INSERT INTO movie_media (movie_id, media_id) VALUES (1,5);
INSERT INTO movie_media (movie_id, media_id) VALUES (1,7);
INSERT INTO movie_media (movie_id, media_id) VALUES (2,6);
INSERT INTO movie_media (movie_id, media_id) VALUES (2,8);
INSERT INTO movie_genre (movie_id, genre_id) VALUES (1,1);
INSERT INTO movie_genre (movie_id, genre_id) VALUES (1,2);
INSERT INTO movie_genre (movie_id, genre_id) VALUES (2,3);
INSERT INTO movie_genre (movie_id, genre_id) VALUES (2,4);
-- person A is both director and actor of movie A (role_id is in the key, so no clash)
INSERT INTO movie_credit (movie_id, person_id, role_id) VALUES (1,1,1);
INSERT INTO movie_credit (movie_id, person_id, role_id) VALUES (1,1,2);
INSERT INTO movie_credit (movie_id, person_id, role_id) VALUES (1,2,2);
INSERT INTO movie_credit (movie_id, person_id, role_id) VALUES (2,3,1);
INSERT INTO movie_credit (movie_id, person_id, role_id) VALUES (2,3,2);
INSERT INTO movie_version (movie_id, audio_language_id, movie_runtime) VALUES (1,2,148);
INSERT INTO movie_version (movie_id, audio_language_id, movie_runtime) VALUES (1,1,152);
INSERT INTO movie_version (movie_id, audio_language_id, movie_runtime) VALUES (2,3,120);

INSERT INTO movie_name (movie_id, language_id, movie_name) VALUES (1,1,'Movie A (Thai title)');
INSERT INTO movie_name (movie_id, language_id, movie_name) VALUES (1,2,'Movie A');
INSERT INTO movie_name (movie_id, language_id, movie_name) VALUES (2,1,'Movie B (Thai title)');
INSERT INTO movie_name (movie_id, language_id, movie_name) VALUES (2,3,'Movie B (Korean title)');
INSERT INTO movie_rerelease (movie_id, movie_rerelease_number, movie_rerelease_date, movie_rerelease_note) VALUES (1,1,'2027-01-15','Re-release in IMAX');
-- ---------- places, showtimes, prices ----------
INSERT INTO branch (branch_id, branch_name, branch_address, branch_latitude, branch_longitude, branch_logo) VALUES (1,'Ratchayothin Branch','Phahonyothin Rd, Bangkok',13.8200,100.5700,'logo1.png');
INSERT INTO branch (branch_id, branch_name, branch_address, branch_latitude, branch_longitude, branch_logo) VALUES (2,'Pinklao Branch','Borommaratchachonnani Rd, Bangkok',13.7800,100.4800,'logo2.png');
INSERT INTO theatre_type (theatre_type_id, theatre_type_name, theatre_type_logo) VALUES (1,'Standard','n.png');
INSERT INTO theatre_type (theatre_type_id, theatre_type_name, theatre_type_logo) VALUES (2,'IMAX','i.png');
INSERT INTO sound_system (sound_id, sound_name) VALUES (1,'Dolby Digital Surround EX');
INSERT INTO sound_system (sound_id, sound_name) VALUES (2,'Dolby Atmos');
INSERT INTO sound_system (sound_id, sound_name) VALUES (3,'IMAX Sound');
INSERT INTO screen_format (screen_id, screen_name) VALUES (1,'Silver Screen');
INSERT INTO screen_format (screen_id, screen_name) VALUES (2,'IMAX');
INSERT INTO screen_format (screen_id, screen_name) VALUES (3,'Panoramic Screen');
INSERT INTO theatre (theatre_id, branch_id, theatre_type_id, sound_id, screen_id, theatre_name) VALUES (1,1,1,1,1,'Theatre 1');
INSERT INTO theatre (theatre_id, branch_id, theatre_type_id, sound_id, screen_id, theatre_name) VALUES (2,1,2,3,2,'IMAX Theatre');
INSERT INTO theatre (theatre_id, branch_id, theatre_type_id, sound_id, screen_id, theatre_name) VALUES (3,2,1,2,1,'Theatre 1 Pinklao');
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (1,'Normal',1);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (2,'Pair Seat',2);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (3,'Premium Seat',1);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (4,'Privilege Seat',1);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (5,'Balcony',1);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (6,'Sofa Seat',1);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (7,'Double Sofa',2);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (8,'Lounge Pair Seat',2);
INSERT INTO seat_type (seat_type_id, seat_type_name, seat_type_capacity) VALUES (9,'Recliner Seat',1);
-- theatre 1: the old seat A1 (seat_id 1) was removed and a pair sofa was added at the same position as a new seat_id (21)
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,1,1,'A',1,'REMOVED',1);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,1,2,'A',2,'ACTIVE',1);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,1,3,'A',3,'ACTIVE',1);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,1,4,'A',4,'ACTIVE',1);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,1,21,'A',1,'ACTIVE',2);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (1,2,1,'A',1,'ACTIVE',1);
INSERT INTO seat (branch_id, theatre_id, seat_id, seat_row, seat_number, seat_status, seat_type_id) VALUES (2,3,1,'A',1,'ACTIVE',1);
INSERT INTO showtime_status (showtime_status_id, showtime_status_name) VALUES (1,'OPEN');
INSERT INTO showtime_status (showtime_status_id, showtime_status_name) VALUES (2,'CANCELLED');
INSERT INTO showtime_dimension (showtime_dimension_id, showtime_dimension_name) VALUES (1,'2D');
INSERT INTO showtime_dimension (showtime_dimension_id, showtime_dimension_name) VALUES (2,'3D');
-- showtime_date is the business date: the 00:30 show belongs to 2026-11-05
INSERT INTO price_period (price_period_id, price_period_name, price_period_day_type, price_period_start_time, price_period_end_time) VALUES (1,'Regular','OTHER','04:00','23:59');
INSERT INTO price_period (price_period_id, price_period_name, price_period_day_type, price_period_start_time, price_period_end_time) VALUES (2,'Thursday','THU','04:00','23:59');
INSERT INTO price_period (price_period_id, price_period_name, price_period_day_type, price_period_start_time, price_period_end_time) VALUES (3,'Late night','OTHER','00:00','03:59');
INSERT INTO price_period (price_period_id, price_period_name, price_period_day_type, price_period_start_time, price_period_end_time) VALUES (4,'Thursday late night','THU','00:00','03:59');
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (1,1,'2026-11-05','14:00','17:00',1,2,1,1,2);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (1,1,'2026-11-05','14:00',1);
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (1,1,'2026-11-05','17:30','20:30',1,2,1,1,2);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (1,1,'2026-11-05','17:30',1);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (1,1,'2026-11-05','17:30',3);
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (1,1,'2026-11-05','00:30','03:00',1,1,1,1,4);
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (1,2,'2026-11-05','15:00','18:00',1,2,2,1,2);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (1,2,'2026-11-05','15:00',1);
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (2,3,'2026-11-05','19:00','21:30',2,3,1,1,2);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (2,3,'2026-11-05','19:00',1);
INSERT INTO showtime (branch_id, theatre_id, showtime_date, showtime_time, showtime_end_time, movie_id, audio_language_id, showtime_dimension_id, showtime_status_id, price_period_id) VALUES (2,3,'2026-12-03','19:00','21:30',2,3,1,1,2);
INSERT INTO showtime_subtitle (branch_id, theatre_id, showtime_date, showtime_time, subtitle_language_id) VALUES (2,3,'2026-12-03','19:00',1);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,1,1,'2026-01-01','9999-12-31',260);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,1,2,'2026-01-01','9999-12-31',240);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,1,3,'2026-01-01','9999-12-31',290);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,1,4,'2026-01-01','9999-12-31',270);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,2,1,'2026-01-01','9999-12-31',300);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,2,2,'2026-01-01','9999-12-31',280);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,2,3,'2026-01-01','9999-12-31',330);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,1,2,4,'2026-01-01','9999-12-31',310);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,2,1,1,'2026-01-01','9999-12-31',800);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,2,1,2,'2026-01-01','9999-12-31',780);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,2,1,3,'2026-01-01','9999-12-31',830);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,1,2,1,4,'2026-01-01','9999-12-31',810);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,2,1,2,1,'2026-01-01','9999-12-31',320);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,2,1,2,2,'2026-01-01','9999-12-31',300);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,2,1,2,3,'2026-01-01','9999-12-31',350);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (1,2,1,2,4,'2026-01-01','9999-12-31',330);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (2,1,1,1,1,'2026-01-01','9999-12-31',180);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (2,1,1,1,2,'2026-01-01','9999-12-31',160);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (2,1,1,1,3,'2026-01-01','9999-12-31',210);
INSERT INTO ticket_price (branch_id, theatre_type_id, seat_type_id, showtime_dimension_id, price_period_id, ticket_price_start_date, ticket_price_end_date, ticket_price_amount) VALUES (2,1,1,1,4,'2026-01-01','9999-12-31',190);
-- Price periods: 1 Regular, 2 Thursday, 3 Late night, 4 Thursday late night (each showtime has one, set by the app).
-- ticket_price holds one price per (branch, theatre type, seat type, dimension, period, date range).
-- ticket_sale_price = price at the time of sale (the Monthly Pass ticket, seat 3, is charged only the difference = 0).
-- ---------- customers, members, promotions ----------
INSERT INTO customer (customer_id, customer_first_name, customer_last_name, customer_email, customer_phone_number, customer_address, customer_date_of_birth) VALUES (1,'Somchai','Jaidee','somchai@example.test','0800000001','Bangkok','2000-01-01');
INSERT INTO customer (customer_id, customer_first_name, customer_last_name, customer_email, customer_phone_number, customer_address, customer_date_of_birth) VALUES (2,'Somying','Rakrian','somying@example.test','0800000002','Bangkok','2001-02-02');
INSERT INTO customer (customer_id, customer_first_name, customer_last_name, customer_email, customer_phone_number, customer_address, customer_date_of_birth) VALUES (3,'Somsak','Meesuk','somsak@example.test','0800000003','Bangkok','1999-03-03');
INSERT INTO customer (customer_id, customer_first_name, customer_last_name, customer_email, customer_phone_number, customer_address, customer_date_of_birth) VALUES (4,'Somsri','Dee','somsri@example.test','0800000004','Bangkok','2004-04-04');
INSERT INTO favorite_branch (customer_id, branch_id) VALUES (1,1);
INSERT INTO favorite_branch (customer_id, branch_id) VALUES (2,2);
INSERT INTO member_type (member_type_id, member_type_name, member_type_class, member_type_price, member_type_duration) VALUES (1,'Monthly Pass','Monthly',500.00,1);
INSERT INTO member_type (member_type_id, member_type_name, member_type_class, member_type_price, member_type_duration) VALUES (2,'Standard Member','Regular',100.00,12);
INSERT INTO member_type (member_type_id, member_type_name, member_type_class, member_type_price, member_type_duration) VALUES (3,'Student Member','Student',30.00,12);
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (1,1,'MAX_PER_MOVIE','1','One viewing per movie');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (2,1,'MIN_GAP_MINUTES','120','Shows at least 2 hours apart');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (3,1,'SEAT_TYPE_ID','1','Normal seats only');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (4,1,'DIMENSION_ID','1','2D shows only');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (5,1,'EXCLUDED_COUNTRY','India','Indian films are not included');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (6,1,'EXCLUDED_GENRE_ID','5','Documentary is not included');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (7,1,'EXCLUDED_GENRE_ID','6','Concert is not included');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (8,3,'MIN_AGE','13','Age 13 or older');
INSERT INTO member_type_condition (member_type_condition_id, member_type_id, member_type_condition_type, member_type_condition_value, member_type_condition_detail) VALUES (9,3,'MAX_AGE','23','Age 23 or younger');
INSERT INTO register (register_id, customer_id, member_type_id, register_datetime, register_status) VALUES (1,2,1,'2026-10-31 18:00:00','COMPLETED');
INSERT INTO register (register_id, customer_id, member_type_id, register_datetime, register_status) VALUES (2,1,2,'2025-12-31 20:00:00','COMPLETED');
INSERT INTO register (register_id, customer_id, member_type_id, register_datetime, register_status) VALUES (3,2,2,'2024-12-30 12:00:00','COMPLETED');
INSERT INTO register (register_id, customer_id, member_type_id, register_datetime, register_status) VALUES (4,2,1,'2025-12-31 09:00:00','COMPLETED');
INSERT INTO register (register_id, customer_id, member_type_id, register_datetime, register_status) VALUES (5,4,3,'2026-11-10 10:00:00','PENDING');
INSERT INTO member (member_id, register_id, member_start_date, member_end_date) VALUES (1,1,'2026-11-01','2026-12-01');
INSERT INTO member (member_id, register_id, member_start_date, member_end_date) VALUES (2,2,'2026-01-01','2027-01-01');
-- renewal history of customer 2 (each new subscription = a new card = a new member row)
INSERT INTO member (member_id, register_id, member_start_date, member_end_date) VALUES (3,3,'2025-01-01','2025-12-31');
INSERT INTO member (member_id, register_id, member_start_date, member_end_date) VALUES (4,4,'2026-01-01','2026-01-31');
INSERT INTO monthly_pass_member (member_id) VALUES (1);
INSERT INTO monthly_pass_member (member_id) VALUES (4);
INSERT INTO member_card (member_id, member_card_issue_date, member_card_no, member_card_status) VALUES (2,'2026-01-01','STD-000002','ACTIVE');
-- customer 2 lost the first card and was issued a new one: both numbers are kept
INSERT INTO member_card (member_id, member_card_issue_date, member_card_no, member_card_status) VALUES (3,'2025-01-01','STD-000003','CANCELLED');
INSERT INTO member_card (member_id, member_card_issue_date, member_card_no, member_card_status) VALUES (3,'2025-07-01','STD-000013','ACTIVE');
INSERT INTO member_card (member_id, member_card_issue_date, member_card_no, member_card_status) VALUES (4,'2026-01-01','MP-000004','ACTIVE');
INSERT INTO reward (reward_id, reward_name, reward_type) VALUES (1,'Free popcorn','Freebie');
INSERT INTO reward (reward_id, reward_name, reward_type) VALUES (2,'Movie A collectible mug','Merchandise');
INSERT INTO reward (reward_id, reward_name, reward_type) VALUES (3,'Thai films T-shirt','Merchandise');
INSERT INTO branch_reward (reward_id, branch_id, branch_reward_point_cost) VALUES (1,1,100);
INSERT INTO branch_reward (reward_id, branch_id, branch_reward_point_cost) VALUES (2,1,100);
INSERT INTO branch_reward (reward_id, branch_id, branch_reward_point_cost) VALUES (3,1,100);
-- reward 2 is tied to movie A; reward 3 is tied to two movies (many-to-many)
INSERT INTO movie_reward (reward_id, movie_id) VALUES (2,1);
INSERT INTO movie_reward (reward_id, movie_id) VALUES (3,1);
INSERT INTO movie_reward (reward_id, movie_id) VALUES (3,2);
INSERT INTO partner (partner_id, partner_name, partner_logo) VALUES (1,'Partner Bank A','bank.png');
INSERT INTO discount (discount_id, partner_id, discount_name, discount_type, discount_value, discount_start_date, discount_end_date, discount_detail, discount_code, discount_usage_limit, discount_image) VALUES (1,1,'50% off with participating credit card','PERCENT',50.00,'2026-11-01','2026-11-30','Promotion details','CARD50',100,'d1.png');
INSERT INTO discount_branch (discount_id, branch_id) VALUES (1,1);
INSERT INTO discount_branch (discount_id, branch_id) VALUES (1,2);
INSERT INTO news (news_id, news_name, news_type, news_detail, news_image, news_start_date, news_end_date, news_participation_limit) VALUES (1,'November promotions','Promotion','News details','n1.png','2026-11-01','2026-11-30',100);
INSERT INTO discount_news (news_id, discount_id) VALUES (1,1);
INSERT INTO customer_news (customer_news_id, customer_id, news_id, branch_id, customer_news_datetime, customer_news_result) VALUES (1,1,1,1,'2026-11-02 10:00:00','Interested');
-- ---------- bookings, tickets, payments, points, products ----------
-- booking 1 is still PENDING (seat held until 13:10); bookings 2-6 are PAID
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (1,1,'0800000001','2026-11-05 13:00:00','2026-11-05 13:10:00','PENDING','BK0001');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (2,1,'0800000001','2026-11-05 12:50:00','2026-11-05 13:00:00','PAID','BK0002');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (3,2,'0800000002','2026-11-05 12:55:00','2026-11-05 13:05:00','PAID','BK0003');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (4,2,'0800000002','2026-11-04 23:50:00','2026-11-05 00:00:00','PAID','BK0004');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (5,1,'0800000001','2026-11-05 18:00:00','2026-11-05 18:10:00','PAID','BK0005');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (6,2,'0800000002','2026-12-03 18:00:00','2026-12-03 18:10:00','PAID','BK0006');
INSERT INTO booking (booking_id, customer_id, booking_phone_number, booking_datetime, booking_expire_datetime, booking_status, booking_code) VALUES (7,NULL,'0811111111','2026-11-05 12:30:00','2026-11-05 12:40:00','PAID','BK0007');
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','14:00',2,1,240);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','14:00',21,2,780);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','14:00',3,3,0);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','00:30',2,4,270);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (2,3,'2026-11-05','19:00',1,5,160);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (2,3,'2026-12-03','19:00',1,6,160);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','17:30',3,7,240);
INSERT INTO ticket (branch_id, theatre_id, showtime_date, showtime_time, seat_id, booking_id, ticket_sale_price) VALUES (1,1,'2026-11-05','17:30',4,7,240);
-- member 1 (Monthly Pass) used the benefit on movie A (cannot watch the same movie twice because PK = member + movie)
INSERT INTO monthly_pass_usage (member_id, movie_id, branch_id, theatre_id, showtime_date, showtime_time, seat_id, monthly_pass_usage_datetime) VALUES (1,1,1,1,'2026-11-05','14:00',3,'2026-11-05 13:05:00');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (1,2,2,1,'2026-11-05 13:02:00','SUCCESS','PromptPay');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (2,3,1,NULL,'2026-11-05 13:06:00','SUCCESS','Monthly Pass');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (3,4,NULL,NULL,'2026-11-05 00:01:00','SUCCESS','Banking App');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (4,5,2,NULL,'2026-11-05 18:02:00','SUCCESS','PromptPay');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (5,6,NULL,NULL,'2026-12-03 18:02:00','SUCCESS','Banking App');
INSERT INTO payment (payment_id, booking_id, member_id, discount_id, payment_datetime, payment_status, payment_method) VALUES (6,7,NULL,NULL,'2026-11-05 12:32:00','SUCCESS','PromptPay');
-- Points earned from a payment (reward/branch empty) and a reward redemption (payment empty)
INSERT INTO point_log (point_log_id, member_id, payment_id, reward_id, branch_id, point_log_amount, point_log_type, point_log_datetime, point_log_expired_date) VALUES (1,2,1,NULL,NULL,390,'EARN','2026-11-05 13:03:00','2027-11-05');
INSERT INTO point_log (point_log_id, member_id, payment_id, reward_id, branch_id, point_log_amount, point_log_type, point_log_datetime, point_log_expired_date) VALUES (2,2,NULL,1,1,-100,'REDEEM','2026-11-06 10:00:00',NULL);
INSERT INTO size (size_id, size_amount) VALUES (1,'27 oz');
INSERT INTO size (size_id, size_amount) VALUES (2,'32 oz');
INSERT INTO flavor (flavor_id, flavor_name) VALUES (1,'Salted');
INSERT INTO flavor (flavor_id, flavor_name) VALUES (2,'Caramel');
-- product 3 is a set (no size -> size_id empty)
INSERT INTO product (product_id, size_id, product_name, product_type, product_image) VALUES (1,1,'Popcorn','Snack','pop.png');
INSERT INTO product (product_id, size_id, product_name, product_type, product_image) VALUES (2,2,'Soft drink','Drink','drink.png');
INSERT INTO product (product_id, size_id, product_name, product_type, product_image) VALUES (3,NULL,'Combo Set L','Set','combo.png');
-- Combo Set L contains 1 popcorn and 1 soft drink (recursive M:N)
INSERT INTO product_set (set_product_id, item_product_id, product_set_quantity) VALUES (3,1,1);
INSERT INTO product_set (set_product_id, item_product_id, product_set_quantity) VALUES (3,2,1);
INSERT INTO product_flavor (product_id, flavor_id, product_flavor_extra_price) VALUES (1,1,0.00);
INSERT INTO product_flavor (product_id, flavor_id, product_flavor_extra_price) VALUES (1,2,5.00);
INSERT INTO product_price (product_id, branch_id, product_price_start_date, product_price_end_date, product_price_amount) VALUES (1,1,'2026-01-01','9999-12-31',120);
INSERT INTO product_price (product_id, branch_id, product_price_start_date, product_price_end_date, product_price_amount) VALUES (2,1,'2026-01-01','9999-12-31',60);
INSERT INTO product_price (product_id, branch_id, product_price_start_date, product_price_end_date, product_price_amount) VALUES (3,1,'2026-01-01','9999-12-31',170);
INSERT INTO booking_product (booking_product_id, booking_id, product_id, branch_id, booking_product_quantity, booking_product_sale_price, booking_product_note) VALUES (1,2,1,1,1,125,'No ice');
INSERT INTO booking_product_flavor (booking_product_id, flavor_id) VALUES (1,2);
-- ============================================================================
