--
-- PostgreSQL database dump
--

-- Dumped from database version 10.4
-- Dumped by pg_dump version 10.4

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
-- Name: bf_depth_summary_before_episode_v(integer, integer, integer, numeric); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_depth_summary_before_episode_v(snapshot_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647, bps_step numeric DEFAULT 25) RETURNS TABLE(volume numeric, bps_level integer, bps_price numeric, bps_vwap numeric, direction character varying, pair character varying, starts_exchange_timestamp timestamp with time zone, episode_no integer, snapshot_id integer)
    LANGUAGE sql
    AS $$

SELECT  sum(order_qty) AS volume,
		bps_level,
		bps_price,
		round(sum(order_qty*order_price)/sum(order_qty), "precision") AS bps_vwap,
		direction,
		pair,
		starts_exchange_timestamp,
		episode_no,
		snapshot_id
FROM (
SELECT 	order_price,
		order_qty, 
		(bf_depth_summary_before_episode_v.bps_step*bps_level)::integer AS bps_level,
		round(best_bid*(1 - bps_level*bf_depth_summary_before_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
		'bid' AS direction,
		pair,
		starts_exchange_timestamp,
		episode_no,
		snapshot_id,
		"precision"
FROM (		
	SELECT 	order_price, 
			order_qty, 
			ceiling((best_bid - order_price)/best_bid/bf_depth_summary_before_episode_v.bps_step*10000)::integer AS bps_level,
			best_bid,
			pair,
			starts_exchange_timestamp,
			episode_no,
			snapshot_id
	FROM (
			SELECT 	order_price, 
					order_qty,
					first_value(order_price) OVER w AS best_bid, 
					pair,
					starts_exchange_timestamp,
					episode_no,
					snapshot_id
			FROM bitfinex.bf_active_orders_before_episode_v
			WHERE snapshot_id = bf_depth_summary_before_episode_v.snapshot_id
			  AND episode_no BETWEEN bf_depth_summary_before_episode_v.first_episode_no 
											AND bf_depth_summary_before_episode_v.last_episode_no
			  AND bitfinex.bf_active_orders_before_episode_v.side = 'B'
			WINDOW w AS (PARTITION BY episode_no ORDER BY order_price DESC)
	) r1
) r2 JOIN bf_pairs USING (pair)
UNION ALL
SELECT 	order_price,
		order_qty, 
		(bf_depth_summary_before_episode_v.bps_step*bps_level)::integer AS bps_level,
		round(best_ask*(1 + bps_level*bf_depth_summary_before_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
		'ask' AS direction,
		pair,
		starts_exchange_timestamp,
		episode_no,
		snapshot_id,
		"precision"
FROM (		
	SELECT 	order_price, 
			order_qty, 
			ceiling((order_price-best_ask)/best_ask/bf_depth_summary_before_episode_v.bps_step*10000)::integer AS bps_level,
			best_ask,
			pair,
			starts_exchange_timestamp,
			episode_no,
			snapshot_id
	FROM (
			SELECT 	order_price, 
					order_qty,
					first_value(order_price) OVER w AS best_ask, 
					pair,
					starts_exchange_timestamp,
					episode_no,
					snapshot_id
			FROM bitfinex.bf_active_orders_before_episode_v
			WHERE snapshot_id = bf_depth_summary_before_episode_v.snapshot_id
			  AND episode_no BETWEEN bf_depth_summary_before_episode_v.first_episode_no 
									AND bf_depth_summary_before_episode_v.last_episode_no
			  AND bitfinex.bf_active_orders_before_episode_v.side = 'A'
			WINDOW w AS (PARTITION BY episode_no ORDER BY order_price)
	) r1
) r2 JOIN bf_pairs USING (pair)
) u 
GROUP BY pair, bps_level, bps_price, direction, starts_exchange_timestamp, episode_no, snapshot_id, "precision";
	

$$;


ALTER FUNCTION bitfinex.bf_depth_summary_before_episode_v(snapshot_id integer, first_episode_no integer, last_episode_no integer, bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_fun_before_insert(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_fun_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	precision bitfinex.bf_pairs.precision%TYPE;
	e bitfinex.bf_order_book_events%ROWTYPE;
	tr_id bigint;
	
BEGIN


	IF NEW.event_price != 0 THEN 
	
		SELECT bf_pairs.precision INTO precision 
		FROM bitfinex.bf_pairs
		WHERE pair = NEW.pair;

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
			RAISE EXCEPTION 'Requested removal of order: %  which is not in the order book!', NEW.order_id;
		END IF;
		
	END IF;
	
	UPDATE bitfinex.bf_order_book_events
	SET order_next_episode_no = NEW.episode_no,
		order_next_event_price = NEW.event_price
	WHERE snapshot_id = NEW.snapshot_id 
	  AND order_id = NEW.order_id 
	  AND episode_no < NEW.episode_no
	  AND order_next_episode_no > NEW.episode_no;
	
	IF NEW.event_qty < 0 THEN 
	 	-- WARNING: SET CONSTRAINT ALL DEFERRED is assumed.
		-- Otherwise both UPDATEs below will fail
		
		SELECT id INTO tr_id
		FROM bitfinex.bf_trades t
		WHERE t.price		= NEW.order_price
		  AND t.qty 		= -NEW.event_qty
		  AND t.snapshot_id = NEW.snapshot_id
		  AND t.event_no IS NULL	
		  AND t.exchange_timestamp BETWEEN 	NEW.exchange_timestamp - 1*interval '1 second' AND
											NEW.exchange_timestamp
		ORDER BY id
		LIMIT 1;
		
		IF FOUND THEN
			
			UPDATE bitfinex.bf_trades 
			SET episode_no = NEW.episode_no, 
				event_no = NEW.event_no
			WHERE id = tr_id;		
			
		ELSE
		
			SELECT id INTO tr_id
			FROM ( 	SELECT id, SUM(qty) OVER (PARTITION BY t.snapshot_id, t.price ORDER BY t.id) AS total_qty  
				   	FROM bitfinex.bf_trades t
					WHERE t.price		= NEW.order_price
			  		  AND t.snapshot_id = NEW.snapshot_id
			  		  AND t.event_no IS NULL 	-- trade has not been associated with 
												-- event. But could be associated with 
												-- episode_no, so episode_no might be NOT NULL
			  		  AND t.exchange_timestamp BETWEEN 	NEW.exchange_timestamp - 1*interval '1 second' 
														AND NEW.exchange_timestamp
					) t
			WHERE t.total_qty = -NEW.event_qty;
			
			IF FOUND THEN
				UPDATE bitfinex.bf_trades t
				SET episode_no = NEW.episode_no, 
					event_no = NEW.event_no	
				WHERE t.price		= NEW.order_price
			  	  AND t.snapshot_id = NEW.snapshot_id
			  	  AND t.event_no IS NULL
			  	  AND t.exchange_timestamp BETWEEN 	NEW.exchange_timestamp - 1*interval '1 second' 
			  										AND NEW.exchange_timestamp 
			  	  AND t.id <= tr_id;			
			END IF;
		END IF;
	END IF;
	
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_events_fun_before_insert() OWNER TO "ob-analytics";

--
-- Name: bf_trades_fun_before_insert(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_trades_fun_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	precision bitfinex.bf_pairs.precision%TYPE;

BEGIN
	SELECT bf_pairs.precision INTO precision 
	FROM bitfinex.bf_pairs
	WHERE pair = NEW.pair;

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


ALTER FUNCTION bitfinex.bf_trades_fun_before_insert() OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: bf_order_book_episodes; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_order_book_episodes (
    snapshot_id integer NOT NULL,
    episode_no integer NOT NULL,
    starts_exchange_timestamp timestamp with time zone NOT NULL,
    ends_exchange_timestamp timestamp with time zone NOT NULL
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
    pair character varying(12),
    order_price numeric,
    event_qty numeric,
    snapshot_id integer NOT NULL,
    episode_no integer NOT NULL,
    exchange_timestamp timestamp(3) with time zone,
    order_next_episode_no integer NOT NULL,
    event_no smallint NOT NULL,
    side character(1) NOT NULL,
    order_next_event_price numeric DEFAULT '-1'::integer NOT NULL
);


ALTER TABLE bitfinex.bf_order_book_events OWNER TO "ob-analytics";

--
-- Name: bf_active_orders_after_period_starts_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_active_orders_after_period_starts_v AS
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
    e.starts_exchange_timestamp,
    e.ends_exchange_timestamp,
    ob.episode_no AS order_episode_no,
    ob.exchange_timestamp AS order_exchange_timestamp,
    ob.pair
   FROM (bitfinex.bf_order_book_episodes e
     JOIN bitfinex.bf_order_book_events ob ON (((ob.snapshot_id = e.snapshot_id) AND (ob.episode_no <= e.episode_no) AND (ob.event_price <> (0)::numeric) AND (ob.order_next_episode_no > e.episode_no))))
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price, ob.order_id), bids AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC, ob.order_id), ask_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price), bid_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC)
  ORDER BY ob.order_price DESC, ((ob.order_id)::numeric * (
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN '-1'::integer
            ELSE 1
        END)::numeric);


ALTER TABLE bitfinex.bf_active_orders_after_period_starts_v OWNER TO "ob-analytics";

--
-- Name: bf_active_orders_before_period_starts_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_active_orders_before_period_starts_v AS
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
    e.starts_exchange_timestamp,
    e.ends_exchange_timestamp,
    ob.episode_no AS order_episode_no,
    ob.exchange_timestamp AS order_exchange_timestamp,
    ob.pair
   FROM (bitfinex.bf_order_book_episodes e
     JOIN bitfinex.bf_order_book_events ob ON (((ob.snapshot_id = e.snapshot_id) AND (ob.episode_no < e.episode_no) AND (ob.event_price <> (0)::numeric) AND ((ob.order_next_episode_no > e.episode_no) OR ((ob.order_next_episode_no = e.episode_no) AND (ob.order_next_event_price > (0)::numeric))))))
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price, ob.order_id), bids AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC, ob.order_id), ask_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price), bid_prices AS (PARTITION BY e.snapshot_id, e.episode_no, ob.side ORDER BY ob.order_price DESC)
  ORDER BY ob.order_price DESC, ((ob.order_id)::numeric * (
        CASE
            WHEN (ob.side = 'A'::bpchar) THEN '-1'::integer
            ELSE 1
        END)::numeric);


