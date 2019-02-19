--
-- PostgreSQL database dump
--

-- Dumped from database version 11.1
-- Dumped by pg_dump version 11.1

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
-- Name: order_type; Type: TYPE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TYPE bitfinex.order_type AS ENUM (
    'hidden',
    'flashed-limit',
    'resting-limit',
    'market',
    'market-limit'
);


ALTER TYPE bitfinex.order_type OWNER TO "ob-analytics";

--
-- Name: raw_event_action; Type: TYPE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TYPE bitfinex.raw_event_action AS ENUM (
    'created',
    'changed',
    'deleted'
);


ALTER TYPE bitfinex.raw_event_action OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: transient_raw_book_events; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_raw_book_events (
    exchange_timestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    pair_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    channel_id integer,
    episode_timestamp timestamp with time zone NOT NULL,
    event_no integer,
    bl integer
);


ALTER TABLE bitfinex.transient_raw_book_events OWNER TO "ob-analytics";

--
-- Name: _diff_order_books(bitfinex.transient_raw_book_events[], bitfinex.transient_raw_book_events[]); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._diff_order_books(p_order_book_before bitfinex.transient_raw_book_events[], p_order_book_after bitfinex.transient_raw_book_events[]) RETURNS bitfinex.transient_raw_book_events[]
    LANGUAGE sql IMMUTABLE
    AS $$
	with ob_before as (
			select *
			from unnest(p_order_book_before) 
		),
		ob_after as (
			select *
			from unnest(p_order_book_after) 
		),
		ts as (
			select distinct episode_timestamp as ts, channel_id	
			from  ob_after
		),
		ob_diff as (
		select coalesce(a.exchange_timestamp, (select ts from ts)) as exchange_timestamp,
				order_id,
				coalesce(a.price, 0), 
				coalesce(a.amount, case when b.amount > 0 then 1 when b.amount < 0 then -1 end), 
				coalesce(a.pair_id, b.pair_id), 
				a.local_timestamp,											-- when the diff event is inferred by us, it will be null
				coalesce(a.channel_id, (select channel_id from ts)),	  -- we need to set properly channel_id for the inferred deletion events too. Otherwise capture_transient_raw..() will miss them
				coalesce(a.episode_timestamp, (select ts from ts)) as episode_timestamp,
				a.event_no as event_no,
				0::integer
		from ob_before b full join ob_after a using (order_id) 
		where  ( a.price is not null and b.price is not null and a.price <> b.price ) or	
				( a.amount is not null and b.amount is not null and a.amount <> b.amount ) or
				( a.price is null and b.price > 0 ) or		-- order has not existed in ob_before, so skip deletion (it has been already deleted)
				( a.price > 0 and b.price is null )		
	)
	select array_agg(ob_diff::bitfinex.transient_raw_book_events order by order_id)	-- order by order_id is for debugging only
	from ob_diff
	;
$$;


