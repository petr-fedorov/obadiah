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
-- Name: depth; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.depth AS (
	ts timestamp with time zone,
	price numeric,
	amount numeric,
	direction bitstamp.direction,
	pair_id smallint,
	order_id bigint,
	is_maker boolean
);


ALTER TYPE bitstamp.depth OWNER TO "ob-analytics";

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
-- Name: oba_depth; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.oba_depth AS (
	"timestamp" timestamp with time zone,
	price numeric,
	volume numeric,
	side text
);


ALTER TYPE bitstamp.oba_depth OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.oba_depth_summary AS (
	"timestamp" timestamp with time zone,
	price numeric,
	volume numeric,
	side text,
	bps_level integer
);


ALTER TYPE bitstamp.oba_depth_summary OWNER TO "ob-analytics";

--
-- Name: oba_event; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.oba_event AS (
	"event.id" bigint,
	id bigint,
	"timestamp" timestamp with time zone,
	"exchange.timestamp" timestamp with time zone,
	price numeric,
	volume numeric,
	action text,
	direction text,
	fill numeric,
	"matching.event" bigint,
	type text,
	"aggressiveness.bps" numeric,
	"real.trade.id" bigint
);


ALTER TYPE bitstamp.oba_event OWNER TO "ob-analytics";

--
-- Name: oba_spread; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.oba_spread AS (
	"best.bid.price" numeric,
	"best.bid.volume" numeric,
	"best.ask.price" numeric,
	"best.ask.volume" numeric,
	"timestamp" timestamp with time zone
);


ALTER TYPE bitstamp.oba_spread OWNER TO "ob-analytics";

--
-- Name: oba_trade; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.oba_trade AS (
	"timestamp" timestamp with time zone,
	price numeric,
	volume numeric,
	direction text,
	"maker.event.id" bigint,
	"taker.event.id" bigint,
	maker bigint,
	taker bigint,
	"real.trade.id" bigint
);


ALTER TYPE bitstamp.oba_trade OWNER TO "ob-analytics";

