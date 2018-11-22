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
    'order_created',
    'order_changed',
    'order_deleted'
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
	event_type bitstamp.live_orders_event,
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

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: live_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_orders (
    order_id bigint NOT NULL,
    amount numeric NOT NULL,
    event bitstamp.live_orders_event NOT NULL,
    order_type bitstamp.direction NOT NULL,
    datetime timestamp with time zone NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    local_timestamp timestamp with time zone,
    pair_id smallint NOT NULL,
    price numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone,
    era timestamp with time zone NOT NULL,
    trade_timestamp timestamp with time zone,
    trade_id bigint,
    matched_microtimestamp timestamp with time zone,
    matched_order_id bigint,
    episode_microtimestamp timestamp with time zone,
    episode_order_id bigint
);


ALTER TABLE bitstamp.live_orders OWNER TO "ob-analytics";

--
-- Name: _events_match_trade(timestamp with time zone, bigint, numeric, numeric, bitstamp.direction, interval); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._events_match_trade(trade_timestamp timestamp with time zone, order_id bigint, amount numeric, price numeric, order_type bitstamp.direction, look_around interval DEFAULT '00:00:02'::interval) RETURNS SETOF bitstamp.live_orders
    LANGUAGE sql STABLE
    AS $$

SELECT live_orders.* 
FROM bitstamp.live_orders 
WHERE microtimestamp BETWEEN _events_match_trade.trade_timestamp - _events_match_trade.look_around  AND _events_match_trade.trade_timestamp + _events_match_trade.look_around
  AND order_id = _events_match_trade.order_id
  AND bitstamp._get_match_rule(	trade_amount := _events_match_trade.amount,
							   	trade_price := _events_match_trade.price,
							   	event_amount := amount,
							   	event_fill := fill,
							   	event := event,
							   	tolerance := 0.1::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_orders.pair_id )
							  ) IS NOT NULL
  AND trade_id IS NULL
  AND order_type = _events_match_trade.order_type
  AND event <> 'order_created'
ORDER BY   COALESCE(fill, 0) DESC, -- if there is matching not-NULL fill, then we match to it
			microtimestamp			  -- we want the earliest one if there are more than one 
LIMIT 1			
FOR UPDATE;		
  

$$;


ALTER FUNCTION bitstamp._events_match_trade(trade_timestamp timestamp with time zone, order_id bigint, amount numeric, price numeric, order_type bitstamp.direction, look_around interval) OWNER TO "ob-analytics";

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


--
-- Name: _order_book_after_event(bitstamp.order_book_record[], bitstamp.live_orders, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._order_book_after_event(s bitstamp.order_book_record[], v bitstamp.live_orders, "only.makers" boolean DEFAULT true) RETURNS bitstamp.order_book_record[]
    LANGUAGE sql IMMUTABLE
    AS $$

WITH orders AS (
		SELECT _order_book_after_event.v.microtimestamp AS ts,
				price,
				amount,
				direction,
				order_id,
				microtimestamp,
				event_type, 
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
			  	FROM unnest(s) i
			  	WHERE ( _order_book_after_event.v.event = 'order_created' OR i.order_id <> _order_book_after_event.v.order_id )
				UNION ALL 
				SELECT  _order_book_after_event.v.microtimestamp, 
						 _order_book_after_event.v.price,
						 _order_book_after_event.v.amount,
						 _order_book_after_event.v.order_type,
						 _order_book_after_event.v.order_id,
						 _order_book_after_event.v.microtimestamp,
						 _order_book_after_event.v.event,
						 _order_book_after_event.v.pair_id,
						 TRUE,
						 _order_book_after_event.v.datetime
				WHERE _order_book_after_event.v.event <> 'order_deleted' 
				) a
		
	)
	SELECT ARRAY(
		SELECT orders.*::bitstamp.order_book_record
		FROM orders	
		WHERE is_maker OR NOT _order_book_after_event."only.makers"
   );

$$;


ALTER FUNCTION bitstamp._order_book_after_event(s bitstamp.order_book_record[], v bitstamp.live_orders, "only.makers" boolean) OWNER TO "ob-analytics";

--
-- Name: spread; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.spread (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
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
    trade_id bigint NOT NULL,
    amount numeric NOT NULL,
    price numeric NOT NULL,
    trade_type bitstamp.direction NOT NULL,
    trade_timestamp timestamp with time zone NOT NULL,
    buy_order_id bigint NOT NULL,
    sell_order_id bigint NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    sell_microtimestamp timestamp with time zone,
    buy_microtimestamp timestamp with time zone,
    buy_match_rule smallint,
    sell_match_rule smallint
);


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

CREATE FUNCTION bitstamp._trades_match_buy_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval DEFAULT '00:00:02'::interval) RETURNS SETOF bitstamp.live_trades
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

