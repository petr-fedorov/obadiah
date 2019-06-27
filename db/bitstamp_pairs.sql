--
-- PostgreSQL database dump
--

-- Dumped from database version 11.2
-- Dumped by pg_dump version 11.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: pairs; Type: TABLE DATA; Schema: bitstamp; Owner: ob-analytics
--

COPY bitstamp.pairs (pair_id, pair, "R0") FROM stdin;
1	BTCUSD	2
2	LTCUSD	2
3	ETHUSD	2
4	XRPUSD	2
5	BCHUSD	2
6	BTCEUR	2
\.


--
-- PostgreSQL database dump complete
--

