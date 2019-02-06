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
-- Data for Name: exchanges; Type: TABLE DATA; Schema: obanalytics; Owner: ob-analytics
--

COPY obanalytics.exchanges (exchange_id, exchange) FROM stdin;
1	bitfinex
2	bitstamp
3	coinbase
\.


--
-- PostgreSQL database dump complete
--