ALTER TABLE bitfinex.bf_active_orders_before_period_starts_v OWNER TO "ob-analytics";

--
-- Name: bf_trades; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_trades (
    id bigint NOT NULL,
    trade_timestamp timestamp(3) with time zone,
    qty numeric,
    price numeric,
    pair character varying(12),
    local_timestamp timestamp(3) with time zone,
    snapshot_id integer,
    exchange_timestamp timestamp(3) with time zone,
    episode_no integer,
    event_no smallint,
    direction character(1) NOT NULL
);


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
    i.pair,
    t.last_trade_exchange_timestamp,
    i.local_timestamp,
    i.order_next_episode_no,
    i.side
   FROM (bitfinex.bf_order_book_events i
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
    len smallint
);


ALTER TABLE bitfinex.bf_snapshots OWNER TO "ob-analytics";

--
-- Name: COLUMN bf_snapshots.len; Type: COMMENT; Schema: bitfinex; Owner: ob-analytics
--

COMMENT ON COLUMN bitfinex.bf_snapshots.len IS 'Number of orders below/above best price specified in Bitfinex'' Raw Book subscription request for this snapshot';


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
-- Name: bf_snapshots_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_snapshots_v AS
 SELECT bf_snapshots.snapshot_id,
    bf_snapshots.len,
    e.events,
    e.last_episode,
    t.trades,
    date_trunc('seconds'::text, LEAST(e.min_e_et, t.min_t_et)) AS starts,
    date_trunc('seconds'::text, GREATEST(e.max_e_et, t.max_t_et)) AS ends,
    t.matched_to_episode,
    t.matched_to_event
   FROM ((bitfinex.bf_snapshots
     LEFT JOIN ( SELECT bf_order_book_events.snapshot_id,
            count(*) AS events,
            min(bf_order_book_events.exchange_timestamp) AS min_e_et,
            max(bf_order_book_events.exchange_timestamp) AS max_e_et,
            max(bf_order_book_events.episode_no) AS last_episode
           FROM bitfinex.bf_order_book_events
          GROUP BY bf_order_book_events.snapshot_id) e USING (snapshot_id))
     LEFT JOIN ( SELECT bf_trades.snapshot_id,
            count(*) AS trades,
            count(*) FILTER (WHERE (bf_trades.event_no IS NOT NULL)) AS matched_to_event,
            count(*) FILTER (WHERE (bf_trades.episode_no IS NOT NULL)) AS matched_to_episode,
            min(bf_trades.exchange_timestamp) AS min_t_et,
            max(bf_trades.exchange_timestamp) AS max_t_et
           FROM bitfinex.bf_trades
          GROUP BY bf_trades.snapshot_id) t USING (snapshot_id))
  ORDER BY bf_snapshots.snapshot_id DESC;


