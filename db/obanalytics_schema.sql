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
-- Name: obanalytics; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA obanalytics;


ALTER SCHEMA obanalytics OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: pairs; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.pairs (
    pair_id smallint NOT NULL,
    pair text NOT NULL,
    "R0" smallint,
    "P0" smallint,
    "P1" smallint,
    "P2" smallint,
    "P3" smallint
);


ALTER TABLE obanalytics.pairs OWNER TO "ob-analytics";

--
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


--
-- PostgreSQL database dump complete
--

