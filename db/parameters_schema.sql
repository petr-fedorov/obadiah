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
-- Name: parameters; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA parameters;


ALTER SCHEMA parameters OWNER TO "ob-analytics";

--
-- Name: max_microtimestamp_change(); Type: FUNCTION; Schema: parameters; Owner: ob-analytics
--

CREATE FUNCTION parameters.max_microtimestamp_change() RETURNS integer
    LANGUAGE plpgsql LEAKPROOF PARALLEL SAFE
    AS $$begin
	return 15; -- Bitstamp 4238507302 BTCEUR 2019-10-18 07:38:30.712732+03
end;
$$;


ALTER FUNCTION parameters.max_microtimestamp_change() OWNER TO "ob-analytics";

--
-- Name: FUNCTION max_microtimestamp_change(); Type: COMMENT; Schema: parameters; Owner: ob-analytics
--

COMMENT ON FUNCTION parameters.max_microtimestamp_change() IS 'A row-level trigger will not allow to change microtimestamp if the previous value is more seconds away than returned by this function';


--
-- PostgreSQL database dump complete
--