ALTER TABLE bitfinex.bf_snapshots_v OWNER TO "ob-analytics";

--
-- Name: bf_trades_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_trades_v AS
 SELECT a.id,
    a.qty,
    a.price,
    a.matched_count,
    a.pair,
    a.snapshot_id,
        CASE
            WHEN (a.episode_no IS NOT NULL) THEN a.episode_no
            ELSE i.episode_no
        END AS episode_no,
    a.event_no,
    a.trade_timestamp,
    a.exchange_timestamp,
    a.event_exchange_timestamp,
    a.local_timestamp,
    a.direction
   FROM (( SELECT t.id,
            t.qty,
            round(t.price, bf_pairs."precision") AS price,
            count(*) OVER (PARTITION BY t.snapshot_id, t.episode_no, t.event_no) AS matched_count,
            t.pair,
            t.snapshot_id,
            t.episode_no,
            t.event_no,
            t.trade_timestamp,
            t.exchange_timestamp,
                CASE
                    WHEN (e.exchange_timestamp IS NOT NULL) THEN e.exchange_timestamp
                    ELSE (max(e.exchange_timestamp) OVER o + (t.trade_timestamp - max(t.trade_timestamp) FILTER (WHERE (e.exchange_timestamp IS NOT NULL)) OVER o))
                END AS event_exchange_timestamp,
            t.local_timestamp,
            t.direction
           FROM ((bitfinex.bf_trades t
             JOIN bitfinex.bf_pairs USING (pair))
             LEFT JOIN bitfinex.bf_order_book_events e ON (((t.snapshot_id = e.snapshot_id) AND (t.episode_no = e.episode_no) AND (t.event_no = e.event_no))))
          WHERE (t.local_timestamp IS NOT NULL)
          WINDOW o AS (PARTITION BY t.snapshot_id ORDER BY t.id)) a
     LEFT JOIN bitfinex.bf_order_book_episodes i ON (((a.episode_no IS NULL) AND (i.snapshot_id = a.snapshot_id) AND (a.event_exchange_timestamp > i.starts_exchange_timestamp) AND (a.event_exchange_timestamp <= i.ends_exchange_timestamp))));


