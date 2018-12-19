--
-- PostgreSQL database dump
--

-- Dumped from database version 10.6
-- Dumped by pg_dump version 10.6

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
-- Name: bitstamp; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA bitstamp;


ALTER SCHEMA bitstamp OWNER TO "ob-analytics";

--
-- Name: direction; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.direction AS ENUM (
    'buy',
    'sell'
);


ALTER TYPE bitstamp.direction OWNER TO "ob-analytics";

--
-- Name: enum_neighborhood; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.enum_neighborhood AS ENUM (
    'before',
    'after'
);


ALTER TYPE bitstamp.enum_neighborhood OWNER TO "ob-analytics";

--
-- Name: live_orders_event; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.live_orders_event AS ENUM (
    'initial',
    'order_created',
    'order_changed',
    'order_deleted',
    'final'
);


ALTER TYPE bitstamp.live_orders_event OWNER TO "ob-analytics";

--
-- Name: order_book_record; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.order_book_record AS (
	ts timestamp with time zone,
	price numeric,
	amount numeric,
	direction bitstamp.direction,
	order_id bigint,
	microtimestamp timestamp with time zone,
	event_no smallint,
	pair_id smallint,
	is_maker boolean,
	datetime timestamp with time zone
);


ALTER TYPE bitstamp.order_book_record OWNER TO "ob-analytics";

--
-- Name: side; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.side AS ENUM (
    'ask',
    'bid'
);


ALTER TYPE bitstamp.side OWNER TO "ob-analytics";

