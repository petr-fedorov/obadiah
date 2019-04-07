--
-- PostgreSQL database dump
--

-- Dumped from database version 11.2
-- Dumped by pg_dump version 11.2

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
-- Name: side; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.side AS ENUM (
    'ask',
    'bid'
);


ALTER TYPE bitstamp.side OWNER TO "ob-analytics";

--
-- Name: depth_record; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.depth_record AS (
	price numeric,
	volume numeric,
	side bitstamp.side
);


ALTER TYPE bitstamp.depth_record OWNER TO "ob-analytics";

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
-- Name: momentary_price; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.momentary_price AS (
	microtimestamp timestamp with time zone,
	pair_id smallint,
	price numeric
);


ALTER TYPE bitstamp.momentary_price OWNER TO "ob-analytics";

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
-- Name: _create_or_extend_draw(bitstamp.momentary_price[], timestamp with time zone, numeric, smallint, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._create_or_extend_draw(p_draw bitstamp.momentary_price[], p_microtimestamp timestamp with time zone, p_price numeric, p_pair smallint, p_minimal_draw numeric) RETURNS bitstamp.momentary_price[]
    LANGUAGE plpgsql
    AS $$
declare 
	ONE_BPS constant numeric := 0.0001;	-- one BASIS POINT (see https://www.investopedia.com/ask/answers/what-basis-point-bps/)
begin 
	p_minimal_draw := p_minimal_draw*ONE_BPS;
	if p_draw is null then	
		-- p_draw[1] - the current draw start
		-- p_draw[2] - the latest turning point (see below)
		-- p_draw[3] - the current draw end
		p_draw := array[row(p_microtimestamp, p_pair, p_price), row(p_microtimestamp, p_pair, p_price), row(p_microtimestamp, p_pair, p_price)];
	else
		-- The turning point helps us to decide whether the current draw is to be extended or a new draw is to be started
		if p_draw[2].price = p_price then 										-- extend the draw, keep the turning point
			p_draw[3] := row(p_microtimestamp, p_pair, p_price);
		else
			if ( (p_draw[2].price >= p_draw[1].price and p_price > p_draw[2].price) or 	-- extend the draw, set the new turning point
			    (p_draw[2].price <= p_draw[1].price and p_price < p_draw[2].price) 	)  then 
					p_draw[2] := row(p_microtimestamp, p_pair, p_price);
					p_draw[3] := row(p_microtimestamp, p_pair, p_price);
			else	-- check whether the current draw ended and new draw is to be started
				if abs(p_draw[2].price - p_draw[1].price)>= p_draw[1].price*p_minimal_draw then -- the current draw has exceeded the minimal draw so check the turning (next) draw  ...
					if abs(p_price - p_draw[2].price)>= p_draw[2].price*p_minimal_draw then -- the turn after the curent draw exceeded  the minmal draw too so start new draw FROM THE TURNING POINT (i.e. in the past)
						p_draw := array[p_draw[2], row(p_microtimestamp, p_pair, p_price)::bitstamp.momentary_price, row(p_microtimestamp, p_pair, p_price)::bitstamp.momentary_price];
					else	-- not yet, extend the turning draw from the turning point
						p_draw[3] := row(p_microtimestamp, p_pair, p_price);
					end if;
				else
					p_draw[2] := row(p_microtimestamp, p_pair, p_price);
					p_draw[3] := row(p_microtimestamp, p_pair, p_price);
				end if;
			end if;
		end if;
	end if;
	return p_draw;
end;
$$;


ALTER FUNCTION bitstamp._create_or_extend_draw(p_draw bitstamp.momentary_price[], p_microtimestamp timestamp with time zone, p_price numeric, p_pair smallint, p_minimal_draw numeric) OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: depth; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.depth (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    depth_change bitstamp.depth_record[] NOT NULL
);


ALTER TABLE bitstamp.depth OWNER TO "ob-analytics";

--
-- Name: _depth_after_depth_change(bitstamp.depth, bitstamp.depth, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._depth_after_depth_change(p_depth bitstamp.depth, p_depth_change bitstamp.depth, p_strict boolean) RETURNS bitstamp.depth
    LANGUAGE plpgsql
    AS $$
begin 
	if p_depth is null then
		if p_strict then
			p_depth := row(p_depth_change.microtimestamp, p_depth_change.pair_id, '{}');
		else
			p_depth := row(p_depth_change.microtimestamp,
						   p_depth_change.pair_id, 
						   array(	select row(price, 
												sum(amount),
												case direction 
													when 'buy' then 'bid'::text
													when 'sell' then 'ask'::text
												end
											 )::bitstamp.depth_record
									 from bitstamp.order_book( p_depth_change.microtimestamp, 
															    p_depth_change.pair_id,
															    p_only_makers := true,
															    p_before := true)
								     where is_maker 
								     group by ts, price, direction, pair_id
						  ));
		end if;
	end if;
	return row(p_depth_change.microtimestamp, 
			    p_depth_change.pair_id,
			    array(
					select row(price, volume, side)::bitstamp.depth_record
					from (
						select coalesce(d.price, c.price) as price, coalesce(c.volume, d.volume) as volume, coalesce(d.side, c.side) as side
						from unnest(p_depth.depth_change) d full join unnest(p_depth_change.depth_change) c using (price, side)
					) a
					where volume <> 0
				)
			  );
end;
$$;


ALTER FUNCTION bitstamp._depth_after_depth_change(p_depth bitstamp.depth, p_depth_change bitstamp.depth, p_strict boolean) OWNER TO "ob-analytics";

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
-- Name: _oba_events_with_id(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._oba_events_with_id(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) RETURNS TABLE(event_id bigint, microtimestamp timestamp with time zone, order_id bigint, event_no smallint, event bitstamp.live_orders_event, order_type bitstamp.direction, price numeric, amount numeric, fill numeric, trade_id bigint, pair_id smallint, datetime timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$

with active_events as (
	select live_orders.*
	from bitstamp.live_orders join bitstamp.pairs using (pair_id) 
	where microtimestamp between p_start_time and p_end_time
	  and pairs.pair = p_pair
	union -- not all !
	select live_orders.*
	from bitstamp.order_book_after(p_start_time, p_pair, p_only_makers := false)
		  join bitstamp.live_orders using (microtimestamp, order_id, event_no)
)
select row_number() over (order by order_id, amount desc, event, microtimestamp ) as event_id,
		microtimestamp, order_id,event_no,event,order_type,price, amount, fill, trade_id, pair_id,
		price_microtimestamp as datetime
from active_events
where not (amount = 0 and event = 'order_created')	

$$;


ALTER FUNCTION bitstamp._oba_events_with_id(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

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
    amount numeric,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no smallint,
    trade_id bigint,
    orig_microtimestamp timestamp with time zone,
    pair_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    datetime timestamp with time zone NOT NULL,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no smallint,
    CONSTRAINT created_is_matchless CHECK (((event <> 'order_created'::bitstamp.live_orders_event) OR ((event = 'order_created'::bitstamp.live_orders_event) AND (trade_id IS NULL)))),
    CONSTRAINT minus_infinity CHECK (((event <> 'order_deleted'::bitstamp.live_orders_event) OR (next_microtimestamp = '-infinity'::timestamp with time zone))),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT price_is_positive CHECK ((price > (0)::numeric))
)
PARTITION BY LIST (order_type);


ALTER TABLE bitstamp.live_orders OWNER TO "ob-analytics";

--
-- Name: _order_book_after_event(bitstamp.order_book_record[], bitstamp.live_orders[], boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp._order_book_after_event(p_ob bitstamp.order_book_record[], p_ep bitstamp.live_orders[], p_strict boolean DEFAULT true) RETURNS bitstamp.order_book_record[]
    LANGUAGE plpgsql STABLE
    AS $$
begin
	if p_ob is null and not p_strict then
		p_ob := array( select order_book from bitstamp.order_book(p_ep[1].microtimestamp, p_ep[1].pair_id, p_only_makers := false, p_before := true ));
	end if;
	
	return ( with mix as (
						select ob.*, false as is_deleted
						from unnest(p_ob) ob
						union all
						select microtimestamp, price,amount,order_type,order_id,microtimestamp,event_no,pair_id,TRUE, price_microtimestamp, event = 'order_deleted' 
						from unnest(p_ep)
					),
					latest_events as (
						select distinct on (order_id) *
						from mix
						order by order_id, event_no desc	-- just take the latest event_no for each order
					),
					orders as (
					select p_ep[1].microtimestamp AS ts, price, amount, direction, order_id,
							microtimestamp,event_no, pair_id,
							coalesce(
								case direction
									-- below 'datetime' is actually 'price_microtimestamp'
									when 'buy' then price < min(price) filter (where direction = 'sell' and amount > 0 ) over (order by datetime, microtimestamp)
									when 'sell' then price > max(price) filter (where direction = 'buy' and amount > 0 ) over (order by datetime, microtimestamp)
								end,
							true) -- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
							as is_maker,
							datetime
					from latest_events
					where not is_deleted
				)
				select array(
					select orders::bitstamp.order_book_record
					from orders
					order by microtimestamp, order_id, event_no 
				)
		);
end;   

$$;


ALTER FUNCTION bitstamp._order_book_after_event(p_ob bitstamp.order_book_record[], p_ep bitstamp.live_orders[], p_strict boolean) OWNER TO "ob-analytics";

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

CREATE FUNCTION bitstamp._spread_from_order_book(p_s bitstamp.order_book_record[]) RETURNS bitstamp.spread
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
		FROM unnest(p_s)
		WHERE is_maker
		GROUP BY pair_id, ts, direction, price
	)
	SELECT b.price, b.qty, s.price, s.qty, COALESCE(b.ts, s.ts), pair_id
	FROM (SELECT * FROM price_levels WHERE direction = 'buy' AND is_best) b FULL JOIN (SELECT * FROM price_levels WHERE direction = 'sell' AND is_best) s USING (pair_id);

$$;


ALTER FUNCTION bitstamp._spread_from_order_book(p_s bitstamp.order_book_record[]) OWNER TO "ob-analytics";

--
-- Name: capture_transient_orders(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.capture_transient_orders(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$

DECLARE 

	v_tolerance numeric;
	v_pair_id smallint;
	v_execution_start_time timestamp with time zone;

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
				COALESCE(lead(microtimestamp) OVER o, case event when 'order_deleted' then '-infinity'::timestamptz else 'infinity'::timestamptz end) AS next_microtimestamp,
				CASE WHEN lead(microtimestamp) OVER o IS NOT NULL THEN row_number() OVER o + 1 ELSE NULL END AS next_event_no
		FROM deleted
		WINDOW o AS (PARTITION BY order_id ORDER BY microtimestamp)
		
	)
	INSERT INTO bitstamp.live_orders (order_id, amount, "event", order_type, datetime, microtimestamp, local_timestamp, pair_id, price,
									 	event_no, fill, next_microtimestamp, next_event_no, price_microtimestamp, price_event_no)
	SELECT order_id, amount, event, order_type, datetime, microtimestamp, local_timestamp, pair_id, price, 
			CASE first_event WHEN 'order_created' THEN event_no ELSE NULL END AS event_no,
			CASE first_event WHEN 'order_created' THEN fill ELSE NULL END AS fill,
			CASE first_event WHEN 'order_created' THEN next_microtimestamp ELSE NULL END AS next_microtimestamp,									  
			CASE first_event WHEN 'order_created' THEN next_event_no ELSE NULL END AS next_event_no,
			CASE first_event WHEN 'order_created' THEN first_value(microtimestamp) OVER p ELSE NULL END AS price_microtimestamp,
			CASE first_event WHEN 'order_created' THEN first_value(event_no) OVER p ELSE NULL END AS price_event_no
	FROM deleted_with_event_no
	WINDOW p AS (PARTITION BY order_id, price ORDER BY microtimestamp)
	ORDER BY microtimestamp, order_id, event;
	/*  to be uncommented after migration to release 11 where upsert is supported on partitioned tables
		on conflict (order_id, era ) where next_event_no is null do update 
																  set microtimestamp = excluded.microtimestamp,
																  	  local_timestamp = excluded.local_timestamp;*/
	
	RAISE DEBUG 'capture_transient_orders() exec time: %', clock_timestamp() - v_execution_start_time; 
END;

$$;


ALTER FUNCTION bitstamp.capture_transient_orders(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

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
-- Name: capture_transient_trades(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.capture_transient_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_trades
    LANGUAGE sql
    AS $$
WITH deleted AS (
	DELETE FROM bitstamp.transient_live_trades
	using bitstamp.pairs
	where pairs.pair = p_pair 
	  and transient_live_trades.pair_id = pairs.pair_id
	RETURNING transient_live_trades.*
)
INSERT INTO bitstamp.live_trades (bitstamp_trade_id, amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp, pair_id)
SELECT 	bitstamp_trade_id, amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, local_timestamp, pair_id
FROM deleted
ORDER BY bitstamp_trade_id
on conflict on constraint live_trades_unique_order_ids_combination 
	do 	update 
		set bitstamp_trade_id = excluded.bitstamp_trade_id, 
			amount = excluded.amount,
			price = excluded.price,
			trade_type = excluded.trade_type, 
			trade_timestamp = excluded.trade_timestamp,
			local_timestamp = excluded.local_timestamp
RETURNING live_trades.*;

$$;


ALTER FUNCTION bitstamp.capture_transient_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: crossed_books(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) RETURNS TABLE(previous_uncrossed timestamp with time zone, next_uncrossed timestamp with time zone, pair_id smallint)
    LANGUAGE sql STABLE
    AS $$

with base_order_books as (
	select ob[1].ts, ob[1].pair_id, exists (select * from unnest(ob) where not is_maker) as is_crossed
	from  bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, false) ob
),
order_books as (
	select ts,  pair_id, is_crossed, 
	coalesce(max(ts) filter (where not is_crossed) over (order by ts), p_start_time - '00:00:00.000001'::interval ) as previous_uncrossed,
	min(ts) filter (where not is_crossed) over (order by ts desc) as next_uncrossed
	from base_order_books 
)
select distinct previous_uncrossed, next_uncrossed, pair_id
from order_books
where is_crossed
;  
$$;


ALTER FUNCTION bitstamp.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: depth_change_after_episode(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.depth_change_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.depth
    LANGUAGE plpgsql STABLE
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of depths
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which depths will be calculated
--		p_strict		- whether to calculate the depth using events before p_start_time (false) or not (false). 
declare
	v_ob_before bitstamp.order_book_record[];
	v_ob bitstamp.order_book_record[];
begin
	
	for v_ob in select ob from bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, p_strict) ob 
	loop
		if v_ob_before is not null then 
			return query 
				select v_ob[1].ts, v_ob[1].pair_id, array_agg(d.d)
				from (
					select row(price, coalesce(af.amount, 0), direction)::bitstamp.depth_record as d
					from (
						select a.price, 
								sum(a.amount) as amount,
								case a.direction 
									when 'buy' then 'bid'::bitstamp.side 
									when 'sell' then 'ask'::bitstamp.side 
								end as direction
						from unnest(v_ob_before) a 
						where a.is_maker 
						group by a.price, a.direction, a.pair_id
					) bf full join (
						select a.price,
								sum(a.amount) as amount,
								case a.direction 
									when 'buy' then 'bid'::bitstamp.side 
									when 'sell' then 'ask'::bitstamp.side 
								end as direction
						from unnest(v_ob) a 
						where a.is_maker 
						group by a.price, a.direction, a.pair_id
					) af using (price, direction)
					where bf.amount is distinct from af.amount
				) d;
		end if;
		v_ob_before := v_ob;
	end loop;			
end;

$$;


ALTER FUNCTION bitstamp.depth_change_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: draws_from_spread(timestamp with time zone, timestamp with time zone, text, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.draws_from_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_minimal_draw numeric DEFAULT 0.0) RETURNS TABLE(start_microtimestamp timestamp with time zone, end_microtimestamp timestamp with time zone, last_microtimestamp timestamp with time zone, start_price numeric, end_price numeric, last_price numeric, pair_id smallint, draw_type text, draw_size numeric, minimal_draw numeric, pair text)
    LANGUAGE sql STABLE
    AS $$ 
with time_range as (
	select pair_id, era, p_start_time as period_start, case when era_end < p_end_time then era_end else p_end_time end as period_end
	from (
		select era, coalesce( lead(era) over (order by era), 'infinity') as era_end, pair_id
		from bitstamp.live_orders_eras join bitstamp.pairs using (pair_id)
		where pairs.pair = p_pair
	) tr
	where p_start_time between era and era_end 
),
spread as (
	select microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id 
	from bitstamp.spread join time_range using (pair_id)
	where microtimestamp between period_start and period_end
	union all
	select p_start_time as microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id  
	from (
		select microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id
		from bitstamp.spread join time_range using (pair_id)
		where microtimestamp between era and period_start
		order by microtimestamp desc
		limit 1
	) first_draw_start
	union all
	select p_end_time as microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id  
	from (
		select microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id
		from bitstamp.spread join time_range using (pair_id)
		where microtimestamp <= p_end_time
		order by microtimestamp desc
		limit 1
	) last_draw_end
),
base_draws as (
	select spread.*,
			bitstamp.draw_agg(microtimestamp, best_bid_price, pair_id,  p_minimal_draw) over w as draw, 
			'bid'::text as draw_type
	from spread
	window w as (order by microtimestamp)
	union all
	select spread.*,
			bitstamp.draw_agg(microtimestamp, best_ask_price, pair_id,  p_minimal_draw) over w as draw,
			'ask'::text as draw_type
	from spread
	window w as (order by microtimestamp)
	
),
draws as (
	select draw[1].microtimestamp as start_microtimestamp, 
			draw[1].price as start_price, 
			draw[2].microtimestamp as end_microtimestamp,
			draw[2].price as end_price,
			draw[3].microtimestamp as last_microtimestamp,
			draw[3].price as last_price,
			draw_type,
			pair_id
	from base_draws
)
select distinct on (start_microtimestamp, draw_type )
					 start_microtimestamp, 
					 last_value(end_microtimestamp) over w as end_microtimestamp,
					 last_microtimestamp,
					 start_price, 
					 last_value(end_price) over w as end_price,
					 last_price,
					 pair_id,
					 draw_type,
					 round((end_price - start_price)/start_price * 10000.0, 2),
					 p_minimal_draw,
					 p_pair
from draws
window w as ( partition by start_microtimestamp, draw_type order by end_microtimestamp )
order by draw_type, start_microtimestamp, end_microtimestamp desc, last_microtimestamp desc	

$$;


ALTER FUNCTION bitstamp.draws_from_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_minimal_draw numeric) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_eternal_orders(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_eternal_orders(ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$

DECLARE
	v_execution_start_time timestamp with time zone;

BEGIN 
	v_execution_start_time := clock_timestamp();
	RETURN QUERY  WITH time_range AS (
						SELECT *
						FROM (
							SELECT pairs.pair_id, era AS "start.time", COALESCE(lead(era) OVER (partition by pair_id ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS "end.time"
							FROM bitstamp.live_orders_eras join bitstamp.pairs using (pair_id)
							where pairs.pair = p_pair
						) r
						WHERE find_and_repair_eternal_orders.ts_within_era BETWEEN r."start.time" AND r."end.time"
					),
					eternal_orders AS (
						SELECT live_orders.*
						FROM bitstamp.live_orders join time_range using (pair_id)
						WHERE microtimestamp BETWEEN "start.time" AND "end.time"
						  AND event <> 'order_deleted'
						  AND next_microtimestamp = 'Infinity'::timestamptz
					),
					filled_orders AS (
						SELECT live_orders.*
						FROM bitstamp.live_orders  join time_range using (pair_id)
						WHERE microtimestamp BETWEEN "start.time" AND "end.time"
						  AND fill > 0
					)
					INSERT INTO bitstamp.live_orders (order_id, amount, event, order_type, datetime, microtimestamp,local_timestamp,pair_id,
													 price, fill, next_microtimestamp)
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
							NULL::timestamptz
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


ALTER FUNCTION bitstamp.find_and_repair_eternal_orders(ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: find_and_repair_missing_fill(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.find_and_repair_missing_fill(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
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
			SELECT era AS era_starts,
					COALESCE(lead(era) OVER (ORDER BY era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) AS era_ends,
					pair_id
			FROM bitstamp.live_orders_eras join bitstamp.pairs using (pair_id)
			where pairs.pair = p_pair
		) r
		WHERE p_ts_within_era BETWEEN r.era_starts AND r.era_ends
	),
	events_fill_missing AS (
		SELECT o.microtimestamp,
				o.order_id,
				o.event_no,
				o.amount,			
				t.amount AS fill					-- fill is equal to the matched trade's amount
		FROM bitstamp.live_orders o join time_range using (pair_id) JOIN bitstamp.live_trades t USING (trade_id) 
		WHERE microtimestamp BETWEEN era_starts and era_ends
		  AND fill IS NULL
	),
	base AS (
		SELECT microtimestamp, order_id, event_no, amount, fill
		FROM events_fill_missing
		UNION ALL 
		SELECT live_orders.microtimestamp, live_orders.order_id, live_orders.event_no, base.amount + base.fill AS amount, 
				CASE live_orders.event_no WHEN 1 THEN -(base.amount + base.fill) ELSE live_orders.fill END AS fill
		FROM bitstamp.live_orders join time_range using (pair_id) JOIN base ON live_orders.order_id = base.order_id
		 and live_orders.microtimestamp between era_starts and era_ends
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


ALTER FUNCTION bitstamp.find_and_repair_missing_fill(p_ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: fix_aggressor_creation_order(timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.fix_aggressor_creation_order(p_ts_within_era timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

declare

	v_execution_start_time timestamp with time zone;
	v_repeat boolean;
begin 
	v_execution_start_time := clock_timestamp();
	loop 
		v_repeat := false;
		
		return query 
			with time_range as (
				select  *
					from (
						select era as start_time, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) as end_time,
								pair_id
						from bitstamp.live_orders_eras join bitstamp.pairs using (pair_id)
						where pairs.pair = p_pair
					) r
				where p_ts_within_era between r.start_time and r.end_time
				),
				trades_with_episode as (
					select sell_microtimestamp as r_microtimestamp, sell_order_id as r_order_id, sell_event_no as r_event_no,
							buy_microtimestamp as a_microtimestamp, buy_order_id as a_order_id, buy_event_no as a_event_no,
							live_buy_orders.price_microtimestamp as episode_microtimestamp, live_buy_orders.price_event_no as episode_event_no, 
							trade_type
					from bitstamp.live_trades join time_range using (pair_id) 
							join bitstamp.live_buy_orders on buy_microtimestamp = microtimestamp and buy_order_id = order_id and buy_event_no = event_no 
					where trade_timestamp between start_time and end_time
					  and trade_type = 'buy'
					union all
					select buy_microtimestamp as r_microtimestamp, buy_order_id as r_order_id, buy_event_no as r_event_no,
							sell_microtimestamp as a_microtimestamp, sell_order_id as a_order_id, sell_event_no as a_event_no,
							live_sell_orders.price_microtimestamp, live_sell_orders.price_event_no, 
							trade_type
					from bitstamp.live_trades join time_range using (pair_id) 
							join bitstamp.live_sell_orders on sell_microtimestamp = microtimestamp and sell_order_id = order_id and sell_event_no = event_no 
					WHERE trade_timestamp between start_time and end_time
					  and trade_type = 'sell'						
				),
				proposed_episodes as (
					select a_microtimestamp as microtimestamp, a_order_id as order_id, a_event_no as event_no, episode_microtimestamp, a_order_id as episode_order_id, episode_event_no
					from trades_with_episode
					union all
					select r_microtimestamp as microtimestamp, r_order_id as order_id, r_event_no as event_no, episode_microtimestamp,  a_order_id as episode_order_id, episode_event_no
					from trades_with_episode

				),
				adjusted_episodes as (
					select episode_microtimestamp, episode_order_id, episode_event_no, min(new_episode_microtimestamp) as new_episode_microtimestamp
					from (
						select episode_microtimestamp, episode_order_id, episode_event_no, 
								min(episode_microtimestamp) over (partition by order_id order by event_no desc) as new_episode_microtimestamp
						from proposed_episodes
					) a
					where new_episode_microtimestamp < episode_microtimestamp
					group by 1,2,3
				)
				update bitstamp.live_orders
				set microtimestamp = new_episode_microtimestamp
				from adjusted_episodes
				where live_orders.microtimestamp = adjusted_episodes.episode_microtimestamp and live_orders.order_id = adjusted_episodes.episode_order_id and live_orders.event_no = episode_event_no
				returning live_orders.*;
				
		if found then
			v_repeat := true;
		end if;
		
		return query 
		  with time_range as (
				select  *
					from (
						select era as start_time, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'Infinity'::timestamptz ) as end_time,
								pair_id
						from bitstamp.live_orders_eras join bitstamp.pairs using (pair_id)
						where pairs.pair = p_pair
					) r
				where p_ts_within_era between r.start_time and r.end_time
				),
				trades as (
					select t.buy_order_id, t.sell_order_id, t.trade_type, 
							b.price_microtimestamp as buy_price_microtimestamp,
							b.price_event_no as buy_price_event_no,
							s.price_microtimestamp as sell_price_microtimestamp,
							s.price_event_no as sell_price_event_no
					from bitstamp.live_trades t join time_range using (pair_id)
							join bitstamp.live_buy_orders b on buy_microtimestamp = b.microtimestamp and buy_order_id = b.order_id and buy_event_no = b.event_no
							join bitstamp.live_sell_orders s on sell_microtimestamp = s.microtimestamp and sell_order_id = s.order_id and sell_event_no = s.event_no	
					where buy_microtimestamp between start_time and end_time or sell_microtimestamp between start_time and end_time 
				),
				episodes as (
					select sell_price_microtimestamp as episode_microtimestamp, sell_order_id as episode_order_id, sell_price_event_no as episode_event_no, buy_price_microtimestamp as new_episode_microtimestamp 
					from trades
					where trade_type = 'buy' and buy_price_microtimestamp < sell_price_microtimestamp 
					union all 
					select  buy_price_microtimestamp as episode_microtimestamp, buy_order_id as episode_order_id, buy_price_event_no as episode_event_no, sell_price_microtimestamp as new_episode_no 
					from trades
					where trade_type = 'sell' and sell_price_microtimestamp < buy_price_microtimestamp 
				)
				update bitstamp.live_orders
				set microtimestamp = new_episode_microtimestamp
				from episodes
				where microtimestamp = episode_microtimestamp
				  and order_id = episode_order_id
				  and event_no = episode_event_no
				returning live_orders.*;
				
		if found then
			v_repeat := true;
		end if;
		-- We loop until all agressors processed by Bitstamp in wrong order are merged together. A single iteration is able to merge
		-- only one aggressor into the First Aggressor. 
		-- Only after that the second agressor (if any) to be merged  into the First Aggressor will become visible and will be merged
		-- If Bitstamp processed ALL aggressors in wrong order then this loop would merge all of them into one and stop
		if not v_repeat then 
			raise debug 'fix_aggressor_creation_order() exec time: %', clock_timestamp() - v_execution_start_time;
			return;
		end if;
	end loop; 
END;	

$$;


ALTER FUNCTION bitstamp.fix_aggressor_creation_order(p_ts_within_era timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: fix_crossed_book(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.fix_crossed_book(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    AS $$
declare 
	crossed_books record;
	v_execution_start_time timestamp with time zone;
begin
	v_execution_start_time := clock_timestamp();

	for crossed_books in (select * from bitstamp.crossed_books(p_start_time, p_end_time, p_pair) where next_uncrossed is not null) loop
		return query with updated as (
						  update bitstamp.live_orders
							 set	microtimestamp = crossed_books.next_uncrossed	-- just merge all 'crossed' order books into the next uncrossed one 
						  where live_orders.pair_id = crossed_books.pair_id
							and live_orders.microtimestamp > crossed_books.previous_uncrossed
							and live_orders.microtimestamp < crossed_books.next_uncrossed
						  returning live_orders.*
						)
						select *
						from updated;
	end loop;
	raise debug 'fix_crossed_books() exec time: %', clock_timestamp() - v_execution_start_time;	
end;	

$$;


ALTER FUNCTION bitstamp.fix_crossed_book(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

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
				  AND abs( (a.fill - e.fill)*CASE WHEN e.price_microtimestamp < a.price_microtimestamp THEN e.price ELSE a.price END) <= tolerance
				  AND extract(epoch from e.microtimestamp) - extract(epoch from a.microtimestamp) < max_interval
				ORDER BY price, microtimestamp
				LIMIT 1;
			ELSE
				SELECT * INTO trade_part
				FROM unnest(trade_parts) AS a
				WHERE a.order_type  = 'buy'::bitstamp.direction
				  AND abs( (a.fill - e.fill)*CASE WHEN e.price_microtimestamp < a.price_microtimestamp THEN e.price ELSE a.price END) <= tolerance
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
									   
				is_e_agressor := NOT ( e.price_microtimestamp < trade_part.price_microtimestamp OR (e.price_microtimestamp = trade_part.price_microtimestamp AND e.order_id < trade_part.order_id ) );

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
/*	DECLARE
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
	END; */
	RAISE DEBUG 'inferred_trades() exec time: %', clock_timestamp() - v_execution_start_time;	
	RETURN;
END;

$$;


ALTER FUNCTION bitstamp.inferred_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_only_missing boolean, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: live_orders_incorporate_new_event(); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.live_orders_incorporate_new_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	v_era timestamptz;
	v_amount numeric;
	
	v_event bitstamp.live_orders;
	
BEGIN 

	select max(era) into v_era
	from bitstamp.live_orders_eras
	where pair_id = new.pair_id
	  and era <= new.microtimestamp;
	  
	if new.event = 'order_created' then 
	
		update bitstamp.live_orders 
		set microtimestamp = new.microtimestamp,
			local_timestamp = new.local_timestamp
		where microtimestamp >= v_era -- existing order_created's microtimestamp equals either v_era or datetime (in case ex-nihilo was received with datetime > v_era)
		  and  order_id = new.order_id 
		  and order_type = new.order_type 
		  and event = 'order_created'
		returning *
		into v_event;
		
		if found then 
			if v_event.next_microtimestamp < 'infinity'  then	-- does next event exist?
				update bitstamp.live_orders
				set fill = v_event.amount - amount
				where microtimestamp = v_event.next_microtimestamp
				  and order_id = v_event.order_id
				  and event_no = v_event.next_event_no;
			end if;
			return null; -- skip insertion of a duplicated order_created event
		end if;
		
	end if;
	  

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
			WHERE microtimestamp BETWEEN v_era AND NEW.microtimestamp
			  AND order_id = NEW.order_id 
			  and order_type = new.order_type
			  AND next_microtimestamp > NEW.microtimestamp
			RETURNING *
			INTO v_event;
			-- amount, next_event_no INTO v_amount, NEW.event_no;
			
			IF FOUND THEN 
				NEW.fill := v_event.amount - NEW.amount; 
				NEW.event_no := v_event.next_event_no;
				
				IF v_event.price = NEW.price THEN 
					NEW.price_microtimestamp := v_event.price_microtimestamp;
					NEW.price_event_no := v_event.price_event_no;
				ELSE	-- currently, it's an instant-type order (Bitstamp changes its price on its own)
					NEW.price_microtimestamp := NEW.microtimestamp;
					NEW.price_event_no := NEW.event_no;
				END IF;
				
			ELSE -- it is ex-nihilo 'order_changed' or 'order_deleted' event

				NEW.fill := NULL;	-- we still don't know fill (yet). Can later try to figure it out from trade. amount will be null too
				-- INSERT the initial 'order_created' event when missing
				NEW.price_microtimestamp := CASE WHEN NEW.datetime < v_era THEN v_era ELSE NEW.datetime END;
				NEW.price_event_no := 1;
				NEW.event_no := 2;

				INSERT INTO bitstamp.live_orders (order_id, amount, event, event_no, order_type, datetime, microtimestamp, 
												  pair_id, price, fill, next_microtimestamp, next_event_no,
												  price_microtimestamp, price_event_no )
				VALUES (NEW.order_id, NEW.amount, 'order_created'::bitstamp.live_orders_event, NEW.price_event_no, NEW.order_type,
						NEW.datetime, NEW.price_microtimestamp, 
						NEW.pair_id, NEW.price, -NEW.amount, NEW.microtimestamp, NEW.event_no, NEW.price_microtimestamp, 
					   NEW.price_event_no);
			
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
					  AND ( trade_id IS NULL OR trade_id = NEW.trade_id )
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
					  AND ( trade_id IS NULL OR trade_id = NEW.trade_id )
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
-- Name: match_trades_to_sequential_events(timestamp with time zone, timestamp with time zone, text, numeric, integer); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.match_trades_to_sequential_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_tolerance_percentage numeric DEFAULT 0.0001, p_offset integer DEFAULT 1) RETURNS SETOF bitstamp.live_trades
    LANGUAGE sql
    AS $$
	with  unmatched_trades as (
			select *  
		    from bitstamp.live_trades join bitstamp.pairs using (pair_id)
			where trade_timestamp between p_start_time and p_end_time  
			  and buy_microtimestamp is null 
			  and sell_microtimestamp is null
		      and pairs.pair = p_pair
		), 
		events as (
			select microtimestamp, order_id, event_no, amount, fill, order_type, price_microtimestamp, event,
					n_microtimestamp, n_order_id, n_event_no, n_amount, n_fill, n_order_type, n_price_microtimestamp, n_event
			from (
				select microtimestamp, order_id, event_no, amount, event, fill, order_type, price_microtimestamp, trade_id,
						lead(microtimestamp, p_offset) over m as n_microtimestamp, 
						lead(order_id, p_offset) over m as n_order_id,
						lead(event_no, p_offset) over m as n_event_no, 
						lead(amount, p_offset) over m as n_amount, 
						lead(event, p_offset) over m as n_event, 
						lead(fill, p_offset) over m as n_fill,
						lead(order_type, p_offset) over m as n_order_type,
						lead(price_microtimestamp, p_offset) over m as n_price_microtimestamp,
						lead(trade_id, p_offset) over m as n_trade_id
				from bitstamp.live_orders join bitstamp.pairs using (pair_id)
				where microtimestamp between p_start_time and p_end_time
				  and pairs.pair = p_pair
				window m as (order by microtimestamp)
			) a
			where order_type <> n_order_type
			  and trade_id is null 
			  and n_trade_id is null
			  and event <> 'order_created'
			  and n_event <> 'order_created'
		),
		proposed_matches as (
			select trade_id, trade_type,  unmatched_trades.amount,  price_microtimestamp, microtimestamp, order_id, event_no, order_type, fill,
					n_price_microtimestamp,   n_microtimestamp,  n_order_id, n_event_no, n_order_type, n_fill,
					bitstamp._get_match_rule(unmatched_trades.amount, unmatched_trades.price, events.amount, events.fill, events.event, p_tolerance_percentage* unmatched_trades.price) as mr,
					bitstamp._get_match_rule(unmatched_trades.amount, unmatched_trades.price, events.n_amount, events.n_fill, events.n_event, p_tolerance_percentage* unmatched_trades.price) as n_mr
			from events join unmatched_trades on (order_id = buy_order_id and n_order_id = sell_order_id) or (n_order_id = buy_order_id and order_id = sell_order_id) 
			where bitstamp._get_match_rule(unmatched_trades.amount, unmatched_trades.price, events.amount, events.fill, events.event, p_tolerance_percentage* unmatched_trades.price) is not null 
			  and bitstamp._get_match_rule(unmatched_trades.amount, unmatched_trades.price, events.n_amount, events.n_fill, events.n_event, p_tolerance_percentage* unmatched_trades.price) is not null					
			  and case trade_type 
					when 'buy' then 
						case order_type 
							when 'buy' then	price_microtimestamp > n_price_microtimestamp
							when 'sell' then price_microtimestamp < n_price_microtimestamp
						end
					when 'sell' then 
						case order_type 
							when 'sell' then price_microtimestamp > n_price_microtimestamp
							when 'buy' then	price_microtimestamp < n_price_microtimestamp
						end
					end 
		),
		matches as (
			select *
			from proposed_matches o
			where not exists (select 	-- a single event may not participate in two trades
								from proposed_matches i 
								where o.order_id = i.n_order_id and o.event_no = i.n_event_no )
		)
/*				select bitstamp_trade_id, live_trades.amount, price, live_trades.trade_type, trade_timestamp, buy_order_id, sell_order_id, 
				local_timestamp, pair_id, 
				case order_type when 'sell' then microtimestamp else n_microtimestamp end,
				case order_type when 'buy' then microtimestamp else n_microtimestamp end,
				case order_type when 'buy' then mr else n_mr end,
				case order_type when 'sell' then mr else n_mr end, 
				case order_type when 'buy' then event_no else n_event_no end,
				case order_type when 'sell' then event_no else n_event_no end,
				trade_id, orig_trade_type
		from bitstamp.live_trades join matches using (trade_id);*/
		update bitstamp.live_trades
		set buy_microtimestamp = case order_type when 'buy' then microtimestamp else n_microtimestamp end,
			buy_event_no = case order_type when 'buy' then event_no else n_event_no end,
			buy_match_rule = case order_type when 'buy' then mr else n_mr end,
			sell_microtimestamp = case order_type when 'sell' then microtimestamp else n_microtimestamp end,
			sell_event_no = case order_type when 'sell' then event_no else n_event_no end,
			sell_match_rule = case order_type when 'sell' then mr else n_mr end
		from matches
		where live_trades.trade_id = matches.trade_id
		returning live_trades.*;
$$;


ALTER FUNCTION bitstamp.match_trades_to_sequential_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_tolerance_percentage numeric, p_offset integer) OWNER TO "ob-analytics";

--
-- Name: move_events(timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.move_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE sql
    AS $$
with chains as (
	select live_orders.*,
			first_value(next_microtimestamp) over (partition by order_id 
												   	 order by microtimestamp desc, event_no desc -- two events may have the same microtimestam => order by event_no is essential
												  ) < p_end_time and
	        not bool_or( buy_microtimestamp is distinct from sell_microtimestamp ) over (partition by order_id )
			as is_completed
	from bitstamp.live_orders left join bitstamp.live_trades on microtimestamp = buy_microtimestamp and order_id = buy_order_id and event_no = buy_event_no 
	where live_orders.pair_id = p_pair_id
	  and order_type = 'buy'
	  and microtimestamp between p_start_time and p_end_time 
	union all
	select live_orders.*, 
			first_value(next_microtimestamp) over (partition by order_id 
												     order by microtimestamp desc, event_no desc -- two events may have the same microtimestam => order by event_no is essential
												  ) < p_end_time and
	        not bool_or( buy_microtimestamp is distinct from sell_microtimestamp ) over (partition by order_id ) as is_completed
	from bitstamp.live_orders left join bitstamp.live_trades on microtimestamp = sell_microtimestamp and order_id = sell_order_id and event_no = sell_event_no 
	where live_orders.pair_id = p_pair_id
	  and order_type = 'sell'
	  and microtimestamp between p_start_time and p_end_time 
),
deleted as (
	delete from bitstamp.live_orders o
	using chains
	where o.microtimestamp = chains.microtimestamp
	  and o.order_id = chains.order_id
	  and o.event_no = chains.event_no
	  and is_completed
	returning o.*, chains.is_completed
),
to_be_inserted as (
	select *
	from deleted
	union all
	select * 
	from chains
	where not is_completed
)
insert into obanalytics.level3_bitstamp ( microtimestamp, order_id, event_no, side, price, amount, fill,
								  next_microtimestamp, next_event_no, pair_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp)
select microtimestamp, order_id, event_no, case order_type when 'buy' then 'b'::character(1) when 'sell' then 's' end, price, amount, fill, 
		case when next_microtimestamp <= p_end_time then next_microtimestamp else 'infinity' end, 
		case when next_microtimestamp <= p_end_time then next_event_no else null end, 
		pair_id, local_timestamp, price_microtimestamp, price_event_no, orig_microtimestamp
from to_be_inserted
order by microtimestamp
on conflict (pair_id, side, microtimestamp, order_id, event_no) do update 
																	 set next_microtimestamp = excluded.next_microtimestamp, 
																		  next_event_no = excluded.next_event_no
																	 where level3_bitstamp.next_event_no is null
																	   and excluded.next_event_no is not null
returning *;

$$;


ALTER FUNCTION bitstamp.move_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer) OWNER TO "ob-analytics";

--
-- Name: move_trades(timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.move_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer) RETURNS SETOF obanalytics.matches
    LANGUAGE sql
    AS $$
with deleted as (
	delete from bitstamp.live_trades
	where pair_id = p_pair_id
	  and buy_microtimestamp = sell_microtimestamp	-- incorrectly matched trades, if any,  will stay in bitstamp.live_trades
	  and buy_microtimestamp between p_start_time and p_end_time
	returning live_trades.*
)
insert into obanalytics.matches_bitstamp (amount, price, side, microtimestamp, buy_order_id, buy_event_no,
										 sell_order_id, sell_event_no, buy_match_rule, sell_match_rule, 
										 local_timestamp, pair_id, exchange_side, exchange_trade_id, 
										 exchange_microtimestamp)
select amount, price, case trade_type when 'buy' then 'b'::character(1) when 'sell' then 's' end, buy_microtimestamp, buy_order_id, buy_event_no,
		sell_order_id, sell_event_no, buy_match_rule, sell_match_rule, local_timestamp, pair_id,
		case trade_type when 'buy' then 'b'::character(1) when 'sell' then 's' else null end as exchange_side, bitstamp_trade_id,
		case when bitstamp_trade_id is not null then trade_timestamp else null end
from deleted
order by buy_microtimestamp
returning matches_bitstamp.*;
$$;


ALTER FUNCTION bitstamp.move_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer) OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying DEFAULT 'BTCUSD'::character varying, p_strict boolean DEFAULT false) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE
    AS $$

	with time_range as (
		select (select pair_id from bitstamp.pairs where pair = p_pair) as pair_id, min(microtimestamp) as start_time
		from bitstamp.depth 
		where microtimestamp >= p_start_time
		  and pair_id = (select pair_id from bitstamp.pairs where pair = p_pair)
	)
	select ts, price, amount, side
	from time_range 
		join lateral (
				select ts,
						pair_id,
						price, 
						sum(amount) as amount,
						case direction 
							when 'buy' then 'bid'::text
							when 'sell' then 'ask'::text
						end as side
				from bitstamp.order_book(start_time, pair_id, p_only_makers := true, p_before := true)
				where is_maker 
				group by ts, price, direction, pair_id
		) a using (pair_id)
	where not p_strict or (p_strict and ts >= p_start_time)
	union all 
	select microtimestamp, price, volume, side::text
	from bitstamp.depth join time_range using (pair_id) join lateral ( select price, volume, side from unnest(depth.depth_change) ) d on true
	where microtimestamp between start_time and p_end_time 
	  and depth.pair_id = (select pair_id from bitstamp.pairs where pair = p_pair )
	  and microtimestamp >= p_start_time -- otherwise, the query optimizer produces a crazy plan!
	  and price is not null;   -- null might happen if an aggressor order_created event is not part of an episode, i.e. dirty data.
	  							-- But plotPriceLevels will fail if price is null, so we need to exclude such rows.
								-- 'not null' constraint is to be added to price and depth_change columns of bitstamp.depth table. Then this check
								-- will be redundant

/*	with depth as (
		select 	microtimestamp, pair_id, depth, lag(depth) over (partition by pair_id order by microtimestamp) as prev_depth
		from (select ob[1].ts as microtimestamp,
			  		  ob[1].pair_id as pair_id, 
			  		  array( select row(a.price, sum(a.amount),
						  	  		  case a.direction when 'buy' then 'bid'::bitstamp.side when 'sell' then 'ask'::bitstamp.side end)::bitstamp.depth_record
							  from unnest(ob) a 
							  where a.is_maker 
							  group by a.price, a.direction, a.pair_id
							  order by a.direction, a.price desc
							) as depth
			   from bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, p_strict) ob
			  ) a
	)
	select microtimestamp as "timestamp", a.price, a.volume, a.side::text
	from depth join lateral (select side, price, coalesce(c.volume, 0) as volume
								from unnest(depth) c full join unnest(prev_depth) p using (side, price) 
								where c.volume is distinct from p.volume ) a on true 
*/

$$;


ALTER FUNCTION bitstamp.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, character varying, boolean, numeric); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair character varying DEFAULT 'BTCUSD'::character varying, p_strict boolean DEFAULT false, p_bps_step numeric DEFAULT 25) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level bigint)
    LANGUAGE sql STABLE
    AS $$

with
depth as (
	select microtimestamp as ts, pair_id, (unnest((d).depth_change)).*
	from (
		select depth.microtimestamp, pair_id, bitstamp.depth_agg(depth, p_strict) over (order by microtimestamp) as d
		from bitstamp.depth  join bitstamp.pairs using (pair_id)
		where microtimestamp between p_start_time and  p_end_time 
		  and pairs.pair = p_pair
	) a 
	),
	depth_with_best_prices as (
		select min(price) filter(where side = 'ask') over (partition by ts) as best_ask_price, 
				max(price) filter(where side = 'bid') over (partition by ts) as best_bid_price, 
				ts, price, volume as amount, side, pair_id
		from depth
),
depth_with_bps_levels as (
	select ts, 
			amount, 
			price,
			side,
			case side
				when 'ask' then ceiling((price-best_ask_price)/best_ask_price/p_bps_step*10000)::bigint
				when 'bid' then ceiling((best_bid_price - price)/best_bid_price/p_bps_step*10000)::bigint
			end as bps_level,
			best_ask_price,
			best_bid_price,
			pair_id
	from depth_with_best_prices
),
depth_with_price_adjusted as (
	select ts,
			amount,
			case side
				when 'ask' then round(best_ask_price*(1 + bps_level*p_bps_step/10000), pairs."R0")
				when 'bid' then round(best_bid_price*(1 - bps_level*p_bps_step/10000), pairs."R0") 
			end as price,
			side,
			bps_level,
			rank() over (partition by bitstamp._in_milliseconds(ts) order by ts desc) as r
	from depth_with_bps_levels join bitstamp.pairs using (pair_id)
)
select ts, 
		price, 
		sum(amount) as volume, 
		side::text, 
		bps_level*p_bps_step::bigint
from depth_with_price_adjusted
where r = 1	-- if rounded to milliseconds ts are not unique, we'll take the LasT one and will drop the first silently
			 -- this is a workaround for the inability of R to handle microseconds in POSIXct 
group by 1, 2, 4, 5

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
	  spread_before AS (
		  SELECT lead(microtimestamp) over (order by microtimestamp) as microtimestamp, 
		  		  best_ask_price, best_bid_price
		  from bitstamp.spread join bitstamp.pairs using (pair_id)
		  where microtimestamp between p_start_time and p_end_time 
		    and pairs.pair = p_pair
		  ),
	  events_after as (
		  select microtimestamp, price, amount, order_type, order_id, event, datetime, fill, trade_id,
		  		  min(price) filter (where is_maker and order_type = 'sell') over (partition by microtimestamp) as best_ask_price,
		  		  max(price) filter (where is_maker and order_type = 'buy') over (partition by microtimestamp) as best_bid_price,
		  		  not is_maker as is_aggressor,
		  		  event_no
		  from (
			  select   microtimestamp,
						ob.price,
						ob.amount,
						direction as order_type,
						order_id,
			  			event,
						ob.datetime,
			  			fill,
			  			trade_id,
			  			event_no,
			  			is_maker
			  from bitstamp.order_book_after(p_start_time, p_pair, p_only_makers := false) ob 
			  		join bitstamp.live_orders using (microtimestamp, order_id, event_no)
			) a
	  ),
	  base_events AS (
		  SELECT event_id,
		  		  microtimestamp,
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
		  		  END AS is_aggressor,		  
		  		  event_no
		  from bitstamp._oba_events_with_id(p_start_time, p_end_time, p_pair) left join spread_before using(microtimestamp) 
	  ),
	  events AS (
		SELECT base_events.*,
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
-- Name: oba_export(timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS TABLE(id bigint, "timestamp" text, "exchange.timestamp" text, price numeric, volume numeric, action text, direction text)
    LANGUAGE sql STABLE
    AS $$
select order_id,
		bitstamp._in_milliseconds(microtimestamp),
		bitstamp._in_milliseconds(datetime),
		price,
		round(amount,8),
		case event
		  when 'order_created' then 'created'::text
		  when 'order_changed' then 'changed'::text
		  when 'order_deleted' then 'deleted'::text
		end,
		case order_type
		  when 'buy' then 'bid'::text
		  when 'sell' then 'ask'::text
		end
from bitstamp._oba_events_with_id(p_start_time, p_end_time, p_pair)
  
$$;


ALTER FUNCTION bitstamp.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, text, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_different boolean DEFAULT true, p_strict boolean DEFAULT false) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--	See bitstamp.spread_by_episode()

	select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
	from bitstamp.spread join bitstamp.pairs using (pair_id)
	where pairs.pair = p_pair
	  and microtimestamp between p_start_time and p_end_time
	union all
	select *
	from (
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, p_start_time
		from bitstamp.spread 
		where pair_id = (select pair_id from bitstamp.pairs where pair = p_pair)
		  and microtimestamp < p_start_time
		order by microtimestamp desc
		limit 1
	) a
	union all
	select *
	from (
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, p_end_time
		from bitstamp.spread
		where pair_id = (select pair_id from bitstamp.pairs where pair = p_pair)
		  and microtimestamp <= p_end_time
		order by microtimestamp desc
		limit 1
	) a
	
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
    LANGUAGE sql STABLE
    AS $$

 WITH trades AS (
		SELECT * 
		FROM bitstamp.live_trades JOIN bitstamp.pairs USING (pair_id)
		WHERE trade_timestamp BETWEEN p_start_time AND p_end_time
	      AND pairs.pair = p_pair
	),
 events as (
	 select *
	 from bitstamp._oba_events_with_id(p_start_time, p_end_time, p_pair) 
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
-- Name: order_book(timestamp with time zone, smallint, boolean, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book(p_ts timestamp with time zone, p_pair_id smallint, p_only_makers boolean, p_before boolean) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	with episode as (
			select microtimestamp as e, pair_id, (select max(era) from bitstamp.live_orders_eras where era <= p_ts and pair_id = p_pair_id ) as s
			from bitstamp.live_orders
			where microtimestamp >= (select max(era) from bitstamp.live_orders_eras where era <= p_ts and pair_id = p_pair_id )
			  and ( microtimestamp < p_ts or ( microtimestamp = p_ts and not p_before ) )
		      and pair_id = p_pair_id
			order by microtimestamp desc
			limit 1
		), 
		orders as (
			select *, 
					coalesce(
						case order_type 
							when 'buy' then price < min(price) filter (where order_type = 'sell' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
							when 'sell' then price > max(price) filter (where order_type = 'buy' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
						end,
					true )	-- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
					as is_maker
			from bitstamp.live_orders join episode using (pair_id)
			where microtimestamp between episode.s and episode.e
			  and next_microtimestamp > episode.e
			  and event <> 'order_deleted'
		)
	select e,
			price,
			amount,
			order_type,
			order_id,
			microtimestamp,
			event_no,
			pair_id,
			is_maker,
			price_microtimestamp 	-- 'datetime' in order_book is actually 'price_microtimestamp'
    from orders
	where is_maker OR NOT p_only_makers
	order by microtimestamp, order_id, event_no;	-- order by must be the same as in spread_after_episode. Change both!

$$;


ALTER FUNCTION bitstamp.order_book(p_ts timestamp with time zone, p_pair_id smallint, p_only_makers boolean, p_before boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_after(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_after(p_ts timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_makers boolean DEFAULT true) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	select order_book.*
	from bitstamp.pairs join bitstamp.order_book(p_ts, pair_id, p_only_makers, p_before := false ) on true
	where pairs.pair = p_pair

$$;


ALTER FUNCTION bitstamp.order_book_after(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_before(timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_before(p_ts timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_only_makers boolean DEFAULT true) RETURNS SETOF bitstamp.order_book_record
    LANGUAGE sql STABLE
    AS $$

	select order_book.*
	from bitstamp.pairs join bitstamp.order_book(p_ts, pair_id, p_only_makers, p_before := true ) on true
	where pairs.pair = p_pair

$$;


ALTER FUNCTION bitstamp.order_book_before(p_ts timestamp with time zone, p_pair text, p_only_makers boolean) OWNER TO "ob-analytics";

--
-- Name: order_book_by_episode(timestamp with time zone, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false) RETURNS SETOF bitstamp.order_book_record[]
    LANGUAGE sql STABLE
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
select bitstamp.order_book_agg(episode, p_strict) over (order by microtimestamp)  as ob
from (
	select microtimestamp, array_agg(live_orders) as episode
	from bitstamp.live_orders 
	where microtimestamp between p_start_time and p_end_time
	  and pair_id = (select pair_id from bitstamp.pairs where pair = p_pair )
	group by microtimestamp  
) a
order by microtimestamp

$$;


ALTER FUNCTION bitstamp.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean) OWNER TO "ob-analytics";

--
-- Name: pga_capture_transient(text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_capture_transient(p_pair text DEFAULT 'BTCUSD'::text) RETURNS void
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
	
	END LOOP;			
	RAISE DEBUG 'pga_process_transient_live_orders() exec time: %', clock_timestamp() - v_execution_start_time;
END;

$$;


ALTER FUNCTION bitstamp.pga_capture_transient(p_pair text) OWNER TO "ob-analytics";

--
-- Name: FUNCTION pga_capture_transient(p_pair text); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.pga_capture_transient(p_pair text) IS 'This function is expected to be run by pgAgent as often as necessary to store order book events from  transient_live_orders table';


--
-- Name: pga_cleanse(text, timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_cleanse(p_pair text DEFAULT 'BTCUSD'::text, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS SETOF bitstamp.live_orders
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_trade bitstamp.live_trades;
	v_trade_id bigint;
	v_pair_id bitstamp.pairs.pair_id%type;
begin 
	v_current_timestamp := current_timestamp;
	
	select pair_id into v_pair_id
	from bitstamp.pairs 
	where pair = p_pair;
	
	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from bitstamp.live_orders_eras 
		where pair_id = v_pair_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from bitstamp.live_orders_eras 
										 where pair_id = v_pair_id ) ) between era_starts and era_ends;

	return query select * from bitstamp.find_and_repair_eternal_orders(v_start, p_pair);																	   
	return query select * from bitstamp.find_and_repair_missing_fill(v_start, p_pair);																	   
	return query select * from bitstamp.fix_aggressor_creation_order(v_start, p_pair);
	return query select * from bitstamp.reveal_episodes(v_start, p_pair);

	-- update microtimestamp of events that couldn't be or shouldn't be matched and which are in the wrong order (i.e. later that its subsequent event)
	declare 
		nothing_updated boolean default false;
		rows_processed integer;
	begin		
		loop
			
			return query with upd as (
					update bitstamp.live_orders
					set microtimestamp = next_microtimestamp
					where microtimestamp between v_start and v_end
					  and ( fill > 0 or fill is null )
					  and trade_id is null	-- this event should has been matched to some trade but couldn't
					  and next_microtimestamp > '-infinity'
					  and next_microtimestamp < microtimestamp
					  and pair_id = v_pair_id
					returning * 
					)
					select * from upd;	-- workaround of bug: live_orders is a partitioned table 
			get diagnostics rows_processed := row_count;
			if found then
				raise debug 'pga_cleanse(%) moved backwards (to earlier next_mcirotimestamp)  %', p_pair, rows_processed;
			else
				exit;
			end if;
		end loop;
		
		loop
			return query 
				with to_be_moved_forward as (
					select *
					from (
						select microtimestamp, order_id, event_no, max(microtimestamp) over (partition by order_id order by event_no) as max_microtimestamp
						from bitstamp.live_orders
						where microtimestamp between v_start and v_end
						  and pair_id = v_pair_id
					) a 
					where microtimestamp < max_microtimestamp 
				),
				upd as (
					update bitstamp.live_orders
					set microtimestamp = max_microtimestamp
					from to_be_moved_forward
					where live_orders.microtimestamp between v_start and v_end
					  and trade_id is null	-- this event should has been matched to some trade but couldn't
					  and live_orders.microtimestamp = to_be_moved_forward.microtimestamp
					  and live_orders.order_id = to_be_moved_forward.order_id
					  and live_orders.event_no = to_be_moved_forward.event_no
					  and pair_id = v_pair_id
					returning live_orders.*
				)
				select * from upd; -- workaround of bug: live_orders is a partitioned table 
			get diagnostics rows_processed := row_count;			  
			if found then
				raise debug 'pga_cleanse(%) moved forward (to max_microtimestamap)  %', p_pair,  rows_processed;
			else
				exit;
			end if;
		end loop;														   
	end;
	if (select count(*)
		from (
			select *, min(microtimestamp) over (partition by order_id order by event_no desc) as min_microtimestamp
			from bitstamp.live_orders
			where microtimestamp between v_start and v_end
			  and pair_id = v_pair_id
		) a 
		where microtimestamp > min_microtimestamp 
		) > 0 then
		raise exception 'An inconsistent event orderding would be created for era %, exiting ...', v_start;
	end if;
	
	return query select * from bitstamp.fix_crossed_book(v_start, v_end, p_pair);
	
	return;
end;

$$;


ALTER FUNCTION bitstamp.pga_cleanse(p_pair text, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: pga_depth(text, interval, timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_depth(p_pair text DEFAULT 'BTCUSD'::text, p_max_interval interval DEFAULT '04:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_last_depth timestamptz;
	v_pair_id bitstamp.pairs.pair_id%type;

	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into v_pair_id
	from bitstamp.pairs 
	where pair = p_pair;
	
	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from bitstamp.live_orders_eras 
		where pair_id = v_pair_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from bitstamp.live_orders_eras 
										 where pair_id = v_pair_id ) ) between era_starts and era_ends;
	select coalesce(max(microtimestamp), v_start) into v_last_depth
	from bitstamp.depth join bitstamp.pairs using (pair_id)
	where microtimestamp between v_start and v_end
	  and pair_id = v_pair_id;
	
	-- delete the latest depth because it could be calculated using incomplete data
	
	delete from bitstamp.depth
	where microtimestamp = v_last_depth
	  and pair_id = v_pair_id;
	  
	if v_end > v_last_depth + p_max_interval then
		v_end := v_last_depth + p_max_interval;
	end if;
	
	raise debug 'pga_depth(): from: %  till: %', v_last_depth, v_end;
	  
	insert into bitstamp.depth (microtimestamp, pair_id, depth_change)
	select microtimestamp, pair_id, coalesce(depth_change, '{}')
	from bitstamp.depth_change_after_episode(v_last_depth, v_end, p_pair, p_strict := false);
	
	raise debug 'pga_depth() exec time: %', clock_timestamp() - v_current_timestamp;
	
	return;
end;

$$;


ALTER FUNCTION bitstamp.pga_depth(p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: pga_match(text, timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_match(p_pair text DEFAULT 'BTCUSD'::text, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS SETOF bitstamp.live_trades
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_execution_start_time timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_trade bitstamp.live_trades;
	v_trade_id bigint;
	v_tolerance_percentage numeric;
	v_pair_id bitstamp.pairs.pair_id%type;
	
	MAX_OFFSET constant integer := 4;	-- the maximum distance (in terms of events) between considered as caused by one trade
	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into v_pair_id
	from bitstamp.pairs 
	where pair = p_pair;
	
	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from bitstamp.live_orders_eras 
		where pair_id = v_pair_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from bitstamp.live_orders_eras 
										 where pair_id = v_pair_id ) ) between era_starts and era_ends;
										 
	select coalesce(max(microtimestamp), v_start) into v_start	-- let's find the latest matched event. 
	from bitstamp.live_orders
	where microtimestamp between v_start and v_end
	  and pair_id = v_pair_id
	  and trade_id is not null;
	
	v_execution_start_time := clock_timestamp();
	
	for v_trade in select * from bitstamp.inferred_trades(v_start, v_end, p_pair, p_only_missing := true, p_strict := false) loop

		return query update bitstamp.live_trades 
					  set buy_microtimestamp = v_trade.buy_microtimestamp, buy_event_no = v_trade.buy_event_no,
						   sell_microtimestamp = v_trade.sell_microtimestamp, sell_event_no = v_trade.sell_event_no,
						   buy_match_rule = v_trade.buy_match_rule,
						   sell_match_rule = v_trade.sell_match_rule,
						   trade_type = v_trade.trade_type,
						   orig_trade_type = case when v_trade.trade_type <> trade_type then trade_type else null end
					  where buy_order_id = v_trade.buy_order_id 
						and sell_order_id = v_trade.sell_order_id
						and pair_id = v_trade.pair_id
					  returning *;

		if not found then 
			return query insert into bitstamp.live_trades (amount, price, trade_type, trade_timestamp, buy_order_id, sell_order_id, 
									 pair_id, sell_microtimestamp, buy_microtimestamp, buy_match_rule, sell_match_rule, buy_event_no, sell_event_no)
						  values (v_trade.amount, v_trade.price, v_trade.trade_type, v_trade.trade_timestamp, v_trade.buy_order_id, v_trade.sell_order_id,
								  v_trade.pair_id, v_trade.sell_microtimestamp, v_trade.buy_microtimestamp, v_trade.buy_match_rule, v_trade.sell_match_rule,
								  v_trade.buy_event_no, v_trade.sell_event_no)
						  returning *;
		end if;

	end loop;
	
	raise debug 'pga_match() inferred_trades cycle exec time: %', clock_timestamp() - v_execution_start_time;	

	foreach v_tolerance_percentage in array '{0.0001, 0.001, 0.01, 0.1, 1}'::numeric[] loop
		for v_offset in 1..MAX_OFFSET loop
			v_execution_start_time := clock_timestamp();
			return query select * from bitstamp.match_trades_to_sequential_events(v_start, v_end, p_pair, 
																					p_tolerance_percentage := v_tolerance_percentage,
																					p_offset := v_offset);
			raise debug 'pga_match() match_trades_to_sequential events with tolerance: %, offset: %, time: %', v_tolerance_percentage, v_offset,  clock_timestamp() - v_execution_start_time;																						
		end loop;
	end loop; 

	raise debug 'pga_match() exec time: %', clock_timestamp() - v_current_timestamp;		
	return;
end;

$$;


ALTER FUNCTION bitstamp.pga_match(p_pair text, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: pga_spread(text, interval, timestamp with time zone); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_spread(p_pair text DEFAULT 'BTCUSD'::text, p_max_interval interval DEFAULT '04:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS SETOF bitstamp.spread
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_last_spread timestamptz;
	v_pair_id bitstamp.pairs.pair_id%type;
	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into v_pair_id
	from bitstamp.pairs 
	where pair = p_pair;
	
	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from bitstamp.live_orders_eras 
		where pair_id = v_pair_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from bitstamp.live_orders_eras 
										 where pair_id = v_pair_id ) ) between era_starts and era_ends;

	select coalesce(max(microtimestamp), v_start) into v_last_spread
	from bitstamp.spread join bitstamp.pairs using (pair_id)
	where microtimestamp between v_start and v_end
	  and pair_id = v_pair_id;
	  
	if v_end > v_last_spread + p_max_interval then
		v_end := v_last_spread + p_max_interval;
	end if;	  
	
	-- delete the latest spread because it could be calculated using incomplete data
	
	delete from bitstamp.spread
	where microtimestamp = v_last_spread
	  and pair_id = v_pair_id;
	  
	insert into bitstamp.spread (best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id)
    select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id
	from bitstamp.spread_after_episode(v_last_spread, v_end, p_pair,
						   p_strict := false, p_with_order_book := false);
	
	raise debug 'pga_spread() exec time: %', clock_timestamp() - v_current_timestamp;
	
	return;
end;

$$;


ALTER FUNCTION bitstamp.pga_spread(p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: pga_transfer(text, timestamp with time zone, interval, boolean); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.pga_transfer(p_pair text, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone, p_delay interval DEFAULT '00:02:00'::interval, p_remove_era boolean DEFAULT NULL::boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_start timestamptz;
	v_end timestamptz;
	
	v_pair_id smallint;
	
begin 

	select pair_id into strict v_pair_id
	from obanalytics.pairs where pair = upper(p_pair);
	
	with eras as (
		select era, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'infinity'::timestamptz) as next_era
		from bitstamp.live_orders_eras
		where pair_id = v_pair_id
	)
	select era, next_era into strict v_start, v_end
	from eras
	where coalesce(p_ts_within_era, 'infinity'::timestamptz) between era and next_era;
	
	insert into obanalytics.level3_eras (era, pair_id, exchange_id)
	select v_start, v_pair_id, exchange_id
	from obanalytics.exchanges 
	where exchange = 'bitstamp'
	on conflict do nothing;
	
	if v_end = 'infinity'::timestamptz then	-- this is the last known era, so p_delay must be applied ...
		if p_remove_era is null or not p_remove_era then 
			select max(microtimestamp) - p_delay into strict v_end
			from bitstamp.live_orders
			where pair_id = v_pair_id
			  and microtimestamp  >= v_start;

			p_remove_era := false;
		end if;
	else
		p_remove_era := true;
	end if;
	
	raise debug 'v_start: %, v_end: %,  p_remove_era: %', v_start, v_end, p_remove_era;
	
	perform bitstamp.move_events(v_start, v_end, v_pair_id);
	perform bitstamp.move_trades(v_start, v_end, v_pair_id);
	 
	if p_remove_era then
		delete from bitstamp.live_orders_eras
		where pair_id = v_pair_id
		  and era = v_start;
		  
		delete from bitstamp.live_orders
		where pair_id = v_pair_id
		  and microtimestamp between v_start and v_end;
		  
	end if;
 
	return 0;
end;
$$;


ALTER FUNCTION bitstamp.pga_transfer(p_pair text, p_ts_within_era timestamp with time zone, p_delay interval, p_remove_era boolean) OWNER TO "ob-analytics";

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
								price_microtimestamp AS episode_microtimestamp
								-- LEAST(price_microtimestamp, sell_microtimestamp) AS episode_microtimestamp	
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
								price_microtimestamp AS episode_microtimestamp
								-- LEAST(price_microtimestamp, buy_microtimestamp) AS episode_microtimestamp 
								-- See comments above regarding LEAST
						FROM bitstamp.live_trades JOIN time_range USING (pair_id) 
								JOIN bitstamp.live_sell_orders ON sell_microtimestamp = microtimestamp AND sell_order_id = order_id AND sell_event_no = event_no 
						WHERE trade_timestamp BETWEEN start_time AND end_time
						  AND trade_type = 'sell'						
					),
					episodes AS (
						SELECT r_microtimestamp AS microtimestamp, r_order_id AS order_id, r_event_no AS event_no, episode_microtimestamp
						FROM trades_with_created
						UNION ALL
						SELECT a_microtimestamp AS microtimestamp, a_order_id AS order_id, a_event_no AS event_no, episode_microtimestamp
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

CREATE FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text, p_strict boolean DEFAULT false, p_only_different boolean DEFAULT true, p_with_order_book boolean DEFAULT false) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, order_book bitstamp.order_book_record[])
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of spreads
--		p_end_time	 - the end of the interval
--		p_pair		 - the pair for which spreads will be calculated
--		p_strict		- whether to calculate the spread using events before p_start_time (false) or not (false). 

with spread as (
	select (bitstamp._spread_from_order_book(ob)).*, case  when p_with_order_book then ob else null end as ob
	from bitstamp.order_book_by_episode(p_start_time, p_end_time, p_pair, p_strict) ob
)
select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, ob
from (
	select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, ob,
		    lag(best_bid_price) over w as p_best_bid_price, 
			lag(best_bid_qty) over w as p_best_bid_qty,
			lag(best_ask_price) over w as p_best_ask_price,
			lag(best_ask_qty) over w as p_best_ask_qty
	from spread
	window w as (order by microtimestamp)
) a
where microtimestamp is not null 
  and ( not p_only_different 
	   	 or best_bid_price is distinct from p_best_bid_price
	     or best_bid_qty is distinct from p_best_bid_qty
	     or best_ask_price is distinct from p_best_ask_price
	     or best_ask_qty is distinct from p_best_ask_qty
	   )
order by microtimestamp

$$;


ALTER FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean, p_only_different boolean, p_with_order_book boolean) OWNER TO "ob-analytics";

--
-- Name: FUNCTION spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean, p_only_different boolean, p_with_order_book boolean); Type: COMMENT; Schema: bitstamp; Owner: ob-analytics
--

COMMENT ON FUNCTION bitstamp.spread_after_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_strict boolean, p_only_different boolean, p_with_order_book boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each episode in the ''live_orders'' table that hits the interval between p_start_time and p_end_time for the given "pair". The spread is calculated using all available data before p_start_time unless "p_p_strict" is set to true. In the latter case the spread is caclulated using only events within the interval between p_start_time and p_end_time';


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
-- Name: summary(integer, text); Type: FUNCTION; Schema: bitstamp; Owner: ob-analytics
--

CREATE FUNCTION bitstamp.summary(p_limit integer DEFAULT 1, p_pair text DEFAULT NULL::text) RETURNS TABLE(era text, pair_id smallint, pair text, events bigint, e_last text, e_per_sec numeric, e_matched bigint, e_not_m bigint, trades bigint, t_matched bigint, t_not_m bigint, t_bitstamp bigint, spreads bigint, s_last text, depth bigint, d_last text)
    LANGUAGE sql STABLE
    AS $$

with eras as (
		select pair_id as era_pair_id, era as era_start, next_era as era_end
		from bitstamp.pairs join lateral (
			select era, coalesce(lead(era) over (partition by pair_id order by era) - '00:00:00.000001'::interval, 'infinity'::timestamptz) as next_era, pair_id
			from bitstamp.live_orders_eras 
			where pair_id = pairs.pair_id 
			order by era desc
			limit p_limit
		) a using (pair_id)
		where pairs.pair = coalesce(p_pair, pairs.pair)
),
events_stat as (
	select era_start, era_pair_id as pair_id, a.*
	from eras join lateral (	-- lateral works better here than group by - no external sort!
				select  count(*) as events,
						 max(microtimestamp) as last_event,
						 min(microtimestamp) as first_event,
						 count(*) filter (where trade_id is null and fill > 0 ) as unmatched_events,
						 count(*) filter (where trade_id is not null ) as matched_events	 
				from bitstamp.live_orders 
				where pair_id = era_pair_id 
		  		  and microtimestamp between era_start and era_end ) a on true
),
trades_stat as (
	select era_start, pair_id, count(*) as trades, 
			count(*) filter (where buy_microtimestamp is not null and sell_microtimestamp is not null) as fully_matched_trades,
			count(*) filter (where buy_microtimestamp is null and sell_microtimestamp is null) as not_matched_trades,
			count(*) filter (where bitstamp_trade_id is not null) as bitstamp_trades
	from eras join bitstamp.live_trades on pair_id = era_pair_id and buy_microtimestamp between era_start and era_end
	group by pair_id, era_start 
),
spread_stat as (
	select era_start, pair_id, count(*) as spreads, max(microtimestamp) as last_spread
	from eras join bitstamp.spread on pair_id = era_pair_id and microtimestamp between era_start and era_end
	group by pair_id, era_start 
),
depth_stat as (
	select era_start, pair_id, count(*) as depth, max(microtimestamp) as last_depth
	from eras join bitstamp.depth on pair_id = era_pair_id and microtimestamp between era_start and era_end
	group by pair_id, era_start 
)
select era_start::text, pair_id, pair,  
		events, last_event::text, case 
									when extract( epoch from last_event - first_event ) > 0 then round((events/extract( epoch from last_event - first_event ))::numeric,2)
									else 0 end as e_per_sec,
  	  	matched_events, unmatched_events
		,trades,  fully_matched_trades, not_matched_trades, bitstamp_trades
		,spreads, last_spread::text 
		,depth, last_depth::text
from eras 
		join bitstamp.pairs on pair_id = era_pair_id
		left join  events_stat using (era_start, pair_id)
		left join  trades_stat using (era_start, pair_id)
		left join  spread_stat using (era_start, pair_id) 
		left join  depth_stat using (era_start, pair_id) 
;

$$;


ALTER FUNCTION bitstamp.summary(p_limit integer, p_pair text) OWNER TO "ob-analytics";

--
-- Name: depth_agg(bitstamp.depth, boolean); Type: AGGREGATE; Schema: bitstamp; Owner: ob-analytics
--

CREATE AGGREGATE bitstamp.depth_agg(depth_change bitstamp.depth, boolean) (
    SFUNC = bitstamp._depth_after_depth_change,
    STYPE = bitstamp.depth
);


ALTER AGGREGATE bitstamp.depth_agg(depth_change bitstamp.depth, boolean) OWNER TO "ob-analytics";

--
-- Name: draw_agg(timestamp with time zone, numeric, smallint, numeric); Type: AGGREGATE; Schema: bitstamp; Owner: ob-analytics
--

CREATE AGGREGATE bitstamp.draw_agg(microtimestamp timestamp with time zone, price numeric, pair_id smallint, minimal_draw numeric) (
    SFUNC = bitstamp._create_or_extend_draw,
    STYPE = bitstamp.momentary_price[]
);


ALTER AGGREGATE bitstamp.draw_agg(microtimestamp timestamp with time zone, price numeric, pair_id smallint, minimal_draw numeric) OWNER TO "ob-analytics";

--
-- Name: order_book_agg(bitstamp.live_orders[], boolean); Type: AGGREGATE; Schema: bitstamp; Owner: ob-analytics
--

CREATE AGGREGATE bitstamp.order_book_agg(event bitstamp.live_orders[], boolean) (
    SFUNC = bitstamp._order_book_after_event,
    STYPE = bitstamp.order_book_record[]
);


ALTER AGGREGATE bitstamp.order_book_agg(event bitstamp.live_orders[], boolean) OWNER TO "ob-analytics";

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
-- Name: depth depth_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.depth
    ADD CONSTRAINT depth_pkey PRIMARY KEY (microtimestamp, pair_id);


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
-- Name: live_trades live_trades_unique_order_ids_combination; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_trades
    ADD CONSTRAINT live_trades_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


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
-- Name: transient_live_trades transient_live_trades_pkey; Type: CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.transient_live_trades
    ADD CONSTRAINT transient_live_trades_pkey PRIMARY KEY (bitstamp_trade_id);


--
-- Name: depth_idx_pair_selection; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX depth_idx_pair_selection ON bitstamp.depth USING btree (pair_id, microtimestamp);


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
-- Name: live_buy_orders_idx_filled; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_buy_orders_idx_filled ON bitstamp.live_buy_orders USING btree (pair_id, microtimestamp) WHERE (fill > (0)::numeric);


--
-- Name: live_buy_orders_idx_order_created; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_buy_orders_idx_order_created ON bitstamp.live_buy_orders USING btree (order_id, microtimestamp) WHERE (event = 'order_created'::bitstamp.live_orders_event);


--
-- Name: live_buy_orders_idx_pair_selection; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_buy_orders_idx_pair_selection ON bitstamp.live_buy_orders USING btree (pair_id, microtimestamp);


--
-- Name: live_sell_orders_fkey_live_sell_orders_price; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_sell_orders_fkey_live_sell_orders_price ON bitstamp.live_sell_orders USING btree (price_microtimestamp, order_id, price_event_no);


--
-- Name: live_sell_orders_fkey_live_trades_trade_id; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_sell_orders_fkey_live_trades_trade_id ON bitstamp.live_sell_orders USING btree (trade_id);


--
-- Name: live_sell_orders_idx_filled; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_sell_orders_idx_filled ON bitstamp.live_sell_orders USING btree (pair_id, microtimestamp) WHERE (fill > (0)::numeric);


--
-- Name: live_sell_orders_idx_order_created; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE UNIQUE INDEX live_sell_orders_idx_order_created ON bitstamp.live_sell_orders USING btree (order_id, microtimestamp) WHERE (event = 'order_created'::bitstamp.live_orders_event);


--
-- Name: live_sell_orders_idx_pair_selection; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX live_sell_orders_idx_pair_selection ON bitstamp.live_sell_orders USING btree (pair_id, microtimestamp);


--
-- Name: spread_idx_pair_selection; Type: INDEX; Schema: bitstamp; Owner: ob-analytics
--

CREATE INDEX spread_idx_pair_selection ON bitstamp.spread USING btree (pair_id, microtimestamp);


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
-- Name: depth depth_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.depth
    ADD CONSTRAINT depth_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) MATCH FULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


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

