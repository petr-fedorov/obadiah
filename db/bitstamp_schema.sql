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
-- Name: live_orders_event; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.live_orders_event AS ENUM (
    'order_created',
    'order_changed',
    'order_deleted'
);


ALTER TYPE bitstamp.live_orders_event OWNER TO "ob-analytics";

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
	pair_id smallint
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

--
-- Name: spread; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.spread AS (
	best_bid_price numeric,
	best_bid_qty numeric,
	best_ask_price numeric,
	best_ask_qty numeric,
	microtimestamp timestamp with time zone
);


ALTER TYPE bitstamp.spread OWNER TO "ob-analytics";

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
    is_maker boolean DEFAULT true NOT NULL
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
							   	tolerance := 10::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_orders.pair_id )
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
							   tolerance := 10::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_trades.pair_id )
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
							   tolerance := 10::numeric^(SELECT "R0" FROM bitstamp.pairs WHERE pairs.pair_id = live_trades.pair_id )
							  ) IS NOT NULL
  AND sell_microtimestamp IS NULL
ORDER BY trade_id -- we want the earliest one available 
FOR UPDATE;
  

$$;


ALTER FUNCTION bitstamp._trades_match_sell_event(microtimestamp timestamp with time zone, order_id bigint, fill numeric, amount numeric, event bitstamp.live_orders_event, look_around interval) OWNER TO "ob-analytics";

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
	CASE NEW.event 
		WHEN 'order_created', 'order_changed'  THEN 
			NEW.next_microtimestamp := 'infinity'::timestamptz;		-- later than all other timestamps
		WHEN 'order_deleted' THEN 
			NEW.next_microtimestamp := '-infinity'::timestamptz;	-- earlier than all other timestamps
	END CASE;
	
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

	SELECT 10::numeric^"R0" INTO tolerance
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
			NEW.is_maker := NEW.order_type <> t.trade_type;
			
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
			NEW.is_maker := NEW.order_type <> t.trade_type;
			
			EXIT;
		END LOOP;
	END IF;
	
	RETURN NEW;

END;

$$;


ALTER FUNCTION bitstamp.live_orders_match() OWNER TO "ob-analytics";

--
-- Name: live_orders_process_agressor(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_process_agressor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	AGRESSOR_WINDOW CONSTANT interval  := '1 sec'::interval;
BEGIN 

	UPDATE bitstamp.live_orders
	   SET is_maker = FALSE
	WHERE microtimestamp BETWEEN NEW.microtimestamp - AGRESSOR_WINDOW AND NEW.microtimestamp
	  AND order_id = NEW.order_id
	  AND event = 'order_created';
	  
	RETURN NEW;

END;

$$;


ALTER FUNCTION bitstamp.live_orders_process_agressor() OWNER TO "ob-analytics";

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

	SELECT 10::numeric^"R0" INTO tolerance 
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
			trade_timestamp = NEW.trade_timestamp,
			is_maker = e.order_type <> NEW.trade_type
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
			trade_timestamp = NEW.trade_timestamp,
			is_maker = e.order_type <> NEW.trade_type
		WHERE CURRENT OF sell_match;
		
		EXIT;
		
	END LOOP;
	
	RETURN NEW;
 
END;

$$;


ALTER FUNCTION bitstamp.live_trades_match() OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT side text, OUT order_id bigint) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$

DECLARE 
	pair_id smallint;
BEGIN

	SELECT pairs.pair_id INTO pair_id
	FROM bitstamp.pairs 
	WHERE pairs.pair = oba_depth.pair;
	
	RETURN QUERY SELECT microtimestamp AS "timestamp",
						  o.price,
						  CASE WHEN o.event <> 'order_deleted' THEN o.amount ELSE 0.0 END AS volume,
						  CASE WHEN order_type = 'buy' THEN 'bid' ELSE 'ask' END as side,
						  o.order_id
				  FROM  ( SELECT *, min(live_orders.price) OVER o <> max(live_orders.price) OVER o AS pacman
				  		   FROM bitstamp.live_orders
				  		   WHERE microtimestamp BETWEEN ( SELECT MAX(era) 
														 	FROM bitstamp.live_orders_eras 
														    WHERE era <= oba_depth."end.time" ) 
						 								AND oba_depth."end.time"
						   WINDOW o AS (PARTITION BY live_orders.order_id)
						 ) o
				  WHERE NOT pacman 
				  	AND (    ( microtimestamp <= oba_depth."start.time" AND next_microtimestamp > oba_depth."start.time") 
						  OR ( microtimestamp BETWEEN oba_depth."start.time" AND oba_depth."end.time")
					     )
				    AND is_maker;