--
-- Name: order_book; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.order_book AS (
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


ALTER TYPE bitstamp.order_book OWNER TO "ob-analytics";

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
    trade_id bigint
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
-- Name: _order_book_after_event(bitstamp.order_book[], bitstamp.live_orders, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._order_book_after_event(s bitstamp.order_book[], v bitstamp.live_orders, "only.makers" boolean DEFAULT true) RETURNS bitstamp.order_book[]
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
		SELECT orders.*::bitstamp.order_book
		FROM orders	
		WHERE is_maker OR NOT _order_book_after_event."only.makers"
   );

$$;


ALTER FUNCTION bitstamp._order_book_after_event(s bitstamp.order_book[], v bitstamp.live_orders, "only.makers" boolean) OWNER TO "ob-analytics";

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
-- Name: _spread_from_order_book(bitstamp.order_book[]); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._spread_from_order_book(s bitstamp.order_book[]) RETURNS bitstamp.spread
    LANGUAGE sql IMMUTABLE
    AS $$

	WITH price_levels AS (
		SELECT ts, 
				direction,
				price,
				sum(amount) AS qty, 
				CASE direction
						WHEN 'sell' THEN price = min(price) FILTER (WHERE direction = 'sell') OVER ()
						WHEN 'buy' THEN price = max(price) FILTER (WHERE direction = 'buy') OVER ()
				END AS is_best,
				pair_id
		FROM unnest(s)
		WHERE is_maker
		GROUP BY pair_id, ts, direction, price
	)
	SELECT b.price, b.qty, s.price, s.qty, COALESCE(b.ts, s.ts), pair_id
	FROM (SELECT * FROM price_levels WHERE direction = 'buy' AND is_best) b FULL JOIN (SELECT * FROM price_levels WHERE direction = 'sell' AND is_best) s USING (pair_id);

$$;


ALTER FUNCTION bitstamp._spread_from_order_book(s bitstamp.order_book[]) OWNER TO "ob-analytics";

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
-- Name: depth_after_event(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.depth_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, strict boolean DEFAULT false) RETURNS SETOF bitstamp.depth
    LANGUAGE plpgsql STABLE
    AS $$

-- ARGUMENTS
--		"start.time" - the start of the interval for the calculation of depths
--		"end.time"	 - the end of the interval
--		"pair"		 - the pair for which depths will be calculated
--		"strict"		- whether to calculate the spread using events before "start.time" (false) or not (false). 

DECLARE
	ob bitstamp.order_book[];
	e bitstamp.live_orders;
	
	depth_before_event bitstamp.depth[];
	depth_after_event bitstamp.depth[];
	
BEGIN
	IF depth_after_event."strict" THEN 
		ob := '{}';	-- only the events within the ["start.time", "end.time"] interval will be used
	ELSE
		ob := NULL;	-- this will force bitstamp._order_book_after_event() to load events before the "start.time" and thus to calculate an entry depth for the interval
	END IF;
	
	FOR e IN SELECT live_orders.* FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
			  WHERE microtimestamp BETWEEN depth_after_event."start.time" AND depth_after_event."end.time" 
			    AND pairs.pair = depth_after_event.pair 
			  ORDER BY microtimestamp LOOP
			  
		depth_before_event := ARRAY( 
			SELECT ROW(e.microtimestamp, price, amount, direction, pair_id, order_id, is_maker)
			FROM unnest(ob) o
			WHERE is_maker 
			  AND o.price = e.price
			);

		IF ob IS NULL THEN 
			ob := ARRAY(SELECT bitstamp.order_book_v(e.microtimestamp, "only.makers" := FALSE));
		ELSE
			ob := bitstamp._order_book_after_event(ob, e, "only.makers" := FALSE);
		END IF;


		depth_after_event := ARRAY( 
			SELECT ROW(e.microtimestamp, price, amount, direction, pair_id, order_id, is_maker)
			FROM unnest(ob) o
			WHERE is_maker 
			  AND o.price = e.price
			);			

		IF depth_after_event = '{}' AND depth_before_event <> '{}' THEN -- price level has been removed completely
			depth_after_event := ARRAY[ROW(e.microtimestamp, e.price, 0.0, e.order_type, e.pair_id, e.order_id, TRUE)];
		END IF;

		IF depth_before_event <> depth_after_event THEN
			RETURN QUERY SELECT * FROM  unnest(depth_after_event);
		END IF;
										   
	END LOOP;
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.depth_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, strict boolean) OWNER TO "ob-analytics";

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
				   	    AND CASE o.order_type
				   				WHEN 'buy' THEN i.price <= o.price
				   				WHEN 'sell' THEN i.price >= o.price
				   			END
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

CREATE FUNCTION bitstamp.inferred_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, "only.missing" boolean DEFAULT true, strict boolean DEFAULT false) RETURNS SETOF bitstamp.live_trades
    LANGUAGE plpgsql STABLE
    AS $$

DECLARE
	
	e bitstamp.live_orders;
	is_e_agressor boolean;
	
	trade_parts		bitstamp.live_orders[];
	trade_part		bitstamp.live_orders;
	
	tolerance numeric;

	
