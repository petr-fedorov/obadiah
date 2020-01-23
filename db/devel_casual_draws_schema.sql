-- Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation,  version 2 of the License

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

--
-- PostgreSQL database dump
--

-- Dumped from database version 11.6
-- Dumped by pg_dump version 11.6

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
-- Name: devel_casual_draws; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA devel_casual_draws;


ALTER SCHEMA devel_casual_draws OWNER TO "ob-analytics";

--
-- Name: bid_ask_spread; Type: TYPE; Schema: devel_casual_draws; Owner: ob-analytics
--

CREATE TYPE devel_casual_draws.bid_ask_spread AS (
	"timestamp" timestamp with time zone,
	"bid.price" double precision,
	"ask.price" double precision
);


ALTER TYPE devel_casual_draws.bid_ask_spread OWNER TO "ob-analytics";

--
-- Name: trading_period(timestamp with time zone, timestamp with time zone, integer, integer, double precision, interval); Type: FUNCTION; Schema: devel_casual_draws; Owner: ob-analytics
--

CREATE FUNCTION devel_casual_draws.trading_period(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_volume double precision, p_frequency interval) RETURNS SETOF devel_casual_draws.bid_ask_spread
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'CalculateTradingPeriod';


ALTER FUNCTION devel_casual_draws.trading_period(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_volume double precision, p_frequency interval) OWNER TO "ob-analytics";

--
-- PostgreSQL database dump complete
--

