--
-- PostgreSQL database dump
--

-- Dumped from database version 10.5
-- Dumped by pg_dump version 10.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bitfinex; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA bitfinex;


ALTER SCHEMA bitfinex OWNER TO "ob-analytics";

--
-- Name: bf_cons_book_events_dress_new_row(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_cons_book_events_dress_new_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$


BEGIN

	IF NEW.cnt != 0 THEN 
		NEW.price_next_episode_no := 2147483647;
		NEW.active_episode_no := NEW.episode_no;
	ELSE
		NEW.price_next_episode_no := -1;
		NEW.active_episode_no := 2147483647;
	END IF;
	
	IF NEW.qty < 0 THEN 
		NEW.qty = -NEW.qty;
		NEW.side = 'A';
	ELSE
		NEW.side = 'B';
	END IF;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_cons_book_events_dress_new_row() OWNER TO "ob-analytics";

--
-- Name: bf_cons_book_events_update_next_episode_no(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_cons_book_events_update_next_episode_no() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
	
	UPDATE bitfinex.bf_cons_book_events
	SET price_next_episode_no = NEW.episode_no
	WHERE snapshot_id = NEW.snapshot_id 
	  AND price = NEW.price
	  AND episode_no < NEW.episode_no
	  AND price_next_episode_no > NEW.episode_no;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_cons_book_events_update_next_episode_no() OWNER TO "ob-analytics";

--
-- Name: bf_depth_summary_after_episode_v(integer, integer, integer, numeric); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_depth_summary_after_episode_v(INOUT snapshot_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647, bps_step numeric DEFAULT 25, OUT volume numeric, OUT bps_level integer, OUT bps_price numeric, OUT bps_vwap numeric, OUT direction character varying, OUT pair character varying, OUT exchange_timestamp timestamp with time zone, OUT episode_no integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$

DECLARE 
	p bitfinex.bf_snapshots.prec%TYPE;
BEGIN
	
	SELECT prec INTO p
	FROM bitfinex.bf_snapshots 
	WHERE bf_snapshots.snapshot_id = bf_depth_summary_after_episode_v.snapshot_id;
	
	IF p = 'R0' THEN

		RETURN QUERY
		SELECT  u.snapshot_id,
				sum(u.order_qty) AS volume,
				u.bps_level,
				u.bps_price,
				round(sum(u.order_qty*u.order_price)/sum(u.order_qty), "precision") AS bps_vwap,
				u.direction,
				u.pair,
				u.exchange_timestamp,
				u.episode_no
		FROM (
			SELECT 	r2.order_price,
					r2.order_qty, 
					(bf_depth_summary_after_episode_v.bps_step*r2.bps_level)::integer AS bps_level,
					round(r2.best_bid*(1 - r2.bps_level*bf_depth_summary_after_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
					'bid'::character varying AS direction,
					r2.pair,
					r2.exchange_timestamp,
					r2.episode_no,
					r2.snapshot_id,
					"precision"
			FROM (		
				SELECT 	r1.order_price, 
						r1.order_qty, 
						ceiling((r1.best_bid - r1.order_price)/r1.best_bid/bf_depth_summary_after_episode_v.bps_step*10000)::integer AS bps_level,
						r1.best_bid,
						r1.pair,
						r1.exchange_timestamp,
						r1.episode_no,
						r1.snapshot_id
				FROM (
						SELECT 	bf_active_orders_after_episode_v.order_price, 
								bf_active_orders_after_episode_v.order_qty,
								first_value(bf_active_orders_after_episode_v.order_price) OVER w AS best_bid, 
								bf_active_orders_after_episode_v.pair,
								bf_active_orders_after_episode_v.exchange_timestamp,
								bf_active_orders_after_episode_v.episode_no,
								bf_active_orders_after_episode_v.snapshot_id
						FROM bitfinex.bf_active_orders_after_episode_v
						WHERE bf_active_orders_after_episode_v.snapshot_id = bf_depth_summary_after_episode_v.snapshot_id
						  AND bf_active_orders_after_episode_v.episode_no BETWEEN bf_depth_summary_after_episode_v.first_episode_no 
														AND bf_depth_summary_after_episode_v.last_episode_no
						  AND bitfinex.bf_active_orders_after_episode_v.side = 'B'
						WINDOW w AS (PARTITION BY bf_active_orders_after_episode_v.episode_no ORDER BY order_price DESC)
			) r1
		) r2 JOIN bitfinex.bf_pairs USING (pair)
		UNION ALL
		SELECT 	r2.order_price,
				r2.order_qty, 
				(bf_depth_summary_after_episode_v.bps_step*r2.bps_level)::integer AS bps_level,
				round(r2.best_ask*(1 + r2.bps_level*bf_depth_summary_after_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
				'ask'::character varying AS direction,
				r2.pair,
				r2.exchange_timestamp,
				r2.episode_no,
				r2.snapshot_id,
				"precision"
		FROM (		
			SELECT 	r1.order_price, 
					r1.order_qty, 
					ceiling((r1.order_price-best_ask)/r1.best_ask/bf_depth_summary_after_episode_v.bps_step*10000)::integer AS bps_level,
					best_ask,
					r1.pair,
					r1.exchange_timestamp,
					r1.episode_no,
					r1.snapshot_id
			FROM (
					SELECT 	bf_active_orders_after_episode_v.order_price, 
							bf_active_orders_after_episode_v.order_qty,
							first_value(bf_active_orders_after_episode_v.order_price) OVER w AS best_ask, 
							bf_active_orders_after_episode_v.pair,
							bf_active_orders_after_episode_v.exchange_timestamp,
							bf_active_orders_after_episode_v.episode_no,
							bf_active_orders_after_episode_v.snapshot_id
					FROM bitfinex.bf_active_orders_after_episode_v
					WHERE bf_active_orders_after_episode_v.snapshot_id = bf_depth_summary_after_episode_v.snapshot_id
					  AND bf_active_orders_after_episode_v.episode_no BETWEEN bf_depth_summary_after_episode_v.first_episode_no 
											AND bf_depth_summary_after_episode_v.last_episode_no
					  AND bitfinex.bf_active_orders_after_episode_v.side = 'A'
					WINDOW w AS (PARTITION BY bf_active_orders_after_episode_v.episode_no ORDER BY order_price)
			) r1
		) r2 JOIN bitfinex.bf_pairs USING (pair)
		) u 
		GROUP BY u.pair, u.bps_level, u.bps_price, u.direction, u.exchange_timestamp, u.episode_no, u.snapshot_id, "precision"
		ORDER BY u.episode_no, u.direction, CASE WHEN u.direction = 'ask' THEN 1 ELSE -1 END*u.bps_level DESC;
	ELSE
		RETURN QUERY
		SELECT  u.snapshot_id,
				sum(u.qty) AS volume,
				u.bps_level,
				u.bps_price,
				round(sum(u.qty*u.price)/sum(u.qty), "precision") AS bps_vwap,
				u.direction,
				u.pair,
				u.exchange_timestamp,
				u.episode_no
		FROM (
			SELECT 	r2.price,
					r2.qty, 
					(bf_depth_summary_after_episode_v.bps_step*r2.bps_level)::integer AS bps_level,
					round(r2.best_bid*(1 - r2.bps_level*bf_depth_summary_after_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
					'bid'::character varying AS direction,
					r2.pair,
					r2.exchange_timestamp,
					r2.episode_no,
					r2.snapshot_id,
					"precision"
			FROM (		
				SELECT 	r1.price, 
						r1.qty, 
						ceiling((r1.best_bid - r1.price)/r1.best_bid/bf_depth_summary_after_episode_v.bps_step*10000)::integer AS bps_level,
						r1.best_bid,
						r1.pair,
						r1.exchange_timestamp,
						r1.episode_no,
						r1.snapshot_id
				FROM (
						SELECT 	bf_price_levels_after_episode_v.price, 
								bf_price_levels_after_episode_v.qty,
								first_value(bf_price_levels_after_episode_v.price) OVER w AS best_bid, 
								bf_price_levels_after_episode_v.pair,
								bf_price_levels_after_episode_v.exchange_timestamp,
								bf_price_levels_after_episode_v.episode_no,
								bf_price_levels_after_episode_v.snapshot_id
						FROM bitfinex.bf_price_levels_after_episode_v 
						WHERE bf_price_levels_after_episode_v.snapshot_id = bf_depth_summary_after_episode_v.snapshot_id
						  AND bf_price_levels_after_episode_v.episode_no BETWEEN bf_depth_summary_after_episode_v.first_episode_no 
														AND bf_depth_summary_after_episode_v.last_episode_no
						  AND bf_price_levels_after_episode_v.side = 'B'
						WINDOW w AS (PARTITION BY bf_price_levels_after_episode_v.episode_no ORDER BY price DESC)
			) r1
		) r2 JOIN bitfinex.bf_pairs USING (pair)
		UNION ALL
		SELECT 	r2.price,
				r2.qty, 
				(bf_depth_summary_after_episode_v.bps_step*r2.bps_level)::integer AS bps_level,
				round(r2.best_ask*(1 + r2.bps_level*bf_depth_summary_after_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
				'ask'::character varying AS direction,
				r2.pair,
				r2.exchange_timestamp,
				r2.episode_no,
				r2.snapshot_id,
				"precision"
		FROM (		
			SELECT 	r1.price, 
					r1.qty, 
					ceiling((r1.price-best_ask)/r1.best_ask/bf_depth_summary_after_episode_v.bps_step*10000)::integer AS bps_level,
					best_ask,
					r1.pair,
					r1.exchange_timestamp,
					r1.episode_no,
					r1.snapshot_id
			FROM (
					SELECT 	bf_price_levels_after_episode_v.price, 
							bf_price_levels_after_episode_v.qty,
							first_value(bf_price_levels_after_episode_v.price) OVER w AS best_ask, 
							bf_price_levels_after_episode_v.pair,
							bf_price_levels_after_episode_v.exchange_timestamp,
							bf_price_levels_after_episode_v.episode_no,
							bf_price_levels_after_episode_v.snapshot_id
					FROM bitfinex.bf_price_levels_after_episode_v 
					WHERE bf_price_levels_after_episode_v.snapshot_id = bf_depth_summary_after_episode_v.snapshot_id
					  AND bf_price_levels_after_episode_v.episode_no BETWEEN bf_depth_summary_after_episode_v.first_episode_no 
											AND bf_depth_summary_after_episode_v.last_episode_no
					  AND bf_price_levels_after_episode_v.side = 'A'
					WINDOW w AS (PARTITION BY bf_price_levels_after_episode_v.episode_no ORDER BY price)
			) r1
		) r2 JOIN bitfinex.bf_pairs USING (pair)
		) u 
		GROUP BY u.pair, u.bps_level, u.bps_price, u.direction, u.exchange_timestamp, u.episode_no, u.snapshot_id, "precision"
		ORDER BY u.episode_no, u.direction, CASE WHEN u.direction = 'ask' THEN 1 ELSE -1 END*u.bps_level DESC;
	END IF;
END

$$;


ALTER FUNCTION bitfinex.bf_depth_summary_after_episode_v(INOUT snapshot_id integer, first_episode_no integer, last_episode_no integer, bps_step numeric, OUT volume numeric, OUT bps_level integer, OUT bps_price numeric, OUT bps_vwap numeric, OUT direction character varying, OUT pair character varying, OUT exchange_timestamp timestamp with time zone, OUT episode_no integer) OWNER TO "ob-analytics";

--
-- Name: bf_order_book_episodes_match_trades_to_episodes(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_episodes_match_trades_to_episodes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE

BEGIN

	WITH RECURSIVE 
		admissible_episode_range AS (
			SELECT 	t.id,
					t.price,
					t.snapshot_id,
	 				t.exchange_timestamp AS tet,
					t.episode_no IS NULL AS not_matched,
					max(t.episode_no) OVER (PARTITION BY t.snapshot_id ORDER BY t.exchange_timestamp) AS b_e,
					min(t.episode_no) OVER (PARTITION BY t.snapshot_id ORDER BY t.exchange_timestamp DESC) AS a_e
			FROM bitfinex.bf_trades t
			WHERE t.snapshot_id = NEW.snapshot_id AND t.exchange_timestamp > NEW.exchange_timestamp - '1 min'::interval
		), 
		between_same_episodes AS (	
			SELECT id, b_e AS episode_no
			FROM admissible_episode_range a
			WHERE not_matched AND a.b_e = a.a_e
		),
		nearest_episodes AS (		
			SELECT * 
			FROM (
				SELECT 	*, 
			   			lag(candidate_episodes) OVER (ORDER BY tet, id) AS p_candidate_episodes,
			   			lag(id) OVER (ORDER BY tet, id) AS p_id
				FROM (
					SELECT 	id, 
							tet, 
							array_agg(episode_no ORDER BY r) AS candidate_episodes
					FROM (	SELECT 	rank() OVER (PARTITION BY a.snapshot_id, 
									id ORDER BY abs( EXTRACT( EPOCH FROM tet) - EXTRACT(EPOCH FROM exchange_timestamp))) AS r, 
		    						a.id, 
									s.episode_no, 
									tet
							FROM (
									SELECT *
									FROM admissible_episode_range a  
									WHERE not_matched AND a.b_e <> a.a_e
								) a JOIN bitfinex.bf_spreads s ON s.snapshot_id = NEW.snapshot_id
									 AND a.snapshot_id = s.snapshot_id 
	 			 					 AND s.episode_no BETWEEN b_e AND a_e AND s.timing = 'B'
	 			 					 AND price BETWEEN s.best_bid_price AND s.best_ask_price 
									JOIN bitfinex.bf_order_book_episodes p ON p.snapshot_id = NEW.snapshot_id
						 			 AND s.snapshot_id = p.snapshot_id 
				 					 AND s.episode_no = p.episode_no 
									 AND p.episode_no BETWEEN b_e AND a_e
						) a
					GROUP BY tet, id
					) a
				)a
		),
		nearest_episode (id, episode_no, p_id) AS (
			SELECT * 
			FROM (
					SELECT 	id, 
							(	SELECT min(episode_no) 
								FROM unnest(candidate_episodes) episode_no
							), 
							p_id
					FROM nearest_episodes
					ORDER BY id
					LIMIT 1
				) a
			UNION ALL
			SELECT 	ps.id, 
					(	SELECT min(episode_no) 
						FROM unnest(candidate_episodes) episode_no
						WHERE episode_no >= p.episode_no
					), 
					ps.p_id
			FROM nearest_episodes ps JOIN nearest_episode p ON  ps.p_id = p.id
		)
	UPDATE bitfinex.bf_trades t
	SET episode_no = a.episode_no
	FROM (
		SELECT * 
		FROM between_same_episodes
	  	UNION ALL
	  	SELECT id, episode_no 
		FROM nearest_episode
	 )
	 a
	WHERE t.snapshot_id = NEW.snapshot_id AND t.episode_no IS NULL AND t.id = a.id;

	RETURN NULL;

END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_episodes_match_trades_to_episodes() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_episodes_match_trades_to_events(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_episodes_match_trades_to_events() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	episodes integer[];
	ts timestamptz[];
	
	behind CONSTANT integer := 2;
	
	events 	CURSOR (p_snapshot_id integer, p_price numeric, p_qty numeric, p_episode_no integer) 
			FOR SELECT event_no 
				FROM bitfinex.bf_order_book_events 
				WHERE snapshot_id = p_snapshot_id
			  	  AND NOT matched
			  	  AND order_price = p_price
			  	  AND event_qty = -p_qty
			  	  AND episode_no = p_episode_no
				ORDER BY event_no
				LIMIT 1 FOR UPDATE;
									
	last_matched_episode bitfinex.bf_trades.episode_no%TYPE;
	
	tr_id bigint;
	
	trades CURSOR (s timestamptz, e timestamptz) FOR	
						SELECT *
						FROM bitfinex.bf_trades
						WHERE snapshot_id = NEW.snapshot_id
		  				  AND exchange_timestamp BETWEEN s AND e
						FOR UPDATE;

	trade_event_no bitfinex.bf_order_book_events.event_no%TYPE;

BEGIN

	SELECT 	array_agg(episode_no), 
			array_agg(exchange_timestamp)
			INTO episodes, ts
	FROM (
		SELECT episode_no, exchange_timestamp
		FROM bitfinex.bf_order_book_episodes
		WHERE snapshot_id = NEW.snapshot_id
		  AND episode_no < NEW.episode_no
		ORDER BY episode_no DESC
		LIMIT behind
	) a;
	
	SELECT max(episode_no) INTO last_matched_episode
	FROM bitfinex.bf_trades
	WHERE snapshot_id = NEW.snapshot_id;
	
	IF last_matched_episode IS NULL THEN
		last_matched_episode := 0;
	END IF;

	IF episodes[behind] IS NOT NULL AND episodes[behind] >= last_matched_episode THEN 
	
		FOR t IN trades(ts[behind], ts[1]) LOOP
			FOR e IN events(t.snapshot_id, t.price, t.qty, episodes[behind])  LOOP
			
				UPDATE bitfinex.bf_trades
				SET episode_no = episodes[behind],
					event_no = e.event_no
				WHERE CURRENT OF trades;
				
				UPDATE bitfinex.bf_order_book_events
				SET matched = True
				WHERE CURRENT OF events;
				
			END LOOP;
			
		END LOOP;
	END IF; 
	
	RETURN NULL;

END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_episodes_match_trades_to_events() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_dress_new_row(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_dress_new_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	precision bitfinex.bf_pairs.precision%TYPE;
	e bitfinex.bf_order_book_events%ROWTYPE;
	
BEGIN

	IF NEW.event_price != 0 THEN 

		SELECT bf_pairs.precision INTO precision 
		FROM bitfinex.bf_pairs JOIN bitfinex.bf_snapshots USING (pair)
		WHERE snapshot_id = NEW.snapshot_id;

		NEW.event_price = round(NEW.event_price, precision);
		NEW.order_price = NEW.event_price;
		
		IF NEW.order_qty < 0 THEN 
			NEW.order_qty = -NEW.order_qty;
			NEW.side = 'A';
		ELSE
			NEW.side = 'B';
		END IF;
		
		SELECT * INTO e
		FROM bitfinex.bf_order_book_events
		WHERE snapshot_id = NEW.snapshot_id 
		  AND order_id = NEW.order_id 
		  AND episode_no < NEW.episode_no
		  AND order_next_episode_no > NEW.episode_no;
		
		IF FOUND THEN
			NEW.event_qty = NEW.order_qty - e.order_qty;
		ELSE
			NEW.event_qty = NEW.order_qty;
		END IF;
		
		NEW.order_next_episode_no := 2147483647;
		NEW.active_episode_no := NEW.episode_no;
		
	ELSE
		
		SELECT * INTO e
		FROM bitfinex.bf_order_book_events
		WHERE snapshot_id = NEW.snapshot_id 
		  AND order_id = NEW.order_id 
		  AND episode_no < NEW.episode_no
		  AND order_next_episode_no > NEW.episode_no;
		
		IF FOUND THEN
			NEW.order_price = e.order_price;
			NEW.side = e.side;
			NEW.event_qty = -e.order_qty;
			NEW.order_qty = 0;
		ELSE
			RAISE WARNING 'Requested removal of order: %  which is not in the order book!', NEW.order_id;
		END IF;
		
		NEW.order_next_episode_no := -1;
		NEW.active_episode_no := 2147483647;
		
	END IF;
	
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_events_dress_new_row() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_match_trades_to_events(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_match_trades_to_events() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	tr_id RECORD;
	last_matched_trade bitfinex.bf_trades.exchange_timestamp%TYPE;
	
BEGIN
	
	-- WARNING: SET CONSTRAINT ALL DEFERRED is assumed.
	-- Otherwise both UPDATEs below will fail

	-- Let's find the last trade which was matched to some event from the PREVIOUS episode
	-- All trades after such trade can be matched to an event from the current episode 
	SELECT max(exchange_timestamp) INTO last_matched_trade
	FROM bitfinex.bf_trades t
	WHERE snapshot_id = NEW.snapshot_id
	  AND episode_no < NEW.episode_no;

	IF last_matched_trade IS NULL THEN
		last_matched_trade = '1970-08-01 20:15:00+3'::timestamptz;
	END IF;
	
	-- It is unlikely that an event is delayed more than few second after the trade
	-- which originated it. 3 seconds should be a resonable delay ? 
	IF NEW.exchange_timestamp - last_matched_trade > '3 second'::interval THEN
		last_matched_trade := NEW.exchange_timestamp - '3 second'::interval;
	END IF;

	SELECT id INTO tr_id
	FROM bitfinex.bf_trades t
	WHERE t.price		= NEW.order_price
	  AND t.qty 		= -NEW.event_qty
	  AND t.snapshot_id = NEW.snapshot_id
	  AND t.event_no IS NULL -- we consider only unmatched trades
	  AND t.exchange_timestamp BETWEEN last_matched_trade AND NEW.exchange_timestamp
	ORDER BY exchange_timestamp
	LIMIT 1;

	IF FOUND THEN

		UPDATE bitfinex.bf_trades 
		SET episode_no = NEW.episode_no, 
			event_no = NEW.event_no
		WHERE id = tr_id.id AND bf_trades.snapshot_id = NEW.snapshot_id;		
		NEW.matched = True;

	ELSE

		SELECT id, exchange_timestamp INTO tr_id
		FROM ( 	SELECT id, exchange_timestamp, SUM(qty) OVER (PARTITION BY t.snapshot_id, t.price ORDER BY t.exchange_timestamp, t.id ) AS total_qty  
				FROM bitfinex.bf_trades t
				WHERE t.price		= NEW.order_price
				AND t.snapshot_id = NEW.snapshot_id
				AND t.event_no IS NULL -- we consider only unmatched trades
				AND t.exchange_timestamp BETWEEN last_matched_trade AND NEW.exchange_timestamp
				) t
		WHERE t.total_qty = -NEW.event_qty;

		IF FOUND THEN
			UPDATE bitfinex.bf_trades t
			SET episode_no = NEW.episode_no, 
				event_no = NEW.event_no	
			WHERE t.price		= NEW.order_price
			AND t.snapshot_id = NEW.snapshot_id
			AND t.event_no IS NULL
			AND t.exchange_timestamp BETWEEN last_matched_trade AND tr_id.exchange_timestamp
			AND t.id <= tr_id.id;

			NEW.matched = True;
		END IF;
	END IF;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_events_match_trades_to_events() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_update_next_episode_no(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_update_next_episode_no() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
	
	UPDATE bitfinex.bf_order_book_events
	SET order_next_episode_no = NEW.episode_no,
		order_next_event_price = NEW.event_price
	WHERE snapshot_id = NEW.snapshot_id 
	  AND order_id = NEW.order_id 
	  AND episode_no < NEW.episode_no
	  AND order_next_episode_no > NEW.episode_no;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_events_update_next_episode_no() OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: bf_spreads; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_spreads (
    best_bid_price numeric NOT NULL,
    best_ask_price numeric NOT NULL,
    best_bid_qty numeric NOT NULL,
    best_ask_qty numeric NOT NULL,
    snapshot_id integer NOT NULL,
    episode_no integer NOT NULL,
    timing character(1) NOT NULL
);


ALTER TABLE bitfinex.bf_spreads OWNER TO "ob-analytics";

--
-- Name: bf_spread_after_episode_v(integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_spread_after_episode_v(s_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647) RETURNS SETOF bitfinex.bf_spreads
    LANGUAGE sql
    AS $$

WITH base AS (	SELECT a.snapshot_id, a.episode_no, side, price, qty
				FROM (
					SELECT 	v.snapshot_id, 
							v.episode_no, 
							side, 
							order_price AS price, 
							SUM(order_qty) AS qty,
							min(order_price) FILTER (WHERE side = 'A') OVER (PARTITION BY v.snapshot_id, v.episode_no, side) AS min_ask,
							max(order_price) FILTER (WHERE side = 'B') OVER (PARTITION BY v.snapshot_id, v.episode_no, side) AS min_bid
					FROM bitfinex.bf_active_orders_after_episode_v v
					WHERE v.snapshot_id = s_id AND v.episode_no BETWEEN first_episode_no AND last_episode_no
					GROUP BY v.snapshot_id, v.episode_no, side, order_price
					) a
				WHERE price = min_ask OR price = min_bid
				ORDER BY episode_no, side
			)
SELECT 	bids.price AS best_bid_price,
		asks.price AS best_ask_price, 
		bids.qty AS best_bid_qty,
		asks.qty AS best_ask_qty,
		snapshot_id,
		episode_no,
		'A'::char(1)
FROM 	(SELECT * FROM base WHERE side = 'A' ) asks JOIN 
		(SELECT * FROM base WHERE side = 'B' ) bids USING (snapshot_id, episode_no);

$$;


ALTER FUNCTION bitfinex.bf_spread_after_episode_v(s_id integer, first_episode_no integer, last_episode_no integer) OWNER TO "ob-analytics";

--
-- Name: bf_spread_between_episodes_v(integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_spread_between_episodes_v(s_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647) RETURNS SETOF bitfinex.bf_spreads
    LANGUAGE sql
    AS $$

WITH base AS (	SELECT a.snapshot_id, a.episode_no, side, price, qty
				FROM (
					SELECT 	v.snapshot_id, 
							v.episode_no, 
							side, 
							order_price AS price, 
							SUM(order_qty) AS qty,
							min(order_price) FILTER (WHERE side = 'A') OVER (PARTITION BY v.snapshot_id, v.episode_no, side) AS min_ask,
							max(order_price) FILTER (WHERE side = 'B') OVER (PARTITION BY v.snapshot_id, v.episode_no, side) AS min_bid
					FROM bitfinex.bf_active_orders_between_episodes_v v
					WHERE v.snapshot_id = s_id AND v.episode_no BETWEEN first_episode_no AND last_episode_no
					GROUP BY v.snapshot_id, v.episode_no, side, order_price
					) a
				WHERE price = min_ask OR price = min_bid
				ORDER BY episode_no, side
			)
SELECT 	bids.price AS best_bid_price,
		asks.price AS best_ask_price, 
		bids.qty AS best_bid_qty,
		asks.qty AS best_ask_qty,
		snapshot_id,
		episode_no,
		'B'::char(1)
FROM 	(SELECT * FROM base WHERE side = 'A' ) asks JOIN 
		(SELECT * FROM base WHERE side = 'B' ) bids USING (snapshot_id, episode_no);

$$;


ALTER FUNCTION bitfinex.bf_spread_between_episodes_v(s_id integer, first_episode_no integer, last_episode_no integer) OWNER TO "ob-analytics";

--
-- Name: bf_trades_check_episode_no_order(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_trades_check_episode_no_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE

	ep_no bitfinex.bf_trades.episode_no%TYPE;

BEGIN
	SELECT max(episode_no) INTO ep_no
	FROM bitfinex.bf_trades
	WHERE snapshot_id = NEW.snapshot_id 
	  AND exchange_timestamp < NEW.exchange_timestamp;
	  
	IF FOUND THEN 
		IF ep_no > NEW.episode_no THEN
			RAISE EXCEPTION 'episode_no % of trade % is less than % in some earlier trade', 
				NEW.episode_no, NEW.id, ep_no;
		END IF;
	END IF;
	
	SELECT min(episode_no) INTO ep_no
	FROM bitfinex.bf_trades
	WHERE snapshot_id = NEW.snapshot_id 
	  AND exchange_timestamp > NEW.exchange_timestamp;
	  
	IF FOUND THEN 
		IF ep_no < NEW.episode_no THEN
			RAISE EXCEPTION 'episode_no % of trade % is greater than % in some later trade', 
				NEW.episode_no, NEW.id, ep_no;
		END IF;
	END IF;
	RETURN NULL;
END;

$$;


ALTER FUNCTION bitfinex.bf_trades_check_episode_no_order() OWNER TO "ob-analytics";

--
-- Name: bf_trades_dress_new_row(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_trades_dress_new_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	precision bitfinex.bf_pairs.precision%TYPE;
	last_episode bitfinex.bf_trades.episode_no%TYPE;
	trade_episode_no bitfinex.bf_order_book_events.episode_no%TYPE;
	trade_event_no bitfinex.bf_order_book_events.event_no%TYPE;

BEGIN
	SELECT bf_pairs.precision INTO precision 
	FROM bitfinex.bf_pairs JOIN bitfinex.bf_snapshots USING (pair)
	WHERE snapshot_id = NEW.snapshot_id;

	NEW.price = round(NEW.price, precision);
	IF NEW.qty < 0 THEN
		NEW.direction = 'S';
		NEW.qty = -NEW.qty;
	ELSE
		NEW.direction  = 'B';
	END IF;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_trades_dress_new_row() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_episodes; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_order_book_episodes (
    snapshot_id integer NOT NULL,
    episode_no integer NOT NULL,
    exchange_timestamp timestamp with time zone NOT NULL
);


ALTER TABLE bitfinex.bf_order_book_episodes OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_order_book_events (
    order_id bigint,
    event_price numeric,
    order_qty numeric,
    local_timestamp timestamp(3) with time zone,
    order_price numeric,
    event_qty numeric,
    snapshot_id integer NOT NULL,
    episode_no integer NOT NULL,
    exchange_timestamp timestamp(3) with time zone,
    order_next_episode_no integer NOT NULL,
    event_no smallint NOT NULL,
    side character(1) NOT NULL,
    matched boolean DEFAULT false NOT NULL,
    order_next_event_price numeric DEFAULT '-2.0'::numeric NOT NULL,
    active_episode_no integer
)
WITH (autovacuum_enabled='true', autovacuum_analyze_threshold='5000', autovacuum_vacuum_threshold='5000', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_vacuum_cost_delay='0');
ALTER TABLE ONLY bitfinex.bf_order_book_events ALTER COLUMN order_next_episode_no SET STATISTICS 1000;
ALTER TABLE ONLY bitfinex.bf_order_book_events ALTER COLUMN active_episode_no SET STATISTICS 1000;


ALTER TABLE bitfinex.bf_order_book_events OWNER TO "ob-analytics";

--
-- Name: bf_pairs; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_pairs (
    pair character varying(12) NOT NULL,
    "precision" integer NOT NULL,
    "P0" smallint,
    "P1" smallint,
    "P2" smallint,
    "P3" smallint
);


ALTER TABLE bitfinex.bf_pairs OWNER TO "ob-analytics";

--
-- Name: bf_snapshots; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_snapshots (
    snapshot_id integer NOT NULL,
    len smallint,
    pair character varying(12) NOT NULL,
    prec character(2) NOT NULL
);


ALTER TABLE bitfinex.bf_snapshots OWNER TO "ob-analytics";

--
-- Name: COLUMN bf_snapshots.len; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_snapshots.len IS 'Number of orders below/above best price specified in Bitfinex'' Raw Book subscription request for this snapshot';


--
-- Name: bf_active_orders_after_episode_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_active_orders_after_episode_v AS
 SELECT ob.side,
    ob.order_price,
    ob.order_id,
    ob.order_qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN sum(ob.order_qty) OVER asks
            ELSE sum(ob.order_qty) OVER bids
        END AS cumm_qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN round((((10000)::numeric * (ob.order_price - first_value(ob.order_price) OVER asks)) / first_value(ob.order_price) OVER asks), 6)
            ELSE round((((10000)::numeric * (first_value(ob.order_price) OVER bids - ob.order_price)) / first_value(ob.order_price) OVER bids), 6)
        END AS bps,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN dense_rank() OVER ask_prices
            ELSE dense_rank() OVER bid_prices
        END AS lvl,
    e.snapshot_id,
    e.episode_no,
    e.exchange_timestamp,
    ob.episode_no AS order_episode_no,
    ob.exchange_timestamp AS order_exchange_timestamp,
    bf_pairs.pair
   FROM (((bitfinex.bf_order_book_episodes e
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     JOIN bitfinex.bf_pairs USING (pair))
     JOIN bitfinex.bf_order_book_events ob ON (((ob.snapshot_id = e.snapshot_id) AND (ob.active_episode_no <= e.episode_no) AND (ob.event_price > (0)::numeric) AND (ob.order_next_episode_no > e.episode_no))))
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price, ob.order_id), bids AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC, ob.order_id), ask_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price), bid_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC)
  ORDER BY ob.order_price DESC, ((ob.order_id)::numeric * (
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN '-1'::integer
            ELSE 1
        END)::numeric);


ALTER TABLE bitfinex.bf_active_orders_after_episode_v OWNER TO "ob-analytics";

--
-- Name: VIEW bf_active_orders_after_episode_v; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON VIEW bitfinex.bf_active_orders_after_episode_v IS 'An actual state of an order book after an episode';


--
-- Name: bf_active_orders_between_episodes_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_active_orders_between_episodes_v AS
 SELECT ob.side,
    ob.order_price,
    ob.order_id,
    ob.order_qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN sum(ob.order_qty) OVER asks
            ELSE sum(ob.order_qty) OVER bids
        END AS cumm_qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN round((((10000)::numeric * (ob.order_price - first_value(ob.order_price) OVER asks)) / first_value(ob.order_price) OVER asks), 6)
            ELSE round((((10000)::numeric * (first_value(ob.order_price) OVER bids - ob.order_price)) / first_value(ob.order_price) OVER bids), 6)
        END AS bps,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN dense_rank() OVER ask_prices
            ELSE dense_rank() OVER bid_prices
        END AS lvl,
    e.snapshot_id,
    e.episode_no,
    e.exchange_timestamp,
    ob.episode_no AS order_episode_no,
    ob.exchange_timestamp AS order_exchange_timestamp,
    bf_pairs.pair
   FROM (((bitfinex.bf_order_book_episodes e
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     JOIN bitfinex.bf_pairs USING (pair))
     JOIN LATERAL ( SELECT ob_1.order_id,
            ob_1.order_qty,
            ob_1.order_price,
            ob_1.snapshot_id,
            ob_1.episode_no,
            ob_1.exchange_timestamp,
            ob_1.side
           FROM bitfinex.bf_order_book_events ob_1
          WHERE ((ob_1.snapshot_id = e.snapshot_id) AND (ob_1.event_price > (0)::numeric) AND (ob_1.active_episode_no < e.episode_no) AND (ob_1.order_next_episode_no > e.episode_no))
        UNION ALL
         SELECT ob_1.order_id,
            ob_1.order_qty,
                CASE
                    WHEN (ob_1.side = 'A'::bpchar) THEN GREATEST(ob_1.order_next_event_price, ob_1.order_price)
                    ELSE LEAST(ob_1.order_next_event_price, ob_1.order_price)
                END AS order_price,
            ob_1.snapshot_id,
            ob_1.episode_no,
            ob_1.exchange_timestamp,
            ob_1.side
           FROM bitfinex.bf_order_book_events ob_1
          WHERE ((ob_1.snapshot_id = e.snapshot_id) AND (ob_1.event_price > (0)::numeric) AND (ob_1.active_episode_no < e.episode_no) AND (ob_1.order_next_episode_no = e.episode_no) AND (ob_1.order_next_event_price > (0)::numeric))) ob USING (snapshot_id))
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price, ob.order_id), bids AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC, ob.order_id), ask_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price), bid_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC)
  ORDER BY ob.order_price DESC, ((ob.order_id)::numeric * (
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN '-1'::integer
            ELSE 1
        END)::numeric);


ALTER TABLE bitfinex.bf_active_orders_between_episodes_v OWNER TO "ob-analytics";

--
-- Name: VIEW bf_active_orders_between_episodes_v; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON VIEW bitfinex.bf_active_orders_between_episodes_v IS 'A possible state of an order book which might happen between episodes when the spread is widest. ';


--
-- Name: bf_cons_book_episodes; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_cons_book_episodes (
    episode_no integer NOT NULL,
    exchange_timestamp timestamp with time zone NOT NULL,
    snapshot_id integer NOT NULL
);


ALTER TABLE bitfinex.bf_cons_book_episodes OWNER TO "ob-analytics";

--
-- Name: bf_cons_book_events; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_cons_book_events (
    episode_no integer NOT NULL,
    event_no smallint NOT NULL,
    price numeric NOT NULL,
    cnt integer NOT NULL,
    qty numeric NOT NULL,
    exchange_timestamp timestamp with time zone NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    snapshot_id integer NOT NULL,
    active_episode_no integer NOT NULL,
    price_next_episode_no integer NOT NULL,
    side character(1) NOT NULL
)
WITH (autovacuum_enabled='true', autovacuum_vacuum_threshold='5000', autovacuum_analyze_threshold='5000', autovacuum_analyze_scale_factor='0.0', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_cost_delay='0');
ALTER TABLE ONLY bitfinex.bf_cons_book_events ALTER COLUMN active_episode_no SET STATISTICS 1000;
ALTER TABLE ONLY bitfinex.bf_cons_book_events ALTER COLUMN price_next_episode_no SET STATISTICS 1000;


ALTER TABLE bitfinex.bf_cons_book_events OWNER TO "ob-analytics";

--
-- Name: bf_trades; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_trades (
    id bigint NOT NULL,
    trade_timestamp timestamp(3) with time zone NOT NULL,
    qty numeric NOT NULL,
    price numeric NOT NULL,
    local_timestamp timestamp(3) with time zone NOT NULL,
    snapshot_id integer NOT NULL,
    exchange_timestamp timestamp(3) with time zone NOT NULL,
    episode_no integer,
    event_no smallint,
    direction character(1) NOT NULL
)
WITH (autovacuum_enabled='true', autovacuum_analyze_threshold='5000', autovacuum_vacuum_threshold='5000', autovacuum_analyze_scale_factor='0.0', autovacuum_vacuum_scale_factor='0.0');


ALTER TABLE bitfinex.bf_trades OWNER TO "ob-analytics";

--
-- Name: COLUMN bf_trades.id; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.id IS 'Bitfinex'' trade database id';


--
-- Name: COLUMN bf_trades.trade_timestamp; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.trade_timestamp IS 'Bitfinex'' millisecond time stamp of the trade';


--
-- Name: COLUMN bf_trades.local_timestamp; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.local_timestamp IS 'When we''ve got this record from Bitfinex';


--
-- Name: COLUMN bf_trades.exchange_timestamp; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.exchange_timestamp IS 'Bitfinex''s timestamp';


--
-- Name: bf_order_book_events_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_order_book_events_v AS
 SELECT i.exchange_timestamp,
    i.snapshot_id,
    i.episode_no,
    i.event_no,
    i.event_qty,
    COALESCE(t.matched_qty, (0)::numeric) AS matched_qty,
    COALESCE(t.mc, (0)::bigint) AS matched_count,
    i.event_price,
    i.order_qty,
    i.order_price,
    i.order_id,
    bf_snapshots.pair,
    t.last_trade_exchange_timestamp,
    i.local_timestamp,
    i.order_next_episode_no,
    i.side
   FROM ((bitfinex.bf_order_book_events i
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     LEFT JOIN ( SELECT bf_trades.snapshot_id,
            bf_trades.episode_no,
            bf_trades.event_no,
            sum(bf_trades.qty) AS matched_qty,
            max(bf_trades.exchange_timestamp) AS last_trade_exchange_timestamp,
            count(*) AS mc
           FROM bitfinex.bf_trades
          GROUP BY bf_trades.snapshot_id, bf_trades.episode_no, bf_trades.event_no) t USING (snapshot_id, episode_no, event_no));


ALTER TABLE bitfinex.bf_order_book_events_v OWNER TO "ob-analytics";

--
-- Name: bf_p_snapshots_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_p_snapshots_v AS
 SELECT s.snapshot_id,
    s.len,
    s.prec,
    e.events,
    e.last_episode,
    date_trunc('seconds'::text, e.min_e_et) AS starts,
    date_trunc('seconds'::text, e.max_e_et) AS ends,
    s.pair
   FROM (bitfinex.bf_snapshots s
     LEFT JOIN ( SELECT bf_cons_book_events.snapshot_id,
            count(*) AS events,
            min(bf_cons_book_events.exchange_timestamp) AS min_e_et,
            max(bf_cons_book_events.exchange_timestamp) AS max_e_et,
            max(bf_cons_book_events.episode_no) AS last_episode
           FROM bitfinex.bf_cons_book_events
          GROUP BY bf_cons_book_events.snapshot_id) e USING (snapshot_id))
  WHERE (s.prec ~~ 'P%'::text)
  ORDER BY s.snapshot_id DESC;


ALTER TABLE bitfinex.bf_p_snapshots_v OWNER TO "ob-analytics";

--
-- Name: bf_price_levels_after_episode_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_price_levels_after_episode_v AS
 SELECT ob.side,
    ob.price,
    ob.cnt,
    ob.qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN sum(ob.qty) OVER asks
            ELSE sum(ob.qty) OVER bids
        END AS cumm_qty,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN ceiling((((10000)::numeric * (ob.price - first_value(ob.price) OVER asks)) / first_value(ob.price) OVER asks))
            ELSE floor((((10000)::numeric * (first_value(ob.price) OVER bids - ob.price)) / first_value(ob.price) OVER bids))
        END AS bps,
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN dense_rank() OVER asks
            ELSE dense_rank() OVER bids
        END AS lvl,
    e.snapshot_id,
    e.episode_no,
    e.exchange_timestamp,
    ob.episode_no AS price_level_episode_no,
    ob.exchange_timestamp AS price_level_exchange_timestamp,
    bf_pairs.pair
   FROM (((bitfinex.bf_cons_book_episodes e
     JOIN bitfinex.bf_cons_book_events ob USING (snapshot_id))
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     JOIN bitfinex.bf_pairs USING (pair))
  WHERE ((ob.active_episode_no <= e.episode_no) AND ((ob.cnt)::numeric > (0)::numeric) AND (ob.price_next_episode_no > e.episode_no))
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.price), bids AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.price DESC)
  ORDER BY ob.price DESC;


ALTER TABLE bitfinex.bf_price_levels_after_episode_v OWNER TO "ob-analytics";

--
-- Name: bf_r_snapshots_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_r_snapshots_v AS
 SELECT s.snapshot_id,
    s.len,
    e.events,
    e.last_episode,
    t.trades,
    date_trunc('seconds'::text, LEAST(e.min_e_et, t.min_t_et)) AS starts,
    date_trunc('seconds'::text, GREATEST(e.max_e_et, t.max_t_et)) AS ends,
    t.matched_to_episode,
    t.matched_to_event,
    s.pair
   FROM ((bitfinex.bf_snapshots s
     LEFT JOIN LATERAL ( SELECT bf_order_book_events.snapshot_id,
            count(*) AS events,
            min(bf_order_book_events.exchange_timestamp) AS min_e_et,
            max(bf_order_book_events.exchange_timestamp) AS max_e_et,
            max(bf_order_book_events.episode_no) AS last_episode
           FROM bitfinex.bf_order_book_events
          WHERE (bf_order_book_events.snapshot_id = s.snapshot_id)
          GROUP BY bf_order_book_events.snapshot_id) e USING (snapshot_id))
     LEFT JOIN LATERAL ( SELECT bf_trades.snapshot_id,
            count(*) AS trades,
            count(*) FILTER (WHERE (bf_trades.event_no IS NOT NULL)) AS matched_to_event,
            count(*) FILTER (WHERE (bf_trades.episode_no IS NOT NULL)) AS matched_to_episode,
            min(bf_trades.exchange_timestamp) AS min_t_et,
            max(bf_trades.exchange_timestamp) AS max_t_et
           FROM bitfinex.bf_trades
          WHERE (bf_trades.snapshot_id = s.snapshot_id)
          GROUP BY bf_trades.snapshot_id) t USING (snapshot_id))
  WHERE (s.prec = 'R0'::bpchar)
  ORDER BY s.snapshot_id DESC;


ALTER TABLE bitfinex.bf_r_snapshots_v OWNER TO "ob-analytics";

--
-- Name: bf_snapshots_snapshot_id_seq; Type: SEQUENCE; Schema: bitfinex; Owner: ob-analytics
--

CREATE SEQUENCE bitfinex.bf_snapshots_snapshot_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bitfinex.bf_snapshots_snapshot_id_seq OWNER TO "ob-analytics";

--
-- Name: bf_snapshots_snapshot_id_seq; Type: SEQUENCE OWNED BY; Schema: bitfinex; Owner: ob-analytics
--

ALTER SEQUENCE bitfinex.bf_snapshots_snapshot_id_seq OWNED BY bitfinex.bf_snapshots.snapshot_id;


--
-- Name: bf_trades_beyond_spread_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_trades_beyond_spread_v AS
 SELECT t.snapshot_id,
    t.episode_no,
    t.id,
    t.trade_timestamp,
    t.qty,
    t.price,
    bf_snapshots.pair,
    t.local_timestamp,
    t.exchange_timestamp,
    t.event_no,
    t.direction,
    s.best_bid_price,
    s.best_ask_price,
    s.best_bid_qty,
    s.best_ask_qty,
    s.timing
   FROM ((bitfinex.bf_trades t
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     JOIN bitfinex.bf_spreads s USING (snapshot_id, episode_no))
  WHERE ((s.timing = 'B'::bpchar) AND (NOT ((t.price >= s.best_bid_price) AND (t.price <= s.best_ask_price))));


ALTER TABLE bitfinex.bf_trades_beyond_spread_v OWNER TO "ob-analytics";

--
-- Name: bf_trades_matched_episode_delay_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_trades_matched_episode_delay_v AS
 SELECT (p.exchange_timestamp - t.exchange_timestamp) AS delay,
    t.id,
    t.exchange_timestamp,
    t.episode_no,
    t.event_no,
    t.qty,
    t.price,
    t.snapshot_id
   FROM (bitfinex.bf_trades t
     JOIN bitfinex.bf_order_book_episodes p USING (snapshot_id, episode_no))
  ORDER BY t.snapshot_id, (p.exchange_timestamp - t.exchange_timestamp) DESC;


ALTER TABLE bitfinex.bf_trades_matched_episode_delay_v OWNER TO "ob-analytics";

--
-- Name: bf_trades_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_trades_v AS
 SELECT t.id,
    t.qty,
    round(t.price, bf_pairs."precision") AS price,
    count(*) OVER (PARTITION BY t.snapshot_id, t.episode_no, t.event_no) AS matched_count,
    bf_pairs.pair,
    t.snapshot_id,
    t.episode_no,
    t.event_no,
    t.trade_timestamp,
    t.exchange_timestamp,
    e.exchange_timestamp AS episode_exchange_timestamp,
    t.local_timestamp,
    t.direction
   FROM (((bitfinex.bf_trades t
     JOIN bitfinex.bf_snapshots USING (snapshot_id))
     JOIN bitfinex.bf_pairs USING (pair))
     LEFT JOIN bitfinex.bf_order_book_episodes e USING (snapshot_id, episode_no))
  WHERE (t.local_timestamp IS NOT NULL);


ALTER TABLE bitfinex.bf_trades_v OWNER TO "ob-analytics";

--
-- Name: bf_snapshots snapshot_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('bitfinex.bf_snapshots_snapshot_id_seq'::regclass);


--
-- Name: bf_cons_book_episodes bf_cons_book_episodes_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_episodes
    ADD CONSTRAINT bf_cons_book_episodes_pkey PRIMARY KEY (snapshot_id, episode_no);


--
-- Name: bf_cons_book_events bf_cons_book_events_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_events
    ADD CONSTRAINT bf_cons_book_events_pkey PRIMARY KEY (snapshot_id, episode_no, event_no);


--
-- Name: bf_order_book_episodes bf_order_book_episodes_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_pkey PRIMARY KEY (snapshot_id, episode_no);


--
-- Name: bf_order_book_events bf_order_book_events_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_pkey PRIMARY KEY (snapshot_id, episode_no, event_no);


--
-- Name: bf_pairs bf_pairs_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_pairs
    ADD CONSTRAINT bf_pairs_pkey PRIMARY KEY (pair);


--
-- Name: bf_snapshots bf_snapshots_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots
    ADD CONSTRAINT bf_snapshots_pkey PRIMARY KEY (snapshot_id);


--
-- Name: bf_spreads bf_spreads_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_spreads
    ADD CONSTRAINT bf_spreads_pkey PRIMARY KEY (snapshot_id, timing, episode_no);


--
-- Name: bf_trades bf_trades_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_pkey PRIMARY KEY (snapshot_id, id);


--
-- Name: bf_cons_book_events_idx_update_next_episode_no; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_cons_book_events_idx_update_next_episode_no ON bitfinex.bf_cons_book_events USING btree (snapshot_id, price, episode_no);


--
-- Name: bf_order_book_events_idx_active_next; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_events_idx_active_next ON bitfinex.bf_order_book_events USING btree (snapshot_id, active_episode_no, order_next_episode_no) WHERE (event_price > (0)::numeric);


--
-- Name: bf_order_book_events_idx_next_active; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_events_idx_next_active ON bitfinex.bf_order_book_events USING btree (snapshot_id, order_next_episode_no, active_episode_no) WHERE (event_price > (0)::numeric);


--
-- Name: bf_order_book_events_idx_update_next_episode_no; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_events_idx_update_next_episode_no ON bitfinex.bf_order_book_events USING btree (snapshot_id, order_id);


--
-- Name: bf_trades_idx_snapshot_id_episode_no_event_no; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id_episode_no_event_no ON bitfinex.bf_trades USING btree (snapshot_id, episode_no, event_no);


--
-- Name: bf_trades_idx_snapshot_id_exchange_timestamp; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id_exchange_timestamp ON bitfinex.bf_trades USING btree (snapshot_id, exchange_timestamp);


--
-- Name: bf_trades a_check_episode_no_order; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE CONSTRAINT TRIGGER a_check_episode_no_order AFTER INSERT OR UPDATE OF episode_no ON bitfinex.bf_trades NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW WHEN ((new.episode_no IS NOT NULL)) EXECUTE PROCEDURE bitfinex.bf_trades_check_episode_no_order();


--
-- Name: bf_trades a_dress_new_row; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_dress_new_row BEFORE INSERT ON bitfinex.bf_trades FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_trades_dress_new_row();


--
-- Name: bf_order_book_events a_dress_new_row; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_dress_new_row BEFORE INSERT ON bitfinex.bf_order_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_dress_new_row();


--
-- Name: bf_cons_book_events a_dress_new_row; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_dress_new_row BEFORE INSERT ON bitfinex.bf_cons_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_cons_book_events_dress_new_row();


--
-- Name: bf_order_book_episodes a_match_trades_to_events; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_match_trades_to_events AFTER INSERT ON bitfinex.bf_order_book_episodes FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_episodes_match_trades_to_events();


--
-- Name: bf_order_book_episodes b_match_trades_to_episodes; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER b_match_trades_to_episodes AFTER INSERT ON bitfinex.bf_order_book_episodes FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_episodes_match_trades_to_episodes();


--
-- Name: bf_order_book_events b_update_next_episode_no; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER b_update_next_episode_no BEFORE INSERT ON bitfinex.bf_order_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_update_next_episode_no();


--
-- Name: bf_cons_book_events b_update_next_episode_no; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER b_update_next_episode_no BEFORE INSERT ON bitfinex.bf_cons_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_cons_book_events_update_next_episode_no();


--
-- Name: bf_order_book_events c_match_trades_to_events; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER c_match_trades_to_events BEFORE INSERT ON bitfinex.bf_order_book_events FOR EACH ROW WHEN ((new.event_qty < (0)::numeric)) EXECUTE PROCEDURE bitfinex.bf_order_book_events_match_trades_to_events();


--
-- Name: bf_cons_book_episodes bf_cons_book_episodes_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_episodes
    ADD CONSTRAINT bf_cons_book_episodes_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_cons_book_events bf_cons_book_events_fkey_bf_cons_book_episodes; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_events
    ADD CONSTRAINT bf_cons_book_events_fkey_bf_cons_book_episodes FOREIGN KEY (snapshot_id, episode_no) REFERENCES bitfinex.bf_cons_book_episodes(snapshot_id, episode_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_cons_book_events bf_cons_book_events_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_events
    ADD CONSTRAINT bf_cons_book_events_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_episodes bf_order_book_episodes_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_events bf_order_book_events_fkey_bf_order_book_episodes; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_bf_order_book_episodes FOREIGN KEY (snapshot_id, episode_no) REFERENCES bitfinex.bf_order_book_episodes(snapshot_id, episode_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_events bf_order_book_events_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_snapshots bf_snapshots_fkey_bf_pairs; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots
    ADD CONSTRAINT bf_snapshots_fkey_bf_pairs FOREIGN KEY (pair) REFERENCES bitfinex.bf_pairs(pair) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_spreads bf_spreads_fkey_episode_no; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_spreads
    ADD CONSTRAINT bf_spreads_fkey_episode_no FOREIGN KEY (snapshot_id, episode_no) REFERENCES bitfinex.bf_order_book_episodes(snapshot_id, episode_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_spreads bf_spreads_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_spreads
    ADD CONSTRAINT bf_spreads_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_trades bf_trades_fkey_bf_order_book_events; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_bf_order_book_events FOREIGN KEY (snapshot_id, episode_no, event_no) REFERENCES bitfinex.bf_order_book_events(snapshot_id, episode_no, event_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_trades bf_trades_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