BEGIN
	IF NOT strict THEN -- get the trade parts outstanding at "start.time"
		SELECT ARRAY[live_orders.*] INTO trade_parts
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp >= ( SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= inferred_trades."start.time" ) 
		  AND microtimestamp < inferred_trades."start.time" 
		  AND next_microtimestamp >= inferred_trades."start.time"
		  AND pairs.pair = inferred_trades.pair
		  AND ( ( live_orders.fill > 0.0 ) OR (live_orders.event <> 'order_created' AND live_orders.fill IS NULL ) );
	ELSE
		trade_parts := '{}';
	END IF;
	
	trade_part := NULL;
									   
	SELECT 0.1::numeric^"R0" INTO tolerance 
 	FROM bitstamp.pairs 
	WHERE pairs.pair = inferred_trades.pair;
	
											 
	FOR e IN SELECT live_orders.* 
			  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
			  WHERE microtimestamp BETWEEN inferred_trades."start.time" AND inferred_trades."end.time" 
			    AND pairs.pair = inferred_trades.pair
			  ORDER BY microtimestamp
				LOOP
									  
		IF ( e.fill > 0.0 ) OR (e.event <> 'order_created' AND e.fill IS NULL) THEN -- it's part of the trade to be inferred
			-- check whether the first part of the trade has been seen already 
			SELECT * INTO trade_part
			FROM unnest(trade_parts) AS a
			WHERE a.order_type  = CASE WHEN e.order_type = 'buy'::bitstamp.direction THEN 'sell'::bitstamp.direction  ELSE 'buy'::bitstamp.direction  END 
 			  AND ( (a.trade_id IS NULL AND e.trade_id IS NULL AND abs( (a.fill - e.fill)*CASE WHEN e.datetime < a.datetime THEN e.price ELSE a.price END) <= tolerance) 
				   OR ( a.trade_id = e.trade_id ) )
			ORDER BY microtimestamp		-- TO DO: add order by 'price' too? 
			LIMIT 1;
									  
			IF FOUND THEN -- the first par has been seen 
				SELECT ARRAY[a.*] INTO trade_parts 
				FROM unnest(trade_parts) AS a 
				WHERE NOT (a.microtimestamp = trade_part.microtimestamp AND a.order_id = trade_part.order_id);
									   
				IF (NOT "only.missing" ) OR e.trade_id IS NULL THEN -- here trade_part.trade_id will be either equal to e.trade_id or both will be NULL
									   
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
								   0::smallint,
								   0::smallint);
				END IF;												  
			ELSE -- the first par has NOT been seen, so e is the first part - save it!
				trade_parts := array_append(trade_parts, e);
			END IF;
		END IF;
	END LOOP;
										   
	RAISE NOTICE 'Trade parts without a pair %', trade_parts;
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.inferred_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, "only.missing" boolean, strict boolean) OWNER TO "ob-analytics";

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
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, strict boolean DEFAULT false) RETURNS SETOF bitstamp.oba_depth
    LANGUAGE sql
    AS $$

  SELECT ts AS "timestamp", price, sum(amount) AS volume, CASE direction WHEN 'buy' THEN 'bid'::text WHEN 'sell' THEN 'ask'::text END
  FROM bitstamp.depth_after_event(oba_depth."start.time", oba_depth."end.time", oba_depth.pair, oba_depth."strict")
  GROUP BY 1, 2, 4;

$$;


ALTER FUNCTION bitstamp.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, strict boolean) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, character varying, boolean, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, strict boolean DEFAULT false, bps_step numeric DEFAULT 25) RETURNS SETOF bitstamp.oba_depth_summary
    LANGUAGE sql STABLE
    AS $$


WITH events AS (
	SELECT MIN(price) FILTER (WHERE direction = 'sell') OVER (PARTITION BY ts) AS best_ask_price, 
			MAX(price) FILTER (WHERE direction = 'buy') OVER (PARTITION BY ts) AS best_bid_price, * 
	FROM bitstamp.order_book_after_event(oba_depth_summary."start.time",
										 oba_depth_summary."end.time",
										 oba_depth_summary.pair,
										 oba_depth_summary.strict)
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
			bps_level
	FROM events_with_bps_levels JOIN bitstamp.pairs USING (pair_id)
)
SELECT ts, 
		price, 
		SUM(amount) AS volume, 
		side, 
		bps_level*oba_depth_summary.bps_step::integer
FROM events_with_price_adjusted
GROUP BY 1, 2, 4, 5


$$;