ALTER TABLE bitfinex.bf_trades_v OWNER TO "ob-analytics";

--
-- Name: bf_snapshots snapshot_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('bitfinex.bf_snapshots_snapshot_id_seq'::regclass);


--
-- Name: bf_order_book_episodes bf_order_book_episodes_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_pkey PRIMARY KEY (snapshot_id, episode_no);


--
-- Name: bf_order_book_episodes bf_order_book_episodes_unq_starts_ends; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_unq_starts_ends UNIQUE (starts_exchange_timestamp, ends_exchange_timestamp) DEFERRABLE;


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
-- Name: bf_trades bf_trades_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_pkey PRIMARY KEY (id);


--
-- Name: bf_trades_idx_snapshot_id_episode_no_event_no; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id_episode_no_event_no ON bitfinex.bf_trades USING btree (snapshot_id, episode_no, event_no);


--
-- Name: bf_order_book_events before_insert; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER before_insert BEFORE INSERT ON bitfinex.bf_order_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_fun_before_insert();


--
-- Name: bf_trades before_insert; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER before_insert BEFORE INSERT ON bitfinex.bf_trades FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_trades_fun_before_insert();


--
-- Name: bf_order_book_episodes bf_order_book_episodes_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_episodes
    ADD CONSTRAINT bf_order_book_episodes_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_events bf_order_book_events_fkey_pair; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_pair FOREIGN KEY (pair) REFERENCES bitfinex.bf_pairs(pair) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_events bf_order_book_events_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_trades bf_trades_fkey_pair; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_pair FOREIGN KEY (pair) REFERENCES bitfinex.bf_pairs(pair) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_trades bf_trades_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: bf_trades bf_trades_fkey_snapshot_id_episode_no_event_no; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_snapshot_id_episode_no_event_no FOREIGN KEY (snapshot_id, episode_no, event_no) REFERENCES bitfinex.bf_order_book_events(snapshot_id, episode_no, event_no) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