ALTER FUNCTION bitfinex._diff_order_books(p_order_book_before bitfinex.transient_raw_book_events[], p_order_book_after bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

--
-- Name: _hidden_order_id(bigint); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._hidden_order_id(id bigint) RETURNS bigint
    LANGUAGE sql STRICT
    AS $$

SELECT ('x'||md5(id::text||'hidden'))::bit(33)::bigint;

$$;


ALTER FUNCTION bitfinex._hidden_order_id(id bigint) OWNER TO "ob-analytics";

--
-- Name: _market_order_id(integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._market_order_id(snapshot_id integer, episode_no integer, mo_id integer) RETURNS bigint
    LANGUAGE sql STRICT
    AS $$

SELECT ('x'||md5(snapshot_id::text||episode_no::text||mo_id::text))::bit(33)::bigint;

$$;


ALTER FUNCTION bitfinex._market_order_id(snapshot_id integer, episode_no integer, mo_id integer) OWNER TO "ob-analytics";

--
-- Name: _revealed_order_id(bigint, bigint); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._revealed_order_id(order_id bigint, reincarnation bigint) RETURNS bigint
    LANGUAGE sql STRICT
    AS $$

SELECT CASE WHEN reincarnation = 0 THEN order_id ELSE ('x'||md5(order_id::text||reincarnation::text||'revealed'))::bit(33)::bigint END;

$$;


ALTER FUNCTION bitfinex._revealed_order_id(order_id bigint, reincarnation bigint) OWNER TO "ob-analytics";

--
-- Name: _update_order_book(bitfinex.transient_raw_book_events[], bitfinex.transient_raw_book_events[]); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._update_order_book(p_order_book bitfinex.transient_raw_book_events[], p_update bitfinex.transient_raw_book_events[]) RETURNS bitfinex.transient_raw_book_events[]
    LANGUAGE sql STABLE
    AS $$
	with ob as (
			select *
			from unnest(p_order_book)
			where price > 0
		), 
		u as (
			select *
			from unnest(p_update)
		),
		order_book as (
		select coalesce(u.exchange_timestamp, ob.exchange_timestamp) as exchange_timestamp,
				order_id,
				coalesce(u.price, ob.price) as price,
				coalesce(u.amount, ob.amount) as amount,
				coalesce(u.pair_id, ob.pair_id) as pair_id,
				coalesce(u.local_timestamp, ob.local_timestamp) as local_timestamp,
				coalesce(u.channel_id, ob.channel_id) as channel_id,
				coalesce(u.episode_timestamp, (select distinct episode_timestamp from u )),
				u.event_no	-- not null only for an update produced from level3 to ensure continuity of event_no's
		from  ob full join  u using (order_id)
	)
	select array_agg(order_book::bitfinex.transient_raw_book_events)
	from order_book
	;
$$;


ALTER FUNCTION bitfinex._update_order_book(p_order_book bitfinex.transient_raw_book_events[], p_update bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

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
    timing character(1) NOT NULL,
    local_timestamp timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


ALTER TABLE bitfinex.bf_spreads OWNER TO "ob-analytics";

--
-- Name: bf_adjust_spread(integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_adjust_spread(snapshot_id integer) RETURNS SETOF bitfinex.bf_spreads
    LANGUAGE plpgsql
    AS $$

BEGIN 
	RETURN QUERY
		UPDATE bitfinex.bf_spreads s
		SET best_bid_price = COALESCE( 
			( 	SELECT min(price)
			 	FROM bitfinex.bf_trades t
			 	WHERE t.snapshot_id = s.snapshot_id
			 	  AND t.episode_no = s.episode_no
			 	  AND t.direction = 'S'
			),
			(	SELECT min(order_price)
			 	FROM bitfinex.bf_order_book_events e
			 	WHERE e.snapshot_id = s.snapshot_id
			   	  AND e.episode_no = s.episode_no
			 	  AND e.event_price = 0
			)
		)
		WHERE s.snapshot_id = bf_adjust_spread.snapshot_id 
		  AND best_bid_qty = 0
		RETURNING *;
		
	RETURN QUERY
		UPDATE bitfinex.bf_spreads s
		SET best_ask_price = COALESCE( 
			( 	SELECT max(price)
			 	FROM bitfinex.bf_trades t
			 	WHERE t.snapshot_id = s.snapshot_id
			 	  AND t.episode_no = s.episode_no
			 	  AND t.direction = 'B'
			),
			(	SELECT max(order_price)
			 	FROM bitfinex.bf_order_book_events e
			 	WHERE e.snapshot_id = s.snapshot_id
			   	  AND e.episode_no = s.episode_no
			 	  AND e.event_price = 0
			)
		)
		WHERE s.snapshot_id = bf_adjust_spread.snapshot_id 
		  AND best_ask_qty = 0
		RETURNING *;
		

END;

$$;


ALTER FUNCTION bitfinex.bf_adjust_spread(snapshot_id integer) OWNER TO "ob-analytics";

--
-- Name: FUNCTION bf_adjust_spread(snapshot_id integer); Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON FUNCTION bitfinex.bf_adjust_spread(snapshot_id integer) IS 'Calculates ''best_bid_price'' and ''best_ask_price'' for those spreads with ''B'' timing where order book is one-sided i.e. bids or asks are competely missing from the order book and the corresponding side of the spread must be estimated from trades or order_book_events themselves';


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
-- Name: bf_infer_agressors(integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_infer_agressors(snapshot_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$

DECLARE 
	MAX_SINGLE_AGRESSOR CONSTANT interval := '0.1 sec'::interval ;	-- the maximum possible interval of time between trades originated by single agressor
	
BEGIN 

	WITH trades_with_market_orders AS (
		SELECT (sum(g::integer) OVER (PARTITION BY a.snapshot_id, episode_no ORDER BY exchange_timestamp))::integer AS mo_id,
			 direction , episode_no, event_no, exchange_timestamp, a.snapshot_id, id, price, qty
		FROM (
			SELECT COALESCE(
				direction !=lag(direction) OVER w 
				OR ( NOT ( episode_no = lag(episode_no) OVER w AND event_no = lag(event_no) OVER w ) -- a trade and the previous one have not been matched to the same event
					 AND ( ( exchange_timestamp - lag(exchange_timestamp) OVER w ) > MAX_SINGLE_AGRESSOR )
				   )
				OR (direction = 'B' AND price < lag(price) OVER w)
				OR (direction = 'S' AND price > lag(price) OVER w)
				, false) AS g, direction , 
			episode_no, exchange_timestamp, bf_trades.snapshot_id, id, price, qty, event_no
			FROM bitfinex.bf_trades
			WHERE bf_trades.snapshot_id = bf_infer_agressors.snapshot_id 
			WINDOW w AS (PARTITION BY bf_trades.snapshot_id, episode_no ORDER BY exchange_timestamp) 
		) a 
	)
	UPDATE bitfinex.bf_trades
	SET	market_order_id = bitfinex._market_order_id(trades_with_market_orders.snapshot_id, trades_with_market_orders.episode_no, mo_id)	
	FROM trades_with_market_orders 
	WHERE trades_with_market_orders.id = bf_trades.id;
												 

END;

$$;


ALTER FUNCTION bitfinex.bf_infer_agressors(snapshot_id integer) OWNER TO "ob-analytics";

--
-- Name: FUNCTION bf_infer_agressors(snapshot_id integer); Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON FUNCTION bitfinex.bf_infer_agressors(snapshot_id integer) IS 'Infers market and market-limit orders from trades ';


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
					COALESCE( max(t.episode_no) OVER (PARTITION BY t.snapshot_id ORDER BY t.exchange_timestamp),
						COALESCE( (	SELECT max(episode_no)
									FROM bitfinex.bf_trades i
									WHERE i.snapshot_id = t.snapshot_id 
									AND i.exchange_timestamp < t.exchange_timestamp
								   ), 0
								 )
					)	AS b_e,
					COALESCE(min(t.episode_no) OVER (PARTITION BY t.snapshot_id ORDER BY t.exchange_timestamp DESC),
							 2147483647 ) AS a_e
			FROM bitfinex.bf_trades t
			WHERE t.snapshot_id = NEW.snapshot_id AND t.exchange_timestamp > NEW.exchange_timestamp - '1 min'::interval
		), 
		between_same_episodes AS (	
			SELECT id, b_e AS episode_no, 4 AS match_rule
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
					FROM (	SELECT 	rank() OVER (PARTITION BY a.snapshot_id, id ORDER BY exchange_timestamp) AS r, 
		    						a.id, 
									a.episode_no, 
									tet
							FROM (
									SELECT *
									FROM admissible_episode_range a JOIN bitfinex.bf_spreads s USING (snapshot_id)
									WHERE not_matched 
								      AND a.b_e <> a.a_e 
									  AND s.timing = 'B'
						  			  AND price BETWEEN s.best_bid_price AND s.best_ask_price 
									  AND s.episode_no BETWEEN b_e AND a_e
								) a JOIN bitfinex.bf_order_book_episodes p USING (snapshot_id, episode_no) 
						        WHERE tet <= exchange_timestamp
						) a
					GROUP BY tet, id
					) a
				)a
		),
		nearest_episode (id, episode_no, p_id, match_rule) AS (
			SELECT *
			FROM (
					SELECT 	id, 
							(	SELECT min(episode_no) 
								FROM unnest(candidate_episodes) episode_no
							), 
							p_id,
						    5 AS match_rule
					FROM nearest_episodes
					ORDER BY tet, id
					LIMIT 1
				) a
			UNION ALL
			SELECT 	ps.id, 
					(	SELECT min(episode_no) 
						FROM unnest(candidate_episodes) episode_no
						WHERE episode_no >= p.episode_no
					), 
					ps.p_id,
				    5 AS match_rule
			FROM nearest_episodes ps JOIN nearest_episode p ON  ps.p_id = p.id
		)
	UPDATE bitfinex.bf_trades t
	SET episode_no = a.episode_no,
		match_rule = a.match_rule
	FROM (
		SELECT id, episode_no, match_rule 
		FROM between_same_episodes
	  	UNION ALL
	  	SELECT id, episode_no, match_rule 
		FROM nearest_episode
	 )
	 a
	WHERE t.snapshot_id = NEW.snapshot_id AND t.episode_no IS NULL AND t.id = a.id;

	RETURN NULL;

END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_episodes_match_trades_to_episodes() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_dress_new_row(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_dress_new_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	R0 bitfinex.bf_pairs."R0"%TYPE;
	e bitfinex.bf_order_book_events%ROWTYPE;
	
BEGIN

	IF NEW.event_price != 0 THEN 

		SELECT bf_pairs."R0" INTO R0 
		FROM bitfinex.bf_pairs JOIN bitfinex.bf_snapshots USING (pair)
		WHERE snapshot_id = NEW.snapshot_id;

		NEW.event_price = round(NEW.event_price, R0);
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
			RAISE WARNING 'Bypassed the removal of order: %  which is not in the order book', NEW.order_id;
			RETURN NULL;
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
			event_no = NEW.event_no,
			match_rule = 1
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
				event_no = NEW.event_no,
				match_rule = 2
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

--
-- Name: bf_snapshots_create_partitions(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_snapshots_create_partitions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	schema_name CONSTANT TEXT := 'bitfinex';
	table_name TEXT;
	s_from	INTEGER;
	s_to   	INTEGER;
	cons_size CONSTANT INTEGER := 100;
	order_size CONSTANT INTEGER := 200;
BEGIN 
	IF NEW.prec <> 'R0' THEN 
		IF NOT EXISTS (	SELECT *
						FROM (
							SELECT regexp_match(relname, '([0-9]+)_([0-9]+)') AS rng
							FROM pg_class 
							WHERE oid::regclass::text LIKE 'bitfinex.bf_cons_book_%'::text
						) r
						WHERE NEW.snapshot_id BETWEEN rng[1]::integer AND rng[2]::integer - 1
					  ) THEN
			s_from := NEW.snapshot_id;
			s_to := s_from + cons_size;
			table_name := 'bf_cons_book_events_' || LPAD(s_from::text,9,'0') || '_' || s_to;
			EXECUTE	'CREATE TABLE ' || schema_name ||'.' ||table_name||' PARTITION OF bitfinex.bf_cons_book_events 
					 FOR VALUES FROM (' ||s_from|| ') TO (' || s_to || ') 
					 WITH (autovacuum_enabled=''true'', autovacuum_vacuum_threshold=''5000'', autovacuum_analyze_threshold=''5000'', autovacuum_analyze_scale_factor=''0.0'', autovacuum_vacuum_scale_factor=''0.0'', autovacuum_vacuum_cost_delay=''0'')';
					
			EXECUTE 'ALTER TABLE ONLY ' || schema_name ||'.' || table_name ||' ADD CONSTRAINT ' ||table_name||'_pkey PRIMARY KEY (snapshot_id, episode_no, event_no);';				
			EXECUTE 'CREATE INDEX ' ||table_name || '_idx_update_next_episode_no ON ' ||schema_name || '.' || table_name || ' USING btree (snapshot_id, price, price_next_episode_no);';
			EXECUTE 'CREATE TRIGGER a_dress_new_row BEFORE INSERT ON ' ||schema_name || '.' || table_name || ' FOR EACH ROW EXECUTE PROCEDURE ' || schema_name || '.bf_cons_book_events_dress_new_row();';
			EXECUTE 'CREATE TRIGGER b_update_next_episode_no BEFORE INSERT ON ' || schema_name || '.' || table_name || ' FOR EACH ROW EXECUTE PROCEDURE '|| schema_name || '.bf_cons_book_events_update_next_episode_no();';
			EXECUTE 'ALTER TABLE ONLY '|| schema_name ||'.' || table_name || ' ADD CONSTRAINT ' ||
						table_name ||'_fkey_bf_cons_book_episodes FOREIGN KEY (snapshot_id, episode_no) REFERENCES ' || schema_name ||'.bf_cons_book_episodes(snapshot_id, episode_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;';
			EXECUTE 'ALTER TABLE ONLY '|| schema_name ||'.' || table_name || ' ADD CONSTRAINT ' ||
						table_name ||'_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES ' || schema_name ||'.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;';
			RAISE NOTICE 'Created partition: %.%', schema_name, table_name;
		END IF;
	ELSE
		IF NOT EXISTS (	SELECT *
						FROM (
							SELECT regexp_match(relname, '([0-9]+)_([0-9]+)') AS rng
							FROM pg_class 
							WHERE oid::regclass::text LIKE 'bitfinex.bf_order_book_%'::text
						) r
						WHERE NEW.snapshot_id BETWEEN rng[1]::integer AND rng[2]::integer - 1
					  ) 
			THEN
			s_from := NEW.snapshot_id;
			s_to := s_from + order_size;
			table_name := 'bf_order_book_events_' || LPAD(s_from::text,9,'0') || '_' || s_to;
			EXECUTE	'CREATE TABLE ' || schema_name ||'.' ||table_name||' PARTITION OF bitfinex.bf_order_book_events 
					 FOR VALUES FROM (' ||s_from|| ') TO (' || s_to || ') 
					 WITH (autovacuum_enabled=''true'', autovacuum_vacuum_threshold=''5000'', autovacuum_analyze_threshold=''5000'', autovacuum_analyze_scale_factor=''0.0'', autovacuum_vacuum_scale_factor=''0.0'', autovacuum_vacuum_cost_delay=''0'')';
					
			EXECUTE 'ALTER TABLE ONLY ' || schema_name ||'.' || table_name ||' ADD CONSTRAINT ' ||table_name||'_pkey PRIMARY KEY (snapshot_id, episode_no, event_no);';				
			EXECUTE 'CREATE INDEX '|| table_name || '_idx_next_active ON ' || schema_name ||'.' || table_name ||' USING btree (snapshot_id, order_next_episode_no, active_episode_no) WHERE (event_price > (0)::numeric);';
			EXECUTE 'CREATE INDEX ' ||table_name || '_idx_update_next_episode_no ON ' ||schema_name || '.' || table_name || ' USING btree (snapshot_id, order_id);';
			EXECUTE 'CREATE TRIGGER a_dress_new_row BEFORE INSERT ON ' ||schema_name || '.' || table_name || ' FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_dress_new_row();';
			EXECUTE 'CREATE TRIGGER b_update_next_episode_no BEFORE INSERT ON ' || schema_name || '.' || table_name || ' FOR EACH ROW EXECUTE PROCEDURE '|| schema_name ||  '.bf_order_book_events_update_next_episode_no();';
			EXECUTE 'CREATE TRIGGER c_match_trades_to_events BEFORE INSERT ON ' || schema_name || '.' || table_name || ' FOR EACH ROW WHEN ((new.event_qty < (0)::numeric)) EXECUTE PROCEDURE '|| schema_name ||'.bf_order_book_events_match_trades_to_events();';
			EXECUTE 'ALTER TABLE ONLY '|| schema_name ||'.' || table_name || ' ADD CONSTRAINT ' ||
						table_name ||'_fkey_bf_order_book_episodes FOREIGN KEY (snapshot_id, episode_no) REFERENCES ' || schema_name ||'.bf_order_book_episodes(snapshot_id, episode_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;';
			EXECUTE 'ALTER TABLE ONLY '|| schema_name ||'.' || table_name || ' ADD CONSTRAINT ' ||
						table_name ||'_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES ' || schema_name ||'.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;';
			RAISE NOTICE 'Created partition: %.%', schema_name, table_name;
		END IF;
	END IF;
	
	RETURN NEW;
	
END;

$$;


ALTER FUNCTION bitfinex.bf_snapshots_create_partitions() OWNER TO "ob-analytics";

--
-- Name: bf_snapshots_v(integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_snapshots_v("limit" integer DEFAULT 5, INOUT snapshot_id integer DEFAULT NULL::integer, OUT prec character, OUT events bigint, OUT trades bigint, OUT matched_to_episode bigint, OUT matched_to_event bigint, OUT starts timestamp with time zone, OUT ends timestamp with time zone, OUT last_episode integer, OUT pair character varying, OUT len smallint) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$

DECLARE
	s RECORD;

BEGIN 

	IF bf_snapshots_v.snapshot_id IS NULL THEN
		SELECT max(bf_snapshots.snapshot_id) INTO snapshot_id
		FROM bitfinex.bf_snapshots;
	END IF;

	FOR s IN 	SELECT * 
				FROM bitfinex.bf_snapshots 
				WHERE bf_snapshots.snapshot_id <= bf_snapshots_v.snapshot_id
				ORDER BY bf_snapshots.snapshot_id DESC
				LIMIT bf_snapshots_v."limit" LOOP
		IF s.prec = 'R0' THEN
			RETURN QUERY	SELECT 	bf_r_snapshots_v.snapshot_id,
									s.prec AS prec,
									bf_r_snapshots_v.events,
									bf_r_snapshots_v.trades,
									bf_r_snapshots_v.matched_to_episode,
									bf_r_snapshots_v.matched_to_event,
									bf_r_snapshots_v.starts,
									bf_r_snapshots_v.ends,
									bf_r_snapshots_v.last_episode,
									bf_r_snapshots_v.pair,
									bf_r_snapshots_v.len
							FROM bitfinex.bf_r_snapshots_v
							WHERE bf_r_snapshots_v.snapshot_id = s.snapshot_id;
		ELSE
			RETURN QUERY	SELECT 	bf_p_snapshots_v.snapshot_id,
									bf_p_snapshots_v.prec,
									bf_p_snapshots_v.events,
									NULL::bigint AS trades,
									NULL::bigint AS matched_to_episode,
									NULL::bigint AS matched_to_event,
									bf_p_snapshots_v.starts,
									bf_p_snapshots_v.ends,
									bf_p_snapshots_v.last_episode,
									bf_p_snapshots_v.pair,
									bf_p_snapshots_v.len
							FROM bitfinex.bf_p_snapshots_v
							WHERE bf_p_snapshots_v.snapshot_id = s.snapshot_id;
		
		END IF;
	END LOOP;				
	RETURN;
END;

$$;


ALTER FUNCTION bitfinex.bf_snapshots_v("limit" integer, INOUT snapshot_id integer, OUT prec character, OUT events bigint, OUT trades bigint, OUT matched_to_episode bigint, OUT matched_to_event bigint, OUT starts timestamp with time zone, OUT ends timestamp with time zone, OUT last_episode integer, OUT pair character varying, OUT len smallint) OWNER TO "ob-analytics";

--
-- Name: bf_spread_after_episode_v(integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_spread_after_episode_v(s_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647) RETURNS SETOF bitfinex.bf_spreads
    LANGUAGE sql STABLE
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
		'A'::char(1),
		clock_timestamp()
FROM 	(SELECT * FROM base WHERE side = 'A' ) asks JOIN 
		(SELECT * FROM base WHERE side = 'B' ) bids USING (snapshot_id, episode_no);

$$;


ALTER FUNCTION bitfinex.bf_spread_after_episode_v(s_id integer, first_episode_no integer, last_episode_no integer) OWNER TO "ob-analytics";

--
-- Name: bf_spread_between_episodes_v(integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_spread_between_episodes_v(s_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647) RETURNS SETOF bitfinex.bf_spreads
    LANGUAGE sql STABLE
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
SELECT 	COALESCE(bids.price, (	SELECT 	MIN(order_price)*0.5	-- the real price is to be calculated manually later on 
							  									-- this price is set to ensure that the spread is wide 
							  									-- enough for matching
							 	FROM 	bitfinex.bf_order_book_events i
							 	WHERE 	i.snapshot_id = asks.snapshot_id 
							  	  AND 	i.episode_no = asks.episode_no
							  	  AND   i.side = 'B'
							      AND 	i.event_price = 0
							 ) 
				)  AS best_bid_price,
		COALESCE(asks.price, (	SELECT 	MAX(order_price)*1.5	-- the real price is to be calculated manually later on 
							 	FROM 	bitfinex.bf_order_book_events i
							 	WHERE 	i.snapshot_id = bids.snapshot_id 
							  	  AND 	i.episode_no = bids.episode_no
							  	  AND   i.side = 'A'
							      AND 	i.event_price = 0
							 ) 
				) AS best_ask_price, 
		COALESCE(bids.qty,0) AS best_bid_qty,
		COALESCE(asks.qty,0) AS best_ask_qty,
		snapshot_id,
		episode_no,
		'B'::char(1),
		clock_timestamp()
FROM 	(SELECT * FROM base WHERE side = 'A' ) asks FULL JOIN 
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
	R0 bitfinex.bf_pairs."R0"%TYPE;
	last_episode bitfinex.bf_trades.episode_no%TYPE;
	trade_episode_no bitfinex.bf_order_book_events.episode_no%TYPE;
	trade_event_no bitfinex.bf_order_book_events.event_no%TYPE;

BEGIN
	SELECT bf_pairs."R0" INTO R0 
	FROM bitfinex.bf_pairs JOIN bitfinex.bf_snapshots USING (pair)
	WHERE snapshot_id = NEW.snapshot_id;

	NEW.price = round(NEW.price, R0);
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
-- Name: capture_transient_raw_book_events(timestamp with time zone, timestamp with time zone, text, interval); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.capture_transient_raw_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_new_era_start_threshold interval DEFAULT '00:00:02'::interval) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    SET work_mem TO '1GB'
    AS $$
declare
	p record;
	v_pair_id smallint;
	v_exchange_id smallint;
	v_last_order_book obanalytics.level3_order_book_record[];
	v_open_orders bitfinex.transient_raw_book_events[];	
	v_era timestamptz;
begin
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = 'bitfinex';

	for p in with channels as (
						select channel_id, episode_timestamp as start_time, 
								coalesce(lead(episode_timestamp) over(partition by pair_id order by episode_timestamp) - '00:00:00.000001'::interval, 
										 'infinity') as end_time
						from bitfinex.transient_raw_book_channels 
						where pair_id = v_pair_id
				)
				select channel_id,
						greatest(start_time, p_start_time) as start_time, 
						least(end_time, p_end_time) as end_time,
						start_time between p_start_time and p_end_time as is_channel_starts
				from channels
				where start_time <= p_end_time
				  and end_time >= p_start_time
				order by 2	-- i.e. output's start_time
				loop
		select array_agg(level3_order_book) into v_last_order_book
		from obanalytics.level3_order_book(p.start_time, 
										   v_pair_id, v_exchange_id,
										   p_only_makers := false,	-- since exchanges sometimes output crossed order books, we'll consider ALL active orders
										   p_before := true);	

		select array_agg(row(microtimestamp, order_id, price,
				case side when 's' then -amount when 'b' then amount end,
				pair_id, null::timestamptz,-1, microtimestamp ,event_no,null::integer)::bitfinex.transient_raw_book_events) 
				into v_open_orders
		from unnest(v_last_order_book);
		if p.is_channel_starts then	
			if v_last_order_book is null or p.start_time - v_last_order_book[1].ts > p_new_era_start_threshold then
				raise log 'Start new era for new channel % because interval % between % and % is greater than threshold %', p.channel_id,  p.start_time -  v_last_order_book[1].ts, p.start_time,  v_last_order_book[1].ts, p_new_era_start_threshold;
				insert into obanalytics.level3_eras (era, pair_id, exchange_id)
				values (p.start_time, v_pair_id, v_exchange_id);
				
				v_open_orders := null;	-- event_no will start from scratch
			else
				raise log 'Continue previous era for new channel % because interval % between % and % is less than threshold %', p.channel_id,  p.start_time -  v_last_order_book[1].ts, p.start_time,  v_last_order_book[1].ts, p_new_era_start_threshold;
				with to_be_replaced as (
					delete from bitfinex.transient_raw_book_events
					where pair_id = v_pair_id
					  and channel_id = p.channel_id
					  and episode_timestamp = p.start_time
					returning *
				),
				base_events as (
					select exchange_timestamp, order_id, round( price, price_precision) as price,
						round(amount, fmu) as amount, pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
					from to_be_replaced join obanalytics.pairs using (pair_id) join bitfinex.latest_symbol_details using (pair_id)
					order by episode_timestamp, order_id, channel_id, pair_id, exchange_timestamp desc, local_timestamp desc
				)
				insert into bitfinex.transient_raw_book_events
				select (d).* 
				from unnest(bitfinex._diff_order_books(v_open_orders, array(select base_events::bitfinex.transient_raw_book_events
																					  	from base_events))) d
				;
			end if;
		else
			raise log 'Continue previous era for old channel %', p.channel_id;
		end if;
		return query 
			with deleted_transient_events as (
				delete from bitfinex.transient_raw_book_events
				where pair_id = v_pair_id
				  and channel_id = p.channel_id
				  and episode_timestamp between p.start_time and p.end_time
				returning *
			),
			base_events as (
				-- takes only the latest event for given order_id within episode. If it is the lonely deletion, level3_incorporate_new_event() will simply drop it
				select distinct on (episode_timestamp, order_id, channel_id, pair_id ) exchange_timestamp, order_id, price, amount,
						pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
				from (
					select exchange_timestamp, order_id, round( price, price_precision) as price,
						round(amount, fmu) as amount, pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
					from deleted_transient_events join obanalytics.pairs using (pair_id) join bitfinex.latest_symbol_details using (pair_id)
				) a
				order by episode_timestamp, order_id, channel_id, pair_id, exchange_timestamp desc, local_timestamp desc
			),
			base_for_insert_level3 as (
				select *
				from base_events
				union all	-- will be empty if the new era starts
				select *
				from unnest(v_open_orders)	
				),
			for_insert_level3 as (
				select episode_timestamp as microtimestamp,
						order_id,
						(coalesce(first_value(event_no) over oe, 1) - 1)::integer + (row_number() over oe)::integer as event_no,
						case when amount < 0 then 's' when amount > 0 then 'b' end as side,
						case when price = 0 then abs(lag(price) over oe) else abs(price) end as  price, 
						case when price = 0 then abs(lag(amount) over oe) else abs(amount) end as amount,
						case when price = 0 then null else abs(amount) - abs(lag(amount) over oe) end as fill, 
						case when price > 0 then coalesce(lead(episode_timestamp) over oe, 'infinity'::timestamptz) when price = 0 then '-infinity'::timestamptz end  as next_microtimestamp,
						case when price > 0 then (coalesce(first_value(event_no) over oe, 1) )::integer + (row_number() over oe)::integer end as next_event_no,
						null::bigint as trade_id,
						pair_id,
						local_timestamp,
						reincarnation_no,
						coalesce((price <> lag(price) over oe and price > 0 )::integer, 1) as is_price_changed,
						channel_id
				from (
					select *, sum(is_resurrected::integer) over o as reincarnation_no 
					from (
						select *, coalesce(lag(price) over o = 0, false) as is_resurrected
						from base_for_insert_level3
						where episode_timestamp <= p_end_time	
						window o as (partition by order_id order by exchange_timestamp, local_timestamp)
					) a
					window o as (partition by order_id order by exchange_timestamp, local_timestamp)
				) a
				window oe as (partition by order_id, reincarnation_no order by exchange_timestamp, local_timestamp)
			)		
			insert into obanalytics.level3_bitfinex (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, 
													 trade_id, pair_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp )
			select microtimestamp, order_id, 
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 
						else event_no end as event_no,	-- event_no MUST be set by BEFORE trigger in order to update the previous event 
					side::character(1), price, amount, 
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else fill end as fill,											-- see the comment for event_no
					next_microtimestamp,
					case when next_microtimestamp = 'infinity' then null else next_event_no end,
					trade_id, pair_id, 
					-- null::smallint as exchange_id, 
					local_timestamp,
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else price_microtimestamp end as price_microtimestamp,			-- see comment for event_no
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else price_event_no end as price_event_no,						-- see comment for event_no
					null::timestamptz
			from (
				select *,
						-- checks that it is not a deletion event, when determining price_microtimestamp & price_event_no
						case when first_value(price)  over op > 0 then 
								first_value(microtimestamp)  over op
							  else 
								null	
						end as price_microtimestamp,	
						case when first_value(price) over op > 0 then 
								first_value(event_no) over op
							  else 
								null	
						end as price_event_no
				from (
					select *, sum(is_price_changed) over (partition by order_id, reincarnation_no order by microtimestamp) as price_group 			-- within an reincarnation of order_id
					from  for_insert_level3
				) a						
				window op as (partition by order_id, reincarnation_no, price_group order by microtimestamp, event_no)
			) a
			where channel_id is distinct from -1 -- i.e. skip channel_id = -1 which represents open orders from level3 table					
			window o as (partition by order_id order by microtimestamp, event_no )   -- if the very first event_no for an order_id in this insert is not 1 then 
			order by microtimestamp, event_no nulls first  							  -- we will set event_no, fill, price_microtimestamp and price event_no to null
			returning *																	-- so level3_incorporate_new_event() will set these fields AND UPDATE PREVIOUS EVENT
			;																			-- nulls first in order by is important! 
	end loop;				
	return;
end;
$$;


ALTER FUNCTION bitfinex.capture_transient_raw_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_new_era_start_threshold interval) OWNER TO "ob-analytics";

--
-- Name: capture_transient_trades(timestamp with time zone, text); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.capture_transient_trades(p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF obanalytics.matches
    LANGUAGE sql
    AS $$
with deleted as (
	delete from bitfinex.transient_trades
	using obanalytics.pairs
	where pairs.pair = upper(p_pair)
	  and transient_trades.pair_id = pairs.pair_id
	  and exchange_timestamp <= p_end_time
	returning transient_trades.*
)
insert into obanalytics.matches_bitfinex (trade_id, amount, price, side, microtimestamp, local_timestamp, pair_id, exchange_trade_id)
select 	trade_id, round(abs(qty), fmu), round(price, price_precision),  case when qty <0 then 's' else 'b' end, exchange_timestamp, local_timestamp, pair_id, id
from deleted join bitfinex.latest_symbol_details using (pair_id) join obanalytics.pairs using (pair_id)
order by exchange_timestamp, id
returning matches_bitfinex.*;

$$;


ALTER FUNCTION bitfinex.capture_transient_trades(p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, character varying, character); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, prec character DEFAULT 'R0'::bpchar, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT side character, OUT snapshot_id integer, OUT episode_no integer) RETURNS SETOF record
    LANGUAGE plpgsql
    SET work_mem TO '8GB'
    AS $_$

DECLARE 
	p numeric;
	
	order_book_episodes CURSOR FOR
			   SELECT 	bf_order_book_episodes.snapshot_id, 
			   			MIN(bf_order_book_episodes.episode_no) AS min_episode_no, 
			   			MAX(bf_order_book_episodes.episode_no) AS max_episode_no
			   FROM bitfinex.bf_order_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
			   WHERE exchange_timestamp BETWEEN "start.time" AND "end.time" 
			     AND bf_snapshots.pair = oba_depth.pair
			   GROUP BY bf_order_book_episodes.snapshot_id;
			   
	cons_book_episodes CURSOR FOR
				SELECT 	bf_cons_book_episodes.snapshot_id, 
						MIN(bf_cons_book_episodes.episode_no) AS min_episode_no, 
						MAX(bf_cons_book_episodes.episode_no) AS max_episode_no
				FROM bitfinex.bf_cons_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
				WHERE bf_snapshots.prec = oba_depth.prec
			     AND exchange_timestamp BETWEEN "start.time" AND "end.time" 
				 AND bf_snapshots.pair = oba_depth.pair
				GROUP BY bf_cons_book_episodes.snapshot_id;	
BEGIN
	EXECUTE format('SELECT 10^(-%I) FROM bitfinex.bf_pairs WHERE pair = $1', prec) INTO p USING  pair;

	FOR rng IN 	order_book_episodes LOOP
		RETURN QUERY 	WITH ob AS (
							SELECT	bf_active_orders_after_episode_v.snapshot_id,
									bf_active_orders_after_episode_v.episode_no,
									exchange_timestamp AS "timestamp",
									CASE	WHEN bf_active_orders_after_episode_v.side = 'A' THEN ceiling(order_price/p)*p
											ELSE floor(order_price/p)*p END AS price,
									bf_active_orders_after_episode_v.side,
									sum(order_qty) AS volume
							FROM bitfinex.bf_active_orders_after_episode_v 
							WHERE bf_active_orders_after_episode_v.snapshot_id = rng.snapshot_id 
							  AND bf_active_orders_after_episode_v.episode_no BETWEEN rng.min_episode_no AND rng.max_episode_no
							GROUP BY 1, 2, 3, 4, 5 ORDER BY 3, 4 DESC
						),
						ob_squared AS (
							SELECT 	a.timestamp,
									a.snapshot_id,
									a.episode_no,
									a.price,
									COALESCE(ob.side, 
											 CASE 	WHEN a.price >= ROUND((MIN(ob.price) FILTER (WHERE ob.side = 'A') OVER w + MAX(ob.price) FILTER (WHERE ob.side = 'B') OVER w)/2,2)
														THEN 'A'::character(1)
													ELSE
														'B'::character(1)
											 END
											) AS side,
									COALESCE(ob.volume, 0.0) AS volume
							FROM (SELECT *
								  FROM (SELECT DISTINCT ob.timestamp, ob.snapshot_id, ob.episode_no
										FROM ob) t CROSS JOIN 
										(SELECT DISTINCT ob.price
										 FROM ob) p 
								 ) a LEFT JOIN ob USING (timestamp, snapshot_id, episode_no,price) 
							WINDOW w AS (PARTITION BY a.timestamp )
						),
						ob_squared_edge_detection AS (
							SELECT *, SUM(ob_squared.volume) OVER (PARTITION BY ob_squared.timestamp, ob_squared.side ORDER BY ob_squared.price*CASE WHEN ob_squared.side = 'A' THEN -1 ELSE 1 END) AS cumsum_from_edge
							FROM ob_squared
						)
						SELECT f.timestamp, f.price, f.volume, f.side, f.snapshot_id, f.episode_no
						FROM ob_squared_edge_detection f
						WHERE cumsum_from_edge > 0 OR prec = 'R0'; 
	END LOOP;
		
	IF prec <> 'R0' THEN
	
		FOR rng IN cons_book_episodes LOOP
		RETURN QUERY 	WITH ob AS (
							SELECT	bf_price_levels_after_episode_v.snapshot_id,
									bf_price_levels_after_episode_v.episode_no,
									exchange_timestamp AS "timestamp",
									CASE	WHEN bf_price_levels_after_episode_v.side = 'A' THEN ceiling(bf_price_levels_after_episode_v.price/p)*p
											ELSE floor(bf_price_levels_after_episode_v.price/p)*p END AS price,
									bf_price_levels_after_episode_v.side,
									sum(bf_price_levels_after_episode_v.qty) AS volume
							FROM bitfinex.bf_price_levels_after_episode_v 
							WHERE bf_price_levels_after_episode_v.snapshot_id = rng.snapshot_id 
							  AND bf_price_levels_after_episode_v.episode_no BETWEEN rng.min_episode_no AND rng.max_episode_no
							GROUP BY 1, 2, 3, 4, 5 ORDER BY 3, 4 DESC
						),
						ob_squared AS (
							SELECT 	a.timestamp,
									a.snapshot_id,
									a.episode_no,
									a.price,
									COALESCE(ob.side, 
											 CASE 	WHEN a.price >= ROUND((MIN(ob.price) FILTER (WHERE ob.side = 'A') OVER w + MAX(ob.price) FILTER (WHERE ob.side = 'B') OVER w)/2,2)
														THEN 'A'::character(1)
													ELSE
														'B'::character(1)
											 END
											) AS side,
									COALESCE(ob.volume, 0.0) AS volume
							FROM (SELECT *
								  FROM (SELECT DISTINCT ob.timestamp, ob.snapshot_id, ob.episode_no
										FROM ob) t CROSS JOIN 
										(SELECT DISTINCT ob.price
										 FROM ob) p 
								 ) a LEFT JOIN ob USING (timestamp, snapshot_id, episode_no,price) 
							WINDOW w AS (PARTITION BY a.timestamp )
						)
						SELECT f.timestamp, f.price, f.volume, f.side, f.snapshot_id, f.episode_no
						FROM ob_squared f;
		END LOOP;	
	
	END IF;
	
	RETURN;
END;

$_$;


ALTER FUNCTION bitfinex.oba_depth("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, prec character, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT side character, OUT snapshot_id integer, OUT episode_no integer) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, character varying, character, numeric); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, prec character DEFAULT 'P1'::character varying, bps_step numeric DEFAULT 25, OUT volume numeric, OUT bps_level integer, OUT bps_price numeric, OUT bps_vwap numeric, OUT direction character varying, OUT "timestamp" timestamp with time zone, OUT snapshot_id integer, OUT episode_no integer) RETURNS SETOF record
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE 

	order_book_episodes CURSOR FOR
			   SELECT 	bf_order_book_episodes.snapshot_id, 
			   			MIN(bf_order_book_episodes.episode_no) AS min_episode_no, 
			   			MAX(bf_order_book_episodes.episode_no) AS max_episode_no
			   FROM bitfinex.bf_order_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
			   WHERE bf_order_book_episodes.exchange_timestamp BETWEEN "start.time" AND "end.time" 
			     AND bf_snapshots.pair = oba_depth_summary.pair
			   GROUP BY bf_order_book_episodes.snapshot_id;
			   
	cons_book_episodes CURSOR FOR
				SELECT 	bf_cons_book_episodes.snapshot_id, 
						MIN(bf_cons_book_episodes.episode_no) AS min_episode_no, 
						MAX(bf_cons_book_episodes.episode_no) AS max_episode_no
				FROM bitfinex.bf_cons_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
				WHERE bf_snapshots.prec = oba_depth_summary.prec
			     AND bf_cons_book_episodes.exchange_timestamp BETWEEN "start.time" AND "end.time" 
				 AND bf_snapshots.pair = oba_depth_summary.pair
				GROUP BY bf_cons_book_episodes.snapshot_id;	
	
BEGIN
	
	IF prec = 'R0' THEN

		FOR rng IN 	order_book_episodes LOOP

			RETURN QUERY
				SELECT  sum(u.order_qty) AS volume,
						u.bps_level,
						u.bps_price,
						round(sum(u.order_qty*u.order_price)/sum(u.order_qty), "R0") AS bps_vwap,
						u.direction,
						u.exchange_timestamp,
						u.snapshot_id,				
						u.episode_no
				FROM (
					SELECT 	r2.order_price,
							r2.order_qty, 
							(oba_depth_summary.bps_step*r2.bps_level)::integer AS bps_level,
							round(r2.best_bid*(1 - r2.bps_level*oba_depth_summary.bps_step/10000), bf_pairs."R0") AS bps_price,
							'bid'::character varying AS direction,
							r2.pair,
							r2.exchange_timestamp,
							r2.episode_no,
							r2.snapshot_id,
							"R0"
					FROM (		
						SELECT 	r1.order_price, 
								r1.order_qty, 
								ceiling((r1.best_bid - r1.order_price)/r1.best_bid/oba_depth_summary.bps_step*10000)::integer AS bps_level,
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
								WHERE bf_active_orders_after_episode_v.snapshot_id = rng.snapshot_id
								  AND bf_active_orders_after_episode_v.episode_no BETWEEN rng.min_episode_no 
																AND rng.max_episode_no
								  AND bitfinex.bf_active_orders_after_episode_v.side = 'B'
								WINDOW w AS (PARTITION BY bf_active_orders_after_episode_v.episode_no ORDER BY order_price DESC)
					) r1
				) r2 JOIN bitfinex.bf_pairs USING (pair)
				UNION ALL
				SELECT 	r2.order_price,
						r2.order_qty, 
						(oba_depth_summary.bps_step*r2.bps_level)::integer AS bps_level,
						round(r2.best_ask*(1 + r2.bps_level*oba_depth_summary.bps_step/10000), bf_pairs."R0") AS bps_price,
						'ask'::character varying AS direction,
						r2.pair,
						r2.exchange_timestamp,
						r2.episode_no,
						r2.snapshot_id,
						"R0"
				FROM (		
					SELECT 	r1.order_price, 
							r1.order_qty, 
							ceiling((r1.order_price-best_ask)/r1.best_ask/oba_depth_summary.bps_step*10000)::integer AS bps_level,
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
							WHERE bf_active_orders_after_episode_v.snapshot_id = rng.snapshot_id
							  AND bf_active_orders_after_episode_v.episode_no BETWEEN rng.min_episode_no 
													AND rng.max_episode_no
							  AND bitfinex.bf_active_orders_after_episode_v.side = 'A'
							WINDOW w AS (PARTITION BY bf_active_orders_after_episode_v.episode_no ORDER BY order_price)
					) r1
				) r2 JOIN bitfinex.bf_pairs USING (pair)
				) u 
				GROUP BY u.pair, u.bps_level, u.bps_price, u.direction, u.exchange_timestamp, u.episode_no, u.snapshot_id, "R0"
				ORDER BY u.episode_no, u.direction, CASE WHEN u.direction = 'ask' THEN 1 ELSE -1 END*u.bps_level DESC;
		END LOOP;
	ELSE
		FOR rng IN cons_book_episodes LOOP

			RETURN QUERY
			SELECT  sum(u.qty) AS volume,
					u.bps_level,
					u.bps_price,
					round(sum(u.qty*u.price)/sum(u.qty), "R0") AS bps_vwap,
					u.direction,
					u.exchange_timestamp,
					u.snapshot_id,
					u.episode_no
			FROM (
				SELECT 	r2.price,
						r2.qty, 
						(oba_depth_summary.bps_step*r2.bps_level)::integer AS bps_level,
						round(r2.best_bid*(1 - r2.bps_level*oba_depth_summary.bps_step/10000), bf_pairs."R0") AS bps_price,
						'bid'::character varying AS direction,
						r2.pair,
						r2.exchange_timestamp,
						r2.episode_no,
						r2.snapshot_id,
						"R0"
				FROM (		
					SELECT 	r1.price, 
							r1.qty, 
							ceiling((r1.best_bid - r1.price)/r1.best_bid/oba_depth_summary.bps_step*10000)::integer AS bps_level,
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
							WHERE bf_price_levels_after_episode_v.snapshot_id = rng.snapshot_id
							  AND bf_price_levels_after_episode_v.episode_no BETWEEN rng.min_episode_no 
															AND rng.max_episode_no
							  AND bf_price_levels_after_episode_v.side = 'B'
							WINDOW w AS (PARTITION BY bf_price_levels_after_episode_v.episode_no ORDER BY price DESC)
				) r1
			) r2 JOIN bitfinex.bf_pairs USING (pair)
			UNION ALL
			SELECT 	r2.price,
					r2.qty, 
					(oba_depth_summary.bps_step*r2.bps_level)::integer AS bps_level,
					round(r2.best_ask*(1 + r2.bps_level*oba_depth_summary.bps_step/10000), bf_pairs."R0") AS bps_price,
					'ask'::character varying AS direction,
					r2.pair,
					r2.exchange_timestamp,
					r2.episode_no,
					r2.snapshot_id,
					"R0"
			FROM (		
				SELECT 	r1.price, 
						r1.qty, 
						ceiling((r1.price-best_ask)/r1.best_ask/oba_depth_summary.bps_step*10000)::integer AS bps_level,
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
						WHERE bf_price_levels_after_episode_v.snapshot_id = rng.snapshot_id
						  AND bf_price_levels_after_episode_v.episode_no BETWEEN rng.min_episode_no 
												AND rng.max_episode_no
						  AND bf_price_levels_after_episode_v.side = 'A'
						WINDOW w AS (PARTITION BY bf_price_levels_after_episode_v.episode_no ORDER BY price)
				) r1
			) r2 JOIN bitfinex.bf_pairs USING (pair)
			) u 
			GROUP BY u.pair, u.bps_level, u.bps_price, u.direction, u.exchange_timestamp, u.episode_no, u.snapshot_id, "R0"
			ORDER BY u.episode_no, u.direction, CASE WHEN u.direction = 'ask' THEN 1 ELSE -1 END*u.bps_level DESC;
		END LOOP;
	END IF;
	RETURN;
END

$$;


ALTER FUNCTION bitfinex.oba_depth_summary("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, prec character, bps_step numeric, OUT volume numeric, OUT bps_level integer, OUT bps_price numeric, OUT bps_vwap numeric, OUT direction character varying, OUT "timestamp" timestamp with time zone, OUT snapshot_id integer, OUT episode_no integer) OWNER TO "ob-analytics";

--
-- Name: oba_events(timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_events("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, OUT "event.id" bigint, OUT id bigint, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT action character varying, OUT direction character varying, OUT type character varying, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint) RETURNS SETOF record
    LANGUAGE plpgsql
    SET work_mem TO '4GB'
    AS $$

DECLARE 

	order_book_episodes CURSOR FOR
			   SELECT 	bf_order_book_episodes.snapshot_id, 
			   			MIN(bf_order_book_episodes.episode_no) AS min_episode_no, 
			   			MAX(bf_order_book_episodes.episode_no) AS max_episode_no
			   FROM bitfinex.bf_order_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
			   WHERE bf_order_book_episodes.exchange_timestamp BETWEEN "start.time" AND "end.time" 
			     AND bf_snapshots.pair = oba_events.pair
			   GROUP BY bf_order_book_episodes.snapshot_id;
			   
	
BEGIN
	
	FOR rng IN 	order_book_episodes LOOP
		RETURN QUERY
			SELECT 	bf_order_book_events.snapshot_id::bigint *10000 + bf_order_book_events.episode_no*100 + bf_order_book_events.event_no AS "event.id",
					order_id AS id,
					bf_order_book_events.exchange_timestamp AS "timestamp",
					order_price AS price,
					abs(event_qty) AS volume,
					'deleted'::character varying AS action,
					CASE WHEN side = 'A' THEN 'ask'::character varying 
						ELSE 'bid'::character varying END AS direction,
					'flashed-limit'::character varying AS "type",
					bf_order_book_events.snapshot_id, 
					bf_order_book_events.episode_no, 
					bf_order_book_events.event_no
			FROM bitfinex.bf_order_book_events LEFT JOIN bitfinex.bf_trades USING (snapshot_id, episode_no, event_no)
			WHERE bf_order_book_events.snapshot_id = rng.snapshot_id
			  AND bf_order_book_events.episode_no BETWEEN rng.min_episode_no AND rng.max_episode_no
			  AND bf_trades.id IS NULL 
			  AND order_qty = 0
			UNION ALL
			SELECT 	bf_order_book_events.snapshot_id*10000 + bf_order_book_events.episode_no*100 + bf_order_book_events.event_no AS "event.id",
					order_id AS id,
					bf_order_book_events.exchange_timestamp AS "timestamp",
					order_price AS price,
					abs(event_qty) AS volume, 'created'::character varying AS action,
					CASE WHEN side = 'A' THEN 'ask'::character varying 
						 ELSE 'bid'::character varying END AS direction, 
					bf_order_book_events."type", 
					bf_order_book_events.snapshot_id, 
					bf_order_book_events.episode_no, 
					bf_order_book_events.event_no
			FROM (	SELECT 	*,
				  			CASE WHEN (first_value(order_qty) OVER o <> 0  OR first_value(matched) OVER o ) THEN 'resting-limit'::character varying 
						 		ELSE 'flashed-limit'::character varying 
							END AS "type"
				  	FROM bitfinex.bf_order_book_events 
				  	WHERE  	bf_order_book_events.snapshot_id = rng.snapshot_id
			  		  AND 	bf_order_book_events.episode_no BETWEEN rng.min_episode_no AND rng.max_episode_no
					WINDOW o AS (PARTITION BY bf_order_book_events.snapshot_id, order_id ORDER BY bf_order_book_events.episode_no DESC)
				 ) bf_order_book_events  LEFT JOIN bitfinex.bf_trades USING (snapshot_id, episode_no, event_no)
			WHERE order_qty = event_qty 
			  AND event_price = order_price;
	END LOOP;
	RETURN;
END

$$;


ALTER FUNCTION bitfinex.oba_events("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, OUT "event.id" bigint, OUT id bigint, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT action character varying, OUT direction character varying, OUT type character varying, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint) OWNER TO "ob-analytics";

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
PARTITION BY RANGE (snapshot_id);
ALTER TABLE ONLY bitfinex.bf_order_book_events ALTER COLUMN active_episode_no SET STATISTICS 1000;


ALTER TABLE bitfinex.bf_order_book_events OWNER TO "ob-analytics";

--
-- Name: bf_pairs; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_pairs (
    pair character varying(12) NOT NULL,
    "R0" integer NOT NULL,
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
    prec character(2) NOT NULL,
    local_timestamp timestamp with time zone DEFAULT clock_timestamp() NOT NULL
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
-- Name: oba_order_book(timestamp with time zone, character varying, integer, numeric, numeric, numeric); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_order_book(tp timestamp with time zone, pair character varying, "max.levels" integer DEFAULT NULL::integer, "bps.range" numeric DEFAULT NULL::integer, "min.bid" numeric DEFAULT NULL::numeric, "max.ask" numeric DEFAULT NULL::numeric) RETURNS SETOF bitfinex.bf_active_orders_after_episode_v
    LANGUAGE plpgsql
    AS $$

DECLARE 
	ep record;

BEGIN 

	SELECT snapshot_id, episode_no INTO ep
	FROM bitfinex.bf_order_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
	WHERE exchange_timestamp <= oba_order_book.tp
	  AND bf_snapshots.pair = oba_order_book.pair
	ORDER BY exchange_timestamp DESC
	LIMIT 1;
	
	RETURN QUERY 
		SELECT * 
		FROM bitfinex.bf_active_orders_after_episode_v
		WHERE snapshot_id = ep.snapshot_id 
		  AND episode_no = ep.episode_no
		  AND bps <= COALESCE("bps.range", bps)
		  AND lvl <= COALESCE("max.levels", lvl)
		  AND (
			  	(	side = 'B' 
			   		AND order_price >= COALESCE("min.bid", order_price)
			  	) OR
			    (	side = 'A'
				 	AND order_price <= COALESCE("max.ask", order_price)
				)
			  );
END;

$$;


ALTER FUNCTION bitfinex.oba_order_book(tp timestamp with time zone, pair character varying, "max.levels" integer, "bps.range" numeric, "min.bid" numeric, "max.ask" numeric) OWNER TO "ob-analytics";

--
-- Name: oba_raw_events(integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_raw_events(s_id integer, OUT id bigint, OUT "timestamp" bigint, OUT "exchange.timestamp" bigint, OUT price numeric, OUT volume numeric, OUT action bitfinex.raw_event_action, OUT direction text, OUT orig_id bigint, OUT order_type bitfinex.order_type, OUT trade_id bigint, OUT trade_qty numeric, OUT trade_timestamp timestamp with time zone, OUT market_order_id bigint, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint) RETURNS SETOF record
    LANGUAGE sql
    AS $$

WITH all_trades AS (
	SELECT id,
			price,
			qty,
			direction,
			bf_order_book_episodes.exchange_timestamp,
			bitfinex.bf_trades.exchange_timestamp AS trade_timestamp,
			market_order_id,
			min(bitfinex.bf_trades.exchange_timestamp) OVER (PARTITION BY snapshot_id, market_order_id ORDER BY bitfinex.bf_trades.exchange_timestamp )
				AS market_order_timestamp,	-- the column is needed to order the output correctly
			id AS trade_id,
			snapshot_id,
			episode_no,
			event_no
	FROM bitfinex.bf_trades JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no)
	WHERE snapshot_id = s_id
),
trades_against_hidden AS (
	SELECT *
	FROM all_trades
	WHERE event_no IS NULL
),
trades_against_revealed AS (
	SELECT *
	FROM all_trades
	WHERE event_no IS NOT NULL
),
all_events AS (
	SELECT *,	
			bool_or(matched) OVER o_asc OR bool_or(matched) OVER o_dsc AS ever_matched,
			row_number() OVER o_asc  AS first_last_no,
			row_number() OVER o_dsc  AS last_first_no
	FROM (
		SELECT *, sum(is_recreated) OVER (PARTITION BY snapshot_id, order_id ORDER BY exchange_timestamp) AS reincarnation
		FROM (
			SELECT *, COALESCE((lag(order_qty) OVER (PARTITION BY snapshot_id, order_id ORDER BY exchange_timestamp) = 0)::integer,0) AS is_recreated
			FROM bitfinex.bf_order_book_events
			WHERE snapshot_id = s_id
		) a
	) b 
	WINDOW o_asc AS (PARTITION BY snapshot_id, order_id, reincarnation ORDER BY exchange_timestamp),
			o_dsc AS (PARTITION BY snapshot_id, order_id, reincarnation ORDER BY exchange_timestamp DESC)
	
), 
matched_events AS (
	SELECT bitfinex._revealed_order_id(order_id, reincarnation) AS id,
			a.exchange_timestamp AS "timestamp",
			a.exchange_timestamp,
			order_price AS price,
			order_qty - trades_against_revealed.qty + SUM(trades_against_revealed.qty) OVER o_dsc  AS volume,
			CASE WHEN order_qty - trades_against_revealed.qty + SUM(trades_against_revealed.qty) OVER o_dsc  > 0 
					THEN 'changed'::bitfinex.raw_event_action 
				 ELSE 'deleted'::bitfinex.raw_event_action 
			END AS "action",
			CASE WHEN side = 'A' THEN 'ask'::text
					 ELSE 'bid'::text END AS "direction", 
			'resting-limit'::bitfinex.order_type AS order_type,
			trades_against_revealed.id AS trade_id,
			trades_against_revealed.qty AS trade_qty,
			trades_against_revealed.trade_timestamp,
			trades_against_revealed.market_order_id AS market_order_id,
			trades_against_revealed.market_order_timestamp AS market_order_timestamp,
			3::integer AS priority,
			snapshot_id,
			episode_no,
			event_no
	FROM (SELECT * FROM all_events	WHERE matched) a JOIN trades_against_revealed USING (snapshot_id, episode_no, event_no)
	WINDOW o_dsc AS (PARTITION BY snapshot_id, episode_no, event_no ORDER BY trades_against_revealed.trade_timestamp DESC)
	
),
not_matched_events AS (
	SELECT bitfinex._revealed_order_id(order_id, reincarnation) AS id,
			exchange_timestamp AS "timestamp",
			exchange_timestamp,
			order_price AS price,
			CASE WHEN last_first_no > 1 THEN order_qty
				 ELSE abs(event_qty)	-- 'deleted' event
			END AS volume,
			CASE WHEN first_last_no = 1 THEN 'created'::bitfinex.raw_event_action 
				  WHEN last_first_no = 1 THEN 'deleted'::bitfinex.raw_event_action 
				ELSE 'changed'::bitfinex.raw_event_action 
			END AS "action",
			CASE WHEN side = 'A' THEN 'ask'::text
					 ELSE 'bid'::text END AS "direction", 
			CASE WHEN ever_matched THEN 'resting-limit'::bitfinex.order_type
				ELSE 'flashed-limit'::bitfinex.order_type 
			END AS order_type,
			NULL::bigint AS trade_id,
			NULL::numeric AS trade_qty,
			NULL::timestamptz AS trade_timestamp,
			NULL::bigint AS market_order_id,
			NULL::timestamptz AS market_order_timestamp,
			CASE WHEN first_last_no = 1 THEN 1::integer
				ELSE 3::integer 
			END AS priority,
			snapshot_id,
			episode_no,
			event_no
	FROM all_events
	WHERE NOT matched
),
order_book_events AS (
	SELECT id, 
		"timestamp",
		exchange_timestamp,
		price,
		-- obAnalytics::processData() matches events to produce trades by volume change only. In order to avoid generation of spurious trades
		-- we slightly modify the volume of 'flashed-limit'-type events which could originate suche trades. Also we check that the change will not 
		-- negatively impact the matched events.
		CASE WHEN direction = 'ask' AND NOT matched AND NOT next_matched THEN volume*(1 + 0.001*(dense_rank() OVER by_fill - 1))
			ELSE volume
		END AS volume,		
		"action",
		"direction",
		order_type,
		trade_id, 
		trade_qty, 
		trade_timestamp,
		market_order_id,
		market_order_timestamp,																								 
		priority,
		snapshot_id,
		episode_no,
		event_no
	FROM (
		SELECT a.*, 
				COALESCE(lead(volume) OVER by_id - volume, 0) AS next_fill,
				COALESCE(lead(matched) OVER by_id, FALSE) AS next_matched	
		FROM (
			SELECT *, FALSE AS matched
			FROM not_matched_events
			UNION ALL
			SELECT *, TRUE AS matched
			FROM matched_events
		) a
		WINDOW by_id AS (PARTITION BY id ORDER BY "timestamp" )
	) b
	WINDOW by_fill AS (PARTITION BY abs(next_fill) ORDER BY exchange_timestamp)
), 
hidden_events AS (
	SELECT bitfinex._hidden_order_id(id) AS id,
			exchange_timestamp AS "timestamp",
			exchange_timestamp,
			price,
			qty AS volume,
			'created'::bitfinex.raw_event_action AS "action",
			CASE WHEN direction = 'B' THEN 'ask'::text
					 ELSE 'bid'::text END AS "direction", 
			'resting-limit'::bitfinex.order_type AS order_type,
			trade_id,
			qty AS trade_qty,
			trade_timestamp,
			market_order_id,
	 		market_order_timestamp, 
			1::integer AS priority,
			snapshot_id,
			episode_no,
			event_no
	FROM trades_against_hidden
	UNION ALL				 
	SELECT bitfinex._hidden_order_id(id)  AS id,
			exchange_timestamp AS "timestamp",
			exchange_timestamp,
			price,
			0 AS volume,
			'deleted'::bitfinex.raw_event_action AS "action",
			CASE WHEN direction = 'B' THEN 'ask'::text
					 ELSE 'bid'::text END AS "direction",
			'resting-limit'::bitfinex.order_type AS order_type	,
			trade_id,
			qty AS trade_qty,
			trade_timestamp,
			market_order_id,
	 		market_order_timestamp, 
			3::integer AS priority,
			snapshot_id,
			episode_no,
			event_no
	FROM trades_against_hidden
) ,
raw_market_order_events AS (
	SELECT market_order_id  AS id,
			last_value(exchange_timestamp) OVER mo_asc AS "timestamp",
			first_value(exchange_timestamp) OVER mo_asc AS exchange_timestamp,
			CASE WHEN direction = 'B' THEN max(price) OVER mo_dsc 
				ELSE min(price) OVER mo_dsc END AS price,
			sum(qty) OVER mo_dsc AS volume, 
			qty, 
			CASE WHEN direction = 'B' THEN 'bid'::text
			 		 ELSE 'ask'::text END AS "direction",
			'market'::bitfinex.order_type AS order_type,	
			trade_id,
			qty AS trade_qty,
			trade_timestamp,
			market_order_id,
			market_order_timestamp,
			row_number() OVER mo_asc  AS first_last_no,
			row_number() OVER mo_dsc  AS last_first_no,
			snapshot_id,
			episode_no,
			event_no
	FROM all_trades
	WINDOW mo_asc AS (PARTITION BY market_order_id ORDER BY trade_timestamp),
			mo_dsc AS (PARTITION BY market_order_id ORDER BY trade_timestamp DESC)
),
market_order_events AS (
	SELECT id, "timestamp", exchange_timestamp, price, volume, 'created'::bitfinex.raw_event_action AS "action", "direction", 
				order_type, trade_id, trade_qty,trade_timestamp, market_order_id, market_order_timestamp, 2::integer AS priority, snapshot_id, episode_no, event_no

	FROM raw_market_order_events
	WHERE first_last_no = 1
	UNION ALL
	SELECT id, "timestamp", exchange_timestamp, price, volume - qty, 'changed'::bitfinex.raw_event_action, "direction",
			order_type, trade_id, trade_qty,trade_timestamp, market_order_id, market_order_timestamp,  3::integer AS priority, snapshot_id, episode_no, event_no
	FROM raw_market_order_events
	WHERE last_first_no != 1 
	UNION ALL
	SELECT id, "timestamp", exchange_timestamp, price, volume - qty, 'deleted'::bitfinex.raw_event_action, "direction",
			order_type, trade_id, trade_qty,trade_timestamp, market_order_id,  market_order_timestamp, 3::integer AS priority, snapshot_id, episode_no, event_no
	FROM raw_market_order_events
	WHERE last_first_no = 1 
),
combined_ordered_events AS (
	SELECT row_number() OVER () AS rn, a.*
	FROM (
		SELECT *
		FROM (
			SELECT * FROM hidden_events
			UNION ALL
			SELECT * FROM order_book_events
			UNION ALL
			SELECT * FROM market_order_events
		) a
		ORDER BY exchange_timestamp, market_order_timestamp, priority, trade_timestamp, action , order_type DESC
	) a
)
SELECT new_id AS id, 
		(EXTRACT( EPOCH FROM "timestamp")*1000)::bigint,
		(EXTRACT( EPOCH FROM exchange_timestamp)*1000)::bigint,
		price,
		volume,
		"action",
		"direction", 
		id AS orig_id, 		
		order_type,
		trade_id,
		trade_qty,
		trade_timestamp,
		market_order_id,
		snapshot_id,
		episode_no,
		event_no
FROM combined_ordered_events JOIN (SELECT id, min(rn) AS new_id FROM combined_ordered_events GROUP BY id) b USING (id);

$$;


ALTER FUNCTION bitfinex.oba_raw_events(s_id integer, OUT id bigint, OUT "timestamp" bigint, OUT "exchange.timestamp" bigint, OUT price numeric, OUT volume numeric, OUT action bitfinex.raw_event_action, OUT direction text, OUT orig_id bigint, OUT order_type bitfinex.order_type, OUT trade_id bigint, OUT trade_qty numeric, OUT trade_timestamp timestamp with time zone, OUT market_order_id bigint, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, OUT "timestamp" timestamp with time zone, OUT "best.bid.price" numeric, OUT "best.bid.volume" numeric, OUT "best.ask.price" numeric, OUT "best.ask.volume" numeric, OUT snapshot_id integer, OUT episode_no integer) RETURNS SETOF record
    LANGUAGE plpgsql
    SET work_mem TO '1GB'
    AS $$

DECLARE 
	p numeric;
	
	order_book_episodes CURSOR FOR
			   SELECT 	bf_order_book_episodes.snapshot_id, 
			   			MIN(bf_order_book_episodes.episode_no) AS min_episode_no, 
			   			MAX(bf_order_book_episodes.episode_no) AS max_episode_no
			   FROM bitfinex.bf_order_book_episodes JOIN bitfinex.bf_snapshots USING (snapshot_id)
			   WHERE exchange_timestamp BETWEEN "start.time" AND "end.time" 
			     AND bf_snapshots.pair = oba_spread.pair
			   GROUP BY bf_order_book_episodes.snapshot_id;
			   
BEGIN

	FOR rng IN 	order_book_episodes LOOP
		RETURN QUERY 
			SELECT 	exchange_timestamp AS "timestamp",
		    		best_bid_price AS "best.bid.price",
		      		best_bid_qty AS "best.bid.vol",
		      		best_ask_price AS "best.ask.price",
		      		best_ask_qty AS "best.ask.vol",
		      		a.snapshot_id,
		      		a.episode_no
  			FROM (
    			SELECT 	*, 
						COALESCE(lag(best_bid_price) OVER p, -1) AS lag_bbp,
              			COALESCE(lag(best_bid_qty) OVER p, -1) AS lag_bbq,
		          		COALESCE(lag(best_ask_price) OVER p, -1) AS lag_bap,
              			COALESCE(lag(best_ask_qty) OVER p, -1) AS lag_baq
    			FROM ( 
					SELECT 	bf_spreads.episode_no,
							best_bid_price,
							best_bid_qty,
							best_ask_price,
	  		        		best_ask_qty,
							bf_spreads.snapshot_id,
							exchange_timestamp - 0.001*'1 sec'::interval AS exchange_timestamp
           			FROM bitfinex.bf_spreads JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no)
			       	WHERE bf_spreads.timing = 'B' 
					  AND bf_spreads.snapshot_id = rng.snapshot_id
					  AND bf_spreads.episode_no BETWEEN rng.min_episode_no  AND rng.max_episode_no
           			UNION ALL
           			SELECT 	bf_spreads.episode_no,
							best_bid_price,
							best_bid_qty,
							best_ask_price,
	  		        		best_ask_qty,
							bf_spreads.snapshot_id,
							exchange_timestamp 
           			FROM bitfinex.bf_spreads JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no)
           			WHERE bf_spreads.timing = 'A' 
					  AND bf_spreads.snapshot_id = rng.snapshot_id
					  AND bf_spreads.episode_no BETWEEN rng.min_episode_no  AND rng.max_episode_no
         		) v
    			WINDOW p AS (PARTITION BY v.snapshot_id  ORDER BY v.episode_no)
  			) a
  			WHERE best_bid_price != lag_bbp
     		   OR best_bid_qty != lag_bbq
     		   OR best_ask_price != lag_bap
      		   OR best_ask_qty != lag_baq;
	END LOOP;
	
	RETURN;
END;

$$;


ALTER FUNCTION bitfinex.oba_spread("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, OUT "timestamp" timestamp with time zone, OUT "best.bid.price" numeric, OUT "best.bid.volume" numeric, OUT "best.ask.price" numeric, OUT "best.ask.volume" numeric, OUT snapshot_id integer, OUT episode_no integer) OWNER TO "ob-analytics";

--
-- Name: oba_trades(timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.oba_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying DEFAULT 'BTCUSD'::character varying, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT direction character varying, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint, OUT id bigint) RETURNS SETOF record
    LANGUAGE sql
    SET work_mem TO '1GB'
    AS $$

	SELECT	bf_order_book_episodes.exchange_timestamp AS "timestamp",
		   	price, 
		   	qty AS volume, 
		   	CASE 	WHEN direction = 'S' THEN 'sell'::character varying
					ELSE 'buy'::character varying
			END AS direction,
			snapshot_id,
			episode_no,
			event_no,
			id
   	FROM bitfinex.bf_trades JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no) JOIN bitfinex.bf_snapshots USING (snapshot_id)
   	WHERE  bf_order_book_episodes.exchange_timestamp  BETWEEN oba_trades."start.time" AND oba_trades."end.time"
	  AND  pair = oba_trades.pair

$$;


ALTER FUNCTION bitfinex.oba_trades("start.time" timestamp with time zone, "end.time" timestamp with time zone, pair character varying, OUT "timestamp" timestamp with time zone, OUT price numeric, OUT volume numeric, OUT direction character varying, OUT snapshot_id integer, OUT episode_no integer, OUT event_no smallint, OUT id bigint) OWNER TO "ob-analytics";

--
-- Name: pga_capture_transient(text, interval); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.pga_capture_transient(p_pair text, p_delay interval DEFAULT '00:02:00'::interval) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
	v_start timestamptz;
	v_end timestamptz;
begin 
	perform bitfinex.capture_transient_trades( 
		( select max(exchange_timestamp)  - p_delay
		  from bitfinex.transient_trades join obanalytics.pairs using (pair_id)
		  where pair = upper(p_pair)
		 ),  p_pair);
	select min(episode_timestamp), max(episode_timestamp) - p_delay into v_start, v_end
	from bitfinex.transient_raw_book_events join obanalytics.pairs using (pair_id)
	where pair = upper(p_pair);
	perform bitfinex.capture_transient_raw_book_events(v_start, v_end, p_pair);
	return 0;											   
end;
$$;


ALTER FUNCTION bitfinex.pga_capture_transient(p_pair text, p_delay interval) OWNER TO "ob-analytics";

--
-- Name: update_symbol_details(text, smallint, numeric, numeric, numeric, numeric, text, boolean); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.update_symbol_details(p_pair text, p_price_precision smallint, p_initial_margin numeric, p_minimum_margin numeric, p_maximum_order_size numeric, p_minimum_order_size numeric, p_expiration text, p_margin boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$

declare
	v_pair_id smallint;
begin

	select pair_id into v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	if v_pair_id is not null then
		if exists (select 1 from bitfinex.symbol_details where pair_id = v_pair_id ) then 
			insert into bitfinex.symbol_details (pair_id, price_precision, initial_margin,minimum_margin,maximum_order_size,minimum_order_size,expiration,margin,known_since)					
			select v_pair_id, p_price_precision, p_initial_margin,p_minimum_margin,p_maximum_order_size,p_minimum_order_size,p_expiration,p_margin,current_timestamp
			from bitfinex.symbol_details
			 where pair_id = v_pair_id and 
			 known_since = (select max(known_since) from bitfinex.symbol_details where pair_id = v_pair_id ) and
			 (	price_precision <> p_price_precision or
				initial_margin <> p_initial_margin or
				minimum_margin <> p_minimum_margin or
				maximum_order_size <> p_maximum_order_size or
				minimum_order_size <> p_minimum_order_size or
				expiration <> p_expiration or
				margin <> p_margin 
			 );
			 return found;
		else
			insert into bitfinex.symbol_details (pair_id, price_precision, initial_margin,minimum_margin,maximum_order_size,minimum_order_size,expiration,margin,known_since)					
			values(v_pair_id, p_price_precision, p_initial_margin,p_minimum_margin,p_maximum_order_size,p_minimum_order_size,p_expiration,p_margin,current_timestamp);
			return true;
		end if;
	else
		return false;
	end if;
end;
$$;


ALTER FUNCTION bitfinex.update_symbol_details(p_pair text, p_price_precision smallint, p_initial_margin numeric, p_minimum_margin numeric, p_maximum_order_size numeric, p_minimum_order_size numeric, p_expiration text, p_margin boolean) OWNER TO "ob-analytics";

--
-- Name: transient_raw_book_agg(bitfinex.transient_raw_book_events[]); Type: AGGREGATE; Schema: bitfinex; Owner: ob-analytics
--

CREATE AGGREGATE bitfinex.transient_raw_book_agg(bitfinex.transient_raw_book_events[]) (
    SFUNC = bitfinex._update_order_book,
    STYPE = bitfinex.transient_raw_book_events[]
);


ALTER AGGREGATE bitfinex.transient_raw_book_agg(bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

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
PARTITION BY RANGE (snapshot_id);
ALTER TABLE ONLY bitfinex.bf_cons_book_events ALTER COLUMN active_episode_no SET STATISTICS 1000;
ALTER TABLE ONLY bitfinex.bf_cons_book_events ALTER COLUMN price_next_episode_no SET STATISTICS 1000;


ALTER TABLE bitfinex.bf_cons_book_events OWNER TO "ob-analytics";

--
-- Name: bf_trades; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_trades (
    id bigint NOT NULL,
    qty numeric NOT NULL,
    price numeric NOT NULL,
    local_timestamp timestamp(3) with time zone NOT NULL,
    snapshot_id integer NOT NULL,
    exchange_timestamp timestamp(3) with time zone NOT NULL,
    episode_no integer,
    event_no smallint,
    direction character(1) NOT NULL,
    match_rule smallint,
    market_order_id bigint
)
WITH (autovacuum_enabled='true', autovacuum_analyze_threshold='5000', autovacuum_vacuum_threshold='5000', autovacuum_analyze_scale_factor='0.0', autovacuum_vacuum_scale_factor='0.0');


ALTER TABLE bitfinex.bf_trades OWNER TO "ob-analytics";

--
-- Name: COLUMN bf_trades.id; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.id IS 'Bitfinex'' trade database id';


--
-- Name: COLUMN bf_trades.local_timestamp; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.local_timestamp IS 'When we''ve got this record from Bitfinex';


--
-- Name: COLUMN bf_trades.exchange_timestamp; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.exchange_timestamp IS 'Bitfinex''s timestamp';


--
-- Name: COLUMN bf_trades.match_rule; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_trades.match_rule IS 'An identifier of SQL statement which matched the trade with an episode.';


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
     LEFT JOIN LATERAL ( SELECT bf_cons_book_events.snapshot_id,
            count(*) AS events,
            min(bf_cons_book_events.exchange_timestamp) AS min_e_et,
            max(bf_cons_book_events.exchange_timestamp) AS max_e_et,
            max(bf_cons_book_events.episode_no) AS last_episode
           FROM bitfinex.bf_cons_book_events
          WHERE (bf_cons_book_events.snapshot_id = s.snapshot_id)
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
    t.match_rule,
    t.id,
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
  WHERE ((s.timing = 'B'::bpchar) AND ((t.price < s.best_bid_price) OR (t.price > s.best_ask_price)));


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
    round(t.price, bf_pairs."R0") AS price,
    count(*) OVER (PARTITION BY t.snapshot_id, t.episode_no, t.event_no) AS matched_count,
    bf_pairs.pair,
    t.snapshot_id,
    t.episode_no,
    t.event_no,
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
-- Name: symbol_details; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.symbol_details (
    pair_id smallint NOT NULL,
    price_precision smallint NOT NULL,
    initial_margin numeric NOT NULL,
    minimum_margin numeric NOT NULL,
    maximum_order_size numeric NOT NULL,
    minimum_order_size numeric NOT NULL,
    expiration text NOT NULL,
    margin boolean NOT NULL,
    known_since timestamp with time zone NOT NULL
);


ALTER TABLE bitfinex.symbol_details OWNER TO "ob-analytics";

--
-- Name: latest_symbol_details; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.latest_symbol_details AS
 SELECT DISTINCT ON (symbol_details.pair_id) symbol_details.pair_id,
    symbol_details.price_precision,
    symbol_details.initial_margin,
    symbol_details.minimum_margin,
    symbol_details.maximum_order_size,
    symbol_details.minimum_order_size,
    symbol_details.expiration,
    symbol_details.margin,
    symbol_details.known_since
   FROM bitfinex.symbol_details
  ORDER BY symbol_details.pair_id, symbol_details.known_since DESC;


ALTER TABLE bitfinex.latest_symbol_details OWNER TO "ob-analytics";

--
-- Name: transient_raw_book_channels; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_raw_book_channels (
    episode_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    channel_id integer NOT NULL
);


ALTER TABLE bitfinex.transient_raw_book_channels OWNER TO "ob-analytics";

--
-- Name: transient_trades; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_trades (
    id bigint NOT NULL,
    qty numeric NOT NULL,
    price numeric NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    exchange_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    channel_id integer NOT NULL,
    trade_id bigint NOT NULL
);


ALTER TABLE bitfinex.transient_trades OWNER TO "ob-analytics";

--
-- Name: transient_trades_trade_id_seq; Type: SEQUENCE; Schema: bitfinex; Owner: ob-analytics
--

CREATE SEQUENCE bitfinex.transient_trades_trade_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bitfinex.transient_trades_trade_id_seq OWNER TO "ob-analytics";

--
-- Name: transient_trades_trade_id_seq; Type: SEQUENCE OWNED BY; Schema: bitfinex; Owner: ob-analytics
--

ALTER SEQUENCE bitfinex.transient_trades_trade_id_seq OWNED BY bitfinex.transient_trades.trade_id;


--
-- Name: bf_snapshots snapshot_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('bitfinex.bf_snapshots_snapshot_id_seq'::regclass);


--
-- Name: transient_trades trade_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.transient_trades ALTER COLUMN trade_id SET DEFAULT nextval('bitfinex.transient_trades_trade_id_seq'::regclass);


--
-- Name: bf_cons_book_episodes bf_cons_book_episodes_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_episodes
    ADD CONSTRAINT bf_cons_book_episodes_pkey PRIMARY KEY (snapshot_id, episode_no);


--
-- Name: bf_order_book_episodes bf_order_book_episodes_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_pkey PRIMARY KEY (snapshot_id, episode_no);


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
-- Name: symbol_details symbol_details_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.symbol_details
    ADD CONSTRAINT symbol_details_pkey PRIMARY KEY (pair_id, known_since);


--
-- Name: bf_cons_book_episodes_idx_by_time; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_cons_book_episodes_idx_by_time ON bitfinex.bf_cons_book_episodes USING btree (exchange_timestamp);


--
-- Name: bf_order_book_episodes_idx_by_time; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_episodes_idx_by_time ON bitfinex.bf_order_book_episodes USING btree (exchange_timestamp);


--
-- Name: bf_trades_idx_snapshot_id_episode_no_event_no; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id_episode_no_event_no ON bitfinex.bf_trades USING btree (snapshot_id, episode_no, event_no);


--
-- Name: bf_trades_idx_snapshot_id_exchange_timestamp; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id_exchange_timestamp ON bitfinex.bf_trades USING btree (snapshot_id, exchange_timestamp);


--
-- Name: transient_raw_book_events_idx_channel; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX transient_raw_book_events_idx_channel ON bitfinex.transient_raw_book_events USING btree (pair_id, channel_id, episode_timestamp);


--
-- Name: bf_trades a_check_episode_no_order; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE CONSTRAINT TRIGGER a_check_episode_no_order AFTER INSERT OR UPDATE OF episode_no ON bitfinex.bf_trades NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW WHEN ((new.episode_no IS NOT NULL)) EXECUTE PROCEDURE bitfinex.bf_trades_check_episode_no_order();


--
-- Name: bf_snapshots a_create_partitions; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_create_partitions AFTER INSERT ON bitfinex.bf_snapshots FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_snapshots_create_partitions();


--
-- Name: bf_trades a_dress_new_row; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_dress_new_row BEFORE INSERT ON bitfinex.bf_trades FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_trades_dress_new_row();


--
-- Name: bf_order_book_episodes a_match_trades_to_episodes; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER a_match_trades_to_episodes AFTER INSERT ON bitfinex.bf_order_book_episodes FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_episodes_match_trades_to_episodes();


--
-- Name: bf_cons_book_episodes bf_cons_book_episodes_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_cons_book_episodes
    ADD CONSTRAINT bf_cons_book_episodes_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_episodes bf_order_book_episodes_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


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
-- Name: bf_trades bf_trades_fkey_bf_snapshots; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_bf_snapshots FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