END;

$$;


ALTER FUNCTION bitstamp.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT side text, OUT order_id bigint) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, "only.different" boolean DEFAULT true) RETURNS SETOF bitstamp.spread
    LANGUAGE sql
    AS $$

SELECT best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
FROM (
	SELECT a.*, lag(best_bid_price) OVER p AS pbp, lag(best_bid_qty) OVER p AS pbq, lag(best_ask_price) OVER p AS pap, lag(best_ask_qty) OVER p AS paq
	FROM (
		SELECT (bitstamp.spread(live_orders.*) OVER (ORDER BY microtimestamp)).*  
		FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
		WHERE microtimestamp BETWEEN oba_spread."start.time" AND oba_spread."end.time" AND pairs.pair = oba_spread.pair
	) a
	WINDOW p AS (ORDER BY microtimestamp)
) b
WHERE best_bid_price <> pbp	OR best_bid_qty <> pbq OR best_ask_price <> pap OR best_ask_qty <> paq OR NOT "only.different"
ORDER BY microtimestamp DESC

$$;


ALTER FUNCTION bitstamp.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, "only.different" boolean) OWNER TO "ob-analytics";

--
-- Name: oba_trades(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text DEFAULT 'BTCUSD'::text, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT direction text, OUT id bigint) RETURNS SETOF record
    LANGUAGE sql
    SET work_mem TO '1GB'
    AS $$

	WITH trades AS (
		SELECT CASE WHEN trade_type = 'sell' THEN COALESCE(buy_microtimestamp, sell_microtimestamp)	  -- trade can be matched partially so will use the available
					  ELSE COALESCE(sell_microtimestamp, buy_microtimestamp) END AS "timestamp",	   --  non-NULL value if the appropriate value is not defined
				live_trades.price,
				live_trades.amount AS volume,
				live_trades.trade_type::text,
				live_trades.trade_id AS id
		FROM bitstamp.live_trades JOIN bitstamp.pairs USING (pair_id)
		WHERE pairs.pair = oba_trades.pair
		  AND ( buy_microtimestamp  BETWEEN oba_trades."start.time" AND oba_trades."end.time"
		        OR sell_microtimestamp BETWEEN oba_trades."start.time" AND oba_trades."end.time"
			   )
	)
	SELECT *
	FROM trades
	WHERE "timestamp" BETWEEN oba_trades."start.time" AND oba_trades."end.time"

$$;


ALTER FUNCTION bitstamp.oba_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair text, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT direction text, OUT id bigint) OWNER TO "ob-analytics";