ALTER FUNCTION bitstamp.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, strict boolean, bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: oba_event(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.oba_event
    LANGUAGE sql STABLE
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.inferred_trades(oba_event."start.time",oba_event."end.time", "only.missing" := FALSE, "strict" := TRUE)
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
	  spread AS (
		  SELECT *
		  FROM bitstamp.spread_after_event(oba_event."start.time",oba_event."end.time", "only.different" := FALSE, "strict" := TRUE)
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
	  base_events AS (
		  SELECT microtimestamp,
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
	  ),
	  events AS (
		SELECT row_number() OVER (ORDER BY order_id, event, microtimestamp) AS event_id,		-- ORDER BY must be the same as in oba_trade(). Change both!
		  		base_events.*,
		  		MAX(price) OVER o_all <> MIN(price) OVER o_all AS order_price_ever_changed,
		  		makers.order_id IS NOT NULL AS is_maker,
		  	    takers.order_id IS NOT NULL AS is_taker,
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
		  CASE WHEN order_price_ever_changed THEN 'pacman'::text
		  	    WHEN NOT is_maker AND NOT is_taker AND is_created AND is_deleted THEN 'flashed-limit'::text
				WHEN NOT is_maker AND NOT is_taker AND NOT is_deleted THEN 'resting-limit'::text
				WHEN is_maker AND NOT is_taker THEN 'resting-limit'::text
				WHEN NOT is_maker AND is_taker AND is_deleted THEN 'market'::text
				WHEN NOT is_maker AND is_taker AND NOT is_deleted THEN 'market-limit'::text
				WHEN is_maker AND is_taker THEN 'market-limit'::text
		  		ELSE 'unknown'::text 
		  END AS "type",
			CASE order_type 
		  		WHEN 'sell' THEN round((best_ask_price - price)/best_ask_price*10000)
		  		WHEN 'buy' THEN round((price - best_bid_price)/best_ask_price*10000)
		  	END AS "aggressiveness.bps",
		trade_id AS "real.trade.id"
  FROM events LEFT JOIN event_connection USING (microtimestamp, order_id) LEFT JOIN spread USING (microtimestamp)
  ORDER BY 1;

$$;


ALTER FUNCTION bitstamp.oba_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, "only.different" boolean DEFAULT true, strict boolean DEFAULT false) RETURNS SETOF bitstamp.oba_spread
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--	See bitstamp.spread_after_event()

	SELECT best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
	FROM bitstamp.spread_after_event(oba_spread."start.time" ,oba_spread."end.time", oba_spread.pair, oba_spread."only.different", oba_spread."strict")

$$;


ALTER FUNCTION bitstamp.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, "only.different" boolean, strict boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, "only.different" boolean, strict boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, "only.different" boolean, strict boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each event in the ''live_orders'' table that hits the interval between "start.time" and "end.time" for the given "pair" and in the format expected by  obAnalytics package. The spread is calculated using all available data before "start.time" unless "strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between "start.time" and "end.time". ';


--
-- Name: oba_trade(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_trade("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.oba_trade
    LANGUAGE sql
    SET work_mem TO '1GB'
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.inferred_trades(oba_trade."start.time",oba_trade."end.time", "only.missing" := FALSE)
	   ),
	  events AS (
		SELECT row_number() OVER (ORDER BY order_id, event, microtimestamp) AS event_id,	-- ORDER BY must be the same as in oba_event(). Change both!
		  		live_orders.*
		FROM bitstamp.live_orders
		WHERE microtimestamp BETWEEN oba_trade."start.time" AND oba_trade."end.time" 
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


ALTER FUNCTION bitstamp.oba_trade("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text) OWNER TO "ob-analytics";

--
-- Name: order_book_after_event(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, strict boolean DEFAULT false) RETURNS SETOF bitstamp.order_book
    LANGUAGE plpgsql STABLE
    AS $$

-- ARGUMENTS
--		"start.time" - the start of the interval for the calculation of order books
--		"end.time"	 - the end of the interval
--		"pair"		 - the pair for which order books will be calculated
--		"strict"		- whether to calculate order books using events before "start.time" (false) or not (false). 

DECLARE
	ob bitstamp.order_book[];
	empty_order_book bitstamp.order_book[];
	
	e bitstamp.live_orders;
	
	volume_before numeric[];
	volume_after numeric[];
	
BEGIN
	IF order_book_after_event."strict" THEN 
		ob := '{}';	-- only the events within the ["start.time", "end.time"] interval will be used
	ELSE
		ob := NULL;	-- this will force bitstamp._order_book_after_event() to load events before the "start.time" and thus to calculate an entry depth for the interval
	END IF;
	
	FOR e IN SELECT live_orders.* FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
			  WHERE microtimestamp BETWEEN order_book_after_event."start.time" AND order_book_after_event."end.time" 
			    AND pairs.pair = order_book_after_event.pair 
			  ORDER BY microtimestamp LOOP
			  
		volume_before := ARRAY( 
			SELECT amount
			FROM unnest(ob) o
			WHERE is_maker 
			ORDER BY price, microtimestamp
			);
			
		IF ob IS NULL THEN 
			ob := ARRAY(SELECT bitstamp.order_book_v(e.microtimestamp, "only.makers" := FALSE));
		ELSE
			ob := bitstamp._order_book_after_event(ob, e, "only.makers" := FALSE);
		END IF;
		
		volume_after := ARRAY( 
			SELECT amount
			FROM unnest(ob) o
			WHERE is_maker 
			ORDER BY price, microtimestamp
			);
			
		IF volume_after = '{}' AND volume_before <> '{}' THEN -- the order book is empty
			empty_order_book := ARRAY[ ROW(e.microtimestamp, NULL, 0.0, 'sell'::bitstamp.direction, e.order_id, NULL, NULL, e.pair_id, TRUE, NULL),
  					      				ROW(e.microtimestamp, NULL, 0.0, 'buy'::bitstamp.direction, e.order_id, NULL, NULL, e.pair_id, TRUE, NULL)
									  ];
			RETURN QUERY SELECT * FROM  unnest(empty_order_book);
											 
		ELSIF  volume_before <> volume_after THEN 
											 
			RETURN QUERY SELECT * FROM  unnest(ob);
											 
		END IF;
										   
	END LOOP;
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.order_book_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, strict boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_v(timestamp with time zone, boolean, bitstamp.enum_neighborhood); Type: FUNCTION; Schema: bitstamp; Owner: postgres
--

CREATE FUNCTION bitstamp.order_book_v(ts timestamp with time zone, "only.makers" boolean DEFAULT true, neighborhood bitstamp.enum_neighborhood DEFAULT 'after'::bitstamp.enum_neighborhood) RETURNS SETOF bitstamp.order_book
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
		FROM bitstamp.live_orders
		WHERE microtimestamp >= (SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= order_book_v.ts ) 
		  AND CASE order_book_v.neighborhood
				WHEN 'after'  THEN  microtimestamp <= order_book_v.ts 
				WHEN 'before' THEN  microtimestamp < order_book_v.ts 
		  	   END
		   AND next_microtimestamp > order_book_v.ts 
		   AND event <> 'order_deleted'
		)
	SELECT order_book_v.ts,
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
	WHERE is_maker OR NOT order_book_v."only.makers"
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_v(ts timestamp with time zone, "only.makers" boolean, neighborhood bitstamp.enum_neighborhood) OWNER TO postgres;

--
-- Name: pga_process_transient_live_orders(text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_process_transient_live_orders(pair text DEFAULT 'BTCUSD'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$

DECLARE

	e bitstamp.transient_live_orders;
	p bitstamp.live_orders;
	prev bitstamp.spread;
	cur bitstamp.spread;
	
	ob bitstamp.order_book[];
	
	v_pair_id smallint;

BEGIN 

	SELECT pair_id INTO v_pair_id
	FROM bitstamp.pairs WHERE pairs.pair = pga_process_transient_live_orders.pair;

	
	
	FOR e IN WITH deleted AS ( DELETE FROM bitstamp.transient_live_orders 
							  	WHERE transient_live_orders.pair_id = v_pair_id
							    RETURNING * ) SELECT * FROM deleted ORDER BY microtimestamp LOOP 
	
	
		IF ob IS NULL THEN 
			ob := ARRAY(SELECT ROW(ob.*) FROM bitstamp.order_book_v(e.microtimestamp, "only.makers" := FALSE, neighborhood := 'before') AS ob);
			prev := bitstamp._spread_from_order_book(ob);
			
			IF prev IS NULL THEN -- ob was empty
				prev := ROW(NULL, NULL, NULL, NULL, e.microtimestamp, v_pair_id);	-- the widest spread - see IF below
			END IF;

		END IF;
		
		p := ROW(e.order_id, e.amount,e.event,e.order_type,e.datetime,e.microtimestamp,e.local_timestamp,e.pair_id, e.price,NULL,NULL,e.era,NULL,NULL)::bitstamp.live_orders;
		
		ob := bitstamp._order_book_after_event(ob, p, "only.makers" := FALSE);	
		cur := bitstamp._spread_from_order_book(ob);
		
		INSERT INTO bitstamp.live_orders 
		VALUES (p.*);
		
		IF cur IS NULL THEN -- ob was empty
			cur := ROW(NULL, NULL, NULL, NULL, e.microtimestamp, v_pair_id);
		END IF;

		IF ( cur.best_bid_price IS DISTINCT FROM  prev.best_bid_price OR 
			 cur.best_bid_qty IS DISTINCT FROM  prev.best_bid_qty OR
			 cur.best_ask_price IS DISTINCT FROM  prev.best_ask_price OR
			 cur.best_ask_qty IS DISTINCT FROM  prev.best_ask_qty ) 
			THEN
				prev := cur;
				INSERT INTO bitstamp.spread
				VALUES (cur.*);
		END IF;

		
	END LOOP;

END;

$$;


ALTER FUNCTION bitstamp.pga_process_transient_live_orders(pair text) OWNER TO "ob-analytics";

--
-- Name: FUNCTION pga_process_transient_live_orders(pair text); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.pga_process_transient_live_orders(pair text) IS 'This function is expected to be run by pgAgent as often as necessary to store order book events from  transient_live_orders table';


--
-- Name: spread_after_event(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, "only.different" boolean DEFAULT true, strict boolean DEFAULT false) RETURNS SETOF bitstamp.spread
    LANGUAGE plpgsql STABLE
    AS $$

-- ARGUMENTS
--		"start.time" - the start of the interval for the calculation of spreads
--		"end.time"	 - the end of the interval
--		"pair"		 - the pair for which spreads will be calculated
--		"only.different"	- whether to output the spread only when it is different from the previous one (true) or after each event (false). true is the default.
--		"strict"		- whether to calculate the spread using events before "start.time" (false) or not (false). 
-- DETAILS
--		If "only.different" is FALSE returns spread after each event or several events that happened simultaneously (i.e. have the same microtimestamp)
--		If "only.different" is TRUE then will check whether the spread has changed and will not return if not.

DECLARE
	cur bitstamp.spread;
	prev bitstamp.spread;
	cur_event_time timestamp with time zone;
	ob bitstamp.order_book[];
	e bitstamp.live_orders;
	v_pair_id smallint;
BEGIN
	IF spread_after_event."strict" THEN 
		ob := '{}';	-- only the events within the ["start.time", "end.time"] interval will be used
	ELSE
		ob := NULL;
	END IF;
	
	SELECT pair_id INTO v_pair_id
	FROM bitstamp.pairs WHERE pairs.pair = p_pair;

	cur_event_time := NULL;
											 
	FOR e IN SELECT live_orders.* FROM bitstamp.live_orders 
			  WHERE microtimestamp BETWEEN spread_after_event."start.time" AND spread_after_event."end.time" 
			    AND pair_id = v_pair_id
			  ORDER BY microtimestamp, order_id LOOP
													 
		IF COALESCE(cur_event_time, e.microtimestamp) = e.microtimestamp THEN 
			
			IF ob IS NULL THEN 
				ob := ARRAY(SELECT bitstamp.order_book_v(e.microtimestamp, "only.makers" := FALSE, neighborhood := 'before'));
				prev := bitstamp._spread_from_order_book(ob);
				IF prev IS NULL THEN -- ob was empty
					prev := ROW(NULL, NULL, NULL, NULL, cur_event_time, v_pair_id);	-- the widest spread - see IF below
				END IF;
			END IF;
														 
			ob := bitstamp._order_book_after_event(ob, e, "only.makers" := FALSE);
		ELSE
			cur := bitstamp._spread_from_order_book(ob);	

			IF cur IS NULL THEN -- ob was empty
				cur := ROW(NULL, NULL, NULL, NULL, cur_event_time, v_pair_id);
			END IF;

			IF  (cur.best_bid_price IS DISTINCT FROM  prev.best_bid_price OR 
				cur.best_bid_qty IS DISTINCT FROM  prev.best_bid_qty OR
				cur.best_ask_price IS DISTINCT FROM  prev.best_ask_price OR
				cur.best_ask_qty IS DISTINCT FROM  prev.best_ask_qty ) 
				OR NOT spread_after_event."only.different" THEN
				prev := cur;
				RETURN NEXT cur;
			END IF;
														 
			ob := bitstamp._order_book_after_event(ob, e, "only.makers" := FALSE);
														 
		END IF;
		cur_event_time := e.microtimestamp;
	END LOOP;
														 
	-- we have to process the last event in the loop above ... so exactly the same code as in ELSE	 
	cur := bitstamp._spread_from_order_book(ob);	

	IF cur IS NULL THEN -- ob was empty
		cur := ROW(NULL, NULL, NULL, NULL, cur_event_time, v_pair_id);
	END IF;

	IF  (cur.best_bid_price IS DISTINCT FROM  prev.best_bid_price OR 
		cur.best_bid_qty IS DISTINCT FROM  prev.best_bid_qty OR
		cur.best_ask_price IS DISTINCT FROM  prev.best_ask_price OR
		cur.best_ask_qty IS DISTINCT FROM  prev.best_ask_qty ) 
		OR NOT spread_after_event."only.different" THEN
		prev := cur;
		RETURN NEXT cur;
	END IF;

	ob := bitstamp._order_book_after_event(ob, e, "only.makers" := FALSE);
														 
														 
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.spread_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, p_pair text, "only.different" boolean, strict boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION spread_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, p_pair text, "only.different" boolean, strict boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.spread_after_event("start.time" timestamp with time zone, "end.time" timestamp with time zone, p_pair text, "only.different" boolean, strict boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each event in the ''live_orders'' table that hits the interval between "start.time" and "end.time" for the given "pair". The spread is calculated using all available data before "start.time" unless "strict" is set to TRUE. In the latter case the spread is caclulated using only events within the interval between "start.time" and "end.time"';


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
-- Name: live_orders a_incorporate_new_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER a_incorporate_new_event BEFORE INSERT ON bitstamp.live_orders FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_orders_incorporate_new_event();


--
-- Name: live_trades a_match_event; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER a_match_event BEFORE INSERT ON bitstamp.live_trades FOR EACH ROW EXECUTE PROCEDURE bitstamp.live_trades_match();


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
-- Name: live_orders live_orders_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: live_trades live_trades_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

