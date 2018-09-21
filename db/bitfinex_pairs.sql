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
-- Data for Name: bf_pairs; Type: TABLE DATA; Schema: bitfinex; Owner: ob-analytics
--

COPY bitfinex.bf_pairs (pair, "R0", "P0", "P1", "P2", "P3") FROM stdin;
BTCUSD	2	1	0	-1	-2
\.


--
-- PostgreSQL database dump complete
--

