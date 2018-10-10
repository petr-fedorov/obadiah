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
-- Name: live_orders_event; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.live_orders_event AS ENUM (
    'order_created',
    'order_changed',
    'order_deleted'
);


ALTER TYPE bitstamp.live_orders_event OWNER TO "ob-analytics";

--
-- Name: live_orders_type; Type: TYPE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TYPE bitstamp.live_orders_type AS ENUM (
    'buy',
    'sell'
);


ALTER TYPE bitstamp.live_orders_type OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: live_orders; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.live_orders (
    order_id bigint NOT NULL,
    amount numeric NOT NULL,
    event bitstamp.live_orders_event NOT NULL,
    order_type bitstamp.live_orders_type NOT NULL,
    datetime timestamp with time zone NOT NULL,
    microtimestamp timestamp with time zone,
    local_timestamp timestamp with time zone,
    pair_id smallint NOT NULL
);


ALTER TABLE bitstamp.live_orders OWNER TO "ob-analytics";

--
-- Name: pairs; Type: TABLE; Schema: bitstamp; Owner: ob-analytics
--

CREATE TABLE bitstamp.pairs (
    pair_id smallint NOT NULL,
    pair character varying NOT NULL
);


ALTER TABLE bitstamp.pairs OWNER TO "ob-analytics";

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
-- Name: live_orders live_orders_fkey_pairs; Type: FK CONSTRAINT; Schema: bitstamp; Owner: ob-analytics
--

ALTER TABLE ONLY bitstamp.live_orders
    ADD CONSTRAINT live_orders_fkey_pairs FOREIGN KEY (pair_id) REFERENCES bitstamp.pairs(pair_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