CREATE FUNCTION bitstamp._trades_match_sell_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval DEFAULT '00:00:02'::interval) RETURNS SETOF bitstamp.live_trades
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
-- Name: depth_by_episode(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.depth_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS TABLE(microtimestamp timestamp with time zone, price numeric, amount numeric, direction bitstamp.direction, pair_id smallint)
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
	
	FOR v_ob_after_episode IN SELECT bitstamp.order_book_by_episodes(p_start_time, p_end_time, p_pair, p_strict)
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
    LANGUAGE sql
    AS $$

WITH time_range AS (
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
INSERT INTO bitstamp.live_orders
SELECT o.order_id,
		o.amount,
		'order_deleted'::bitstamp.live_orders_event,
		o.order_type,
		o.datetime,
		n.microtimestamp - '00:00:00.000001'::interval,	-- the cancellation will be just before the crossing event 
		NULL::timestamptz, -- we didn't receive this event from Bitstamp!
		o.pair_id,
		o.price,
		0.0::numeric,	-- the order had been cancelled 
		'Infinity'::timestamptz,
		o.era,
		NULL::timestamptz,
		NULL::bigint
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
RETURNING *	

$$;


ALTER FUNCTION bitstamp.find_and_repair_eternal_orders(ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_ex_nihilo_orders(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_ex_nihilo_orders(ts_within_era timestamp with time zone) RETURNS SETOF bitstamp.live_orders
    LANGUAGE sql
    AS $$

WITH time_range AS (
	SELECT *
	FROM (
		SELECT era AS "start.time", COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS "end.time"
		FROM bitstamp.live_orders_eras
	) r
	WHERE find_and_repair_ex_nihilo_orders.ts_within_era BETWEEN r."start.time" AND r."end.time"
),
events_with_first_event AS (
	SELECT *, first_value(event) OVER o AS first_event, first_value(microtimestamp) OVER o AS first_microtimestamp
	FROM bitstamp.live_orders 
	WHERE microtimestamp BETWEEN (SELECT "start.time" FROM time_range) AND (SELECT "end.time" FROM time_range)
	WINDOW o AS (PARTITION BY order_id ORDER BY microtimestamp)
)
INSERT INTO bitstamp.live_orders
SELECT o.order_id,
		o.amount + COALESCE(o.fill,0),			-- our best guess of the order amount when it was created
		'order_created'::bitstamp.live_orders_event,
		o.order_type,
		o.datetime,
		CASE WHEN o.datetime < o.era THEN o.era ELSE o.datetime END,	  -- the creation event will be at the start of the current era if the order 
																			 -- was created earlier or it's creation time known up to a second
		NULL::timestamptz, -- we didn't receive this event from Bitstamp!
		o.pair_id,
		o.price,
		o.fill,	
		o.microtimestamp, 	-- we know the next event microtimestamp precisely!
		o.era,
		NULL::timestamptz,
		NULL::bigint
FROM events_with_first_event o
WHERE o.first_event <> 'order_created' 
  AND microtimestamp = first_microtimestamp	-- i.e. only the first known event for each order_id
  AND ( ( trade_id IS NULL AND fill IS NULL )	-- fill is used to determine 'order_created' amount, so we temporarily ignore inconsisten events.
	    OR 										 -- They might be included later when they are repaired.
	    ( trade_id IS NOT NULL AND fill IS NOT NULL )
	   )
  AND microtimestamp > (SELECT "start.time" FROM time_range)  
RETURNING *	

$$;


ALTER FUNCTION bitstamp.find_and_repair_ex_nihilo_orders(ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_missing_fill(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_missing_fill(ts_within_era timestamp with time zone) RETURNS SETOF bitstamp.live_orders
    LANGUAGE sql
    AS $$

WITH time_range AS (
	SELECT *
	FROM (
		SELECT era AS "start.time", COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS "end.time"
		FROM bitstamp.live_orders_eras
	) r
	WHERE find_and_repair_missing_fill.ts_within_era BETWEEN r."start.time" AND r."end.time"
),
events_fill_missing AS (
	SELECT o.order_id,
			o.amount,			
			o.event,
			o.order_type,
			o.datetime,
			o.microtimestamp,
			o.local_timestamp,
			o.pair_id,
			o.price,
			t.amount AS fill,					-- fill is equal to the matched trade's amount
			o.next_microtimestamp, 	
			o.era,
			o.trade_timestamp,
			o.trade_id
	FROM bitstamp.live_orders o JOIN bitstamp.live_trades t USING (trade_timestamp, trade_id)
	WHERE microtimestamp BETWEEN (SELECT "start.time" FROM time_range) AND (SELECT "end.time" FROM time_range)
	  AND fill IS NULL
	  AND o.trade_id IS NOT NULL
)	
UPDATE bitstamp.live_orders
SET fill = events_fill_missing.fill
FROM events_fill_missing
WHERE live_orders.microtimestamp = events_fill_missing.microtimestamp
  AND live_orders.order_id = events_fill_missing.order_id
RETURNING live_orders.*	

$$;


ALTER FUNCTION bitstamp.find_and_repair_missing_fill(ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: inferred_trades(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.inferred_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_missing boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.live_trades
    LANGUAGE plpgsql STABLE
    AS $$

DECLARE
	
	e bitstamp.live_orders;
	is_e_agressor boolean;
	
	trade_parts		bitstamp.live_orders[];
	trade_part		bitstamp.live_orders;
	
	tolerance numeric;
	

BEGIN
	IF NOT p_strict THEN -- get the trade parts outstanding at p_start_time
		trade_parts := ARRAY(SELECT ROW(live_orders.*) 
							  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
							  WHERE microtimestamp >= ( SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= p_start_time ) 
		  						AND microtimestamp < p_start_time 
		  						AND next_microtimestamp >= p_start_time
		  						AND pairs.pair = p_pair
		  						AND ( ( live_orders.fill > 0.0 ) OR (live_orders.event <> 'order_created' AND live_orders.fill IS NULL ) )
							);
	ELSE
		trade_parts := '{}';
	END IF;
	
	IF NOT p_only_missing  THEN
		RETURN QUERY SELECT trade_id,
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
							  sell_match_rule
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
			
			SELECT * INTO trade_part
			FROM unnest(trade_parts) AS a
			WHERE a.order_type  = CASE WHEN e.order_type = 'buy'::bitstamp.direction THEN 'sell'::bitstamp.direction  ELSE 'buy'::bitstamp.direction  END 
 			  AND abs( (a.fill - e.fill)*CASE WHEN e.datetime < a.datetime THEN e.price ELSE a.price END) <= tolerance
			ORDER BY microtimestamp		-- TO DO: add order by 'price' too? 
			LIMIT 1;

									  
			IF FOUND THEN -- the first par has been seen 
			
				trade_parts := ARRAY( SELECT ROW(a.*)
									   FROM unnest(trade_parts) AS a 
									   WHERE NOT (a.microtimestamp = trade_part.microtimestamp AND a.order_id = trade_part.order_id)
									 );
									   
				is_e_agressor := NOT ( e.datetime < trade_part.datetime OR (e.datetime = trade_part.datetime AND e.order_id < trade_part.order_id ) );

				RETURN NEXT ( e.trade_id,
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
							   NULL::smallint); 
			ELSE -- the first par has NOT been seen, so e is the first part - save it!

				trade_parts := array_append(trade_parts, e);

			END IF;
		END IF;
	END LOOP;
	
	RAISE DEBUG 'Number of not matched trade parts: %  ', array_length(trade_parts,1);
	RAISE DEBUG 'Not matched trade parts: %', trade_parts;
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.inferred_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_missing boolean, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: live_orders_eras_v(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_eras_v(OUT era timestamp with time zone, OUT last_event timestamp with time zone, OUT events bigint, OUT e_per_sec numeric, OUT matched_buy_events bigint, OUT matched_sell_events bigint, OUT trades bigint, OUT fully_matched_trades bigint, OUT partially_matched_trades bigint, OUT not_matched_trades bigint) RETURNS SETOF record
    LANGUAGE sql STABLE
    AS $$

WITH eras AS (
	SELECT era, COALESCE(lead(era) OVER (ORDER BY era), 'infinity'::timestamptz) AS next_era
	FROM bitstamp.live_orders_eras
),
eras_orders_trades AS (
SELECT era, last_event, events, matched_buy,matched_sell, trades, fully_matched_trades, partially_matched_trades, not_matched_trades, first_event

FROM eras JOIN LATERAL (  SELECT count(*) AS events, max(microtimestamp) AS last_event, min(microtimestamp) AS first_event, 
									count(*) FILTER (WHERE trade_id IS NOT NULL AND order_type = 'buy') as matched_buy,
									count(*) FILTER (WHERE trade_id IS NOT NULL AND order_type = 'sell') as matched_sell
							FROM bitstamp.live_orders 
			  				WHERE microtimestamp >= eras.era AND microtimestamp < eras.next_era
			 			 ) e ON TRUE
		   JOIN LATERAL (SELECT count(*) AS trades, 
						  count(*) FILTER (WHERE buy_microtimestamp IS NOT NULL AND sell_microtimestamp IS NOT NULL) AS fully_matched_trades,
						  count(*) FILTER (WHERE ( buy_microtimestamp IS NOT NULL AND sell_microtimestamp IS NULL) OR ( buy_microtimestamp IS NULL AND sell_microtimestamp IS NOT NULL)) AS partially_matched_trades,
						  count(*) FILTER (WHERE buy_microtimestamp IS NULL AND sell_microtimestamp IS NULL) AS not_matched_trades
			  FROM bitstamp.live_trades
			  WHERE trade_timestamp >= eras.era AND trade_timestamp < eras.next_era
			 ) t ON TRUE
)
SELECT era, last_event, events, CASE WHEN EXTRACT( EPOCH FROM last_event - first_event ) > 0 THEN round((events/EXTRACT( EPOCH FROM last_event - first_event ))::numeric,2) ELSE 0 END AS e_per_sec, matched_buy,matched_sell, trades, fully_matched_trades, partially_matched_trades, not_matched_trades
FROM eras_orders_trades
ORDER BY era DESC;

$$;


ALTER FUNCTION bitstamp.live_orders_eras_v(OUT era timestamp with time zone, OUT last_event timestamp with time zone, OUT events bigint, OUT e_per_sec numeric, OUT matched_buy_events bigint, OUT matched_sell_events bigint, OUT trades bigint, OUT fully_matched_trades bigint, OUT partially_matched_trades bigint, OUT not_matched_trades bigint) OWNER TO "ob-analytics";

--
-- Name: live_orders_incorporate_new_event(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_incorporate_new_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	previous_event CURSOR FOR  SELECT * 
								FROM bitstamp.live_orders 
								WHERE microtimestamp >= NEW.era
							  	  AND order_id = NEW.order_id 
								  AND next_microtimestamp > NEW.microtimestamp FOR UPDATE;
	eon timestamptz;
BEGIN 

	eon := bitstamp._get_live_orders_eon(NEW.microtimestamp);
	
	-- 'eon' is a period of time covered by a single live_orders partition
	-- 'era' is a period that started when a Websocket connection to Bitstamp had been successfully established 
	
	-- Events in the era can't cross an eon boundary. An event will be assigned to the new era starting when the most recent eon eon starts
	-- if the eon bondary has been crossed.
	
	IF eon > NEW.era THEN 
		NEW.era := eon;	
	END IF;

	-- set 'next_microtimestamp'
	IF NEW.next_microtimestamp IS NULL THEN 
		CASE NEW.event 
			WHEN 'order_created', 'order_changed'  THEN 
				NEW.next_microtimestamp := 'infinity'::timestamptz;		-- later than all other timestamps
			WHEN 'order_deleted' THEN 
				NEW.next_microtimestamp := '-infinity'::timestamptz;	-- earlier than all other timestamps
		END CASE;
	END IF;
	
	CASE NEW.event
		WHEN 'order_created' THEN
			NEW.fill = -NEW.amount;
			
		WHEN 'order_changed', 'order_deleted' THEN
			FOR e IN previous_event LOOP
			
				UPDATE bitstamp.live_orders
				SET next_microtimestamp = NEW.microtimestamp
				WHERE CURRENT OF previous_event;

				NEW.fill = e.amount - NEW.amount;

			END LOOP;
	END CASE;
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitstamp.live_orders_incorporate_new_event() OWNER TO "ob-analytics";

--
-- Name: live_orders_match(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_match() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
						  
	buy_match CURSOR FOR SELECT * FROM bitstamp._trades_match_buy_event(NEW.microtimestamp, NEW.order_id, NEW.fill, NEW.amount, NEW.event);

	sell_match CURSOR FOR SELECT * FROM bitstamp._trades_match_sell_event(NEW.microtimestamp, NEW.order_id, NEW.fill, NEW.amount, NEW.event);	

	t RECORD;						   
	tolerance numeric;

BEGIN 

	SELECT 0.1::numeric^"R0" INTO tolerance
	FROM bitstamp.pairs 
	WHERE pairs.pair_id = NEW.pair_id;
	
	IF NEW.order_type = 'buy' THEN
		FOR t IN buy_match LOOP
		
			UPDATE bitstamp.live_trades
			SET buy_microtimestamp = NEW.microtimestamp,
				buy_match_rule = bitstamp._get_match_rule(trade_amount := t.amount,
							   							  trade_price := t.price,
							   							  event_amount := NEW.amount,
							   							  event_fill := NEW.fill,
							   							  event := NEW.event,
							   							  tolerance := tolerance
							  							 ) + 10
			WHERE CURRENT OF buy_match;
			
			NEW.trade_id := t.trade_id;
			NEW.trade_timestamp := t.trade_timestamp;
			
			EXIT;
		END LOOP;
	ELSE
		FOR t IN sell_match LOOP
		
			UPDATE bitstamp.live_trades
			SET sell_microtimestamp = NEW.microtimestamp,
				sell_match_rule = bitstamp._get_match_rule(trade_amount := t.amount,
							   							   trade_price := t.price,
							   							   event_amount := NEW.amount,
							   							   event_fill := NEW.fill,
							   							   event := NEW.event,
							   							   tolerance := tolerance
							  							  ) + 10
			WHERE CURRENT OF sell_match;
			
			NEW.trade_id := t.trade_id;
			NEW.trade_timestamp := t.trade_timestamp;
			
			EXIT;
		END LOOP;
	END IF;
	
	RETURN NEW;

END;

$$;


ALTER FUNCTION bitstamp.live_orders_match() OWNER TO "ob-analytics";

--
-- Name: live_orders_update_previous(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_update_previous() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN 
	UPDATE bitstamp.live_orders
	SET next_microtimestamp = NEW.microtimestamp,
	     order_id = NEW.order_id
	WHERE live_orders.order_id = OLD.order_id
	  AND live_orders.next_microtimestamp = OLD.next_microtimestamp;
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitstamp.live_orders_update_previous() OWNER TO "ob-analytics";

--
-- Name: live_trades_match(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_trades_match() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	LOOK_AROUND CONSTANT interval := '2 sec'::interval; 
	
	buy_match CURSOR FOR SELECT * FROM bitstamp._events_match_trade(NEW.trade_timestamp, NEW.buy_order_id, NEW.amount,  NEW.price, 'buy'::bitstamp.direction);

	sell_match CURSOR FOR SELECT * FROM bitstamp._events_match_trade(NEW.trade_timestamp, NEW.sell_order_id, NEW.amount, NEW.price, 'sell'::bitstamp.direction);

	e RECORD;
	
	tolerance numeric;
	
BEGIN 

	SELECT 0.1::numeric^"R0" INTO tolerance 
 	FROM bitstamp.pairs 
	WHERE pairs.pair_id = NEW.pair_id;
	
	FOR e in buy_match LOOP
		NEW.buy_microtimestamp := e.microtimestamp;
		NEW.buy_match_rule := 20 + bitstamp._get_match_rule( trade_amount := NEW.amount,
														   	  trade_price := NEW.price,
															  event_amount := e.amount,
															  event_fill := e.fill,
															  event := e.event,
															  tolerance := tolerance
														     );
		
		UPDATE bitstamp.live_orders
		SET trade_id = NEW.trade_id,
			trade_timestamp = NEW.trade_timestamp
		WHERE CURRENT OF buy_match;
		
		EXIT;
		
	END LOOP;

	FOR e in sell_match LOOP
		NEW.sell_microtimestamp := e.microtimestamp;
		
		NEW.sell_match_rule := 20 + bitstamp._get_match_rule( trade_amount := NEW.amount,
														   	  trade_price := NEW.price,
															  event_amount := e.amount,
															  event_fill := e.fill,
															  event := e.event,
															  tolerance := tolerance
														     );
		
		UPDATE bitstamp.live_orders
		SET trade_id = NEW.trade_id,
			trade_timestamp = NEW.trade_timestamp
		WHERE CURRENT OF sell_match;
		
		EXIT;
		
	END LOOP;
	
	RETURN NEW;
 
END;

$$;


ALTER FUNCTION bitstamp.live_trades_match() OWNER TO "ob-analytics";

--
-- Name: match_order_book_events(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.match_order_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE sql
    AS $$

WITH trades AS (
	SELECT buy_microtimestamp, buy_order_id, sell_microtimestamp, sell_order_id
	FROM bitstamp.inferred_trades(p_start_time, p_end_time, p_pair, FALSE)
	ORDER BY trade_timestamp
),
events AS (
	SELECT *
	FROM bitstamp.live_orders
	WHERE microtimestamp BETWEEN p_start_time AND p_end_time
),
matched_events AS (
	SELECT order_id, amount, event, order_type, datetime, microtimestamp, local_timestamp, pair_id, price, fill, next_microtimestamp, 
			era, trade_timestamp, trade_id,
			CASE order_type WHEN 'buy' THEN sell_microtimestamp WHEN 'sell' THEN buy_microtimestamp END AS matched_microtimestamp,
			CASE order_type WHEN 'buy' THEN sell_order_id WHEN 'sell' THEN buy_order_id END AS matched_order_id
	FROM events LEFT JOIN trades ON CASE order_type 
										WHEN 'buy' THEN microtimestamp = buy_microtimestamp AND order_id = buy_order_id
										WHEN 'sell' THEN microtimestamp = sell_microtimestamp AND order_id = sell_order_id
									  END
)	
UPDATE bitstamp.live_orders
SET matched_microtimestamp = matched_events.matched_microtimestamp,
	matched_order_id = matched_events.matched_order_id
FROM matched_events
WHERE matched_events.matched_microtimestamp IS NOT NULL 
  AND matched_events.microtimestamp = live_orders.microtimestamp
  AND matched_events.order_id = live_orders.order_id
RETURNING live_orders.*;
	
$$;


ALTER FUNCTION bitstamp.match_order_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying DEFAULT 'BTCUSD'::character varying, p_strict boolean DEFAULT false) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE
    AS $$

  SELECT microtimestamp AS "timestamp", price, amount AS volume, CASE direction WHEN 'buy' THEN 'bid'::text WHEN 'sell' THEN 'ask'::text END
  FROM bitstamp.depth_by_episode(p_start_time, p_end_time, p_pair, p_strict);
 

$$;


ALTER FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, character varying, boolean, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, strict boolean DEFAULT false, bps_step numeric DEFAULT 25) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level integer)
    LANGUAGE sql STABLE
    AS $$

WITH events AS (
	SELECT MIN(price) FILTER (WHERE direction = 'sell') OVER (PARTITION BY ts) AS best_ask_price, 
			MAX(price) FILTER (WHERE direction = 'buy') OVER (PARTITION BY ts) AS best_bid_price, * 
	FROM 	( SELECT order_book_entry.* 
			   FROM bitstamp.order_book_by_episodes(oba_depth_summary."start.time",oba_depth_summary."end.time",
										 oba_depth_summary.pair,oba_depth_summary.strict) 
					 JOIN LATERAL unnest(order_book_by_episodes) AS order_book_entry ON TRUE
			 ) a
	WHERE is_maker 
),
events_with_bps_levels AS (
	SELECT ts, 
			amount, 
			price,
			direction,
			CASE direction
				WHEN 'sell' THEN ceiling((price-best_ask_price)/best_ask_price/oba_depth_summary.bps_step*10000)::integer
				WHEN 'buy' THEN ceiling((best_bid_price - price)/best_bid_price/oba_depth_summary.bps_step*10000)::integer 
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
				WHEN 'sell' THEN round(best_ask_price*(1 + bps_level*oba_depth_summary.bps_step/10000), pairs."R0")
				WHEN 'buy' THEN round(best_bid_price*(1 - bps_level*oba_depth_summary.bps_step/10000), pairs."R0") 
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
		bps_level*oba_depth_summary.bps_step::integer
FROM events_with_price_adjusted
WHERE r = 1	-- if rounded to milliseconds ts are not unique, we'll take the LAST one and will drop the first silently
			 -- this is a workaround for the inability of R to handle microseconds in POSIXct 
GROUP BY 1, 2, 4, 5

$$;


ALTER FUNCTION bitstamp.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, strict boolean, bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: oba_event(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text) RETURNS TABLE("event.id" bigint, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, action text, direction text, fill numeric, "matching.event" bigint, type text, "aggressiveness.bps" numeric, "real.trade.id" bigint, is_aggressor boolean, is_created boolean, is_ever_resting boolean, is_ever_aggressor boolean, is_ever_filled boolean, is_deleted boolean, is_price_ever_changed boolean, best_bid_price numeric, best_ask_price numeric)
    LANGUAGE sql STABLE
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.inferred_trades(oba_event."start.time",oba_event."end.time", pair, FALSE, TRUE)
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
		  FROM bitstamp.spread_by_episode("start.time", "end.time", pair, TRUE, TRUE)
		  ),
	  shifted_events AS (
		  SELECT GREATEST(microtimestamp, matched_microtimestamp) AS microtimestamp,
		  		  price,
		  		  amount,
		  		  order_type,
		  		  order_id,
		  		  event,
		  		  datetime,
		  		  fill,
		  		  trade_id
		  FROM bitstamp.live_orders
		  WHERE microtimestamp BETWEEN oba_event."start.time" AND oba_event."end.time" 
	  )	,
	  base_events AS (
		  SELECT microtimestamp,
		  		  price,
		  		  amount,
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
		          END AS is_aggressor
		  FROM shifted_events LEFT JOIN spread USING (microtimestamp)
	  ),
	  events AS (
		SELECT row_number() OVER (ORDER BY order_id, event, microtimestamp) AS event_id,		-- ORDER BY must be the same as in oba_trade(). Change both!
		  		base_events.*,
		  		MAX(price) OVER o_all <> MIN(price) OVER o_all AS is_price_ever_changed,
				bool_or(NOT is_aggressor) OVER o_all AS is_ever_resting,
		  		bool_or(is_aggressor) OVER o_all AS is_ever_aggressor, 	
		  		bool_or(COALESCE(fill, CASE WHEN event <> 'order_deleted' THEN 1.0 ELSE NULL END ) > 0.0 ) OVER o_all AS is_ever_filled, 	
		  		first_value(event) OVER o_after = 'order_deleted' AS is_deleted,
		  		first_value(event) OVER o_before = 'order_created' AS is_created
		FROM base_events LEFT JOIN makers USING (order_id) LEFT JOIN takers USING (order_id) 
		WINDOW o_all AS (PARTITION BY order_id), 
		  		o_after AS (PARTITION BY order_id ORDER BY microtimestamp DESC),
		  		o_before AS (PARTITION BY order_id ORDER BY microtimestamp)
	  ),
	  event_connection AS (
		  SELECT buy_microtimestamp AS microtimestamp, 
		  		  buy_order_id AS order_id, 
		  		  events.event_id
		  FROM trades JOIN events ON sell_microtimestamp = microtimestamp AND sell_order_id = order_id
		  UNION ALL
		  SELECT sell_microtimestamp AS microtimestamp, 
		  		  sell_order_id AS order_id, 
		  		  events.event_id
		  FROM trades JOIN events ON buy_microtimestamp = microtimestamp AND buy_order_id = order_id
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
		trade_id AS "real.trade.id",
		is_aggressor,
		is_created,
		is_ever_resting,
		is_ever_aggressor,
		is_ever_filled,
		is_deleted,
		is_price_ever_changed,
		best_bid_price,
		best_ask_price
  FROM events LEFT JOIN event_connection USING (microtimestamp, order_id) 
  ORDER BY 1;

$$;


ALTER FUNCTION bitstamp.oba_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--	See bitstamp.spread_by_episode()

	SELECT best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
	FROM bitstamp.spread_by_episode(p_start_time , p_end_time, p_pair, p_only_different, p_strict)

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
		FROM bitstamp.inferred_trades(p_start_time, p_end_time, p_pair, FALSE, p_strict)
	   ),
	  events AS (
		SELECT row_number() OVER (ORDER BY order_id, event, microtimestamp) AS event_id,	-- ORDER BY must be the same as in oba_event(). Change both!
		  		live_orders.*
		FROM bitstamp.live_orders
		WHERE microtimestamp BETWEEN p_start_time AND p_end_time 
	  )
  SELECT trades.trade_timestamp AS "timestamp",
  		  trades.price,
		  trades.amount AS volume,
		  trades.trade_type::text AS direction,
		  CASE trade_type
		  	WHEN 'buy' THEN s.event_id
			WHEN 'sell' THEN b.event_id
		  END AS "maker.event.id",
		  CASE trade_type
		  	WHEN 'buy' THEN b.event_id
			WHEN 'sell' THEN s.event_id
		  END AS "taker.event.id",
		  CASE trade_type
		  	WHEN 'buy' THEN sell_order_id
			WHEN 'sell' THEN buy_order_id
		  END AS maker,
		  CASE trade_type
		  	WHEN 'buy' THEN buy_order_id
			WHEN 'sell' THEN sell_order_id
		  END AS taker,
		  trades.trade_id 
  FROM trades JOIN events b ON buy_microtimestamp = b.microtimestamp AND buy_order_id = b.order_id 
  		JOIN events s ON sell_microtimestamp = s.microtimestamp AND sell_order_id = s.order_id 
  ORDER BY trades.trade_timestamp;

$$;


ALTER FUNCTION bitstamp.oba_trade(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_after(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: postgres
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
			event,
			pair_id,
			is_maker,
			datetime
    FROM orders
	WHERE is_maker OR NOT p_only_makers
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_after(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO postgres;

--
-- Name: order_book_before(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: postgres
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


ALTER FUNCTION bitstamp.order_book_before(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO postgres;

--
-- Name: order_book_by_episodes(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_by_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.order_book_record[]
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

	FOR v_r IN SELECT ROW(live_orders.*) AS e, lead(microtimestamp) OVER (ORDER BY microtimestamp) AS n
										   FROM bitstamp.live_orders
			  							   WHERE microtimestamp BETWEEN p_start_time AND p_end_time 
			    							 AND pair_id = v_pair_id
			  							   ORDER BY microtimestamp, order_id 
	LOOP
		v_event := v_r.e;
		v_next_microtimestamp 	:= v_r.n;
		
		IF ob IS NULL THEN 
			ob := ARRAY(SELECT bitstamp.order_book_after(v_event.microtimestamp, p_pair, FALSE));
		ELSE													 
			ob := bitstamp._order_book_after_event(ob, v_event, "only.makers" := FALSE);
		END IF;
													 
		IF NOT ( v_event.fill > 0.0 AND v_event.microtimestamp < COALESCE(v_event.matched_microtimestamp, v_event.microtimestamp) )	AND 
		   NOT ( v_event.microtimestamp = v_next_microtimestamp ) THEN
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


ALTER FUNCTION bitstamp.order_book_by_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: pga_process_transient_live_orders(text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text DEFAULT 'BTCUSD'::text) RETURNS void
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE

	v_pair_id smallint;
	
	v_start_time timestamp with time zone;
	v_end_time timestamp with time zone;
	
	v_era timestamp with time zone;

BEGIN 
	SET CONSTRAINTS ALL DEFERRED;

	SELECT pair_id INTO v_pair_id
	FROM bitstamp.pairs WHERE pairs.pair = p_pair;
	
	SELECT MIN(microtimestamp), MAX(microtimestamp) INTO v_start_time, v_end_time
	FROM bitstamp.transient_live_orders 
	WHERE pair_id = v_pair_id;
	
	WITH deleted AS (
		DELETE FROM bitstamp.transient_live_orders 
		WHERE pair_id = v_pair_id
	  	AND microtimestamp BETWEEN v_start_time AND v_end_time
		RETURNING *
	)
	INSERT INTO bitstamp.live_orders (order_id, amount, "event", order_type, datetime, microtimestamp, local_timestamp, pair_id, price, era)
	SELECT order_id, amount, "event", order_type, datetime, microtimestamp, local_timestamp, pair_id, price, era
	FROM deleted 
	ORDER BY microtimestamp;
	
	FOR v_era IN SELECT DISTINCT era FROM bitstamp.live_orders WHERE pair_id = v_pair_id	AND microtimestamp BETWEEN v_start_time AND v_end_time
			LOOP
			PERFORM bitstamp.find_and_repair_missing_fill(v_era);
			PERFORM bitstamp.find_and_repair_ex_nihilo_orders(v_era);
			PERFORM bitstamp.find_and_repair_eternal_orders(v_era);
	END LOOP;			
	
	PERFORM bitstamp.match_order_book_events(v_start_time, v_end_time, p_pair);
	
	
	INSERT INTO bitstamp.spread
	SELECT * FROM bitstamp.spread_by_episode(v_start_time, v_end_time, p_pair, TRUE, FALSE );

END;

$$;


ALTER FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text) OWNER TO "ob-analytics";

--
-- Name: FUNCTION pga_process_transient_live_orders(p_pair text); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.pga_process_transient_live_orders(p_pair text) IS 'This function is expected to be run by pgAgent as often as necessary to store order book events from  transient_live_orders table';


--
-- Name: spread_by_episode(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.spread
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
											 
	FOR v_ob IN SELECT * FROM bitstamp.order_book_by_episodes(p_start_time, p_end_time, p_pair, p_strict)
	LOOP
		v_cur := bitstamp._spread_from_order_book(v_ob);	
		IF  (v_cur.best_bid_price IS DISTINCT FROM  v_prev.best_bid_price OR 
			v_cur.best_bid_qty IS DISTINCT FROM  v_prev.best_bid_qty OR
			v_cur.best_ask_price IS DISTINCT FROM  v_prev.best_ask_price OR
			v_cur.best_ask_qty IS DISTINCT FROM  v_prev.best_ask_qty ) 
			OR NOT p_only_different THEN
			v_prev := v_cur;
			RETURN NEXT v_cur;
		END IF;
	END LOOP;
	
END;

$$;


ALTER FUNCTION bitstamp.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_different boolean, p_strict boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each episode in the ''live_orders'' table that hits the interval between p_start_time and p_end_time for the given "pair". The spread is calculated using all available data before p_start_time unless "p_p_strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between p_start_time and p_end_time';


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
-- Name: live_orders_eras; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_orders_eras (
    era timestamp with time zone NOT NULL
);


ALTER TABLE bitstamp.live_orders_eras OWNER TO "ob-analytics";

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
-- Name: diff_order_book diff_order_book_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.diff_order_book
    ADD CONSTRAINT diff_order_book_pkey PRIMARY KEY ("timestamp", price, side);


--
-- Name: live_orders_eras eras_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders_eras
    ADD CONSTRAINT eras_pkey PRIMARY KEY (era);


--
-- Name: live_orders live_orders_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_pkey PRIMARY KEY (microtimestamp, order_id);


--
-- Name: live_trades live_trades_pkey ; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT "live_trades_pkey " PRIMARY KEY (trade_timestamp, trade_id);


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
    ADD CONSTRAINT spread_pkey PRIMARY KEY (pair_id, microtimestamp);


--
-- Name: live_orders_idx_order_id; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_orders_idx_order_id ON bitstamp.live_orders USING btree (order_id);


--
-- Name: live_orders a_incorporate_new_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER a_incorporate_new_event BEFORE INSERT ON bitstamp.live_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_incorporate_new_event();


--
-- Name: live_trades a_match_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER a_match_event BEFORE INSERT ON bitstamp.live_trades FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_trades_match();


--
-- Name: live_orders a_update_previous; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER a_update_previous AFTER UPDATE OF order_id, microtimestamp ON bitstamp.live_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_update_previous();


--
-- Name: live_orders b_match_trade; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER b_match_trade BEFORE INSERT ON bitstamp.live_orders FOR EACH ROW WHEN ((new.event <> 'order_created'::bitstamp.live_orders_event)) EXECUTE PROCEDURE bitstamp.live_orders_match();


--
-- Name: live_orders live_orders_fkey_eras; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_fkey_eras FOREIGN KEY (era) REFERENCES bitstamp.live_orders_eras(era) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_orders live_orders_fkey_matched_live_orders; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_fkey_matched_live_orders FOREIGN KEY (matched_microtimestamp, matched_order_id) REFERENCES bitstamp.live_orders(microtimestamp, order_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_orders live_orders_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_trades live_trades_fkey_buy_live_orders; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_buy_live_orders FOREIGN KEY (buy_microtimestamp, buy_order_id) REFERENCES bitstamp.live_orders(microtimestamp, order_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_trades live_trades_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_trades live_trades_fkey_sell_live_orders; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_sell_live_orders FOREIGN KEY (sell_microtimestamp, sell_order_id) REFERENCES bitstamp.live_orders(microtimestamp, order_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