--
-- Name: order_book_v(timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_v(ts timestamp with time zone) RETURNS SETOF bitstamp.order_book
    LANGUAGE sql
    AS $$

	SELECT order_book_v.ts,
			price,
			amount,
			order_type,
			order_id,
			microtimestamp,
			event,
			pair_id
	FROM bitstamp.live_orders
	WHERE microtimestamp BETWEEN (SELECT MAX(era) FROM bitstamp.live_orders_eras WHERE era <= order_book_v.ts ) AND order_book_v.ts 
	  AND next_microtimestamp > order_book_v.ts 
	  AND event <> 'order_deleted'
	  AND is_maker
	ORDER BY order_type DESC, price DESC;

$$;


ALTER FUNCTION bitstamp.order_book_v(ts timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: spread_ffunc(bitstamp.order_book[]); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_ffunc(s bitstamp.order_book[]) RETURNS bitstamp.spread
    LANGUAGE plpgsql
    AS $$

	
DECLARE 
	
	spread bitstamp.spread;
	
BEGIN
	WITH price_levels AS (
		SELECT ts, direction, price, sum(amount) AS qty, dense_rank() OVER (PARTITION BY direction ORDER BY price*CASE WHEN direction = 'buy' THEN -1 ELSE 1 END ) AS r
		FROM unnest(s)
		GROUP BY ts, direction, price
	)
	SELECT b.price, b.qty, s.price, s.qty, COALESCE(b.ts, s.ts) INTO spread
	FROM (SELECT * FROM price_levels WHERE direction = 'buy' AND r = 1) b FULL JOIN (SELECT * FROM price_levels WHERE direction = 'sell' AND r = 1) s ON TRUE;
	
	RETURN spread;
END;

$$;


ALTER FUNCTION bitstamp.spread_ffunc(s bitstamp.order_book[]) OWNER TO "ob-analytics";

--
-- Name: spread_sfunc(bitstamp.order_book[], bitstamp.live_orders); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.spread_sfunc(s bitstamp.order_book[], v bitstamp.live_orders) RETURNS bitstamp.order_book[]
    LANGUAGE plpgsql
    AS $$

DECLARE

	i bigint;

BEGIN 
	
	IF s IS NULL THEN
		s := ARRAY(SELECT bitstamp.order_book_v(spread_sfunc.v.microtimestamp));
 	ELSE
		IF spread_sfunc.v.event <> 'order_created' THEN 
			s := ARRAY(SELECT  ROW(spread_sfunc.v.microtimestamp,
								s_prev.price,
								s_prev.amount,
								s_prev.direction,
								s_prev.order_id,
								s_prev.microtimestamp,
								s_prev.event_type,
								s_prev.pair_id)
						FROM unnest(s) AS s_prev
						WHERE s_prev.order_id <> spread_sfunc.v.order_id);
		ELSE
			s := ARRAY(SELECT  ROW(spread_sfunc.v.microtimestamp,
								s_prev.price,
								s_prev.amount,
								s_prev.direction,
								s_prev.order_id,
								s_prev.microtimestamp,
								s_prev.event_type,
								s_prev.pair_id)
						FROM unnest(s) AS s_prev
					  );
		END IF;
												
		IF spread_sfunc.v.event <> 'order_deleted' AND spread_sfunc.v.is_maker THEN 
			s := array_append(s, ROW(spread_sfunc.v.microtimestamp, 
									 spread_sfunc.v.price,
									 spread_sfunc.v.amount,
									 spread_sfunc.v.order_type,
									 spread_sfunc.v.order_id,
									 spread_sfunc.v.microtimestamp,
									 spread_sfunc.v.event,
									 spread_sfunc.v.pair_id
									)::bitstamp.order_book);
		END IF;												
	END IF;
	RETURN s;
END;

$$;


ALTER FUNCTION bitstamp.spread_sfunc(s bitstamp.order_book[], v bitstamp.live_orders) OWNER TO "ob-analytics";

--
-- Name: spread(bitstamp.live_orders); Type: AGGREGATE; Schema: bitstamp; Owner: ob-analytics
--

CREATE AGGREGATE bitstamp.spread(bitstamp.live_orders) (
    SFUNC = bitstamp.spread_sfunc,
    STYPE = bitstamp.order_book[],
    FINALFUNC = bitstamp.spread_ffunc
);


ALTER AGGREGATE bitstamp.spread(bitstamp.live_orders) OWNER TO "ob-analytics";

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
-- Name: fki_live_orders_fkey_eras; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX fki_live_orders_fkey_eras ON bitstamp.live_orders USING btree (era);


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
-- Name: live_orders c_process_agressor; Type: TRIGGER; Schema: bitstamp; Owner: ob-analytics
--

CREATE TRIGGER c_process_agressor BEFORE INSERT OR UPDATE ON bitstamp.live_orders FOR EACH ROW WHEN (((NOT new.is_maker) AND (new.event <> 'order_created'::bitstamp.live_orders_event))) EXECUTE PROCEDURE bitstamp.live_orders_process_agressor();


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

