--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.8
-- Dumped by pg_dump version 9.6.8

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

CREATE FUNCTION bitfinex.bf_depth_summary_before_episode_v(snapshot_id integer, first_episode_no integer DEFAULT 0, last_episode_no integer DEFAULT 2147483647, bps_step numeric DEFAULT 25) RETURNS TABLE(event_id bigint, volume numeric, bps_level integer, bps_price numeric, bps_vwap numeric, direction character varying, pair character varying, exchange_timestamp timestamp with time zone, episode_no integer, snapshot_id integer)
    LANGUAGE sql
    AS $$

SELECT  event_id,
		abs(sum(order_qty)) AS volume,
		bps_level,
		bps_price,
		round(abs(sum(order_qty*order_price)/sum(order_qty)), "precision") AS bps_vwap,
		direction,
		pair,
		exchange_timestamp,
		episode_no,
		snapshot_id
FROM (
SELECT 	event_id, 
		order_price,
		order_qty, 
		(bf_depth_summary_before_episode_v.bps_step*bps_level)::integer AS bps_level,
		round(best_bid*(1 - bps_level*bf_depth_summary_before_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
		'bid' AS direction,
		pair,
		exchange_timestamp,
		episode_no,
		snapshot_id,
		"precision"
FROM (		
	SELECT 	event_id, 
			order_price, 
			order_qty, 
			ceiling((best_bid - order_price)/best_bid/bf_depth_summary_before_episode_v.bps_step*10000)::integer AS bps_level,
			best_bid,
			pair,
			exchange_timestamp,
			episode_no,
			snapshot_id
	FROM (
			SELECT 	event_id,
					order_price, 
					order_qty,
					first_value(order_price) OVER w AS best_bid, 
					pair,
					exchange_timestamp,
					episode_no,
					snapshot_id
			FROM bitfinex.bf_active_orders_before_episode_v
			WHERE snapshot_id = bf_depth_summary_before_episode_v.snapshot_id
			  AND episode_no BETWEEN bf_depth_summary_before_episode_v.first_episode_no 
											AND bf_depth_summary_before_episode_v.last_episode_no
			  AND bitfinex.bf_active_orders_before_episode_v.order_qty > 0
			WINDOW w AS (PARTITION BY episode_no ORDER BY order_price DESC)
	) r1
) r2 JOIN bf_pairs USING (pair)
UNION ALL
SELECT 	event_id, 
		order_price,
		order_qty, 
		(bf_depth_summary_before_episode_v.bps_step*bps_level)::integer AS bps_level,
		round(best_ask*(1 + bps_level*bf_depth_summary_before_episode_v.bps_step/10000), bf_pairs."precision") AS bps_price,
		'ask' AS direction,
		pair,
		exchange_timestamp,
		episode_no,
		snapshot_id,
		"precision"
FROM (		
	SELECT 	event_id, 
			order_price, 
			order_qty, 
			ceiling((order_price-best_ask)/best_ask/bf_depth_summary_before_episode_v.bps_step*10000)::integer AS bps_level,
			best_ask,
			pair,
			exchange_timestamp,
			episode_no,
			snapshot_id
	FROM (
			SELECT 	event_id,
					order_price, 
					order_qty,
					first_value(order_price) OVER w AS best_ask, 
					pair,
					exchange_timestamp,
					episode_no,
					snapshot_id
			FROM bitfinex.bf_active_orders_before_episode_v
			WHERE snapshot_id = bf_depth_summary_before_episode_v.snapshot_id
			  AND episode_no BETWEEN bf_depth_summary_before_episode_v.first_episode_no 
									AND bf_depth_summary_before_episode_v.last_episode_no
			  AND bitfinex.bf_active_orders_before_episode_v.order_qty < 0
			WINDOW w AS (PARTITION BY episode_no ORDER BY order_price)
	) r1
) r2 JOIN bf_pairs USING (pair)
) u 
GROUP BY event_id, pair, bps_level, bps_price, direction, exchange_timestamp, episode_no, snapshot_id, "precision";
	

$$;


ALTER FUNCTION bitfinex.bf_depth_summary_before_episode_v(snapshot_id integer, first_episode_no integer, last_episode_no integer, bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_fun_after_insert(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_fun_after_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE 

	trade_match_single CURSOR  FOR	SELECT qty 
									FROM bitfinex.bf_trades t
									WHERE t.price		= NEW.order_price
									  AND t.qty 		= NEW.event_qty
									  AND t.snapshot_id = NEW.snapshot_id
									  AND t.event_id IS NULL
									  AND t.exchange_timestamp >= NEW.exchange_timestamp - 1*interval '1 second'
									ORDER BY id;

BEGIN 
	UPDATE bitfinex.bf_order_book_events
	SET order_next_event_id = NEW.event_id
	WHERE snapshot_id = NEW.snapshot_id 
	  AND order_id = NEW.order_id 
	  AND event_id != NEW.event_id
	  AND order_next_event_id IS NULL;
	  
	FOR qty IN trade_match_single LOOP
	
		UPDATE bitfinex.bf_trades 
		SET event_id = NEW.event_id
		WHERE CURRENT OF trade_match_single;
		
		RETURN NULL;
	
	END LOOP;

	RETURN NULL;
END;

$$;


ALTER FUNCTION bitfinex.bf_order_book_events_fun_after_insert() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_fun_before_insert(); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.bf_order_book_events_fun_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE
	precision bitfinex.bf_pairs.precision%TYPE;
	previous_order bitfinex.bf_order_book_events%ROWTYPE;
	
BEGIN
	
	IF NEW.event_price != 0 THEN 
	
		SELECT bf_pairs.precision INTO precision 
		FROM bitfinex.bf_pairs
		WHERE pair = NEW.pair;

		NEW.event_price = round(NEW.event_price, precision);
		NEW.order_price = NEW.event_price;
		
		SELECT * INTO previous_order
		FROM bitfinex.bf_order_book_events
		WHERE order_id = NEW.order_id AND snapshot_id = NEW.snapshot_id
		ORDER BY event_id DESC
		LIMIT 1;
		
		IF FOUND THEN
			NEW.event_qty = NEW.order_qty - previous_order.order_qty;
		ELSE
			NEW.event_qty = NEW.order_qty;
		END IF;
		
	ELSE
	
		SELECT * INTO previous_order
		FROM bitfinex.bf_order_book_events
		WHERE order_id = NEW.order_id AND snapshot_id = NEW.snapshot_id
		ORDER BY event_id DESC
		LIMIT 1;
		
		IF FOUND THEN
			NEW.order_price = previous_order.order_price;
			NEW.event_qty = -previous_order.order_qty;
			NEW.order_qty = 0;
		ELSE
			RAISE EXCEPTION 'Requested removal of order: %  which is not in the order book!', NEW.order_id;
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
	RETURN NEW;
END;

$$;


ALTER FUNCTION bitfinex.bf_trades_fun_before_insert() OWNER TO "ob-analytics";

--
-- Name: bf_order_book_events_event_id_seq; Type: SEQUENCE; Schema: bitfinex; Owner: ob-analytics
--

CREATE SEQUENCE bitfinex.bf_order_book_events_event_id_seq
    START WITH 10
    INCREMENT BY 10
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bitfinex.bf_order_book_events_event_id_seq OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: bf_order_book_events; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.bf_order_book_events (
    order_id bigint,
    event_price numeric,
    order_qty numeric,
    local_timestamp timestamp(3) with time zone,
    pair character varying(12),
    event_id bigint DEFAULT nextval('bitfinex.bf_order_book_events_event_id_seq'::regclass) NOT NULL,
    order_price numeric,
    event_qty numeric,
    snapshot_id integer,
    episode_no integer,
    exchange_timestamp timestamp(3) with time zone,
    order_next_event_id bigint
);


ALTER TABLE bitfinex.bf_order_book_events OWNER TO "ob-analytics";

--
-- Name: bf_order_book_episodes_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_order_book_episodes_v AS
 SELECT DISTINCT ON (bf_order_book_events.snapshot_id, bf_order_book_events.episode_no) bf_order_book_events.snapshot_id,
    bf_order_book_events.episode_no,
    bf_order_book_events.event_id,
    bf_order_book_events.exchange_timestamp,
    bf_order_book_events.pair,
    bf_order_book_events.local_timestamp
   FROM bitfinex.bf_order_book_events
  ORDER BY bf_order_book_events.snapshot_id, bf_order_book_events.episode_no, bf_order_book_events.event_id;


ALTER TABLE bitfinex.bf_order_book_episodes_v OWNER TO "ob-analytics";

--
-- Name: bf_active_orders_before_episode_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_active_orders_before_episode_v AS
 SELECT e.episode_no,
    ob.order_price,
    ob.order_id,
    ob.event_id AS order_event_id,
    ob.order_qty,
        CASE
            WHEN (ob.order_qty < (0)::numeric) THEN sum(ob.order_qty) OVER asks
            ELSE sum(ob.order_qty) OVER bids
        END AS cumm_qty,
        CASE
            WHEN (ob.order_qty < (0)::numeric) THEN round((((10000)::numeric * (ob.order_price - first_value(ob.order_price) OVER asks)) / first_value(ob.order_price) OVER asks), 6)
            ELSE round((((10000)::numeric * (first_value(ob.order_price) OVER bids - ob.order_price)) / first_value(ob.order_price) OVER bids), 6)
        END AS bps,
        CASE
            WHEN (ob.order_qty < (0)::numeric) THEN dense_rank() OVER ask_prices
            ELSE dense_rank() OVER bid_prices
        END AS lvl,
    e.snapshot_id,
    e.event_id,
    e.pair,
    e.exchange_timestamp,
    ob.exchange_timestamp AS order_exchange_timestamp
   FROM bitfinex.bf_order_book_episodes_v e,
    LATERAL ( SELECT ob_1.event_id,
            ob_1.order_price,
            ob_1.order_qty,
            ob_1.event_price,
            ob_1.order_id,
            ob_1.exchange_timestamp
           FROM bitfinex.bf_order_book_events ob_1
          WHERE ((ob_1.snapshot_id = e.snapshot_id) AND (ob_1.event_id < e.event_id) AND (ob_1.event_price <> (0)::numeric) AND (COALESCE(ob_1.order_next_event_id, e.event_id) >= e.event_id))) ob
  WINDOW asks AS (PARTITION BY e.snapshot_id, e.episode_no, (sign(ob.order_qty)) ORDER BY ob.order_price, ob.order_id), bids AS (PARTITION BY e.snapshot_id, e.episode_no, (sign(ob.order_qty)) ORDER BY ob.order_price DESC, ob.order_id), ask_prices AS (PARTITION BY e.snapshot_id, e.episode_no, (sign(ob.order_qty)) ORDER BY ob.order_price), bid_prices AS (PARTITION BY e.snapshot_id, e.episode_no, (sign(ob.order_qty)) ORDER BY ob.order_price DESC)
  ORDER BY ob.order_price DESC, ((ob.order_id)::numeric * sign(ob.order_qty));


ALTER TABLE bitfinex.bf_active_orders_before_episode_v OWNER TO "ob-analytics";

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
    event_id bigint,
    snapshot_id integer,
    exchange_timestamp timestamp(3) with time zone
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
    i.event_id,
    i.event_qty,
    COALESCE(t.matched_qty, (0)::numeric) AS matched_qty,
    COALESCE(t.mc, (0)::bigint) AS matched_count,
    i.event_price,
    i.order_qty,
    i.order_price,
    i.order_id,
    i.pair,
    i.snapshot_id,
    t.last_trade_exchange_timestamp,
    i.episode_no,
    i.local_timestamp
   FROM (bitfinex.bf_order_book_events i
     LEFT JOIN LATERAL ( SELECT i.event_id,
            sum(bf_trades.qty) AS matched_qty,
            max(bf_trades.exchange_timestamp) AS last_trade_exchange_timestamp,
            count(*) AS mc
           FROM bitfinex.bf_trades
          WHERE (bf_trades.event_id = i.event_id)) t USING (event_id));


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
-- Name: bf_trades_v; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.bf_trades_v AS
 SELECT t.exchange_timestamp,
    t.id,
    t.qty,
    round(t.price, bf_pairs."precision") AS price,
    t.event_id,
    count(*) OVER (PARTITION BY t.event_id, t.snapshot_id) AS matched_count,
    t.trade_timestamp,
    t.pair,
    t.snapshot_id,
    e.episode_no,
    t.local_timestamp,
    (t.exchange_timestamp - t.trade_timestamp) AS sdelay,
    (e.exchange_timestamp - t.exchange_timestamp) AS edelay,
    (t.local_timestamp - t.exchange_timestamp) AS ndelay
   FROM ((bitfinex.bf_trades t
     JOIN bitfinex.bf_pairs USING (pair))
     LEFT JOIN bitfinex.bf_order_book_events e ON (((t.event_id = e.event_id) AND (t.snapshot_id = e.snapshot_id))))
  WHERE (t.local_timestamp IS NOT NULL);


ALTER TABLE bitfinex.bf_trades_v OWNER TO "ob-analytics";

--
-- Name: bf_snapshots snapshot_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('bitfinex.bf_snapshots_snapshot_id_seq'::regclass);


--
-- Name: bf_order_book_events bf_order_book_events_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_pkey PRIMARY KEY (event_id);


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
-- Name: bf_order_book_events_idx_order_id_snapshot_id; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_events_idx_order_id_snapshot_id ON bitfinex.bf_order_book_events USING btree (order_id, snapshot_id);


--
-- Name: bf_order_book_events_idx_order_next_event_id; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE UNIQUE INDEX bf_order_book_events_idx_order_next_event_id ON bitfinex.bf_order_book_events USING btree (order_next_event_id);


--
-- Name: bf_order_book_events_idx_snapshot_id; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_order_book_events_idx_snapshot_id ON bitfinex.bf_order_book_events USING btree (snapshot_id);


--
-- Name: bf_trades_idx_event_id; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_event_id ON bitfinex.bf_trades USING btree (event_id);


--
-- Name: bf_trades_idx_snapshot_id; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX bf_trades_idx_snapshot_id ON bitfinex.bf_trades USING btree (snapshot_id);


--
-- Name: bf_order_book_events after_insert; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER after_insert AFTER INSERT ON bitfinex.bf_order_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_fun_after_insert();


--
-- Name: bf_order_book_events before_insert; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER before_insert BEFORE INSERT ON bitfinex.bf_order_book_events FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_order_book_events_fun_before_insert();


--
-- Name: bf_trades before_insert; Type: TRIGGER; Schema: bitfinex; Owner: ob-analytics
--

CREATE TRIGGER before_insert BEFORE INSERT ON bitfinex.bf_trades FOR EACH ROW EXECUTE PROCEDURE bitfinex.bf_trades_fun_before_insert();


--
-- Name: bf_order_book_events bf_order_book_events_fkey_pair; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_pair FOREIGN KEY (pair) REFERENCES bitfinex.bf_pairs(pair) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: bf_order_book_events bf_order_book_events_fkey_snapshot_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_order_book_events
    ADD CONSTRAINT bf_order_book_events_fkey_snapshot_id FOREIGN KEY (snapshot_id) REFERENCES bitfinex.bf_snapshots(snapshot_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: bf_trades bf_trades_fkey_event_id; Type: FK CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.bf_trades
    ADD CONSTRAINT bf_trades_fkey_event_id FOREIGN KEY (event_id) REFERENCES bitfinex.bf_order_book_events(event_id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE;


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
-- PostgreSQL database dump complete
--