--
-- Name: _get_live_orders_eon(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._get_live_orders_eon(ts timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT '-infinity'::timestamptz;
$$;


ALTER FUNCTION bitstamp._get_live_orders_eon(ts timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: FUNCTION _get_live_orders_eon(ts timestamp with time zone); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp._get_live_orders_eon(ts timestamp with time zone) IS 'When bitstamp.live_orders will be partitioned, this function will return the ''eon'' for the provided timestamp. Currently returns -inf';


--
-- Name: _get_match_rule(numeric, numeric, numeric, numeric, bitstamp.live_orders_event, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._get_match_rule(trade_amount numeric, trade_price numeric, event_amount numeric, event_fill numeric, event bitstamp.live_orders_event, tolerance numeric) RETURNS smallint
    LANGUAGE sql IMMUTABLE
    AS $$

    SELECT CASE 
				WHEN _get_match_rule.trade_amount = _get_match_rule.event_fill
					THEN 0::smallint	-- the event matches the trade with certainty. Usually 98% of all matches have this code.
				WHEN abs(_get_match_rule.trade_amount*_get_match_rule.trade_price - _get_match_rule.event_fill*_get_match_rule.trade_price) < tolerance 
					THEN 1::smallint	-- it is highly likely that the event matches the trade. 'fill' and 'amount' are different due to rounding errors but within tolerance
	      		WHEN _get_match_rule.event_fill IS NULL 
					THEN 2::smallint	-- it is likely that the event matches the trade. 'fill' is not available since the previous event is missing
	      		WHEN _get_match_rule.event = 'order_deleted' 
				 AND _get_match_rule.event_fill = 0.0 
				 AND abs(_get_match_rule.trade_amount*_get_match_rule.trade_price - _get_match_rule.event_amount*_get_match_rule.trade_price) < tolerance 
				  	THEN 3::smallint	-- it is highly likely that the event matches the trade. 'fill' is wrong due to Bitstamp's bug while 'amount's are within tolerance
		  ELSE NULL::smallint
    END;
	           

$$;


ALTER FUNCTION bitstamp._get_match_rule(trade_amount numeric, trade_price numeric, event_amount numeric, event_fill numeric, event bitstamp.live_orders_event, tolerance numeric) OWNER TO "ob-analytics";

--
-- Name: FUNCTION _get_match_rule(trade_amount numeric, trade_price numeric, event_amount numeric, event_fill numeric, event bitstamp.live_orders_event, tolerance numeric); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp._get_match_rule(trade_amount numeric, trade_price numeric, event_amount numeric, event_fill numeric, event bitstamp.live_orders_event, tolerance numeric) IS 'The function determines the ''ones'' part of the two-digit matching rule code used to match a trade and an event. See the function body for details';


--
-- Name: _in_milliseconds(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._in_milliseconds(ts timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$

SELECT ( ( EXTRACT( EPOCH FROM (_in_milliseconds.ts - '1514754000 seconds'::interval) )::numeric(20,5) + 1514754000 )*1000 )::text;

$$;


ALTER FUNCTION bitstamp._in_milliseconds(ts timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: FUNCTION _in_milliseconds(ts timestamp with time zone); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp._in_milliseconds(ts timestamp with time zone) IS 'Since R''s POSIXct is not able to handle time with the precision higher than 0.1 of millisecond, this function converts timestamp to text with this precision to ensure that the timestamps are not mangled by an interface between Postgres and R somehow.';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: live_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_orders (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no smallint NOT NULL,
    event bitstamp.live_orders_event NOT NULL,
    order_type bitstamp.direction NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no smallint,
    trade_id bigint,
    orig_microtimestamp timestamp with time zone,
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    datetime timestamp with time zone NOT NULL,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no smallint,
    CONSTRAINT created_amount_positive CHECK (((event <> 'order_created'::bitstamp.live_orders_event) OR (amount > (0)::numeric))),
    CONSTRAINT created_is_matchless CHECK (((event <> 'order_created'::bitstamp.live_orders_event) OR ((event = 'order_created'::bitstamp.live_orders_event) AND (trade_id IS NULL)))),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT only_ex_nihilo_may_have_price_event_no_null CHECK (((price_event_no IS NOT NULL) OR ((price_event_no IS NULL) AND (event_no = 1) AND (event <> 'order_created'::bitstamp.live_orders_event)))),
    CONSTRAINT price_is_positive CHECK ((price > (0)::numeric))
)
PARTITION BY LIST (order_type);


ALTER TABLE bitstamp.live_orders OWNER TO "ob-analytics";

--
-- Name: _order_book_after_event(bitstamp.order_book_record[], bitstamp.live_orders, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._order_book_after_event(p_ob bitstamp.order_book_record[], p_ev bitstamp.live_orders, p_only_makers boolean DEFAULT true) RETURNS bitstamp.order_book_record[]
    LANGUAGE sql IMMUTABLE
    AS $$

WITH orders AS (
		SELECT  p_ev.microtimestamp AS ts,
				price,
				amount,
				direction,
				order_id,
				microtimestamp,
				event_no, 
				pair_id,
				COALESCE(
					CASE direction
						WHEN 'buy' THEN price < min(price) FILTER (WHERE direction = 'sell') OVER (ORDER BY datetime, microtimestamp)
						WHEN 'sell' THEN price > max(price) FILTER (WHERE direction = 'buy') OVER (ORDER BY datetime, microtimestamp)
					END,
				TRUE) -- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
				AS is_maker,
				datetime
		FROM ( SELECT * 
			  	FROM unnest(p_ob) i
			  	WHERE ( p_ev.event = 'order_created' OR i.order_id <> p_ev.order_id )
				UNION ALL 
				SELECT  p_ev.microtimestamp, 
						 p_ev.price,
						 p_ev.amount,
						 p_ev.order_type,
						 p_ev.order_id,
						 p_ev.microtimestamp,
						 p_ev.event_no,
						 p_ev.pair_id,
						 TRUE,
						 p_ev.datetime
				WHERE p_ev.event <> 'order_deleted' 
				) a
		
	)
	SELECT ARRAY(
		SELECT orders.*::bitstamp.order_book_record
		FROM orders	
		WHERE is_maker OR NOT p_only_makers
   );

$$;


ALTER FUNCTION bitstamp._order_book_after_event(p_ob bitstamp.order_book_record[], p_ev bitstamp.live_orders, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: spread; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.spread (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    episode_microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL
);


ALTER TABLE bitstamp.spread OWNER TO "ob-analytics";

--
-- Name: _spread_from_order_book(bitstamp.order_book_record[]); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._spread_from_order_book(s bitstamp.order_book_record[]) RETURNS bitstamp.spread
    LANGUAGE sql IMMUTABLE
    AS $$

	WITH price_levels AS (
		SELECT ts, 
				direction,
				price,
				sum(amount) AS qty, 
				CASE direction
						WHEN 'sell' THEN price IS NOT DISTINCT FROM min(price) FILTER (WHERE direction = 'sell') OVER ()
						WHEN 'buy' THEN price IS NOT DISTINCT FROM max(price) FILTER (WHERE direction = 'buy') OVER ()
				END AS is_best,
				pair_id
		FROM unnest(s)
		WHERE is_maker
		GROUP BY pair_id, ts, direction, price
	)
	SELECT b.price, b.qty, s.price, s.qty, COALESCE(b.ts, s.ts), pair_id
	FROM (SELECT * FROM price_levels WHERE direction = 'buy' AND is_best) b FULL JOIN (SELECT * FROM price_levels WHERE direction = 'sell' AND is_best) s USING (pair_id);

$$;


ALTER FUNCTION bitstamp._spread_from_order_book(s bitstamp.order_book_record[]) OWNER TO "ob-analytics";

--
-- Name: live_trades; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_trades (
    bitstamp_trade_id bigint,
    amount numeric NOT NULL,
    price numeric NOT NULL,
    trade_type bitstamp.direction NOT NULL,
    trade_timestamp timestamp with time zone NOT NULL,
    buy_order_id bigint NOT NULL,
    sell_order_id bigint NOT NULL,
    local_timestamp timestamp with time zone,
    pair_id smallint NOT NULL,
    sell_microtimestamp timestamp with time zone,
    buy_microtimestamp timestamp with time zone,
    buy_match_rule smallint,
    sell_match_rule smallint,
    buy_event_no smallint,
    sell_event_no smallint,
    trade_id bigint NOT NULL,
    orig_trade_type bitstamp.direction,
    CONSTRAINT microtimestamp_and_event_no_must_be_changed_together CHECK (((((sell_microtimestamp IS NULL) AND (sell_event_no IS NULL)) OR ((sell_microtimestamp IS NOT NULL) AND (sell_event_no IS NOT NULL))) AND (((buy_microtimestamp IS NULL) AND (buy_event_no IS NULL)) OR ((buy_microtimestamp IS NOT NULL) AND (buy_event_no IS NOT NULL)))))
)
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE bitstamp.live_trades OWNER TO "ob-analytics";

--
-- Name: COLUMN live_trades.buy_match_rule; Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON COLUMN bitstamp.live_trades.buy_match_rule IS 'A two-digit code of the match rule used to match this trade with a buy order event. ''tens'' digit determines whether the event was matched to the previously saved trade (''1'') or vice versa (''2''). ''ones'' part is given by _get_match_rule() function';


--
-- Name: COLUMN live_trades.sell_match_rule; Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON COLUMN bitstamp.live_trades.sell_match_rule IS 'A two-digit code of the match rule used to match this trade with a sell order event. ''tens'' digit determines whether the event was matched to the previously saved trade (''1'') or vice versa (''2''). ''ones'' part is given by _get_match_rule() function.';


--
-- Name: _trades_match_buy_event(timestamp with time zone, bigint, numeric, numeric, bitstamp.live_orders_event, interval); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._trades_match_buy_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval DEFAULT '00:00:01'::interval) RETURNS SETOF bitstamp.live_trades
    LANGUAGE sql STABLE
    AS $$

SELECT live_trades.*
FROM bitstamp.live_trades  
WHERE trade_timestamp BETWEEN _trades_match_buy_event.microtimestamp - _trades_match_buy_event.look_around  
									AND _trades_match_buy_event.microtimestamp + _trades_match_buy_event.look_around  
  AND buy_order_id = _trades_match_buy_event.order_id
  AND bitstamp._get_match_rule(trade_amount := amount,
							   trade_price := price,
							   event_amount := _trades_match_buy_event.amount,
							   event_fill := _trades_match_buy_event.fill,
							   event := _trades_match_buy_event.event,
							   tolerance := 0.1::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_trades.pair_id )
							  ) IS NOT NULL
   AND buy_microtimestamp IS NULL
ORDER BY trade_id -- we want the earliest one available 
FOR UPDATE;
  

$$;


ALTER FUNCTION bitstamp._trades_match_buy_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval) OWNER TO "ob-analytics";

--
-- Name: _trades_match_sell_event(timestamp with time zone, bigint, numeric, numeric, bitstamp.live_orders_event, interval); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._trades_match_sell_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval DEFAULT '00:00:01'::interval) RETURNS SETOF bitstamp.live_trades
    LANGUAGE sql STABLE
    AS $$

SELECT live_trades.*
FROM bitstamp.live_trades
WHERE trade_timestamp BETWEEN _trades_match_sell_event.microtimestamp - _trades_match_sell_event.look_around  
									AND _trades_match_sell_event.microtimestamp + _trades_match_sell_event.look_around  
  AND sell_order_id = _trades_match_sell_event.order_id
  AND bitstamp._get_match_rule(trade_amount := amount,
							   trade_price := price,
							   event_amount := _trades_match_sell_event.amount,
							   event_fill := _trades_match_sell_event.fill,
							   event := _trades_match_sell_event.event,
							   tolerance := 0.1::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_trades.pair_id )
							  ) IS NOT NULL
  AND sell_microtimestamp IS NULL
ORDER BY trade_id -- we want the earliest one available 
FOR UPDATE;
  

$$;


ALTER FUNCTION bitstamp._trades_match_sell_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval) OWNER TO "ob-analytics";

--
-- Name: assign_episodes(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.assign_episodes(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE

	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	WITH time_range AS (
		SELECT *
		FROM (
			SELECT era AS start_time, COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS end_time,
					pair_id
			FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
			WHERE pairs.pair = p_pair
		) r
		WHERE p_ts_within_era BETWEEN r.start_time AND r.end_time
	)
	UPDATE bitstamp.live_orders
	SET episode_microtimestamp = NULL,
		episode_order_id = NULL
	FROM time_range	
	WHERE microtimestamp BETWEEN start_time AND end_time
	  AND episode_microtimestamp IS NOT NULL;
	RETURN QUERY   WITH time_range AS (
						SELECT *
						FROM (
							SELECT era AS start_time, COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS end_time,
									pair_id
							FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
							WHERE pairs.pair = p_pair
						) r
						WHERE p_ts_within_era BETWEEN r.start_time AND r.end_time
					),
					-- For episode assignment purposes, order is identified by its ID and its price.
					-- When order's price has been changed (currently by Bitstamp), we consider it as a newly created order
					order_created_pass1 AS (
						SELECT DISTINCT order_id, first_value(microtimestamp) OVER order_life AS created_microtimestamp
						FROM bitstamp.live_orders JOIN time_range USING (pair_id)
						WHERE microtimestamp BETWEEN start_time AND end_time
						WINDOW order_life AS (PARTITION BY order_id, price ORDER BY microtimestamp)
					),
					episodes_pass1 AS (
						SELECT DISTINCT ON (microtimestamp, live_orders.order_id)  microtimestamp, live_orders.order_id, 
							GREATEST(e.created_microtimestamp, m.created_microtimestamp) AS episode_microtimestamp,
							CASE WHEN e.created_microtimestamp > m.created_microtimestamp THEN e.order_id ELSE m.order_id END AS episode_order_id
						FROM bitstamp.live_orders JOIN time_range USING (pair_id) 
								JOIN order_created_pass1 e ON e.order_id = live_orders.order_id AND e.created_microtimestamp <= live_orders.microtimestamp
								JOIN order_created_pass1 m ON m.order_id = matched_order_id AND m.created_microtimestamp <= live_orders.microtimestamp
						WHERE microtimestamp BETWEEN start_time AND end_time
						-- DISTINCT above and ORDER BY below gives us the most recent events for e. and m. 
						ORDER BY microtimestamp, live_orders.order_id, e.created_microtimestamp DESC, m.created_microtimestamp DESC	
					),
					-- Here we check whether Bitstamp has processed some market orders in the wrong order, i.e. those arrived later were processed eariler
					-- If there are no such orders, the query will be empty
					update_order_created_wrong_processing_order AS (
						SELECT a.order_id, 
								a.episode_microtimestamp AS created_microtimestamp, 
								order_created_pass1.created_microtimestamp AS episode_microtimestamp,
								order_created_pass1.order_id AS episode_order_id
						FROM (
							SELECT *, min(episode_microtimestamp) OVER ahead AS created_microtimestamp
							FROM episodes_pass1
							WINDOW ahead AS (ORDER BY microtimestamp DESC)
						) a JOIN order_created_pass1 USING (created_microtimestamp) 
						WHERE episode_microtimestamp > created_microtimestamp	
					),
					-- Usually 'order_created' is an episode on its own. But if Bitstamp has processed some market orders in the wrong order (the above query is non-empty)
					-- then we will assign wrong market orders to another episode - the episode of the market order which had to be processed first
					-- This newly assigned episode will be used afterwards for these orders
					order_created_pass2 AS (
						SELECT order_id, created_microtimestamp, 
								COALESCE(episode_order_id, order_id) AS episode_order_id,
								COALESCE(episode_microtimestamp, created_microtimestamp) AS episode_microtimestamp
						FROM order_created_pass1 LEFT JOIN update_order_created_wrong_processing_order USING (order_id, created_microtimestamp)
					),
					episodes_pass2 AS (
						SELECT *
						FROM (
							SELECT DISTINCT ON (live_orders.order_id, microtimestamp)  
									live_orders.order_id,
									microtimestamp, 
									GREATEST(e.episode_microtimestamp, m.episode_microtimestamp) AS episode_microtimestamp,
									CASE WHEN e.episode_microtimestamp > m.episode_microtimestamp THEN e.episode_order_id ELSE m.episode_order_id END AS episode_order_id
							FROM bitstamp.live_orders JOIN time_range USING (pair_id) 
								JOIN order_created_pass2 e ON e.order_id = live_orders.order_id AND e.created_microtimestamp <= live_orders.microtimestamp
								JOIN order_created_pass2 m ON m.order_id = matched_order_id AND m.created_microtimestamp <= live_orders.microtimestamp
							WHERE microtimestamp BETWEEN start_time AND end_time
							ORDER BY live_orders.order_id, microtimestamp, e.created_microtimestamp DESC, m.created_microtimestamp DESC
						) a
						UNION ALL
						SELECT * 
						FROM update_order_created_wrong_processing_order	-- the wrong 'order_created' events will receive episode_microtimestamp, episode_order_id too
					),
					-- Now all unmatched events which have happened between two events assigned to the same episode in the previous passes, will be assigned to the episode too
					update_all_within_episode AS (
						SELECT order_id, microtimestamp, previous_episode_microtimestamp AS episode_microtimestamp, previous_episode_order_id AS episode_order_id
						FROM (
							SELECT order_id, 
									microtimestamp,
									live_orders.matched_microtimestamp,
									ep.episode_microtimestamp, 
									last(ep.episode_microtimestamp) OVER ahead  AS next_episode_microtimestamp,
									last(ep.episode_order_id) OVER ahead AS next_episode_order_id,
									last(ep.episode_microtimestamp) OVER behind  AS previous_episode_microtimestamp,
									last(ep.episode_order_id) OVER behind AS previous_episode_order_id
							FROM bitstamp.live_orders JOIN time_range USING (pair_id) LEFT JOIN episodes_pass2 ep USING (order_id, microtimestamp)
							WHERE microtimestamp BETWEEN start_time AND end_time
							WINDOW ahead AS (ORDER BY microtimestamp DESC), behind  AS (ORDER BY microtimestamp)
						) a
						WHERE episode_microtimestamp IS NULL	-- we need only events which were not yet assigned to an episode
						 AND matched_microtimestamp IS NULL		-- .. and definitely not matched (above condition implies this one, but just in case ...)
						 AND next_episode_microtimestamp = previous_episode_microtimestamp
						 AND next_episode_order_id = previous_episode_order_id
					),
					episodes_final_pass AS (
						SELECT *
						FROM update_all_within_episode
						UNION ALL
						SELECT *
						FROM episodes_pass2
					)
					UPDATE bitstamp.live_orders
					SET episode_microtimestamp = episodes_final_pass.episode_microtimestamp,
						episode_order_id = episodes_final_pass.episode_order_id
					FROM episodes_final_pass
					WHERE live_orders.microtimestamp = episodes_final_pass.microtimestamp 
					  AND live_orders.order_id = episodes_final_pass.order_id 
					RETURNING live_orders.*;
	RAISE DEBUG 'assign_episodes() exec time: %', clock_timestamp() - v_execution_start_time;
	RETURN;
END;	

$$;


ALTER FUNCTION bitstamp.assign_episodes(p_ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: capture_transient_orders(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.capture_transient_orders(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$

DECLARE 

	e record;
	t record;						   
	
	buy_match CURSOR (c_microtimestamp timestamptz, c_order_id bigint, c_fill numeric, c_amount numeric, c_event bitstamp.live_orders_event )
					  FOR SELECT * FROM bitstamp._trades_match_buy_event(c_microtimestamp, c_order_id, c_fill, c_amount, c_event);

	sell_match CURSOR (c_microtimestamp timestamptz, c_order_id bigint, c_fill numeric,  c_amount numeric, c_event bitstamp.live_orders_event )
					  FOR SELECT * FROM bitstamp._trades_match_sell_event(c_microtimestamp, c_order_id, c_fill, c_amount, c_event);	
	v_tolerance numeric;
	v_pair_id smallint;
	v_execution_start_time timestamp with time zone;
	v_statement_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	
	SELECT pair_id, 0.1::numeric^"R0" INTO v_pair_id, v_tolerance
	FROM bitstamp.pairs 
	WHERE pairs.pair = p_pair;
	
	-- Keep the first  'order_created' and 'order_deleted' events for the given order id and delete the other
	WITH duplicates AS (
		SELECT order_id, event, lead(microtimestamp) OVER (PARTITION BY event, order_id ORDER BY microtimestamp) AS microtimestamp
		FROM bitstamp.transient_live_orders
		WHERE event <> 'order_changed'
		  AND pair_id = v_pair_id
		  AND microtimestamp BETWEEN p_start_time AND p_end_time
		
	)
	DELETE FROM bitstamp.transient_live_orders
	USING duplicates
	WHERE transient_live_orders.order_id = duplicates.order_id
	  AND transient_live_orders.microtimestamp = duplicates.microtimestamp;	
	  
	v_statement_execution_start_time := clock_timestamp();
	WITH deleted AS (
		DELETE FROM bitstamp.transient_live_orders 
		WHERE pair_id = v_pair_id
		  AND microtimestamp BETWEEN p_start_time AND p_end_time
		RETURNING *
	),
	deleted_with_event_no AS (
		SELECT *,
				first_value(event) OVER o AS first_event,
				row_number() OVER o AS event_no,
				COALESCE(lag(amount) OVER o, 0) - amount AS fill,
				COALESCE(lead(microtimestamp) OVER o, 'infinity'::timestamptz) AS next_microtimestamp,
				CASE WHEN lead(microtimestamp) OVER o IS NOT NULL THEN row_number() OVER o + 1 ELSE NULL END AS next_event_no
		FROM deleted
		WINDOW o AS (PARTITION BY order_id ORDER BY microtimestamp)
		
	)
	INSERT INTO bitstamp.live_orders (order_id, amount, "event", order_type, datetime, microtimestamp, local_timestamp, pair_id, price, era,
									 	event_no, fill, next_microtimestamp, next_event_no, price_microtimestamp, price_event_no)
	SELECT order_id, amount, event, order_type, datetime, microtimestamp, local_timestamp, pair_id, price, era,
			CASE first_event WHEN 'order_created' THEN event_no ELSE NULL END AS event_no,
			CASE first_event WHEN 'order_created' THEN fill ELSE NULL END AS fill,
			CASE first_event WHEN 'order_created' THEN next_microtimestamp ELSE NULL END AS next_microtimestamp,									  
			CASE first_event WHEN 'order_created' THEN next_event_no ELSE NULL END AS next_event_no,
			CASE first_event WHEN 'order_created' THEN first_value(microtimestamp) OVER p ELSE NULL END AS price_microtimestamp,
			CASE first_event WHEN 'order_created' THEN first_value(event_no) OVER p ELSE NULL END AS price_event_no
	FROM deleted_with_event_no
	WINDOW p AS (PARTITION BY order_id, price ORDER BY microtimestamp)
	ORDER BY microtimestamp, order_id, event;
	
	
	RAISE DEBUG 'capture_transient_orders() INSERT live_orders exec time: %', clock_timestamp() - v_statement_execution_start_time;
	
	FOR e IN SELECT * FROM bitstamp.live_orders WHERE microtimestamp BETWEEN p_start_time AND p_end_time ORDER BY microtimestamp
		LOOP
					  
		IF  e.event <> 'order_created' THEN 
			IF e.order_type = 'buy' THEN
				FOR t IN buy_match(e.microtimestamp, e.order_id, e.fill, e.amount, e.event ) LOOP

					UPDATE bitstamp.live_trades
					SET buy_microtimestamp = e.microtimestamp,
						buy_event_no = e.event_no,
						buy_match_rule = bitstamp._get_match_rule(trade_amount := t.amount,
																  trade_price := t.price,
																  event_amount := e.amount,
																  event_fill := e.fill,
																  event := e.event,
																  tolerance := v_tolerance
																 )
					WHERE CURRENT OF buy_match;

					EXIT;
				END LOOP;
			ELSE
				FOR t IN sell_match(e.microtimestamp, e.order_id, e.fill, e.amount, e.event ) LOOP

					UPDATE bitstamp.live_trades
					SET sell_microtimestamp = e.microtimestamp,
						sell_event_no = e.event_no,
						sell_match_rule = bitstamp._get_match_rule(trade_amount := t.amount,
																   trade_price := t.price,
																   event_amount := e.amount,
																   event_fill := e.fill,
																   event := e.event,
																   tolerance := v_tolerance
																  ) 
					WHERE CURRENT OF sell_match;
					EXIT;
				END LOOP;
			END IF;
		END IF;			
	END LOOP;
	RAISE DEBUG 'capture_transient_orders() exec time: %', clock_timestamp() - v_execution_start_time;
END;

$$;


ALTER FUNCTION bitstamp.capture_transient_orders(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: capture_transient_trades(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.capture_transient_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_trades
    LANGUAGE sql
    AS $$
WITH deleted AS (
	DELETE FROM bitstamp.transient_live_trades
	RETURNING *
)
INSERT INTO bitstamp.live_trades (bitstamp_trade_id, amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp, pair_id)
SELECT 	bitstamp_trade_id, amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp, pair_id
FROM deleted
ORDER BY bitstamp_trade_id
RETURNING live_trades.*;

$$;


ALTER FUNCTION bitstamp.capture_transient_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: depth_by_episode(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.depth_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS TABLE(episode_microtimestamp timestamp with time zone, price numeric, amount numeric, direction bitstamp.direction, pair_id smallint)
    LANGUAGE plpgsql STABLE
    SET work_mem TO '4GB'
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of depths
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which depths will be calculated
--		p_strict  	 - whether to calculate the spread using events before p_start_time (false) or not (true). 

DECLARE
	v_ob_before_episode bitstamp.order_book_record[];
	v_ob_after_episode bitstamp.order_book_record[];
	
BEGIN
	IF p_strict THEN 
		v_ob_before_episode := '{}';	-- only the events within the [p_start_time, p_end_time] interval will be used
	ELSE
		v_ob_before_episode := NULL;	-- this will force bitstamp._order_book_after_event() to load events before the p_start_time and thus to calculate an entry depth for the interval
	END IF;
	
	FOR v_ob_after_episode IN SELECT bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, p_strict)
	LOOP

		IF v_ob_before_episode IS NULL THEN 
			v_ob_before_episode := ARRAY(SELECT bitstamp.order_book_before( v_ob_after_episode[1].ts, p_pair, FALSE));
		END IF;
																  
		RETURN QUERY WITH dynamics AS (
							SELECT * 
							FROM (  SELECT b.price, SUM(b.amount) AS amount_b, b.direction, b.pair_id 
								  	 FROM unnest(v_ob_before_episode) b 
								     WHERE b.is_maker
								 	 GROUP BY b.price, b.direction, b.pair_id ) b 
					  		 	  FULL JOIN 
							 	  ( SELECT a.price, SUM(a.amount) AS amount_a, a.direction, a.pair_id 
								    FROM unnest(v_ob_after_episode) a 
								    WHERE a.is_maker 
								    GROUP BY a.price, a.direction, a.pair_id ) a 
							 	  USING (price, pair_id, direction)
					  )
					  SELECT v_ob_after_episode[1].ts, dynamics.price, COALESCE(amount_a,0), dynamics.direction, dynamics.pair_id
					  FROM dynamics
					  WHERE amount_a IS DISTINCT FROM amount_b;
																  
		v_ob_before_episode := v_ob_after_episode;
										   
	END LOOP;
	
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.depth_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_eternal_orders(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_eternal_orders(ts_within_era timestamp with time zone) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$

DECLARE
	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	RETURN QUERY  WITH time_range AS (
						SELECT *
						FROM (
							SELECT era AS "start.time", COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS "end.time"
							FROM bitstamp.live_orders_eras
						) r
						WHERE find_and_repair_eternal_orders.ts_within_era BETWEEN r."start.time" AND r."end.time"
					),
					eternal_orders AS (
						SELECT *
						FROM bitstamp.live_orders 
						WHERE microtimestamp BETWEEN (SELECT "start.time" FROM time_range) AND (SELECT "end.time" FROM time_range)
						  AND event <> 'order_deleted'
						  AND next_microtimestamp = 'Infinity'::timestamptz
					),
					filled_orders AS (
						SELECT *
						FROM bitstamp.live_orders 
						WHERE microtimestamp BETWEEN (SELECT "start.time" FROM time_range) AND (SELECT "end.time" FROM time_range)
						  AND fill > 0
					)
					INSERT INTO bitstamp.live_orders (order_id, amount, event, order_type, datetime, microtimestamp,local_timestamp,pair_id,
													 price, fill, next_microtimestamp, era )
					SELECT o.order_id,
							o.amount,
							'order_deleted'::bitstamp.live_orders_event,
							o.order_type,
							o.datetime,
							n.microtimestamp - '00:00:00.000001'::interval,	-- the cancellation will be just before the crossing event 
							NULL::timestamptz, -- we didn't receive this event from Bitstamp!
							o.pair_id,
							o.price,
							NULL::numeric,	-- a trigger will update chain appropriately only if 'fill' and 'next_microtimestamp' are both NULLs
							NULL::timestamptz,
							o.era
					FROM eternal_orders o
						 JOIN LATERAL (	 -- the first 'filled' order that crossed the 'eternal' order. The latter had to be cancelled before but for some reason wasn't
										  SELECT microtimestamp	
										  FROM filled_orders i
										  WHERE i.microtimestamp > o.microtimestamp
											AND i.order_type = o.order_type
											AND i.order_id <> o.order_id -- this is a redundant condition because eternal_orders.next_microtimestamp would not be infinity. But just in case ...
											AND ( CASE o.order_type
													WHEN 'buy' THEN  i.price < o.price 
													WHEN 'sell' THEN  i.price > o.price 
												  END OR (i.price = o.price AND i.datetime > o.datetime ) )
										  ORDER BY microtimestamp
										  LIMIT 1
									  ) n ON TRUE
					RETURNING live_orders.*	;
	RAISE DEBUG 'find_and_repair_eternal_orders() exec time: %', clock_timestamp() - v_execution_start_time;						
	RETURN;
END;	

$$;


ALTER FUNCTION bitstamp.find_and_repair_eternal_orders(ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_missing_fill(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_missing_fill(ts_within_era timestamp with time zone) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$

DECLARE
	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();

RETURN QUERY 
	WITH RECURSIVE time_range AS (
		SELECT *
		FROM (
			SELECT era AS "start.time", COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS "end.time"
			FROM bitstamp.live_orders_eras
		) r
		WHERE find_and_repair_missing_fill.ts_within_era BETWEEN r."start.time" AND r."end.time"
	),
	events_fill_missing AS (
		SELECT o.microtimestamp,
				o.order_id,
				o.event_no,
				o.amount,			
				t.amount AS fill					-- fill is equal to the matched trade's amount
		FROM bitstamp.live_orders o JOIN bitstamp.live_trades t USING (trade_id)
		WHERE microtimestamp BETWEEN (SELECT "start.time" FROM time_range) AND (SELECT "end.time" FROM time_range)
		  AND fill IS NULL
	),
	base AS (
		SELECT microtimestamp, order_id, event_no, amount, fill
		FROM events_fill_missing
		UNION ALL 
		SELECT live_orders.microtimestamp, live_orders.order_id, live_orders.event_no, base.amount + base.fill AS amount, 
				CASE live_orders.event_no WHEN 1 THEN -(base.amount + base.fill) ELSE live_orders.fill END AS fill
		FROM bitstamp.live_orders JOIN base ON live_orders.order_id = base.order_id
		 AND live_orders.event_no = base.event_no - 1
	)	
	UPDATE bitstamp.live_orders
	SET amount = base.amount, fill = base.fill
	FROM base
	WHERE live_orders.microtimestamp = base.microtimestamp
	  AND live_orders.order_id = base.order_id
	  AND live_orders.event_no = base.event_no
	RETURNING live_orders.*	;
	RAISE DEBUG 'find_and_repair_missing_fill() exec time: %', clock_timestamp() - v_execution_start_time;	
	RETURN;
END;	

$$;


ALTER FUNCTION bitstamp.find_and_repair_missing_fill(ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_partially_matched(timestamp with time zone, text, numeric, interval); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_partially_matched(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_tolerance_percentage numeric DEFAULT 0.0001, p_look_around interval DEFAULT '00:00:02'::interval) RETURNS SETOF bitstamp.live_trades
    LANGUAGE plpgsql
    AS $$

DECLARE
	trades CURSOR (p_start_time timestamptz, p_end_time timestamptz, p_pair_id smallint) FOR
				SELECT * 
				FROM bitstamp.live_trades
				WHERE pair_id = p_pair_id
				  AND trade_timestamp BETWEEN date_trunc('seconds', p_start_time) AND date_trunc('seconds', p_end_time)
				  AND ( buy_microtimestamp IS NULL OR sell_microtimestamp IS NULL )
				FOR UPDATE;
				
	v_start_time timestamp with time zone;
	v_end_time timestamp with time zone;
	v_pair_id smallint;
	v_execution_start_time timestamp with time zone;
	v_statement_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	SELECT pair_id INTO v_pair_id 
	FROM bitstamp.pairs 
	WHERE pair = p_pair;
	
	SELECT start_time, end_time INTO v_start_time, v_end_time
	FROM (
		SELECT era AS start_time, COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS end_time
		FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
		WHERE pairs.pair = p_pair
	) r
	WHERE p_ts_within_era BETWEEN  start_time AND end_time;
	
	
	FOR t IN trades(v_start_time, v_end_time, v_pair_id) LOOP
	
		IF t.buy_microtimestamp IS NULL THEN 
			v_statement_execution_start_time := clock_timestamp();
			RETURN QUERY
				WITH matching_event AS (
					SELECT microtimestamp AS buy_microtimestamp, order_id AS buy_order_id, event_no AS buy_event_no,  buy_match_rule
					FROM (
						SELECT ABS(EXTRACT(epoch FROM e.microtimestamp - COALESCE(t.sell_microtimestamp, t.trade_timestamp))) AS distance, 
								MIN(ABS(EXTRACT(epoch FROM e.microtimestamp - COALESCE(t.sell_microtimestamp, t.trade_timestamp)))) OVER (PARTITION BY t.trade_id) AS min_distance,
								e.microtimestamp,
								e.order_id,
								e.event_no,
								bitstamp._get_match_rule(t.amount, t.price, e.amount,e.fill, e.event, t.price * p_tolerance_percentage) AS buy_match_rule
						FROM bitstamp.live_orders e 
						WHERE e.microtimestamp BETWEEN COALESCE(t.sell_microtimestamp, t.trade_timestamp) - p_look_around AND COALESCE(t.sell_microtimestamp, t.trade_timestamp) + p_look_around
						  AND pair_id = v_pair_id
						  AND order_id = t.buy_order_id
						  AND order_type = 'buy'
						  AND e.trade_id IS NULL
						  AND bitstamp._get_match_rule(t.amount, t.price, e.amount,e.fill, e.event, t.price * p_tolerance_percentage) IS NOT NULL
					) a
					WHERE distance = min_distance
				)
				UPDATE bitstamp.live_trades
				SET buy_microtimestamp = matching_event.buy_microtimestamp,
					buy_event_no = matching_event.buy_event_no,
					buy_match_rule = matching_event.buy_match_rule
				FROM matching_event
				WHERE CURRENT OF trades
				RETURNING live_trades.*;
			--RAISE DEBUG 'find_and_repair_partially_matched() BUY exec: % for %', clock_timestamp() - v_statement_execution_start_time, t;
		END IF;
		IF t.sell_microtimestamp IS NULL THEN 										
			v_statement_execution_start_time := clock_timestamp();
			RETURN QUERY
				WITH matching_event AS (
					SELECT microtimestamp AS sell_microtimestamp, order_id AS sell_order_id, event_no AS sell_event_no, sell_match_rule
					FROM (
						SELECT ABS(EXTRACT(epoch FROM e.microtimestamp - COALESCE(t.buy_microtimestamp, t.trade_timestamp))) AS distance, 
								MIN(ABS(EXTRACT(epoch FROM e.microtimestamp - COALESCE(t.buy_microtimestamp, t.trade_timestamp)))) OVER (PARTITION BY t.trade_id) AS min_distance,
								e.microtimestamp,
								e.event_no,
								e.order_id,
								bitstamp._get_match_rule(t.amount, t.price, e.amount,e.fill, e.event, t.price * p_tolerance_percentage) AS sell_match_rule
						FROM bitstamp.live_orders e 
						WHERE e.microtimestamp BETWEEN COALESCE(t.buy_microtimestamp, t.trade_timestamp) - p_look_around AND COALESCE(t.buy_microtimestamp, t.trade_timestamp) + p_look_around
						  AND pair_id = v_pair_id
						  AND order_id = t.sell_order_id																					   
						  AND order_type = 'sell'
						  AND e.trade_id IS NULL
						  AND bitstamp._get_match_rule(t.amount, t.price, e.amount,e.fill, e.event, t.price * p_tolerance_percentage) IS NOT NULL
					) a
					WHERE distance = min_distance
				)
				UPDATE bitstamp.live_trades
				SET sell_microtimestamp = matching_event.sell_microtimestamp,
					sell_event_no = matching_event.sell_event_no,
					sell_match_rule = matching_event.sell_match_rule
				FROM matching_event
				WHERE CURRENT OF trades
				RETURNING live_trades.*;		
			--RAISE DEBUG 'find_and_repair_partially_matched() SELL exec: % for %', clock_timestamp() - v_statement_execution_start_time, t;										
		END IF;
	END LOOP;
	RAISE DEBUG 'find_and_repair_partially_matched() TOTAL exec time: %', clock_timestamp() - v_execution_start_time;										
END;

$$;


ALTER FUNCTION bitstamp.find_and_repair_partially_matched(p_ts_within_era timestamp with time zone, p_pair text, p_tolerance_percentage numeric, p_look_around interval) OWNER TO "ob-analytics";

--
-- Name: fix_aggressor_creation_order(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.fix_aggressor_creation_order(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE

	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	RETURN QUERY 
		WITH time_range AS (
						SELECT *
						FROM (
							SELECT era AS start_time, COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS end_time,
									pair_id
							FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
							WHERE pairs.pair = p_pair
						) r
						WHERE p_ts_within_era BETWEEN r.start_time AND r.end_time
						),
						trades_with_price_microtimestamp AS (
							SELECT sell_microtimestamp AS r_microtimestamp, sell_order_id AS r_order_id, sell_event_no AS r_event_no,
									price_microtimestamp, price_event_no, buy_microtimestamp AS a_microtimestamp, buy_order_id AS a_order_id, buy_event_no AS a_event_no,
									trade_type
							FROM bitstamp.live_trades JOIN time_range USING (pair_id) 
									JOIN bitstamp.live_buy_orders ON buy_microtimestamp = microtimestamp AND buy_order_id = order_id AND buy_event_no = event_no 
							WHERE trade_timestamp BETWEEN start_time AND end_time
							  AND trade_type = 'buy'
							UNION ALL
							SELECT buy_microtimestamp AS r_microtimestamp, buy_order_id AS r_order_id, buy_event_no AS r_event_no,
									price_microtimestamp, price_event_no, sell_microtimestamp AS a_microtimestamp, sell_order_id AS a_order_id, sell_event_no AS a_event_no,
									trade_type
							FROM bitstamp.live_trades JOIN time_range USING (pair_id) 
									JOIN bitstamp.live_sell_orders ON sell_microtimestamp = microtimestamp AND sell_order_id = order_id AND sell_event_no = event_no 
							WHERE trade_timestamp BETWEEN start_time AND end_time
							  AND trade_type = 'sell'						
						),
						new_created_microtimestamps AS (
							SELECT l.a_order_id, l.price_microtimestamp, l.price_event_no, MIN(r.price_microtimestamp) AS new_microtimestamp
							FROM trades_with_price_microtimestamp l JOIN trades_with_price_microtimestamp r USING (r_order_id)
							WHERE l.price_microtimestamp > r.price_microtimestamp 
							  AND l.r_microtimestamp < r.r_microtimestamp 
							GROUP BY l.a_order_id, l.price_microtimestamp, l.price_event_no
						)
					UPDATE bitstamp.live_orders					
					SET microtimestamp = new_microtimestamp
					FROM new_created_microtimestamps
					WHERE microtimestamp = new_created_microtimestamps.price_microtimestamp
					  AND order_id = new_created_microtimestamps.a_order_id
					  AND event_no = new_created_microtimestamps.price_event_no
					RETURNING live_orders.* ;
	RAISE DEBUG 'fix_aggressor_creation_order() exec time: %', clock_timestamp() - v_execution_start_time;
	RETURN;
END;	

$$;


ALTER FUNCTION bitstamp.fix_aggressor_creation_order(p_ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: inferred_trades(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.inferred_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_missing boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.live_trades
    LANGUAGE plpgsql STABLE
    AS $$

DECLARE
	
	e bitstamp.live_orders;
	is_e_agressor boolean;
	
	max_interval CONSTANT numeric := 2.0;	-- must be less or equal to the threshould in interval_between_events_must_be_small check constraint on bitstamp.live_trades
	
	trade_parts		bitstamp.live_orders[];
	trade_part		bitstamp.live_orders;
	
	tolerance numeric;
	
	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	IF NOT p_strict THEN -- get the trade parts outstanding at p_start_time
		trade_parts := ARRAY(SELECT ROW(live_orders.*) 
							  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
							  WHERE microtimestamp >= ( SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= p_start_time ) 
		  						AND microtimestamp < p_start_time 
		  						AND next_microtimestamp >= p_start_time
		  						AND pairs.pair = p_pair
							 	AND trade_id IS NULL 
		  						AND ( ( live_orders.fill > 0.0 ) OR (live_orders.event <> 'order_created' AND live_orders.fill IS NULL ) )
							);
	ELSE
		trade_parts := '{}';
	END IF;
	
	IF NOT p_only_missing  THEN
		RETURN QUERY SELECT bitstamp_trade_id,
							  amount,
							  price, 
							  trade_type,
							  GREATEST(buy_microtimestamp, sell_microtimestamp),
							  buy_order_id,
							  sell_order_id,
							  local_timestamp,
							  pair_id,
							  sell_microtimestamp,
							  buy_microtimestamp,
							  buy_match_rule,
							  sell_match_rule,
							  buy_event_no,
							  sell_event_no,
							  trade_id,
							  orig_trade_type
					  FROM bitstamp.live_trades JOIN bitstamp.pairs USING (pair_id)
					  WHERE pairs.pair = p_pair
					    AND GREATEST(buy_microtimestamp, sell_microtimestamp) BETWEEN inferred_trades.p_start_time AND inferred_trades.p_end_time ;
	END IF;
	
	trade_part := NULL;
									   
	SELECT 0.1::numeric^"R0" INTO tolerance 
 	FROM bitstamp.pairs 
	WHERE pairs.pair = p_pair;
	
											 
	FOR e IN SELECT live_orders.*
			  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
			  WHERE microtimestamp BETWEEN p_start_time AND p_end_time 
			    AND pairs.pair = p_pair
				AND trade_id IS NULL
			  ORDER BY microtimestamp
				LOOP
									  
		IF ( e.fill > 0.0 ) OR (e.event <> 'order_created' AND e.fill IS NULL) THEN -- it's part of the trade to be inferred
			-- check whether the first part of the trade has been seen already 
			
			IF e.order_type = 'buy' THEN 
				SELECT * INTO trade_part
				FROM unnest(trade_parts) AS a
				WHERE a.order_type  = 'sell'::bitstamp.direction
				  AND abs( (a.fill - e.fill)*CASE WHEN e.datetime < a.datetime THEN e.price ELSE a.price END) <= tolerance
				  AND extract(epoch from e.microtimestamp) - extract(epoch from a.microtimestamp) < max_interval
				ORDER BY price, microtimestamp
				LIMIT 1;
			ELSE
				SELECT * INTO trade_part
				FROM unnest(trade_parts) AS a
				WHERE a.order_type  = 'buy'::bitstamp.direction
				  AND abs( (a.fill - e.fill)*CASE WHEN e.datetime < a.datetime THEN e.price ELSE a.price END) <= tolerance
				  AND extract(epoch from e.microtimestamp) - extract(epoch from a.microtimestamp) < max_interval				  
				ORDER BY price DESC, microtimestamp	
				LIMIT 1;
			END IF;			

									  
			IF FOUND THEN -- the first par has been seen 
			
				trade_parts := ARRAY( SELECT ROW(a.*)
									   FROM unnest(trade_parts) AS a 
									   WHERE NOT (a.microtimestamp = trade_part.microtimestamp 
												  AND a.order_id = trade_part.order_id 
												  AND a.event_no = trade_part.event_no)
									 );
									   
				is_e_agressor := NOT ( e.datetime < trade_part.datetime OR (e.datetime = trade_part.datetime AND e.order_id < trade_part.order_id ) );

				RETURN NEXT ( NULL::bigint,	-- bitstamp_trade_id is always NULL here
							   COALESCE(e.fill, trade_part.fill), 
								-- maker's price defines trade price
							   CASE WHEN NOT is_e_agressor THEN e.price ELSE trade_part.price END, 
								-- trade type below is defined by maker's type, i.e. who was sitting in the order book 
							   CASE WHEN is_e_agressor THEN e.order_type  ELSE trade_part.order_type END, 
								-- trade_timestamp below is defined by a maker departure time from the order book, so its price line 
								-- on plotPriceLevels chart ends by the trade
							   CASE WHEN NOT is_e_agressor THEN e.microtimestamp ELSE trade_part.microtimestamp END,
							   CASE e.order_type WHEN 'buy' THEN e.order_id ELSE trade_part.order_id END, 
							   CASE e.order_type WHEN 'sell' THEN e.order_id ELSE trade_part.order_id END, 
							   e.local_timestamp, e.pair_id, 
							   CASE e.order_type WHEN 'sell' THEN e.microtimestamp ELSE trade_part.microtimestamp END, 								 
							   CASE e.order_type WHEN 'buy' THEN e.microtimestamp ELSE trade_part.microtimestamp END,
							   NULL::smallint,
							   NULL::smallint,
							   CASE e.order_type WHEN 'buy' THEN e.event_no ELSE trade_part.event_no END, 
							   CASE e.order_type WHEN 'sell' THEN e.event_no ELSE trade_part.event_no END,
							   NULL::bigint,
							   NULL::bitstamp.direction); 	-- trade_id is always NULL here
			ELSE -- the first par has NOT been seen, so e is the first part - save it!

				trade_parts := array_append(trade_parts, e);

			END IF;
		END IF;
	END LOOP;
	
	RAISE DEBUG 'Number of not matched trade parts: %  ', array_length(trade_parts,1);
	DECLARE
		i integer DEFAULT 0;
	BEGIN
		FOREACH trade_part IN ARRAY trade_parts LOOP
			IF trade_part.fill IS NOT NULL THEN 
				RAISE DEBUG 'Not matched and fill IS NOT NULL: %, %, %, %, %, %', trade_part.microtimestamp, trade_part.order_id, trade_part.event, trade_part.fill, trade_part.price, trade_part.amount;
			ELSE
				i := i + 1;
			END IF;
		END LOOP;
		RAISE DEBUG 'Number of not matched where fill IS NULL: %', i;
	END;
	RAISE DEBUG 'inferred_trades() exec time: %', clock_timestamp() - v_execution_start_time;	
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.inferred_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_missing boolean, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: live_orders_eras_v(text, integer); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_eras_v(p_pair text DEFAULT 'BTCUSD'::text, p_limit integer DEFAULT 5) RETURNS TABLE(era timestamp with time zone, pair text, last_event timestamp with time zone, events bigint, e_per_sec numeric, matched_events bigint, unmatched_events bigint, trades bigint, fully_matched_trades bigint, partially_matched_trades bigint, not_matched_trades bigint, bitstamp_trades bigint)
    LANGUAGE sql STABLE
    AS $$

WITH eras AS (
		SELECT era, pair, COALESCE(lead(era) OVER (ORDER BY era), 'infinity'::timestamptz) AS next_era
		FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
	    WHERE pairs.pair = p_pair
		ORDER BY era DESC
		LIMIT p_limit
),
eras_orders_trades AS (
SELECT era, pair, last_event, events, matched_events, unmatched_events, trades, fully_matched_trades, partially_matched_trades, not_matched_trades, first_event, bitstamp_trades

FROM eras JOIN LATERAL (  SELECT count(*) AS events, max(microtimestamp) AS last_event, min(microtimestamp) AS first_event,
							count(*) FILTER (WHERE trade_id IS NULL AND fill > 0 ) AS unmatched_events,
							count(*) FILTER (WHERE trade_id IS NOT NULL ) AS matched_events
							FROM bitstamp.live_orders 
			  				WHERE microtimestamp >= eras.era AND microtimestamp < eras.next_era
			 			 ) e ON TRUE
		   JOIN LATERAL (SELECT count(*) AS trades, 
						  count(*) FILTER (WHERE buy_microtimestamp IS NOT NULL AND sell_microtimestamp IS NOT NULL) AS fully_matched_trades,
						  count(*) FILTER (WHERE ( buy_microtimestamp IS NOT NULL AND sell_microtimestamp IS NULL) OR ( buy_microtimestamp IS NULL AND sell_microtimestamp IS NOT NULL)) AS partially_matched_trades,
						  count(*) FILTER (WHERE buy_microtimestamp IS NULL AND sell_microtimestamp IS NULL) AS not_matched_trades,
						  count(*) FILTER (WHERE bitstamp_trade_id IS NOT NULL) AS bitstamp_trades
			  FROM bitstamp.live_trades
			  WHERE trade_timestamp >= eras.era AND trade_timestamp < eras.next_era
			 ) t ON TRUE
)
SELECT era, pair, last_event, events, 
						 CASE WHEN EXTRACT( EPOCH FROM last_event - first_event ) > 0 THEN round((events/EXTRACT( EPOCH FROM last_event - first_event ))::numeric,2) ELSE 0 END AS e_per_sec,
						  matched_events, unmatched_events,trades,  fully_matched_trades, partially_matched_trades, not_matched_trades, bitstamp_trades
FROM eras_orders_trades
ORDER BY era DESC;

$$;


ALTER FUNCTION bitstamp.live_orders_eras_v(p_pair text, p_limit integer) OWNER TO "ob-analytics";

--
-- Name: live_orders_incorporate_new_event(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_incorporate_new_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	v_eon timestamptz;
	v_amount numeric;
	
	prev_event bitstamp.live_orders;
	
BEGIN 

	v_eon := bitstamp._get_live_orders_eon(NEW.microtimestamp);
	
	-- 'eon' is a period of time covered by a single live_orders partition
	-- 'era' is a period that started when a Websocket connection to Bitstamp had been successfully established 
	
	-- Events in the era can't cross an eon boundary. An event will be assigned to the new era starting when the most recent eon eon starts
	-- if the eon bondary has been crossed.
	
	IF v_eon > NEW.era THEN 
		NEW.era := v_eon;	
	END IF;
	
	-- I. First, look behind. NEW.fill IS NULL when the inserter has not done it itself!
	
	IF NEW.fill IS NULL THEN 

		IF NEW.event = 'order_created' THEN
			NEW.fill := -NEW.amount;
			NEW.price_microtimestamp := NEW.microtimestamp;
			NEW.price_event_no := 1;
			NEW.event_no := 1;
		ELSE
			UPDATE bitstamp.live_orders
			   SET next_microtimestamp = NEW.microtimestamp,
				   next_event_no = event_no + 1
			WHERE microtimestamp BETWEEN NEW.era AND NEW.microtimestamp
			  AND order_id = NEW.order_id 
			  AND next_microtimestamp > NEW.microtimestamp
			  AND era = NEW.era
			RETURNING *
			INTO prev_event;
			-- amount, next_event_no INTO v_amount, NEW.event_no;
			
			IF FOUND THEN 
				NEW.fill := prev_event.amount - NEW.amount; 
				NEW.event_no := prev_event.next_event_no;
				
				IF prev_event.price = NEW.price THEN 
					NEW.price_microtimestamp := prev_event.price_microtimestamp;
					NEW.price_event_no := prev_event.price_event_no;
				ELSE	-- currently, it's an instant-type order (Bitstamp changes its price on its own)
					NEW.price_microtimestamp := NEW.microtimestamp;
					NEW.price_event_no := NEW.event_no;
				END IF;
				
			ELSE -- it is ex-nihilo 'order_changed' or 'order_deleted' event

				IF NEW.amount > 0 THEN 

					NEW.fill := NULL;	-- we still don't know fill (yet). Can later try to figure it out from trade
					-- INSERT the initial 'order_created' event when missing
					NEW.price_microtimestamp := CASE WHEN NEW.datetime < NEW.era THEN NEW.era ELSE NEW.datetime END;
					NEW.price_event_no := 1;
					NEW.event_no := 2;
					
					INSERT INTO bitstamp.live_orders (order_id, amount, event, event_no, order_type, datetime, microtimestamp, 
													  pair_id, price, fill, next_microtimestamp, next_event_no,era,
													  price_microtimestamp, price_event_no )
					VALUES (NEW.order_id, NEW.amount, 'order_created'::bitstamp.live_orders_event, NEW.price_event_no, NEW.order_type,
							NEW.datetime, NEW.price_microtimestamp, 
							NEW.pair_id, NEW.price, -NEW.amount, NEW.microtimestamp, NEW.event_no, NEW.era, NEW.price_microtimestamp, 
						   NEW.price_event_no);

				ELSE --	will not create 'order_created' for ex-nihilo, this order will be the first one
					NEW.event_no := 1;
					NEW.price_microtimestamp := NEW.datetime;
					NEW.price_event_no := NULL;	-- this is allowed only for ex-nihilo orders
				END IF;
			
			END IF;
		END IF;
		
	END IF;
	
	IF NEW.next_microtimestamp IS NULL THEN 
		IF NEW.event <> 'order_deleted' THEN 
			NEW.next_microtimestamp := 'infinity'::timestamptz;		
		ELSE
			NEW.next_microtimestamp := '-infinity'::timestamptz;		
		END IF;
	END IF;

	--RAISE DEBUG '%', NEW;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitstamp.live_orders_incorporate_new_event() OWNER TO "ob-analytics";

--
-- Name: live_orders_manage_orig_microtimestamp(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_manage_orig_microtimestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	CASE TG_OP
		WHEN 'INSERT' THEN 
			IF NEW.orig_microtimestamp <> NEW.microtimestamp THEN 	-- orig_microtimestamp can be either NULL or equal to NEW.microtimestamp
				RAISE EXCEPTION 'Attempt to set orig_microtimestamp to % while microtimestamp is %', NEW.orig_microtimestamp, NEW.microtimestamp;
			END IF;
		WHEN 'UPDATE' THEN 
			IF OLD.orig_microtimestamp IS NULL THEN
				IF OLD.microtimestamp <> NEW.microtimestamp THEN
					NEW.orig_microtimestamp := OLD.microtimestamp;
				END IF;
			ELSE
				IF NEW.orig_microtimestamp IS DISTINCT FROM OLD.orig_microtimestamp THEN 
					RAISE EXCEPTION 'Attempt to change orig_microtimestamp from % to %', OLD.orig_microtimestamp, NEW.orig_microtimestamp;
				END IF;
			END IF;
	END CASE;
	RETURN NEW;
END;
	

$$;


ALTER FUNCTION bitstamp.live_orders_manage_orig_microtimestamp() OWNER TO "ob-analytics";

--
-- Name: live_orders_redirect_insert(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_redirect_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN 

	IF NEW.order_type = 'buy' THEN
		INSERT INTO bitstamp.live_buy_orders VALUES (NEW.*);
	ELSE 	
		INSERT INTO bitstamp.live_sell_orders VALUES (NEW.*);
	END IF;
	RETURN NULL;
END;

$$;


ALTER FUNCTION bitstamp.live_orders_redirect_insert() OWNER TO "ob-analytics";

--
-- Name: live_trades_manage_linked_events(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_trades_manage_linked_events() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN 
	CASE TG_OP
		WHEN 'INSERT' THEN
			IF NEW.buy_microtimestamp IS NOT NULL THEN
			
				UPDATE bitstamp.live_buy_orders 
				SET trade_id = NEW.trade_id
				WHERE order_id = NEW.buy_order_id 
				  AND microtimestamp = NEW.buy_microtimestamp 
				  AND event_no = NEW.buy_event_no;
				  
				IF NOT FOUND THEN
					RAISE EXCEPTION 'Could not update linked buy event for %', NEW;
				END IF;
				
			END IF;
			
			IF NEW.sell_microtimestamp IS NOT NULL THEN
			
				UPDATE bitstamp.live_sell_orders 
				SET trade_id = NEW.trade_id
				WHERE order_id = NEW.sell_order_id 
				  AND microtimestamp = NEW.sell_microtimestamp 
				  AND event_no = NEW.sell_event_no;
				  
				IF NOT FOUND THEN
					RAISE EXCEPTION 'Could not update linked sell event for %', NEW;
				END IF;				  
				  
			END IF;
		
		WHEN 'UPDATE' THEN	
			-- It is assumed that (i) 'buy_order_id' and 'sell_order_id' are never changed for they assigned by Bitstamp
			-- and (ii) this code is called only when either (buy|sell)_microtimestamp or(buy|sell)_event_no or both are changed
			
			IF OLD.buy_microtimestamp IS DISTINCT FROM NEW.buy_microtimestamp OR OLD.buy_event_no IS DISTINCT FROM NEW.buy_event_no THEN  
			
				IF OLD.buy_microtimestamp IS NOT NULL THEN

					UPDATE bitstamp.live_buy_orders 
					SET	trade_id = NULL
					WHERE order_id = OLD.buy_order_id 
					  AND microtimestamp = OLD.buy_microtimestamp
					  AND event_no = OLD.buy_event_no;

				END IF;
			
				IF NEW.buy_microtimestamp IS NOT NULL THEN
				
					UPDATE bitstamp.live_buy_orders 
					SET trade_id = NEW.trade_id
					WHERE order_id = NEW.buy_order_id 
					  AND microtimestamp = NEW.buy_microtimestamp
					  AND event_no = NEW.buy_event_no;
					  
					IF NOT FOUND THEN
						RAISE EXCEPTION 'Could not update linked buy event for %', NEW;
					END IF;					  
					
				END IF;
				
			END IF;
			
			IF OLD.sell_microtimestamp IS DISTINCT FROM NEW.sell_microtimestamp OR OLD.sell_event_no IS DISTINCT FROM NEW.sell_event_no THEN

				IF OLD.sell_microtimestamp IS NOT NULL THEN
					UPDATE bitstamp.live_sell_orders 
					SET	trade_id = NULL
					WHERE order_id = OLD.sell_order_id 
					  AND microtimestamp = OLD.sell_microtimestamp
					  AND event_no = OLD.sell_event_no;
				END IF;
				
				IF NEW.sell_microtimestamp IS NOT NULL THEN
				
					UPDATE bitstamp.live_sell_orders 
					SET trade_id = NEW.trade_id
					WHERE order_id = NEW.sell_order_id 
					  AND microtimestamp = NEW.sell_microtimestamp 
					  AND event_no = NEW.sell_event_no;
					  
					IF NOT FOUND THEN
						RAISE EXCEPTION 'Could not update linked sell event for %', NEW;
					END IF;					  
					
				END IF;
				
			END IF;
		ELSE
			RAISE EXCEPTION 'Can not process TG_OP %', TG_OP;
	END CASE;
    RETURN NULL;
END;

$$;


ALTER FUNCTION bitstamp.live_trades_manage_linked_events() OWNER TO "ob-analytics";

--
-- Name: live_trades_manage_trade_type(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_trades_manage_trade_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 

BEGIN

	IF NEW.buy_microtimestamp IS NOT NULL AND NEW.sell_microtimestamp IS NOT NULL THEN 
		IF ( SELECT price_microtimestamp FROM bitstamp.live_orders WHERE microtimestamp = NEW.buy_microtimestamp AND order_id = NEW.buy_order_id AND event_no = NEW.buy_event_no ) >
		   ( SELECT price_microtimestamp FROM bitstamp.live_orders WHERE microtimestamp = NEW.sell_microtimestamp AND order_id = NEW.sell_order_id AND event_no = NEW.sell_event_no )
		   THEN 
			IF NEW.trade_type <> 'buy' THEN 
				IF NEW.orig_trade_type IS NULL THEN -- we save orig_trade_type only once per trade. It is supposed to be genetrated by Bitstamp
					NEW.orig_trade_type := NEW.trade_type;
				END IF;
				NEW.trade_type := 'buy';
			END IF;
		ELSE
			IF NEW.trade_type <> 'sell' THEN 
				IF NEW.orig_trade_type IS NULL THEN 
					NEW.orig_trade_type := NEW.trade_type;
				END IF;
				NEW.trade_type := 'sell';
		   END IF;
		END IF;
	END IF;
	
	IF TG_OP = 'UPDATE' THEN 
		IF OLD.orig_trade_type IS NULL THEN
			IF OLD.trade_type <> NEW.trade_type THEN
				NEW.orig_trade_type := OLD.trade_type;	-- we save orig_trade_type only once per trade. It is supposed to be genetrated by Bitstamp
			END IF;
		ELSE
			IF NEW.orig_trade_type IS DISTINCT FROM OLD.orig_trade_type THEN 
				RAISE EXCEPTION 'Attempt to change orig_trade_type for trade % from % to %', OLD.trade_id, OLD.orig_trade_type, NEW.orig_trade_type;
			END IF;
		END IF;
	END IF;
	
	RETURN NEW;
END;
	

$$;


ALTER FUNCTION bitstamp.live_trades_manage_trade_type() OWNER TO "ob-analytics";

--
-- Name: live_trades_validate(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_trades_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN 
	IF OLD.buy_order_id <> NEW.buy_order_id THEN 
		RAISE EXCEPTION 'Attempt to change buy_order_id from % to %', OLD.buy_order_id, NEW.buy_order_id;
	END IF;
	IF OLD.sell_order_id <> NEW.sell_order_id THEN 
		RAISE EXCEPTION 'Attempt to change sell_order_id from % to %', OLD.sell_order_id, NEW.sell_order_id;
	END IF;
				   
	RETURN NEW;
END;
$$;


ALTER FUNCTION bitstamp.live_trades_validate() OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying DEFAULT 'BTCUSD'::character varying, p_strict boolean DEFAULT false) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE
    AS $$

  SELECT episode_microtimestamp AS "timestamp", price, amount AS volume, CASE direction WHEN 'buy' THEN 'bid'::text WHEN 'sell' THEN 'ask'::text END
  FROM bitstamp.depth_by_episode(p_start_time, p_end_time, p_pair, p_strict);
 

$$;


ALTER FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, character varying, boolean, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying DEFAULT 'BTCUSD'::character varying, p_strict boolean DEFAULT false, p_bps_step numeric DEFAULT 25) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level integer)
    LANGUAGE sql STABLE
    AS $$

WITH events AS (
	SELECT MIN(price) FILTER (WHERE direction = 'sell') OVER (PARTITION BY ts) AS best_ask_price, 
			MAX(price) FILTER (WHERE direction = 'buy') OVER (PARTITION BY ts) AS best_bid_price, * 
	FROM 	( SELECT order_book_entry.* 
			   FROM bitstamp.order_book_by_episode(p_start_time,p_end_time, p_pair,p_strict) 
					 JOIN LATERAL unnest(order_book_by_episode) AS order_book_entry ON TRUE
			 ) a
	WHERE is_maker 
),
events_with_bps_levels AS (
	SELECT ts, 
			amount, 
			price,
			direction,
			CASE direction
				WHEN 'sell' THEN ceiling((price-best_ask_price)/best_ask_price/p_bps_step*10000)::integer
				WHEN 'buy' THEN ceiling((best_bid_price - price)/best_bid_price/p_bps_step*10000)::integer 
			END AS bps_level,
			best_ask_price,
			best_bid_price,
			pair_id
	FROM events 
),
events_with_price_adjusted AS (
	SELECT ts,
			amount,
			CASE direction
				WHEN 'sell' THEN round(best_ask_price*(1 + bps_level*p_bps_step/10000), pairs."R0")
				WHEN 'buy' THEN round(best_bid_price*(1 - bps_level*p_bps_step/10000), pairs."R0") 
			END AS price,
			CASE direction
				WHEN 'sell' THEN 'ask'::text
				WHEN 'buy'	THEN 'bid'::text
			END AS side,
			bps_level,
			rank() OVER (PARTITION BY bitstamp._in_milliseconds(ts) ORDER BY ts DESC) AS r
	FROM events_with_bps_levels JOIN bitstamp.pairs USING (pair_id)
)
SELECT ts, 
		price, 
		SUM(amount) AS volume, 
		side, 
		bps_level*p_bps_step::integer
FROM events_with_price_adjusted
WHERE r = 1	-- if rounded to milliseconds ts are not unique, we'll take the LAST one and will drop the first silently
			 -- this is a workaround for the inability of R to handle microseconds in POSIXct 
GROUP BY 1, 2, 4, 5

$$;


ALTER FUNCTION bitstamp.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying, p_strict boolean, p_bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: oba_event(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_event(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS TABLE("event.id" bigint, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, action text, direction text, fill numeric, "matching.event" bigint, type text, "aggressiveness.bps" numeric, trade bigint, event_no smallint, is_aggressor boolean, is_created boolean, is_ever_resting boolean, is_ever_aggressor boolean, is_ever_filled boolean, is_deleted boolean, is_price_ever_changed boolean, best_bid_price numeric, best_ask_price numeric)
    LANGUAGE sql STABLE
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.live_trades JOIN bitstamp.pairs USING (pair_id)
		WHERE trade_timestamp BETWEEN p_start_time AND p_end_time
	      AND pairs.pair = p_pair
	   ),
	  takers AS (
		  SELECT DISTINCT buy_order_id AS order_id
		  FROM trades
		  WHERE trade_type = 'buy'
		  UNION	-- not ALL, unique
		  SELECT DISTINCT sell_order_id AS order_id
		  FROM trades
		  WHERE trade_type = 'sell'				
		),
	  makers AS (
		  SELECT DISTINCT buy_order_id AS order_id
		  FROM trades
		  WHERE trade_type = 'sell'
		  UNION -- not ALL, unique
		  SELECT DISTINCT sell_order_id AS order_id
		  FROM trades
		  WHERE trade_type = 'buy'				
		),
	  spread AS (
		  SELECT *
		  FROM bitstamp.spread_before_episode(p_start_time, p_end_time, p_pair, TRUE, TRUE)
		  ),
	  base_events AS (
		  SELECT microtimestamp,
		  		  live_orders.price,
		  		  live_orders.amount,
		  		  order_type,
		  		  order_id,
		  		  event,
		  		  datetime,
		  		  fill,
		  		  trade_id,
		  		  -- The columns below require 'first-last-agg' from PGXN to be installed
		  		  -- https://pgxn.org/dist/first_last_agg/doc/first_last_agg.html
		  		  last(best_ask_price) OVER (ORDER BY microtimestamp) AS best_ask_price,	
		  		  last(best_bid_price) OVER (ORDER BY microtimestamp) AS best_bid_price,	
		  		  -- COALESCE below on the right handles the case of one-sided order book ...
		  		  CASE 
		  			WHEN event <> 'order_deleted' THEN
					  CASE order_type 
						WHEN 'sell' THEN price <= COALESCE(last(best_bid_price) OVER (ORDER BY microtimestamp), price - 1)
						WHEN 'buy' THEN price >= COALESCE(last(best_ask_price) OVER (ORDER BY microtimestamp) , price + 1 )
		 			  END
		  			ELSE NULL
		  		  END AS is_aggressor,		  
		  		  event_no
		  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id) LEFT JOIN spread USING(microtimestamp) 
		  WHERE microtimestamp BETWEEN oba_event.p_start_time AND oba_event.p_end_time 
		  	AND pairs.pair = p_pair
	  ),
	  events AS (
		SELECT row_number() OVER (ORDER BY order_id, amount DESC, event, microtimestamp ) AS event_id,		-- ORDER BY must be the same as in oba_trade(). Change both!
		  		base_events.*,
		  		MAX(price) OVER o_all <> MIN(price) OVER o_all AS is_price_ever_changed,
				bool_or(NOT is_aggressor) OVER o_all AS is_ever_resting,
		  		bool_or(is_aggressor) OVER o_all AS is_ever_aggressor, 	
		  		bool_or(COALESCE(fill, CASE WHEN event <> 'order_deleted' THEN 1.0 ELSE NULL END ) > 0.0 ) OVER o_all AS is_ever_filled, 	
		  		first_value(event) OVER o_after = 'order_deleted' AS is_deleted,
		  		first_value(event) OVER o_before = 'order_created' AS is_created
		FROM base_events LEFT JOIN makers USING (order_id) LEFT JOIN takers USING (order_id) 
		WINDOW o_all AS (PARTITION BY order_id), 
		  		o_after AS (PARTITION BY order_id ORDER BY microtimestamp DESC, event_no DESC),
		  		o_before AS (PARTITION BY order_id ORDER BY microtimestamp, event_no)
	  ),
	  event_connection AS (
		  SELECT buy_microtimestamp AS microtimestamp, 
		   	      buy_event_no AS event_no,
		  		  buy_order_id AS order_id, 
		  		  events.event_id
		  FROM trades JOIN events ON sell_microtimestamp = microtimestamp AND sell_order_id = order_id AND sell_event_no = event_no
		  UNION ALL
		  SELECT sell_microtimestamp AS microtimestamp, 
		  		  sell_event_no AS event_no,
		  		  sell_order_id AS order_id, 
		  		  events.event_id
		  FROM trades JOIN events ON buy_microtimestamp = microtimestamp AND buy_order_id = order_id AND buy_event_no = event_no
	  )
  SELECT events.event_id AS "event.id",
  		  order_id AS id,
		  microtimestamp AS "timestamp",
		  datetime AS "exchange.timestamp",
		  price, 
		  amount AS volume,
		  CASE event
		  	WHEN 'order_created' THEN 'created'::text
			WHEN 'order_changed' THEN 'changed'::text
			WHEN 'order_deleted' THEN 'deleted'::text
		  END AS action,
		  CASE order_type
		  	WHEN 'buy' THEN 'bid'::text
			WHEN 'sell' THEN 'ask'::text
		  END AS direction,
		  CASE WHEN fill > 0.0 THEN fill
		  		ELSE 0.0
		  END AS fill,
		  event_connection.event_id AS "matching.event",
		  CASE WHEN is_price_ever_changed THEN 'pacman'::text
		  	    WHEN is_ever_resting AND NOT is_ever_aggressor AND NOT is_ever_filled AND is_deleted THEN 'flashed-limit'::text
				WHEN is_ever_resting AND NOT is_ever_aggressor AND NOT is_ever_filled AND NOT is_deleted THEN 'resting-limit'::text
				WHEN is_ever_resting AND NOT is_ever_aggressor AND is_ever_filled THEN 'resting-limit'::text
				WHEN NOT is_ever_resting AND is_ever_aggressor AND is_deleted AND is_ever_filled THEN 'market'::text
				-- when two market orders have been placed simulltaneously, the first might take all liquidity 
				-- so the second will not be executed and no change event will be generated for it so is_ever_resting will be 'False'.
				-- In spite of this it will be resting the order book for some time so its type is 'flashed-limit'.
				WHEN NOT is_ever_resting AND is_ever_aggressor AND is_deleted AND NOT is_ever_filled THEN 'flashed-limit'::text	
				WHEN is_ever_resting AND is_ever_aggressor THEN 'market-limit'::text
		  		ELSE 'unknown'::text 
		  END AS "type",
			CASE order_type 
		  		WHEN 'sell' THEN round((best_ask_price - price)/best_ask_price*10000)
		  		WHEN 'buy' THEN round((price - best_bid_price)/best_ask_price*10000)
		  	END AS "aggressiveness.bps",
		trade_id,
		event_no,
		is_aggressor,
		is_created,
		is_ever_resting,
		is_ever_aggressor,
		is_ever_filled,
		is_deleted,
		is_price_ever_changed,
		best_bid_price,
		best_ask_price
  FROM events LEFT JOIN event_connection USING (microtimestamp, event_no, order_id) 
  ORDER BY 1;

$$;


ALTER FUNCTION bitstamp.oba_event(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--	See bitstamp.spread_by_episode()

	SELECT best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
	FROM bitstamp.spread_after_episode(p_start_time , p_end_time, p_pair, p_only_different, p_strict)

$$;


ALTER FUNCTION bitstamp.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each event in the ''live_orders'' table that hits the interval between p_start_time and p_end_time for the given "pair" and in the format expected by  obAnalytics package. The spread is calculated using all available data before p_start_time unless "p_strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between p_start_time and p_end_time. ';


--
-- Name: oba_trade(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_trade(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT true) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, direction text, "maker.event.id" bigint, "taker.event.id" bigint, maker bigint, taker bigint, "real.trade.id" bigint)
    LANGUAGE sql
    SET work_mem TO '1GB'
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.live_trades JOIN bitstamp.pairs USING (pair_id)
		WHERE trade_timestamp BETWEEN p_start_time AND p_end_time
	      AND pairs.pair = p_pair
	),
	events AS (
		SELECT row_number() OVER (ORDER BY order_id, amount DESC, event,  microtimestamp ) AS event_id,	-- ORDER BY must be the same as in oba_event(). Change both!
				live_orders.*
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp BETWEEN p_start_time AND p_end_time 
	      AND pairs.pair = p_pair
	)
  SELECT CASE trade_type
  			WHEN 'buy' THEN buy_microtimestamp
			WHEN 'sell' THEN sell_microtimestamp
		  END,
  		  trades.price,
		  trades.amount,
		  trades.trade_type::text,
		  CASE trade_type
		  	WHEN 'buy' THEN s.event_id
			WHEN 'sell' THEN b.event_id
		  END,
		  CASE trade_type
		  	WHEN 'buy' THEN b.event_id
			WHEN 'sell' THEN s.event_id
		  END,
		  CASE trade_type
		  	WHEN 'buy' THEN sell_order_id
			WHEN 'sell' THEN buy_order_id
		  END,
		  CASE trade_type
		  	WHEN 'buy' THEN buy_order_id
			WHEN 'sell' THEN sell_order_id
		  END,
		  trades.bitstamp_trade_id 
  FROM trades JOIN events b ON buy_microtimestamp = b.microtimestamp AND buy_order_id = b.order_id AND buy_event_no = b.event_no
  		JOIN events s ON sell_microtimestamp = s.microtimestamp AND sell_order_id = s.order_id  AND sell_event_no = s.event_no
  ORDER BY 1

$$;


ALTER FUNCTION bitstamp.oba_trade(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_after(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_after(p_ts timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_makers boolean DEFAULT true) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	WITH orders AS (
		SELECT *, 
				COALESCE(
					CASE order_type 
						WHEN 'buy' THEN price < min(price) FILTER (WHERE order_type = 'sell') OVER (ORDER BY datetime, microtimestamp)
						WHEN 'sell' THEN price > max(price) FILTER (WHERE order_type = 'buy') OVER (ORDER BY datetime, microtimestamp)
					END,
				TRUE )	-- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
				AS is_maker
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp BETWEEN (SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= p_ts ) AND p_ts
 	   	  AND next_microtimestamp > p_ts 
		  AND event <> 'order_deleted'
		  AND pairs.pair = p_pair
		)
	SELECT p_ts,
			price,
			amount,
			order_type,
			order_id,
			microtimestamp,
			event_no,
			pair_id,
			is_maker,
			datetime
    FROM orders
	WHERE is_maker OR NOT p_only_makers
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_after(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_after_episode(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_after_episode(p_ts timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_makers boolean DEFAULT true) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	WITH orders AS (
		SELECT *, 
				COALESCE(
					CASE order_type 
						WHEN 'buy' THEN price < min(price) FILTER (WHERE order_type = 'sell') OVER (ORDER BY datetime, microtimestamp)
						WHEN 'sell' THEN price > max(price) FILTER (WHERE order_type = 'buy') OVER (ORDER BY datetime, microtimestamp)
					END,
				TRUE )	-- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
				AS is_maker
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp BETWEEN (SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= p_ts ) AND p_ts
 	   	  AND next_microtimestamp > p_ts 
		  AND event <> 'order_deleted'
		  AND pairs.pair = p_pair
		)
	SELECT p_ts,
			price,
			amount,
			order_type,
			order_id,
			microtimestamp,
			event_no,
			pair_id,
			is_maker,
			datetime
    FROM orders
	WHERE is_maker OR NOT p_only_makers
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_after_episode(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_before(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_before(p_ts timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_makers boolean DEFAULT true) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	WITH orders AS (
		SELECT *, 
				COALESCE(
					CASE order_type 
						WHEN 'buy' THEN price < min(price) FILTER (WHERE order_type = 'sell') OVER (ORDER BY datetime, microtimestamp)
						WHEN 'sell' THEN price > max(price) FILTER (WHERE order_type = 'buy') OVER (ORDER BY datetime, microtimestamp)
					END,
				TRUE )	-- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
				AS is_maker
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp >= (SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= p_ts ) 
 		  AND microtimestamp < p_ts 
 	   	  AND next_microtimestamp >= p_ts 
		  AND event <> 'order_deleted'
		  AND pairs.pair = p_pair
		)
	SELECT p_ts,
			price,
			amount,
			order_type,
			order_id,
			microtimestamp,
			event,
			pair_id,
			is_maker,
			datetime
    FROM orders
	WHERE is_maker OR NOT p_only_makers
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_before(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_by_episode(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.order_book_record[]
    LANGUAGE plpgsql STABLE
    SET work_mem TO '4GB'
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the production of the order book snapshots
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which order books will be calculated
--		p_strict		- whether to calculate the spread using events before p_start_time (false) or not (false). 
-- DETAILS
-- 		An episode is a moment in time when the order book, derived from Bitstamp's data is in consistent state. 
--		The state of the order book is consistent when:
--			(a) all events that happened simultaneously (i.e. having the same microtimestamp) are reflected in the order book
--			(b) both events that constitute a trade are reflected in the order book
-- 		This function processes the order book events sequentially and returns consistent snapshots of the order book between
--		p_start_time and p_end_time.
--		These consistent snapshots are then used to calculate spread, depth and depth.summary. Note that the consitent order book may still be crossed.
--		It is assumed that spread, depth and depth.summary will ignore the unprocessed agressors crossing the book. 
--		

DECLARE
	ob bitstamp.order_book_record[];
	
	v_event bitstamp.live_orders;
	v_next_microtimestamp timestamp with time zone;
	
	v_pair_id smallint;
	
	v_r record;
BEGIN
	IF p_strict THEN 
		ob := '{}';	-- only the events within the [p_start_time, p_end_time] interval will be used
	ELSE
		ob := NULL;
	END IF;
	
	SELECT pair_id INTO v_pair_id
	FROM bitstamp.pairs WHERE pairs.pair = p_pair;

	FOR v_r IN SELECT ROW(live_orders.*) AS e, lead(microtimestamp) OVER (ORDER BY microtimestamp, event_no) AS n
										   FROM bitstamp.live_orders
			  							   WHERE microtimestamp BETWEEN p_start_time AND p_end_time 
			    							 AND pair_id = v_pair_id
			  							   ORDER BY microtimestamp, event_no
	LOOP
		v_event := v_r.e;
		v_next_microtimestamp 	:= v_r.n;
		
		IF ob IS NULL THEN 
			ob := ARRAY(SELECT bitstamp.order_book_after(v_event.microtimestamp, p_pair, FALSE));
		ELSE													 
			ob := bitstamp._order_book_after_event(ob, v_event, p_only_makers := FALSE);
		END IF;
													 
		IF NOT ( v_event.microtimestamp = v_next_microtimestamp ) THEN
			IF ob = '{}' THEN
				RETURN NEXT ARRAY[ ROW(v_event.microtimestamp, NULL, NULL, 'sell'::bitstamp.direction, NULL, NULL, NULL, e.pair_id, TRUE, NULL),
  					      			 ROW(v_event.microtimestamp, NULL, NULL, 'buy'::bitstamp.direction, NULL, NULL, NULL, e.pair_id, TRUE, NULL)
									  ];
			ELSE
				RETURN NEXT ob;
			END IF;
		END IF;
	END LOOP;
END;

$$;


ALTER FUNCTION bitstamp.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: pga_process_transient_live_orders(text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text DEFAULT 'BTCUSD'::text) RETURNS void
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE

	
	v_start_time timestamp with time zone;
	v_end_time timestamp with time zone;
	
	v_era timestamp with time zone;
	
	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	SET CONSTRAINTS ALL DEFERRED;
	
	FOR v_era IN SELECT DISTINCT era FROM bitstamp.transient_live_orders JOIN bitstamp.pairs USING (pair_id) WHERE pairs.pair = p_pair ORDER BY era
		LOOP
	
		SELECT MIN(microtimestamp), MAX(microtimestamp) INTO v_start_time, v_end_time
		FROM bitstamp.transient_live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE pairs.pair = p_pair AND era = v_era;
		PERFORM bitstamp.capture_transient_trades(v_start_time, v_end_time, p_pair);
		PERFORM bitstamp.capture_transient_orders(v_start_time, v_end_time, p_pair);
		PERFORM bitstamp.find_and_repair_missing_fill(v_era);
		PERFORM bitstamp.find_and_repair_eternal_orders(v_era);
		PERFORM bitstamp.find_and_repair_partially_matched(v_era, p_pair,  p_tolerance_percentage := 0.005);

		INSERT INTO bitstamp.live_trades (amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp,
										 pair_id, sell_microtimestamp, buy_microtimestamp, buy_match_rule, sell_match_rule, buy_event_no, sell_event_no)
		SELECT amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp,
										 pair_id, sell_microtimestamp, buy_microtimestamp, buy_match_rule, sell_match_rule, buy_event_no, sell_event_no
		FROM bitstamp.inferred_trades(v_start_time, v_end_time, p_pair, p_only_missing := TRUE, p_strict := FALSE);
		
		PERFORM bitstamp.fix_aggressor_creation_order(v_era, p_pair);
		PERFORM bitstamp.reveal_episodes(v_era, p_pair);

		--INSERT INTO bitstamp.spread
		--SELECT * FROM bitstamp.spread_by_episode(v_start_time, v_end_time, p_pair, TRUE, FALSE );
	
	END LOOP;			
	RAISE DEBUG 'pga_process_transient_live_orders() exec time: %', clock_timestamp() - v_execution_start_time;
END;

$$;


ALTER FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text) OWNER TO "ob-analytics";

--
-- Name: FUNCTION pga_process_transient_live_orders(p_pair text); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text) IS 'This function is expected to be run by pgAgent as often as necessary to store order book events from  transient_live_orders table';


--
-- Name: protect_columns(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.protect_columns() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN 
	RAISE EXCEPTION 'You are trying to change an unchangeable column in % table!', TG_TABLE_NAME;
END;

$$;


ALTER FUNCTION bitstamp.protect_columns() OWNER TO "ob-analytics";

--
-- Name: reveal_episodes(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.reveal_episodes(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE

	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	RETURN QUERY   WITH time_range AS (
						SELECT *
						FROM (
							SELECT era AS start_time, COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS end_time,
									pair_id
							FROM bitstamp.live_orders_eras JOIN bitstamp.pairs USING (pair_id)
							WHERE pairs.pair = p_pair
						) r
						WHERE p_ts_within_era BETWEEN r.start_time AND r.end_time
					),
					trades_with_created AS (
						SELECT sell_microtimestamp AS r_microtimestamp, sell_order_id AS r_order_id, sell_event_no AS r_event_no,
								buy_microtimestamp AS a_microtimestamp, buy_order_id AS a_order_id, buy_event_no AS a_event_no,
								trade_type,
								LEAST(price_microtimestamp, sell_microtimestamp) AS created_microtimestamp	
								-- In general for any event price_microtimestamp <= microtimestamp. Thus we always move aggressor event 
								-- (buy_microtimestamp) back in time
								-- LEAST handles the rare case when the resting event (sell_microtimestamp) is simultaneously the latest 
								-- price-setting event for the given order_id and we would move it forward in time without LEAST, which is wrong.
						FROM bitstamp.live_trades JOIN time_range USING (pair_id) 
								JOIN bitstamp.live_buy_orders ON buy_microtimestamp = microtimestamp AND buy_order_id = order_id AND buy_event_no = event_no 
						WHERE trade_timestamp BETWEEN start_time AND end_time
						  AND trade_type = 'buy'
						UNION ALL
						SELECT buy_microtimestamp AS r_microtimestamp, buy_order_id AS r_order_id, buy_event_no AS r_event_no,
								sell_microtimestamp AS a_microtimestamp, sell_order_id AS a_order_id, sell_event_no AS a_event_no,
								trade_type,
								LEAST(price_microtimestamp, buy_microtimestamp) AS created_microtimestamp 
								-- See comments above regarding LEAST
						FROM bitstamp.live_trades JOIN time_range USING (pair_id) 
								JOIN bitstamp.live_sell_orders ON sell_microtimestamp = microtimestamp AND sell_order_id = order_id AND sell_event_no = event_no 
						WHERE trade_timestamp BETWEEN start_time AND end_time
						  AND trade_type = 'sell'						
					),
					episodes AS (
						SELECT r_microtimestamp AS microtimestamp, r_order_id AS order_id, r_event_no AS event_no, created_microtimestamp AS episode_microtimestamp
						FROM trades_with_created
						UNION ALL
						SELECT a_microtimestamp AS microtimestamp, a_order_id AS order_id, a_event_no AS event_no, created_microtimestamp AS episode_microtimestamp
						FROM trades_with_created
					)
					UPDATE bitstamp.live_orders
					SET microtimestamp = episodes.episode_microtimestamp
					FROM episodes
					WHERE live_orders.microtimestamp = episodes.microtimestamp 
					  AND live_orders.order_id = episodes.order_id 
					  AND live_orders.event_no = episodes.event_no
					  AND live_orders.microtimestamp <> episodes.episode_microtimestamp
					RETURNING live_orders.*;
	RAISE DEBUG 'reveal_episodes() exec time: %', clock_timestamp() - v_execution_start_time;
	RETURN;
END;	

$$;


ALTER FUNCTION bitstamp.reveal_episodes(p_ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: spread_after_episode(timestamp with time zone, timestamp with time zone, text, boolean, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false, p_with_order_book boolean DEFAULT false) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, order_book bitstamp.order_book_record[])
    LANGUAGE plpgsql STABLE
    SET work_mem TO '4GB'
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of spreads
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which spreads will be calculated
--		p_only_different	- whether to output the spread only when it is different from the v_previous one (true) or after each event (false). true is the default.
--		p_strict		- whether to calculate the spread using events before p_start_time (false) or not (false). 
-- DETAILS
--		If p_only_different is FALSE returns spread after each episode
--		If p_only_different is TRUE then will check whether the spread has changed and will skip if it does not.

DECLARE
	v_cur bitstamp.spread;
	v_prev bitstamp.spread;
	v_ob bitstamp.order_book_record[];
BEGIN

	v_prev := ROW(NULL, NULL, NULL, NULL, NULL, NULL);
											 
	FOR v_ob IN SELECT * FROM bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, p_strict)
	LOOP
		v_cur := bitstamp._spread_from_order_book(v_ob);	
		IF  (v_cur.best_bid_price IS DISTINCT FROM  v_prev.best_bid_price OR 
			v_cur.best_bid_qty IS DISTINCT FROM  v_prev.best_bid_qty OR
			v_cur.best_ask_price IS DISTINCT FROM  v_prev.best_ask_price OR
			v_cur.best_ask_qty IS DISTINCT FROM  v_prev.best_ask_qty ) 
			OR NOT p_only_different THEN
			v_prev := v_cur;
			best_bid_price := v_cur.best_bid_price;
		    best_ask_price := v_cur.best_ask_price;
			best_bid_qty := v_cur.best_bid_qty;
			best_ask_qty := v_cur.best_ask_qty;
			microtimestamp := v_cur.episode_microtimestamp;
			pair_id := v_cur.pair_id;
			IF p_with_order_book THEN 
		    	order_book := v_ob;
			END IF;
			RETURN NEXT;
		END IF;
	END LOOP;
	
END;

$$;


ALTER FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each episode in the ''live_orders'' table that hits the interval between p_start_time and p_end_time for the given "pair". The spread is calculated using all available data before p_start_time unless "p_p_strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between p_start_time and p_end_time';


--
-- Name: spread_before_episode(timestamp with time zone, timestamp with time zone, text, boolean, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_before_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false, p_with_order_book boolean DEFAULT false) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, order_book bitstamp.order_book_record[])
    LANGUAGE sql STABLE
    SET work_mem TO '4GB'
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of spreads
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which spreads will be calculated
--		p_only_different	- whether to output the spread only when it is different from the v_previous one (true) or after each event (false). true is the default.
--		p_strict		- whether to calculate the spread using events before p_start_time (false) or not (false). 
-- DETAILS
--		If p_only_different is FALSE returns spread after each episode
--		If p_only_different is TRUE then will check whether the spread has changed and will skip if it does not.

SELECT *
FROM (
	SELECT best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, 
			lead(microtimestamp) OVER (ORDER BY microtimestamp) AS microtimestamp, pair_id, order_book
	FROM bitstamp.spread_after_episode(p_start_time, p_end_time, p_pair,p_only_different, p_strict, p_with_order_book)
) a
WHERE microtimestamp IS NOT NULL;	
				  

$$;


ALTER FUNCTION bitstamp.spread_before_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION spread_before_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.spread_before_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean, p_with_order_book boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") before each episode (i.e. after previous episode) in the ''live_orders'' table that hits the interval between p_start_time and p_end_time for the given "pair". The spread is calculated using all available data before p_start_time unless "p_p_strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between p_start_time and p_end_time';


--
-- Name: diff_order_book; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.diff_order_book (
    "timestamp" timestamp with time zone NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    side bitstamp.side NOT NULL,
    pair_id smallint NOT NULL,
    local_timestamp timestamp with time zone NOT NULL
);


ALTER TABLE bitstamp.diff_order_book OWNER TO "ob-analytics";

--
-- Name: live_buy_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_buy_orders PARTITION OF bitstamp.live_orders
FOR VALUES IN ('buy')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE bitstamp.live_buy_orders OWNER TO "ob-analytics";

--
-- Name: live_orders_eras; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_orders_eras (
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL
);


ALTER TABLE bitstamp.live_orders_eras OWNER TO "ob-analytics";

--
-- Name: live_sell_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_sell_orders PARTITION OF bitstamp.live_orders
FOR VALUES IN ('sell')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE bitstamp.live_sell_orders OWNER TO "ob-analytics";

--
-- Name: live_trades_trade_id_seq; Type: SEQUENCE; Schema: bitstamp; Owner: ob-analytics
--

CREATE SEQUENCE bitstamp.live_trades_trade_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bitstamp.live_trades_trade_id_seq OWNER TO "ob-analytics";

--
-- Name: live_trades_trade_id_seq; Type: SEQUENCE OWNED BY; Schema: bitstamp; Owner: ob-analytics
--

ALTER SEQUENCE bitstamp.live_trades_trade_id_seq OWNED BY bitstamp.live_trades.trade_id;


--
-- Name: pairs; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.pairs (
    pair_id smallint NOT NULL,
    pair character varying NOT NULL,
    "R0" smallint NOT NULL
);


ALTER TABLE bitstamp.pairs OWNER TO "ob-analytics";

--
-- Name: COLUMN pairs."R0"; Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON COLUMN bitstamp.pairs."R0" IS 'A negative order of magnitude of the fractional monetary unit used to represent price in the pair. For example for BTCUSD pair the fractional monetary unit is 1 cent or 0.01 of USD and the value of R0 is 2';


--
-- Name: transient_live_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.transient_live_orders (
    order_id bigint NOT NULL,
    amount numeric NOT NULL,
    event bitstamp.live_orders_event NOT NULL,
    order_type bitstamp.direction NOT NULL,
    datetime timestamp with time zone NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    price numeric NOT NULL,
    era timestamp with time zone NOT NULL
);


ALTER TABLE bitstamp.transient_live_orders OWNER TO "ob-analytics";

--
-- Name: transient_live_trades; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.transient_live_trades (
    bitstamp_trade_id bigint NOT NULL,
    amount numeric NOT NULL,
    price numeric NOT NULL,
    trade_type bitstamp.direction NOT NULL,
    trade_timestamp timestamp with time zone NOT NULL,
    buy_order_id bigint NOT NULL,
    sell_order_id bigint NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL
);


ALTER TABLE bitstamp.transient_live_trades OWNER TO "ob-analytics";

--
-- Name: live_trades trade_id; Type: DEFAULT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades ALTER COLUMN trade_id SET DEFAULT nextval('bitstamp.live_trades_trade_id_seq'::regclass);


--
-- Name: diff_order_book diff_order_book_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.diff_order_book
    ADD CONSTRAINT diff_order_book_pkey PRIMARY KEY ("timestamp", price, side);


--
-- Name: live_buy_orders live_buy_orders_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: live_buy_orders live_buy_orders_unique_next; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_buy_orders live_buy_orders_unique_trade_id; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_unique_trade_id UNIQUE (microtimestamp, order_id, event_no, trade_id);


--
-- Name: live_orders_eras live_orders_eras_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders_eras
    ADD CONSTRAINT live_orders_eras_pkey PRIMARY KEY (era, pair_id);


--
-- Name: live_sell_orders live_sell_orders_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: live_sell_orders live_sell_orders_unique_next; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_sell_orders live_sell_orders_unique_trade_id; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_unique_trade_id UNIQUE (microtimestamp, order_id, event_no, trade_id);


--
-- Name: live_trades live_trades_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_pkey PRIMARY KEY (trade_id);


--
-- Name: live_trades live_trades_uique_sell_event; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_uique_sell_event UNIQUE (sell_microtimestamp, sell_order_id, sell_event_no, trade_id);


--
-- Name: live_trades live_trades_unique_buy_event; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_unique_buy_event UNIQUE (buy_microtimestamp, buy_order_id, buy_event_no, trade_id);


--
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


--
-- Name: pairs pairs_unq; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.pairs
    ADD CONSTRAINT pairs_unq UNIQUE (pair) DEFERRABLE;


--
-- Name: spread spread_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.spread
    ADD CONSTRAINT spread_pkey PRIMARY KEY (pair_id, episode_microtimestamp);


--
-- Name: transient_live_trades transient_live_trades_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.transient_live_trades
    ADD CONSTRAINT transient_live_trades_pkey PRIMARY KEY (bitstamp_trade_id);


--
-- Name: fki_live_sell_orders_fkey_live_sell_orders; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX fki_live_sell_orders_fkey_live_sell_orders ON bitstamp.live_sell_orders USING btree (next_microtimestamp, order_id, next_event_no);


--
-- Name: fki_live_trades_fkey_live_buy_orders; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX fki_live_trades_fkey_live_buy_orders ON bitstamp.live_trades USING btree (buy_microtimestamp, buy_order_id, buy_event_no);


--
-- Name: fki_live_trades_fkey_live_sell_orders; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX fki_live_trades_fkey_live_sell_orders ON bitstamp.live_trades USING btree (sell_microtimestamp, sell_order_id, sell_event_no);


--
-- Name: live_buy_orders_fkey_live_buy_orders_next; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_buy_orders_fkey_live_buy_orders_next ON bitstamp.live_buy_orders USING btree (next_microtimestamp, order_id, next_event_no);


--
-- Name: live_buy_orders_fkey_live_buy_orders_price; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_buy_orders_fkey_live_buy_orders_price ON bitstamp.live_buy_orders USING btree (price_microtimestamp, order_id, price_event_no);


--
-- Name: live_buy_orders_fkey_live_trades_trade_id; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_buy_orders_fkey_live_trades_trade_id ON bitstamp.live_buy_orders USING btree (trade_id);


--
-- Name: live_buy_orders_unique_chain_end; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_buy_orders_unique_chain_end ON bitstamp.live_buy_orders USING btree (order_id, era) WHERE (next_event_no IS NULL);


--
-- Name: live_sell_orders_fkey_live_sell_orders_price; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_sell_orders_fkey_live_sell_orders_price ON bitstamp.live_sell_orders USING btree (price_microtimestamp, order_id, price_event_no);


--
-- Name: live_sell_orders_fkey_live_trades_trade_id; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_sell_orders_fkey_live_trades_trade_id ON bitstamp.live_sell_orders USING btree (trade_id);


--
-- Name: live_sell_orders_unique_chain_end; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_sell_orders_unique_chain_end ON bitstamp.live_sell_orders USING btree (order_id, era) WHERE (next_event_no IS NULL);


--
-- Name: live_trades aa_managed_linked_events; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER aa_managed_linked_events AFTER INSERT OR UPDATE OF sell_microtimestamp, buy_microtimestamp, buy_event_no, sell_event_no ON bitstamp.live_trades FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_trades_manage_linked_events();


--
-- Name: live_trades aa_validate; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE CONSTRAINT TRIGGER aa_validate AFTER UPDATE ON bitstamp.live_trades DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_trades_validate();


--
-- Name: live_sell_orders ba_incorporate_new_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON bitstamp.live_sell_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_incorporate_new_event();


--
-- Name: live_buy_orders ba_incorporate_new_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON bitstamp.live_buy_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_incorporate_new_event();


--
-- Name: live_buy_orders bz_manage_orig_microtimestamp; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER bz_manage_orig_microtimestamp BEFORE INSERT OR UPDATE OF microtimestamp, orig_microtimestamp ON bitstamp.live_buy_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_manage_orig_microtimestamp();


--
-- Name: live_sell_orders bz_manage_orig_microtimestamp; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER bz_manage_orig_microtimestamp BEFORE INSERT OR UPDATE OF microtimestamp, orig_microtimestamp ON bitstamp.live_sell_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_manage_orig_microtimestamp();


--
-- Name: live_trades bz_manage_trade_type; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER bz_manage_trade_type BEFORE INSERT OR UPDATE OF trade_type, buy_microtimestamp, sell_microtimestamp ON bitstamp.live_trades FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_trades_manage_trade_type();


--
-- Name: live_buy_orders live_buy_orders_fkey_era; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_era FOREIGN KEY (era, pair_id) REFERENCES bitstamp.live_orders_eras(era, pair_id) ON UPDATE CASCADE;


--
-- Name: live_buy_orders live_buy_orders_fkey_live_buy_orders_next; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_live_buy_orders_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES bitstamp.live_buy_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_buy_orders live_buy_orders_fkey_live_buy_orders_price; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_live_buy_orders_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES bitstamp.live_buy_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_buy_orders live_buy_orders_fkey_live_trades; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_live_trades FOREIGN KEY (trade_id) REFERENCES bitstamp.live_trades(trade_id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_buy_orders live_buy_orders_fkey_live_trades_match; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_live_trades_match FOREIGN KEY (microtimestamp, order_id, event_no, trade_id) REFERENCES bitstamp.live_trades(buy_microtimestamp, buy_order_id, buy_event_no, trade_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_buy_orders live_buy_orders_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_buy_orders
    ADD CONSTRAINT live_buy_orders_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE;


--
-- Name: live_orders_eras live_orders_eras_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders_eras
    ADD CONSTRAINT live_orders_eras_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE;


--
-- Name: live_sell_orders live_sell_orders_fkey_era; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_era FOREIGN KEY (era, pair_id) REFERENCES bitstamp.live_orders_eras(era, pair_id) MATCH FULL ON UPDATE CASCADE;


--
-- Name: live_sell_orders live_sell_orders_fkey_live_sell_orders_next; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_live_sell_orders_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES bitstamp.live_sell_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_sell_orders live_sell_orders_fkey_live_sell_orders_price; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_live_sell_orders_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES bitstamp.live_sell_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_sell_orders live_sell_orders_fkey_live_trades; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_live_trades FOREIGN KEY (trade_id) REFERENCES bitstamp.live_trades(trade_id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_sell_orders live_sell_orders_fkey_live_trades_match; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_live_trades_match FOREIGN KEY (microtimestamp, order_id, event_no, trade_id) REFERENCES bitstamp.live_trades(sell_microtimestamp, sell_order_id, sell_event_no, trade_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_sell_orders live_sell_orders_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_sell_orders
    ADD CONSTRAINT live_sell_orders_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE;


--
-- Name: live_trades live_trades_fkey_live_buy_orders; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_live_buy_orders FOREIGN KEY (buy_microtimestamp, buy_order_id, buy_event_no) REFERENCES bitstamp.live_buy_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_trades live_trades_fkey_live_buy_orders_trade_id; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_live_buy_orders_trade_id FOREIGN KEY (buy_microtimestamp, buy_order_id, buy_event_no, trade_id) REFERENCES bitstamp.live_buy_orders(microtimestamp, order_id, event_no, trade_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_trades live_trades_fkey_live_sell_orders; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_live_sell_orders FOREIGN KEY (sell_microtimestamp, sell_order_id, sell_event_no) REFERENCES bitstamp.live_sell_orders(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_trades live_trades_fkey_live_sell_orders_trade_id; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_live_sell_orders_trade_id FOREIGN KEY (sell_microtimestamp, sell_order_id, sell_event_no, trade_id) REFERENCES bitstamp.live_sell_orders(microtimestamp, order_id, event_no, trade_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: live_trades live_trades_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) MATCH FULL ON UPDATE CASCADE;


--
-- PostgreSQL database dump complete
--

