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
-- Data for Name: pairs; Type: TABLE DATA; Schema: obanalytics; Owner: ob-analytics
--

COPY obanalytics.pairs (pair_id, pair, "R0", "P0", "P1", "P2", "P3") FROM stdin;
1	BTCUSD	2	\N	\N	\N	\N
2	LTCUSD	2	\N	\N	\N	\N
3	ETHUSD	2	\N	\N	\N	\N
4	XRPUSD	2	\N	\N	\N	\N
5	BCHUSD	2	\N	\N	\N	\N
6	BTCEUR	2	\N	\N	\N	\N
\.


--
-- PostgreSQL database dump complete
--

