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
-- Name: max_microtimestamp_change(integer, integer); Type: FUNCTION; Schema: parameters; Owner: ob-analytics
--

CREATE FUNCTION parameters.max_microtimestamp_change(p_pair_id integer, p_exchange_id integer) RETURNS integer
    LANGUAGE plpgsql LEAKPROOF PARALLEL SAFE
    AS $$begin
 case 
 	when p_pair_id = 6 and p_exchange_id = 2 then
		return 22; -- Bitstamp 4435127512 BTCEUR 2019-12-10 00:05:16.121599+03
	else
		return 5;
 end case;
end; 
$$;


ALTER FUNCTION parameters.max_microtimestamp_change(p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: FUNCTION max_microtimestamp_change(p_pair_id integer, p_exchange_id integer); Type: COMMENT; Schema: parameters; Owner: ob-analytics
--

COMMENT ON FUNCTION parameters.max_microtimestamp_change(p_pair_id integer, p_exchange_id integer) IS 'A row-level trigger will not allow to change microtimestamp if the previous value is more seconds away than returned by this function';


--
-- PostgreSQL database dump complete
--

