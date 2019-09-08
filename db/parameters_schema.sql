--
-- PostgreSQL database dump
--

-- Dumped from database version 11.4
-- Dumped by pg_dump version 11.4

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
    AS $$
begin
	return 70; -- 60 seconds. 
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

