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
-- Name: devel_imbalance; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA devel_imbalance;


ALTER SCHEMA devel_imbalance OWNER TO "ob-analytics";

--
-- Name: _to_postgres_microseconds(timestamp with time zone); Type: FUNCTION; Schema: devel_imbalance; Owner: ob-analytics
--

CREATE FUNCTION devel_imbalance._to_postgres_microseconds(p_timestamptz timestamp with time zone) RETURNS bigint
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'to_microseconds';


ALTER FUNCTION devel_imbalance._to_postgres_microseconds(p_timestamptz timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: queues(timestamp with time zone, timestamp with time zone, integer, integer, double precision, integer, integer, text, interval); Type: FUNCTION; Schema: devel_imbalance; Owner: ob-analytics
--

CREATE FUNCTION devel_imbalance.queues(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_tick_size double precision, p_first_tick integer, p_last_tick integer, p_tich_type text, p_frequency interval DEFAULT NULL::interval) RETURNS TABLE("timestamp" timestamp with time zone, "bid.price" double precision, "ask.price" double precision, b double precision[], a double precision[])
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'GetOrderBookQueues';


ALTER FUNCTION devel_imbalance.queues(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_tick_size double precision, p_first_tick integer, p_last_tick integer, p_tich_type text, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: trading_strategy(timestamp with time zone, timestamp with time zone, integer, integer, double precision, double precision, double precision, interval); Type: FUNCTION; Schema: devel_imbalance; Owner: postgres
--

CREATE FUNCTION devel_imbalance.trading_strategy(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_volume double precision DEFAULT 0, p_phi double precision DEFAULT 0.0, p_rho double precision DEFAULT 0.0, p_frequency interval DEFAULT NULL::interval) RETURNS TABLE("opened.at" timestamp with time zone, "open.price" double precision, "closed.at" timestamp with time zone, "close.price" double precision, "bps.return" double precision, rate double precision, "log.return" double precision)
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'DiscoverPositions';


ALTER FUNCTION devel_imbalance.trading_strategy(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_volume double precision, p_phi double precision, p_rho double precision, p_frequency interval) OWNER TO postgres;

--
-- Name: SCHEMA devel_imbalance; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA devel_imbalance TO obauser;


--
-- PostgreSQL database dump complete
--

