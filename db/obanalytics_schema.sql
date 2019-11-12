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

-- Dumped from database version 11.5
-- Dumped by pg_dump version 11.5

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
-- Name: obanalytics; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA obanalytics;


ALTER SCHEMA obanalytics OWNER TO "ob-analytics";

--
-- Name: draw_interim_price; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.draw_interim_price AS (
	microtimestamp timestamp with time zone,
	price numeric
);


ALTER TYPE obanalytics.draw_interim_price OWNER TO "ob-analytics";

--
-- Name: level2_depth_record; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_record AS (
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2_depth_record OWNER TO "ob-analytics";

--
-- Name: level2_depth_summary_internal_state; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_summary_internal_state AS (
	full_depth obanalytics.level2_depth_record[],
	bps_step integer,
	max_bps_level integer,
	pair_id smallint
);


ALTER TYPE obanalytics.level2_depth_summary_internal_state OWNER TO "ob-analytics";

--
-- Name: level2_depth_summary_record; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_summary_record AS (
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2_depth_summary_record OWNER TO "ob-analytics";

--
-- Name: level2t; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2t AS (
	microtimestamp timestamp with time zone,
	pair_id smallint,
	exchange_id smallint,
	"precision" character(2),
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2t OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: level3; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3 (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.level3 OWNER TO "ob-analytics";

--
-- Name: COLUMN level3.exchange_microtimestamp; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.level3.exchange_microtimestamp IS 'An microtimestamp of an event as asigned by an exchange. Not null if different from ''microtimestamp''';


--
-- Name: pair_of_ob; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.pair_of_ob AS (
	ob1 obanalytics.level3[],
	ob2 obanalytics.level3[]
);


ALTER TYPE obanalytics.pair_of_ob OWNER TO "ob-analytics";

--
-- Name: matches; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.matches OWNER TO "ob-analytics";

--
-- Name: COLUMN matches.exchange_side; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.matches.exchange_side IS 'Type of trade as reported by an exchange. Not null if different from ''trade_type''';


--
-- Name: _create_level1_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_level1_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'level1';
	v_table_name := v_parent_table || '_' || p_exchange;

	i = 1;
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list ( pair_id )' ;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by range (microtimestamp)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'level1_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists '||V_SCHEMA ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column microtimestamp set statistics 1000 ';

	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp) ';  
	
	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_level1_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_level2_partition(text, text, character, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_precision) in ('r0', 'p0', 'p1', 'p2', 'p3', 'p4') then 
		raise exception 'Invalid p_precision: %. Valid values are r0, p0, p1, p2, p3, p4', p_precision;
	end if;
	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'level2';
	v_table_name := v_parent_table || '_' || p_exchange;

	i = 1;
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list ( pair_id )' ;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by list (precision)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_precision);
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| quote_literal(p_precision) || ') partition by range (microtimestamp)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column precision set default ' || quote_literal(p_precision);

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column microtimestamp set statistics 1000 ';

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'level2_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_precision || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists '||V_SCHEMA ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column precision set default ' || quote_literal(p_precision);

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp) ';  
	
	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_level3_partition(text, character, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_side) in ('b', 's') then 
		raise exception 'Invalid p_side: % ', p_side;
	end if;
	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'level3';
	v_table_name := v_parent_table || '_' || p_exchange;

	i = 1;
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list ( pair_id )' ;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by list (side)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column microtimestamp set statistics 1000 ';

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_side);
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| quote_literal(p_side) || ') partition by range (microtimestamp)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column side set default ' || quote_literal(p_side);
	
	

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_side || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists '||V_SCHEMA ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column side set default ' || quote_literal(p_side);

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp, order_id, event_no) ';  
	
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_next foreign key (next_microtimestamp, order_id, next_event_no) references '||V_SCHEMA ||v_table_name ||
							' match simple on update cascade on delete no action deferrable initially deferred';
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_price foreign key (price_microtimestamp, order_id, price_event_no) references '||V_SCHEMA ||v_table_name ||
							' match simple on update cascade on delete no action deferrable initially deferred';

	i := i+1;
	v_statements[i] := v_statement || '_unique_next unique (next_microtimestamp, order_id, next_event_no) deferrable initially deferred';
	
	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	
	i := i+1;
	v_statements[i] := 'create trigger '||v_table_name||'_ba_incorporate_new_event before insert on '||V_SCHEMA||v_table_name||
		' for each row execute procedure obanalytics.level3_incorporate_new_event()';

	i := i+1;
	v_statements[i] := 'create trigger '||v_table_name||'_bz_save_exchange_microtimestamp before update of microtimestamp on '||V_SCHEMA||v_table_name||
		' for each row execute procedure obanalytics.save_exchange_microtimestamp()';
		
    i := i+1;
	v_statements[i] := 'create index '||v_table_name||'_fkey_level3_price on '|| V_SCHEMA || v_table_name || '(price_microtimestamp, order_id, price_event_no)';

	
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_matches_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	v_buy_orders_table text;
	v_sell_orders_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'matches';
	v_table_name := v_parent_table || '_' || p_exchange;
	i = 1;
	
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list (pair_id)' ;
						
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	
	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	i := i + 1;

	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by range (microtimestamp)';

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'matches_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists '||V_SCHEMA ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
							
	i := i + 1;
	v_statements[i] := 'create trigger '||v_table_name||'_bz_save_exchange_microtimestamp before update of microtimestamp on '||V_SCHEMA||v_table_name||
		' for each row execute procedure obanalytics.save_exchange_microtimestamp()';
	
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;
	
	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;

	i := i+1;
	v_statements[i] := v_statement || '_unique_order_ids_combination unique (buy_order_id, sell_order_id) ';
	
	v_buy_orders_table :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || 'b' ||  p_year || lpad(p_month::text, 2, '0') ;	
	v_sell_orders_table :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || 's' ||  p_year || lpad(p_month::text, 2, '0') ;	

	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_buys  foreign key (buy_event_no, microtimestamp, buy_order_id) references '||V_SCHEMA ||v_buy_orders_table ||
							'(event_no, microtimestamp, order_id) match simple on update cascade on delete no action deferrable initially deferred';
							
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_sells  foreign key (sell_event_no, microtimestamp, sell_order_id) references '||V_SCHEMA ||v_sell_orders_table ||
							'(event_no, microtimestamp, order_id) match simple on update cascade on delete no action deferrable initially deferred';

	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	

	foreach v_statement in array v_statements loop
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_or_extend_draw(obanalytics.draw_interim_price[], timestamp with time zone, numeric, numeric, numeric); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_or_extend_draw(p_draw obanalytics.draw_interim_price[], p_microtimestamp timestamp with time zone, p_price numeric, p_minimal_draw numeric, p_minimal_draw_decline numeric) RETURNS obanalytics.draw_interim_price[]
    LANGUAGE plpgsql
    AS $$declare 
	ONE_PCT constant numeric := 0.01;	-- one percent
begin 
	if p_draw is null then	
		-- p_draw[1] - the current draw start
		-- p_draw[2] - the latest turning point (see below)
		-- p_draw[3] - the current draw end
		p_draw := array[row(p_microtimestamp, p_price), row(p_microtimestamp, p_price), row(p_microtimestamp,  p_price), row(p_microtimestamp,  0.0)];
	else
		-- The turning point helps us to decide whether the current draw is to be extended or a new draw is to be started
		if p_draw[2].price = p_price then 										-- extend the draw, keep the turning point
			p_draw[3] := row(p_microtimestamp, p_price);
		else
			if ( (p_draw[2].price >= p_draw[1].price and p_price > p_draw[2].price) or 	-- extend the draw, set the new turning point
			    (p_draw[2].price <= p_draw[1].price and p_price < p_draw[2].price) 	)  then 
					p_draw[2] := row(p_microtimestamp, p_price);
					p_draw[3] := row(p_microtimestamp, p_price);
					raise debug '%, % - the current draw extended', p_microtimestamp, p_price;
					
			else	-- check whether the current draw ended and new draw is to be started
				-- the magical formula below for p_minimal_draw ensures that the turning point will not be too far away
				p_minimal_draw := ONE_PCT*p_minimal_draw/(1 + p_minimal_draw_decline*extract(epoch from p_draw[2].microtimestamp - p_draw[1].microtimestamp));
				raise debug 'p_minimal draw %', p_minimal_draw;
				if abs(p_price - p_draw[2].price)>= abs(p_draw[2].price - p_draw[1].price)*p_minimal_draw then -- the turn after the curent draw exceeded  the minmal draw too so start new draw FROM THE TURNING POINT (i.e. in the past)
					raise debug '%, % - TURNING POINT: the draw % - % completed', p_microtimestamp, p_price, p_draw[1].microtimestamp, p_draw[2].microtimestamp;
					p_draw := array[p_draw[2],
									row(p_microtimestamp, p_price)::obanalytics.draw_interim_price,
									row(p_microtimestamp, p_price)::obanalytics.draw_interim_price
								   ];
				else	-- not yet, extend the turning draw from the turning point
					p_draw[3] := row(p_microtimestamp, p_price);
					raise debug '%, % - the draw after turning point extended', p_microtimestamp, p_price;
				end if;
			end if;
		end if;
	end if;
	return p_draw;
end;
$$;


ALTER FUNCTION obanalytics._create_or_extend_draw(p_draw obanalytics.draw_interim_price[], p_microtimestamp timestamp with time zone, p_price numeric, p_minimal_draw numeric, p_minimal_draw_decline numeric) OWNER TO "ob-analytics";

--
-- Name: _depth_after_depth_change(obanalytics.level2_depth_record[], obanalytics.level2_depth_record[], timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE plpgsql
    AS $$
begin 
	
	if p_depth is null then
		p_depth := array(	select row(price,  
											sum(amount),
									   		side,
									   		null
										 )::obanalytics.level2_depth_record
								 from obanalytics.order_book( p_microtimestamp, p_pair_id, p_exchange_id,
															p_only_makers := true,p_before := true) join unnest(ob) on true
								 group by ts, price, side
					  );
	end if;
	return array(  select row(price, volume, side, null)::obanalytics.level2_depth_record
					from (
						select coalesce(d.price, c.price) as price, coalesce(c.volume, d.volume) as volume, coalesce(d.side, c.side) as side
						from unnest(p_depth) d full join unnest(p_depth_change) c using (price, side)
					) a
					where volume <> 0
				 	order by price desc
				);
end;
$$;


ALTER FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: _depth_change(obanalytics.pair_of_ob); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change(p_obs obanalytics.pair_of_ob) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql
    AS $$
select * from obanalytics._depth_change(
	coalesce(p_obs.ob1,
			 coalesce ( (   select ob 
							from obanalytics.order_book( ( select max(microtimestamp) from unnest(p_obs.ob2)),	-- ob's ts is max(microtimestamp), see order_book() code
														  ( select pair_id from unnest(p_obs.ob2) limit 1),
														  ( select exchange_id from unnest(p_obs.ob2) limit 1),
														  p_only_makers := true,
														  p_before := true,	-- we need ob BEFORE here
														  p_check_takers := true))),
			 			p_obs.ob2 ),
			  p_obs.ob2);

$$;


ALTER FUNCTION obanalytics._depth_change(p_obs obanalytics.pair_of_ob) OWNER TO "ob-analytics";

--
-- Name: _depth_change(obanalytics.level3[], obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql
    AS $$select array_agg(row(price, coalesce(af.amount, 0), side, null::integer)::obanalytics.level2_depth_record  order by price, side)
from (
	select a.price, sum(a.amount) as amount,a.side
	from unnest(p_ob_before) a 
	-- where a.is_maker 
	group by a.price, a.side, a.pair_id
) bf full join (
	select a.price, sum(a.amount) as amount, a.side
	from unnest(p_ob_after) a 
	-- where a.is_maker 
	group by a.price, a.side, a.pair_id
) af using (price, side)
where bf.amount is distinct from af.amount$$;


ALTER FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: _depth_change_sfunc(obanalytics.pair_of_ob, obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change_sfunc(p_obs obanalytics.pair_of_ob, p_ob obanalytics.level3[]) RETURNS obanalytics.pair_of_ob
    LANGUAGE sql STABLE
    AS $$
	select (p_obs.ob2, p_ob)::obanalytics.pair_of_ob;

$$;


ALTER FUNCTION obanalytics._depth_change_sfunc(p_obs obanalytics.pair_of_ob, p_ob obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: _depth_summary(obanalytics.level2_depth_summary_internal_state); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_summary(p_depth obanalytics.level2_depth_summary_internal_state) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql STABLE
    AS $$

with depth as (
	select price, volume, side
	from unnest(p_depth.full_depth) d
),	
depth_with_best_prices as (
	select min(price) filter(where side = 's') over () as best_ask_price, 
			max(price) filter(where side = 'b') over () as best_bid_price, 
			price,
			volume as amount,
			side
	from depth
),
depth_with_bps_levels as (
	select amount, 
			price,
			side,
			case side
				when 's' then ceiling((price-best_ask_price)/best_ask_price/p_depth.bps_step*10000)::numeric	
				when 'b' then ceiling((best_bid_price-price)/best_bid_price/p_depth.bps_step*10000)::numeric	
			end*p_depth.bps_step as bps_level,
			best_ask_price,
			best_bid_price
	from depth_with_best_prices
),
depth_with_price_adjusted as (
	select amount,
			case side
				when 's' then round(best_ask_price*(1 + bps_level/10000), (select "R0" from obanalytics.pairs where pair_id = p_depth.pair_id)) 
				when 'b' then round(best_bid_price*(1 - bps_level/10000), (select "R0" from obanalytics.pairs where pair_id = p_depth.pair_id)) 
			end as price,
			side,
			bps_level
	from depth_with_bps_levels 
	where bps_level <= p_depth.max_bps_level
),
depth_summary as (
	select price, 
			sum(amount), 
			side, 
			bps_level::bigint
	from depth_with_price_adjusted
	group by 1, 3, 4
)
select array_agg(depth_summary::obanalytics.level2_depth_record)
from depth_summary

$$;


ALTER FUNCTION obanalytics._depth_summary(p_depth obanalytics.level2_depth_summary_internal_state) OWNER TO "ob-analytics";

--
-- Name: _depth_summary_after_depth_change(obanalytics.level2_depth_summary_internal_state, obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_summary_after_depth_change(p_internal_state obanalytics.level2_depth_summary_internal_state, p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) RETURNS obanalytics.level2_depth_summary_internal_state
    LANGUAGE sql STABLE
    AS $$
select obanalytics._depth_after_depth_change(p_internal_state.full_depth, p_depth_change, p_microtimestamp, p_pair_id, p_exchange_id),
		p_bps_step, 
		p_max_bps_level,
		p_pair_id::smallint;
$$;


ALTER FUNCTION obanalytics._depth_summary_after_depth_change(p_internal_state obanalytics.level2_depth_summary_internal_state, p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_level1_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_level1_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	v_table_name :=  'level1_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_level1_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_level2_partition(text, text, character, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_precision) in ('r0', 'p0', 'p1', 'p2', 'p3', 'p4') then 
		raise exception 'Invalid p_precision: %. Valid values are r0, p1, p2, p3, p4', p_precision;
	end if;

	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	v_table_name :=  'level2_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_precision || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_level3_partition(text, character, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_side) in ('b', 's') then 
		raise exception 'Invalid p_side: % ', p_side;
	end if;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	v_table_name :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_side || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_matches_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);
	
	v_table_name :=  'matches_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _is_valid_taker_event(timestamp with time zone, bigint, integer, integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._is_valid_taker_event(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id integer, p_exchange_id integer, p_next_microtimestamp timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
begin 
	if p_next_microtimestamp = '-infinity' then
		return true;
	else
		raise exception 'Invalid taker event: % % % % %', p_microtimestamp, p_order_id, p_event_no, 
				(select pair from obanalytics.pairs where pair_id = p_pair_id),
				(select exchange from obanalytics.exchanges where exchange_id = p_exchange_id);
	end if;				
end;
$$;


ALTER FUNCTION obanalytics._is_valid_taker_event(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id integer, p_exchange_id integer, p_next_microtimestamp timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: _level3_uuid(timestamp with time zone, bigint, integer, smallint, smallint); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._level3_uuid(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id smallint, p_exchange_id smallint) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    AS $$select md5(p_microtimestamp::text||'#'||p_order_id::text||'#'||p_event_no::text||'#'||p_exchange_id||'#'||p_pair_id)::uuid;$$;


ALTER FUNCTION obanalytics._level3_uuid(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id smallint, p_exchange_id smallint) OWNER TO "ob-analytics";

--
-- Name: _order_book_after_episode(obanalytics.level3[], obanalytics.level3[], boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._order_book_after_episode(p_ob obanalytics.level3[], p_ep obanalytics.level3[], p_check_takers boolean) RETURNS obanalytics.level3[]
    LANGUAGE plpgsql STABLE
    AS $$begin
	if p_ob is null then
		select ob into p_ob
		from obanalytics.order_book(p_ep[1].microtimestamp, p_ep[1].pair_id, p_ep[1].exchange_id, p_only_makers := false, p_before := true, p_check_takers := p_check_takers );
	end if;
	
	return ( with mix as (
						select ob.*, false as is_deleted
						from unnest(p_ob) ob
						union all
						select ob.*, next_microtimestamp = '-infinity'::timestamptz as is_deleted
						from unnest(p_ep) ob
					),
					latest_events as (
						select distinct on (order_id) *
						from mix
						order by order_id, event_no desc	-- just take the latest event_no for each order
					),
					orders as (
					select microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp,
							price_microtimestamp, price_event_no, exchange_microtimestamp, 
							coalesce(
								case side
									when 'b' then price <= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
									when 's' then price >= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
								end,
							true) -- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
							as is_maker,
							coalesce(
								case side 
									when 'b' then price > min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
									when 's' then price < max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
								end,
							false )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are not crossed
							as is_crossed
					from latest_events
					where not is_deleted
				)
				select array(
					select orders::obanalytics.level3
					from orders
					where not p_check_takers 
					    or (is_maker or (not is_maker and obanalytics._is_valid_taker_event(microtimestamp, order_id, event_no, pair_id, exchange_id, next_microtimestamp)))
					order by price, microtimestamp, order_id, event_no 
					-- order by must be the same as in obanalytics.order_book(). Change both!					
				));
end;   

$$;


ALTER FUNCTION obanalytics._order_book_after_episode(p_ob obanalytics.level3[], p_ep obanalytics.level3[], p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: _periods_within_eras(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._periods_within_eras(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) RETURNS TABLE(period_start timestamp with time zone, period_end timestamp with time zone, previous_period_end timestamp with time zone)
    LANGUAGE sql
    AS $$	select period_start, period_end, lag(period_end) over (order by period_start) as previous_period_end
	from (
		select period_start, period_end
		from (
			select greatest(get._date_ceiling(era, p_frequency), get._date_floor(p_start_time, p_frequency)) as period_start, 
					least(coalesce(get._date_floor(level3, p_frequency), get._date_ceiling(era, p_frequency)), get._date_floor(p_end_time, p_frequency)) as period_end
			from obanalytics.level3_eras
			where pair_id = p_pair_id
			  and exchange_id = p_exchange_id
			  and get._date_floor(p_start_time, p_frequency) <= coalesce(get._date_floor(level3, p_frequency), get._date_ceiling(era, p_frequency))
			  and get._date_floor(p_end_time, p_frequency) >= get._date_ceiling(era, p_frequency)
		) e
		where get._date_floor(period_end, p_frequency) > get._date_floor(period_start, p_frequency)
	) p
$$;


ALTER FUNCTION obanalytics._periods_within_eras(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: level1; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1 (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.level1 OWNER TO "ob-analytics";

--
-- Name: _spread_from_order_book(timestamp with time zone, obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._spread_from_order_book(p_ts timestamp with time zone, p_order_book obanalytics.level3[]) RETURNS obanalytics.level1
    LANGUAGE sql IMMUTABLE
    AS $$
with price_levels as (
	select side,
			price,
			sum(amount) as qty, 
			case side
					when 's' then price is not distinct from min(price) filter (where side = 's') over ()
					when 'b' then price is not distinct from max(price) filter (where side = 'b') over ()
			end as is_best,
			pair_id,
			exchange_id
	from unnest(p_order_book)
	--where is_maker
	group by exchange_id, pair_id,side, price
)
select b.price, b.qty, s.price, s.qty, p_ts, pair_id, exchange_id
from (select * from price_levels where side = 'b' and is_best) b full join 
	  (select * from price_levels where side = 's' and is_best) s using (exchange_id, pair_id);

$$;


ALTER FUNCTION obanalytics._spread_from_order_book(p_ts timestamp with time zone, p_order_book obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: check_microtimestamp_change(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.check_microtimestamp_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	if  new.microtimestamp > old.microtimestamp + make_interval(secs := parameters.max_microtimestamp_change()) or
		new.microtimestamp < old.microtimestamp then	
		raise exception 'An attempt to move % % % % % to % is blocked', old.microtimestamp, old.order_id, old.event_no, old.pair_id, old.exchange_id, new.microtimestamp;
	end if;
	return null;
END;
	

$$;


ALTER FUNCTION obanalytics.check_microtimestamp_change() OWNER TO "ob-analytics";

--
-- Name: create_partitions(text, text, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.create_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin 
	perform obanalytics._create_level1_partition(p_exchange, p_pair, p_year, p_month);
	perform obanalytics._create_level2_partition(p_exchange, p_pair, 'r0', p_year, p_month);
	perform obanalytics._create_level3_partition(p_exchange, 'b', p_pair, p_year, p_month);
	perform obanalytics._create_level3_partition(p_exchange, 's', p_pair, p_year, p_month);
	perform obanalytics._create_matches_partition(p_exchange, p_pair, p_year, p_month);
end;
$$;


ALTER FUNCTION obanalytics.create_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) OWNER TO "ob-analytics";

--
-- Name: crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(previous_uncrossed timestamp with time zone, first_crossed timestamp with time zone, next_uncrossed timestamp with time zone, pair_id smallint, exchange_id smallint)
    LANGUAGE sql STABLE
    AS $$

with base_order_books as (
	select ts, exists (select * from unnest(ob) where not is_maker) as is_crossed
	from  obanalytics.order_book_by_episode(p_start_time, p_end_time + 
											make_interval(
												secs := parameters.max_microtimestamp_change()),	-- next_uncrossed may be few seconds beyond p_end_time
											p_pair_id, p_exchange_id, false) ob					-- if we dont' find it, merge_crossed_books() will stuck 
																								-- i.e. will not be able to fix an invalid taker event
	),
order_books as (
	select ts, is_crossed, 
	coalesce(max(ts) filter (where not is_crossed) over (order by ts), p_start_time - '00:00:00.000001'::interval ) as previous_uncrossed,
	min(ts) filter (where not is_crossed) over (order by ts desc) as next_uncrossed,
	min(ts) filter (where is_crossed) over (order by ts) as first_crossed
	from base_order_books 
)
select distinct previous_uncrossed, first_crossed, next_uncrossed, p_pair_id::smallint, p_exchange_id::smallint
from order_books
where is_crossed 
  and previous_uncrossed < p_end_time
;  
$$;


ALTER FUNCTION obanalytics.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: level2; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.level2 OWNER TO "ob-analytics";

--
-- Name: depth_change_by_episode(timestamp with time zone, timestamp with time zone, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean DEFAULT true) RETURNS SETOF obanalytics.level2
    LANGUAGE plpgsql STABLE
    AS $$-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of depths
--		p_end_time	 - the end of the interval
--		p_pair_id	 - the id of pair for which depths will be calculated
--		p_exchange_id - the id of exchange where depths will be calculated
-- NOTE
--		Precision of depth is P0, i.e. not rounded prices are used
declare
	v_ob_before record;
	v_ob record;
begin
	
	select ts, ob 
	from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := true) 
	into v_ob_before;	-- so there will be a depth_change generated for the very first episode greater or equal to p_start_time
	
	for v_ob in select ts, ob from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers) 
	loop
		if v_ob_before is not null then -- if p_start_time equals to an era start then v_ob_before will be null 
										 -- so we don't generate depth_change for the era start
													 
			return query 
				select v_ob.ts, p_pair_id::smallint, p_exchange_id::smallint, 'r0'::character(2), coalesce(d, '{}')
				from obanalytics._depth_change(v_ob_before.ob, v_ob.ob) d;
		end if;
		v_ob_before := v_ob;
	end loop;			
end;

$$;


ALTER FUNCTION obanalytics.depth_change_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: depth_change_by_episode2(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode2(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level2
    LANGUAGE plpython2u STABLE
    AS $_$

from obadiah_db.orderbook import OrderBook
# import logging
# logging.basicConfig(filename='log/obadiah_db.log',level=logging.DEBUG)

def generator():
	ob=OrderBook(False) 
	ob.update(
		plpy.execute(
			plpy.prepare('''select ob.* 
							from obanalytics.order_book( $1, $2, $3, false, true, $4 ) join unnest(ob) ob on true
						 ''', ["timestamptz", "integer", "integer", "boolean"]),
		[p_start_time, p_pair_id, p_exchange_id, False]))
	for e in plpy.cursor(
		plpy.prepare('''	with level3 as (
					 			-- we take only the latest event per episode. In case an order was created and deleted within an episode it will be ignored completely ...
								select distinct on (microtimestamp, order_id) *	
								from obanalytics.level3
								where microtimestamp between $1 and $2
							  	  and pair_id = $3
							   	  and exchange_id = $4
								order by microtimestamp, order_id, event_no desc
							)
							select microtimestamp as ts, array_agg(level3) as episode
							from level3
							group by microtimestamp
					 		order by microtimestamp
					''',["timestamptz", "timestamptz", "integer", "integer"]),
		[p_start_time, p_end_time, p_pair_id, p_exchange_id]):
		
		yield {"microtimestamp": e["ts"], "pair_id": p_pair_id, "exchange_id": p_exchange_id, "precision":'r0', "depth_change": ob.update(e["episode"])}
return generator()

$_$;


ALTER FUNCTION obanalytics.depth_change_by_episode2(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: depth_change_by_episode4(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode4(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level2t
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'depth_change_by_episode';


ALTER FUNCTION obanalytics.depth_change_by_episode4(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: draws_from_spread(timestamp with time zone, timestamp with time zone, integer, integer, text, interval, boolean, numeric, numeric, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.draws_from_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer, p_pair_id integer, p_draw_type text, p_frequency interval DEFAULT NULL::interval, p_skip_crossed boolean DEFAULT true, p_minimal_draw_pct numeric DEFAULT 0.0, p_minimal_draw_decline numeric DEFAULT 0.01, p_price_decimal_places integer DEFAULT 2) RETURNS TABLE(start_microtimestamp timestamp with time zone, end_microtimestamp timestamp with time zone, last_microtimestamp timestamp with time zone, start_price numeric, end_price numeric, last_price numeric, exchange_id smallint, pair_id smallint, draw_type text, draw_size numeric, minimal_draw numeric, exchange text, pair text)
    LANGUAGE sql STABLE
    AS $$ 

with spread as (
	select microtimestamp, best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, pair_id 
	from obanalytics.level1_continuous(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency, p_skip_crossed)
),
base_draws as (
	select spread.*,
			obanalytics.draw_agg(microtimestamp,
								 case p_draw_type 
								 	when 'bid' then round(best_bid_price, p_price_decimal_places)
								    when 'ask' then round(best_ask_price, p_price_decimal_places)
								    when 'mid-price' then round((best_bid_price + best_ask_price)/2, p_price_decimal_places)
								 end,
								 p_minimal_draw_pct, p_minimal_draw_decline) over w as draw, 
			p_draw_type as draw_type
	from spread
	window w as (order by microtimestamp)
),
draws as (
	select draw[1].microtimestamp as start_microtimestamp, 
			draw[1].price as start_price, 
			draw[2].microtimestamp as end_microtimestamp,
			draw[2].price as end_price,
			draw[3].microtimestamp as last_microtimestamp,
			draw[3].price as last_price,
			draw_type
	from base_draws
)
select distinct on (start_microtimestamp, draw_type )
					 start_microtimestamp, 
					 last_value(end_microtimestamp) over w as end_microtimestamp,
					 last_microtimestamp,
					 start_price, 
					 last_value(end_price) over w as end_price,
					 last_price,
					 p_exchange_id::smallint, 
					 p_pair_id::smallint,
					 draw_type,
					 round((end_price - start_price)/start_price * 10000.0, 2),
					 p_minimal_draw_pct,
					 (select exchange from obanalytics.exchanges where exchange_id = p_exchange_id),
					 (select pair from obanalytics.pairs where pair_id = p_pair_id)
from draws
window w as ( partition by start_microtimestamp, draw_type order by end_microtimestamp )
order by draw_type, start_microtimestamp, end_microtimestamp desc, last_microtimestamp desc	

$$;


ALTER FUNCTION obanalytics.draws_from_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer, p_pair_id integer, p_draw_type text, p_frequency interval, p_skip_crossed boolean, p_minimal_draw_pct numeric, p_minimal_draw_decline numeric, p_price_decimal_places integer) OWNER TO "ob-analytics";

--
-- Name: drop_leaf_partitions(text, text, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.drop_leaf_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin 
	perform obanalytics._drop_leaf_matches_partition(p_exchange, p_pair, p_year, p_month, true);
	perform obanalytics._drop_leaf_level3_partition(p_exchange, 'b', p_pair, p_year, p_month, true);
	perform obanalytics._drop_leaf_level3_partition(p_exchange, 's', p_pair, p_year, p_month, true);
	perform obanalytics._drop_leaf_level2_partition(p_exchange, p_pair, 'p0', p_year, p_month, true);	
	perform obanalytics._drop_leaf_level1_partition(p_exchange, p_pair, p_year, p_month, true);
	
end;
$$;


ALTER FUNCTION obanalytics.drop_leaf_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) OWNER TO "ob-analytics";

--
-- Name: fix_crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.fix_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$-- NOTE:
--		This function is supposed to be doing something useful only after pga_spread() is failed due to crossed order book
--		It is expected that Bitfinex produces rather few 'bad' events and rarely, so order book is crossed for relatively short
-- 		period of time (i.e. 5 minutes). Otherwise one has to run this function manually, with higher p_max_interval

declare 
	v_current_timestamp timestamptz;
	
begin 
	v_current_timestamp := clock_timestamp();
	raise debug 'Started fix_crossed_books(%, %, %, %)', p_start_time, p_end_time, p_pair_id, p_exchange_id;
	
	-- Merge crossed books to the next taker's event if it is exists (i.e. next_microtimestamp is not -infinity)
	return query 		
		with takers as (
			select distinct  on (microtimestamp, order_id, event_no) microtimestamp, order_id, next_microtimestamp, next_event_no
			from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers :=false) 
			join unnest(ob) as ob on true
			where not is_maker
			  and next_microtimestamp > '-infinity'
			  and next_microtimestamp <= microtimestamp + make_interval(secs := parameters.max_microtimestamp_change())
			order by microtimestamp, order_id, event_no,
					  ts	-- we need the earliest ts where order book became crossed			
		),
		merge_intervals as (	-- there may be several takers, so first we need to understand which episodes to merge. 
								-- the algorithm has been adapted from here: https://wiki.postgresql.org/wiki/Range_aggregation
			select min(microtimestamp) as microtimestamp, max(next_microtimestamp) as next_microtimestamp 
			from (
				select microtimestamp, order_id, next_microtimestamp, next_event_no, last(interval_start) over (order by microtimestamp) as interval_start
				from (
					select microtimestamp, order_id, next_microtimestamp, next_event_no,
							case when microtimestamp < coalesce(max(next_microtimestamp) over (order by microtimestamp rows between unbounded preceding and 1 preceding), microtimestamp) then null
									else microtimestamp end 
							as interval_start
					from takers		
				) takers
			) merge_intervals
			group by interval_start
		)
		select merge_episodes.*
		from merge_intervals join obanalytics.merge_episodes(microtimestamp, next_microtimestamp, p_pair_id, p_exchange_id) on true;
	
	raise debug 'Merged crossed books to the next takers event - fix_crossed_books(%, %, %, %)', p_start_time, p_end_time, p_pair_id, p_exchange_id;
	
	-- Fix eternal crossed orders, which should have been removed by an exchange, but weren't for some reasons
	return query 
		insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no)
		select distinct on (microtimestamp, order_id)  ts, order_id, 
				null as event_no, -- null here (as well as any null below) should case before row trigger to fire and to update the previous event 
				side, price, amount, fill, '-infinity',
				null as next_event_no,
				pair_id, exchange_id, null as local_timestamp,
				null as price_microtimestamp, 
				null as price_event_no
		from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers :=false) 
		join unnest(ob) ob on true 
		where is_crossed and next_microtimestamp = 'infinity'
		order by microtimestamp, order_id,
				  ts	-- we need the earliest ts where order book became crossed
		returning level3.*;
		
	raise debug 'Fixed eternal crossed orders - fix_crossed_books(%, %, %, %)', p_start_time, p_end_time, p_pair_id, p_exchange_id;
	
	
	-- Fix eternal takers, which should have been removed by an exchange, but weren't for some reasons
	return query 
		insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no)
		select distinct on (microtimestamp, order_id)  ts, order_id, 
				null as event_no, -- null here (as well as any null below) should case before row trigger to fire and to update the previous event 
				side, price, amount, fill, '-infinity',
				null as next_event_no,
				pair_id, exchange_id, null as local_timestamp,
				null as price_microtimestamp, 
				null as price_event_no
		from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers :=false) 
		join unnest(ob) ob on true 
		where not is_maker and next_microtimestamp = 'infinity'
		order by microtimestamp, order_id,
				  ts	-- we need the earliest ts where order book became crossed
		returning level3.*;
		
	raise debug 'Fixed eternal takers  - fix_crossed_books(%, %, %, %)', p_start_time, p_end_time, p_pair_id, p_exchange_id;
	
	
	-- Finally, try to merge remaining episodes producing crossed order books
	return query select * from obanalytics.merge_crossed_books(p_start_time, p_end_time, p_pair_id, p_exchange_id); 
	

	raise debug 'fix_crossed_books() exec time: %', clock_timestamp() - v_current_timestamp;
	return;
end;

$$;


ALTER FUNCTION obanalytics.fix_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: level3_eras; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_eras (
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL,
    level1 timestamp with time zone,
    level2 timestamp with time zone,
    level3 timestamp with time zone
);


ALTER TABLE obanalytics.level3_eras OWNER TO "ob-analytics";

--
-- Name: COLUMN level3_eras.level1; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.level3_eras.level1 IS 'A microtimestamp of the latest calculated level1 event in this era ';


--
-- Name: insert_level3_era(timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.insert_level3_era(p_new_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3_eras
    LANGUAGE plpgsql
    AS $$
declare
	v_previous_era obanalytics.level3_eras%rowtype;
	v_new_era obanalytics.level3_eras%rowtype;
	v_next_era obanalytics.level3_eras%rowtype;
begin

	select distinct on (pair_id, exchange_id) * into strict v_previous_era 
	from obanalytics.level3_eras
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and era <= p_new_era
	order by exchange_id, pair_id, era desc;
	
	select distinct on (pair_id, exchange_id) * into strict v_next_era 
	from obanalytics.level3_eras
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and era >= p_new_era
	order by exchange_id, pair_id, era ;
	
	
	if exists (select * 
			    from obanalytics.level1 
			    where microtimestamp >= p_new_era 
			   	  and microtimestamp < v_next_era.era
			      and pair_id = p_pair_id
			      and exchange_id = p_exchange_id ) or
		exists (select * 
			    from obanalytics.level2
			    where microtimestamp >= p_new_era 
				  and microtimestamp < v_next_era.era
			      and pair_id = p_pair_id
			      and exchange_id = p_exchange_id ) then 
		raise exception 'Can not insert new era - clear level1 & level2 first!';
	end if;
	
	if p_new_era = v_previous_era.era or p_new_era = v_next_era.era then
		raise exception 'Can not insert new era - already exists!';
	end if;
	
	with recursive to_be_updated as (
		select next_microtimestamp as microtimestamp, order_id, next_event_no as event_no, 2::integer as new_event_no,
				p_new_era as new_price_microtimestamp,	1::integer as new_price_event_no 
		from obanalytics.level3
		where exchange_id = p_exchange_id
		  and pair_id = p_pair_id
		  and microtimestamp >= v_previous_era.era
		  and microtimestamp < p_new_era
		  and next_microtimestamp >= p_new_era
		  and isfinite(next_microtimestamp)
		union all
		select next_microtimestamp, order_id, next_event_no, to_be_updated.new_event_no + 1,
				case when price_microtimestamp < new_price_microtimestamp 
						then new_price_microtimestamp
					  else price_microtimestamp
				end,
				case when price_microtimestamp < new_price_microtimestamp 
						then price_event_no 
					  else event_no
				end
		from (select * from obanalytics.level3 
			   where microtimestamp >= p_new_era
				 and microtimestamp < v_next_era.era
				 and exchange_id = p_exchange_id
				 and pair_id = p_pair_id
			  ) level3 join to_be_updated using (microtimestamp, order_id, event_no)
		where isfinite(next_microtimestamp)
	)
	update obanalytics.level3
	   set event_no = to_be_updated.new_event_no,
	   	    price_microtimestamp = to_be_updated.new_price_microtimestamp,
			price_event_no = to_be_updated.new_price_event_no
	from to_be_updated
	where level3.pair_id = p_pair_id
	  and level3.exchange_id = p_exchange_id
	  and level3.microtimestamp >= p_new_era
	  and level3.microtimestamp < v_next_era.era
	  and level3.microtimestamp = to_be_updated.microtimestamp
	  and level3.order_id = to_be_updated.order_id
	  and level3.event_no = to_be_updated.event_no;
	
	insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, 
								     pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp)
	select p_new_era,
			order_id,
			1,				-- event_no: must be always 1
			side, 
			price, 
			amount, 
			fill,
			next_microtimestamp, 
			next_event_no,
			pair_id,
			exchange_id,
			null::timestamptz,	--	local_timestamp
			p_new_era,
			1,
			null::timestamptz	-- exchange_timestamp
	from obanalytics.level3
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= v_previous_era.era 
	  and microtimestamp < p_new_era
	  and next_microtimestamp >= p_new_era
	  and next_microtimestamp < 'infinity';
	  
	update obanalytics.level3	  
	  set next_microtimestamp = 'infinity',
	      next_event_no = null
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= v_previous_era.era 
	  and microtimestamp < p_new_era
	  and next_microtimestamp >= p_new_era
	  and next_microtimestamp < 'infinity'
	  ;
	  
	update obanalytics.level3_eras
	  set  level2 = (select max(microtimestamp) 
					from obanalytics.level2
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era),
	   	    level1 = (select max(microtimestamp) 
					from obanalytics.level1
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era),
	  		 level3 = (select max(microtimestamp) 
					from obanalytics.level3
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era)
	where era = v_previous_era.era
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;
	  
    insert into obanalytics.level3_eras (era, pair_id, exchange_id, level3)	  
	values (p_new_era, p_pair_id, p_exchange_id, (select max(microtimestamp)
					   	 from obanalytics.level3
					     where pair_id = p_pair_id
					       and exchange_id = p_exchange_id
					       and microtimestamp >= p_new_era
					       and microtimestamp < v_next_era.era ));
	return query select *
				  from obanalytics.level3_eras
				  where pair_id = p_pair_id
				    and exchange_id = p_exchange_id
					and era between v_previous_era.era and v_next_era.era;
	return;
end;
$$;


ALTER FUNCTION obanalytics.insert_level3_era(p_new_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: level1_continuous(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level1_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval, p_skip_crossed boolean DEFAULT true) RETURNS SETOF obanalytics.level1
    LANGUAGE sql STABLE
    AS $$-- NOTE:

with periods as (
	select * 
	from obanalytics._periods_within_eras(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency)
)
select level1.*
from periods join obanalytics.spread_by_episode3(period_start, period_end, p_pair_id, p_exchange_id, p_frequency) level1 on true 
where not p_skip_crossed or (best_bid_price <= best_ask_price)
  ;

$$;


ALTER FUNCTION obanalytics.level1_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval, p_skip_crossed boolean) OWNER TO "ob-analytics";

--
-- Name: level1_update_level3_eras(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level1_update_level3_eras() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin 
	with latest_events as (
		select exchange_id, pair_id, max(microtimestamp) as latest
		from inserted
		group by exchange_id, pair_id
	),
	eras as (
		select exchange_id, pair_id, latest, max(era) as era
		from obanalytics.level3_eras join latest_events using (exchange_id, pair_id)
		where era <= latest
		group by exchange_id, pair_id, latest
	)
	update obanalytics.level3_eras
	   set level1 = latest
	from eras
	where level3_eras.era = eras.era
	  and level3_eras.exchange_id = eras.exchange_id
	  and level3_eras.pair_id = eras.pair_id
	  and (level1 is null or level1 < latest);
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level1_update_level3_eras() OWNER TO "ob-analytics";

--
-- Name: level2_continuous(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level2t
    LANGUAGE sql STABLE
    AS $$-- NOTE:
--	When 'microtimestamp' in returned record 
--		1. equals to 'p_start_time' and equals to some 'era' from obanalytics.level3_eras then 'depth_change' is a full depth from obanalytics.order_book(microtimestamp)
--		2. equals to 'p_start_time' and in the middle of an era or 
--		   'microtimestamp' > p_start_time and <= p_end_time and equals to some 'era' then 
--			'depth_change' is _depth_change(ob1, ob2) where ob1 = order_book(microtimestamp - '00:00:00.000001') and ob2 = order_book(microtimestamp)
--		3. Otherwise 'depth_change' is from corresponding obanalytics.level2 record
--	It is not possible to use order_book(p_before :=true) as the start of an era since it will be empty!

with periods as (
	select * 
	from obanalytics._periods_within_eras(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency)
),
starting_depth_change as (
	select period_start, p_pair_id::smallint, p_exchange_id::smallint, 'r0', (unnest(c)).*
	from periods join obanalytics.order_book(previous_period_end, p_pair_id,p_exchange_id, false, false,false ) b on true 
				 join obanalytics.order_book(period_start, p_pair_id,p_exchange_id, false, true, false ) a on true 
				 join obanalytics._depth_change(b.ob, a.ob) c on true
	where previous_period_end is not null
)
select *
from starting_depth_change
union all
select level2.*
from periods join obanalytics.depth_change_by_episode4(period_start, period_end, p_pair_id, p_exchange_id, p_frequency) level2 on true 
where microtimestamp >= period_start
  and microtimestamp <= period_end
  and level2.pair_id = p_pair_id
  and level2.exchange_id = p_exchange_id 
  and level2.precision = 'r0' 
  ;

$$;


ALTER FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: level2_update_level3_eras(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level2_update_level3_eras() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin 
	with latest_events as (
		select exchange_id, pair_id, max(microtimestamp) as latest
		from inserted
		group by exchange_id, pair_id
	),
	eras as (
		select exchange_id, pair_id, latest, max(era) as era
		from obanalytics.level3_eras join latest_events using (exchange_id, pair_id)
		where era <= latest
		group by exchange_id, pair_id, latest
	)
	update obanalytics.level3_eras
	   set level2 = latest
	from eras
	where level3_eras.era = eras.era
	  and level3_eras.exchange_id = eras.exchange_id
	  and level3_eras.pair_id = eras.pair_id
	  and (level2 is null or level2 < latest);
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level2_update_level3_eras() OWNER TO "ob-analytics";

--
-- Name: level3_incorporate_new_event(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_incorporate_new_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

declare
	v_era timestamptz;
	v_amount numeric;
	
	v_event obanalytics.level3;
	
begin
	  
	if new.price_microtimestamp is null or new.event_no is null then 
		raise debug 'Will process  %, %', new.microtimestamp, new.order_id;
	-- The values of the above two columns depend on the previous event for the order_id if any and are mandatory (not null). 
	-- They have to be set by either an inserter of the record (more effective) or by this trigger
		begin
			select max(era) into v_era
			from obanalytics.level3_eras
			where pair_id = new.pair_id
			  and exchange_id = new.exchange_id
			  and era <= new.microtimestamp;
		
			update obanalytics.level3
			   set next_microtimestamp = new.microtimestamp,
				   next_event_no = event_no + 1
			where exchange_id = new.exchange_id
			  and pair_id = new.pair_id
			  and microtimestamp between v_era and new.microtimestamp
			  and order_id = new.order_id 
			  and side = new.side
			  and next_microtimestamp > new.microtimestamp
			returning *
			into v_event;
			-- amount, next_event_no INTO v_amount, NEW.event_no;
		exception 
			when too_many_rows then
				raise exception 'too many rows for %, %, %', new.microtimestamp, new.order_id, new.event_no;
		end;
		if found then
		
			if new.price = 0 then 
				new.price = v_event.price;
				new.amount = v_event.amount;
				new.fill = null;
			else
				new.fill := v_event.amount - new.amount; 
			end if;

			new.event_no := v_event.next_event_no;

			if v_event.price = new.price THEN 
				new.price_microtimestamp := v_event.price_microtimestamp;
				new.price_event_no := v_event.price_event_no;
			else	
				new.price_microtimestamp := new.microtimestamp;
				new.price_event_no := new.event_no;
			end if;

		else -- it is the first event for order_id (or first after the latest 'deletion' )
			-- new.fill will remain null. Might set it later from matched trade, if any
			if new.price > 0 then 
				new.price_microtimestamp := new.microtimestamp;
				new.price_event_no := 1;
				new.event_no := 1;
			else
				raise notice 'Skipped insertion of %, %, %, %', new.microtimestamp, new.order_id, new.event_no, new.local_timestamp;
				return null;	-- skip insertion
			end if;
		end if;
		
	end if;
	return new;
end;

$$;


ALTER FUNCTION obanalytics.level3_incorporate_new_event() OWNER TO "ob-analytics";

--
-- Name: level3_update_chain_after_delete(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_update_chain_after_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
	v_previous_event obanalytics.level3%rowtype;
begin 
	if old.event_no > 1 then
	
		update obanalytics.level3
		   set next_microtimestamp = case when isfinite(old.next_microtimestamp) then old.next_microtimestamp else 'infinity' end,
		       next_event_no = case when isfinite(old.next_microtimestamp) then old.next_event_no else null end
		where exchange_id = old.exchange_id
		  and pair_id = old.pair_id
		  and microtimestamp between (	select max(era)
									     from obanalytics.level3_eras
									     where exchange_id = old.exchange_id
									  	   and pair_id = old.pair_id
									       and era <= old.microtimestamp ) and old.microtimestamp
		  and order_id = old.order_id										   
		  and event_no = old.event_no - 1
		returning level3.* into v_previous_event;
	 		
	end if;
	
	-- NOT READY: need to update price_microtimestamp recursively!!!
	
	if isfinite(old.next_microtimestamp) then
		update obanalytics.level3
		   set price_microtimestamp = v_previous_event.price_microtimestamp,
		       price_event_no = v_previous_event.price_event_no
		where exchange_id = old.exchange_id
		  and pair_id = old.pair_id
		  and microtimestamp = old.next_microtimestamp
		  and order_id = old.order_id										   
		  and event_no = old.next_event_no
		  and price_microtimestamp = old.microtimestamp
		  and price_event_no = old.event_no;
	end if;
	return old;
end;$$;


ALTER FUNCTION obanalytics.level3_update_chain_after_delete() OWNER TO "ob-analytics";

--
-- Name: level3_update_level3_eras(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_update_level3_eras() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin 
	with latest_events as (
		select exchange_id, pair_id, max(microtimestamp) as latest
		from inserted
		group by exchange_id, pair_id
	),
	eras as (
		select exchange_id, pair_id, latest, max(era) as era
		from obanalytics.level3_eras join latest_events using (exchange_id, pair_id)
		where era <= latest
		group by exchange_id, pair_id, latest
	)
	update obanalytics.level3_eras
	   set level3 = latest
	from eras
	where level3_eras.era = eras.era
	  and level3_eras.exchange_id = eras.exchange_id
	  and level3_eras.pair_id = eras.pair_id
	  and (level3 is null or level3 < latest);
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level3_update_level3_eras() OWNER TO "ob-analytics";

--
-- Name: merge_crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare 
	crossed_books record;
	v_execution_start_time timestamp with time zone;
begin
	v_execution_start_time := clock_timestamp();
	raise debug 'merge_crossed_books(%, %, %, %)', p_start_time, p_end_time,  p_pair_id, p_exchange_id;

	for crossed_books in (select * from obanalytics.crossed_books(p_start_time, p_end_time, p_pair_id, p_exchange_id) where next_uncrossed is not null) loop
		if crossed_books.next_uncrossed is null then 
			raise exception 'Unable to find next uncrossed order book:  previous_uncrossed=%, pair_id=%, exchange_id=%', crossed_books.previous_uncrossed, p_pair_id, p_exchange_id;
		end if;
		return query select * from obanalytics.merge_episodes(crossed_books.first_crossed, crossed_books.next_uncrossed, p_pair_id, p_exchange_id);
	end loop;
	raise debug 'merge_crossed_books() exec time: %', clock_timestamp() - v_execution_start_time;	
end;	

$$;


ALTER FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: FUNCTION merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) IS 'Merges episode(s) which produce crossed book into the next one which does not ';


--
-- Name: merge_episodes(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.merge_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE sql
    AS $$
with to_be_updated as (
	select coalesce(min(microtimestamp) filter (where next_microtimestamp = '-infinity') over (partition by order_id order by microtimestamp desc), 
					'infinity'::timestamptz) as next_death,
			first_value(microtimestamp) over (partition by order_id order by microtimestamp desc) as last_seen,
			microtimestamp, order_id, event_no 
	from obanalytics.level3
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= p_start_time
	  and microtimestamp < p_end_time
)
update obanalytics.level3
    set microtimestamp = case when next_death < p_end_time 
							         and next_death < last_seen -- the order is resurrected after next_death.
									 							-- Bitfinex does that and we can use next_death for Bitfinex because all matches are single-sided
																-- In case of Bitstamp we would have to move both sides of the match - much more difficult to do ...
									then next_death
							   else p_end_time 
							   end,
		next_microtimestamp = case when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp <= next_death 
											and isfinite(level3.next_microtimestamp) and isfinite(next_death) 
											and next_death < last_seen -- the order is resurrected after next_death. Bitfinex does that
										then next_death
									when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp < p_end_time
										then p_end_time
									else level3.next_microtimestamp 
									end
from to_be_updated 
/*select case when next_death < p_end_time 
			then next_death
		   else p_end_time 
	    end as microtimestamp,
		level3.order_id,
		level3.event_no,
		level3.side,
		level3.price,
		level3.amount,
		level3.fill,
		case when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp <= next_death and isfinite(level3.next_microtimestamp)
				then next_death
			  when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp < p_end_time
			  	then p_end_time
			  else level3.next_microtimestamp 
			  end as next_microtimestamp,
	     level3.next_event_no,
		 level3.pair_id,
		 level3.exchange_id,
		 level3.local_timestamp,
		 level3.price_microtimestamp,
		 level3.price_event_no,
		 level3.exchange_microtimestamp,
		 level3.is_maker,
		 level3.is_crossed
from obanalytics.level3, to_be_updated 
*/
where level3.pair_id = p_pair_id
  and level3.exchange_id = p_exchange_id
  and level3.microtimestamp >= p_start_time
  and level3.microtimestamp < p_end_time
  and level3.microtimestamp = to_be_updated.microtimestamp
  and level3.order_id = to_be_updated.order_id
  and level3.event_no = to_be_updated.event_no
returning level3.*;  

$$;


ALTER FUNCTION obanalytics.merge_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: order_book(timestamp with time zone, integer, integer, boolean, boolean, boolean, character); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean DEFAULT false, p_side character DEFAULT NULL::bpchar) RETURNS TABLE(ts timestamp with time zone, ob obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$
	with orders as (
			select microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp,
					price_microtimestamp, price_event_no, exchange_microtimestamp, 
					coalesce(
						case side 
							when 'b' then price <= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
							when 's' then price >= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
						end,
					true )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are makers
					as is_maker,
					coalesce(
						case side 
							when 'b' then price > min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
							when 's' then price < max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
						end,
					false )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are not crossed
					as is_crossed
			from obanalytics.level3 
			where microtimestamp >= ( select max(era) as s
				 					   from obanalytics.level3_eras 
				 					   where era <= p_ts 
				    					 and pair_id = p_pair_id 
				   						 and exchange_id = p_exchange_id ) 
			  and case when p_before then  microtimestamp < p_ts and next_microtimestamp >= p_ts 
						when not p_before then microtimestamp <= p_ts and next_microtimestamp > p_ts 
		  	      end
			  and case when p_side is null then true else side =p_side end
			  and pair_id = p_pair_id
			  and exchange_id = p_exchange_id		
		)
	select (select max(microtimestamp) from orders ) as ts,
			array_agg(orders::obanalytics.level3 order by price, microtimestamp, order_id, event_no) 	
				  -- order by must be the same as in obanalytics._order_book_after_episode(). Change both!
    from orders
	where is_maker OR NOT p_only_makers
	  and (not p_check_takers or (not is_maker and obanalytics._is_valid_taker_event(microtimestamp, order_id, event_no, pair_id, exchange_id, next_microtimestamp)));

$$;


ALTER FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean, p_side character) OWNER TO "ob-analytics";

--
-- Name: order_book_by_episode(timestamp with time zone, timestamp with time zone, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean DEFAULT true) RETURNS TABLE(ts timestamp with time zone, ob obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--		p_start_time  - the start of the interval for the production of the order book snapshots
--		p_end_time	  - the end of the interval
--		p_pair_id	  - id of the pair for which order books will be calculated
--		p_exchange_id - id of the exchange where order book is calculated

-- DETAILS
-- 		An episode is a moment in time when the order book, derived from obanalytics's data is in consistent state. 
--		The state of the order book is consistent when:
--			(a) all events that happened simultaneously (i.e. having the same microtimestamp) are reflected in the order book
--			(b) both events that constitute a trade are reflected in the order book
-- 		This function processes the order book events sequentially and returns consistent snapshots of the order book between
--		p_start_time and p_end_time.
--		These consistent snapshots are then used to calculate spread, depth and depth.summary. Note that the consitent order book may still be crossed.
--		It is assumed that spread, depth and depth.summary will ignore the unprocessed agressors crossing the book. 
--		
with eras as (
	select era, next_era
	from (
		select era, coalesce(lead(era) over (order by era), 'infinity') as next_era
		from obanalytics.level3_eras
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id 
	) a
	where p_start_time < next_era 
	  and p_end_time >= era
)
select microtimestamp as ts, obanalytics.order_book_agg(episode, p_check_takers) over (partition by era order by microtimestamp)  as ob
from (
	select microtimestamp, array_agg(level3) as episode
	from obanalytics.level3
	where microtimestamp between p_start_time and p_end_time
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	group by microtimestamp  
) a join eras on microtimestamp >= era and microtimestamp < next_era
order by era, ts

$$;


ALTER FUNCTION obanalytics.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: pga_summarize(text, text, interval, timestamp with time zone, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.pga_summarize(p_exchange text, p_pair text, p_max_interval interval DEFAULT '00:15:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone, p_delay interval DEFAULT '00:02:00'::interval) RETURNS TABLE(summarized text, pair text, exchange text, first_microtimestamp timestamp with time zone, last_microtimestamp timestamp with time zone, record_count integer)
    LANGUAGE plpgsql
    AS $$-- PARAMETERS:
--
--	p_max_interval	interval 		If NULL, summarize using all available data, subject to limitations, enforced by the other parameters.
-- 									If NOT NULL, then sum of all summarized intervals (for different eras, if more than one) will not exceed p_max_interval
--	p_ts_within_era	timestamptz		If NULL, summarize starting from the most recent level1 or level2 data (which is earlier) for all eras if more than one
--									If NOT NULL then summarize ONLY within the era p_ts_within_era belongs to

declare 
	v_current_timestamp timestamptz;
	
	v_first_era timestamptz;
	v_last_era timestamptz;
	
	v_start timestamptz;
	v_end timestamptz;
	
	v_pair_id obanalytics.pairs.pair_id%type;
	v_exchange_id obanalytics.exchanges.exchange_id%type;
	
	e record;
	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs 
	where pairs.pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchanges.exchange = lower(p_exchange);
	
	begin

		if p_ts_within_era is null then	-- we start from the latest era where level1 and level2 have already been calculated.
										 -- If a new era has started this start point will ensure that we'll calculate remaining 
										 -- level1 and level2 for the old era(s) as well as the new one(s)
			select max(era) into v_first_era
			from obanalytics.level3_eras 
			where pair_id = v_pair_id
			   and exchange_id = v_exchange_id
			   and level1 is not null and level2 is not null;
			   
			if v_first_era is null then 
				-- start from the very first era available
				select min(era) into v_first_era
				from obanalytics.level3_eras 
				where pair_id = v_pair_id
				  and exchange_id = v_exchange_id;

			end if;
			
			v_last_era := 'infinity';	-- i.e. we'll summarize all eras after the first one

		else

			select max(era) into v_first_era
			from obanalytics.level3_eras 
			where pair_id = v_pair_id
			   and exchange_id = v_exchange_id
			   and p_ts_within_era >= era;
			   
			v_last_era := v_first_era;			   
			
		end if;

	end;
	
	create temp table if not exists level1 (like obanalytics.level1) on commit delete rows;
	create temp table if not exists level2 (like obanalytics.level2) on commit delete rows;
	
	raise debug 'v_first_era=%  v_last_era=%', v_first_era, v_last_era;
	
	for e in   select starts, ends, first_level1, first_level2
				from (
					select era as starts, case 
											when lead(era) over (order by era) is not null then 
												coalesce(level3, lead(era) over (order by era)  - '00:00:00.000001'::interval)
											else
												coalesce(level3 - p_delay, era)
											end as ends,
							coalesce(level1 + '00:00:00.000001'::interval, era) as first_level1,
							coalesce(level2 + '00:00:00.000001'::interval, era) as first_level2
					from obanalytics.level3_eras 
					where pair_id = v_pair_id
					  and exchange_id = v_exchange_id
					  and level3 is not null
				) a
				where a.starts between v_first_era and v_last_era
				order by starts loop
		raise debug 'e.starts=%, e.ends=%', e.starts, e.ends;
		e.starts :=  least(e.first_level1, e.first_level2);
		e.ends := least(e.ends, e.starts + p_max_interval);
		
		raise debug 'pga_summarize(%, %) start: %, end: %, remaining interval: % ', p_exchange, p_pair, e.starts, e.ends, p_max_interval; 
		
		
/*		The SQL statement works slower than PL/PGSQL code. But may be improved in the future ... 

		with base as (
			select (obanalytics._spread_from_order_book(ts, ob)).*, obanalytics.depth_change_agg(ob) over (order by ts) as depth_change 
			from obanalytics.order_book_by_episode(e.starts, e.ends, v_pair_id, v_exchange_id)
		),
		insert_level2 as (
			insert into obanalytics.level2 (microtimestamp, pair_id, exchange_id, precision,  depth_change)
			select microtimestamp, pair_id, exchange_id, 'r0'::character(2), depth_change
			from base
			where depth_change is not null
			  and microtimestamp > e.first_level2
		)
		insert into obanalytics.level1 (best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id)
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id
		from (
			select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id,
					lag(best_bid_price) over w as p_best_bid_price, 
					lag(best_bid_qty) over w as p_best_bid_qty,
					lag(best_ask_price) over w as p_best_ask_price,
					lag(best_ask_qty) over w as p_best_ask_qty
			from base
			window w as (order by microtimestamp)
		) a
		where microtimestamp > e.first_level1
		  and (  best_bid_price is distinct from p_best_bid_price
				 or best_bid_qty is distinct from p_best_bid_qty
				 or best_ask_price is distinct from p_best_ask_price
				 or best_ask_qty is distinct from p_best_ask_qty
			   ); */
		
		declare
			v_ob_before record;
			v_ob record;
			v_l1_before obanalytics.level1;
			v_l1 obanalytics.level1;
		begin

				select ts, ob 
				from obanalytics.order_book(e.starts, v_pair_id, v_exchange_id, p_only_makers := true, p_before := true) 
				into v_ob_before;	-- so we are readyf for a depth_change generation for the very first episode greater or equal to e.starts
				
				select * into v_l1_before
				from obanalytics.level1
				where microtimestamp = e.first_level1
				  and exchange_id = v_exchange_id
				  and pair_id = v_pair_id;

				for v_ob in select ts, ob from obanalytics.order_book_by_episode(e.starts, e.ends, v_pair_id, v_exchange_id) 
				loop
					if v_ob.ts > e.first_level1 then
						select * into v_l1
						from obanalytics._spread_from_order_book(v_ob.ts, v_ob.ob);
						
						if (v_l1_before.best_bid_price is distinct from v_l1.best_bid_price or
						    v_l1_before.best_bid_qty  is distinct from v_l1.best_bid_qty or
						    v_l1_before.best_ask_price is distinct from v_l1.best_ask_price or
						    v_l1_before.best_ask_qty is distinct from v_l1.best_ask_qty )
						then
							-- Let's check whether v_l1 is empty ...
							if v_l1.microtimestamp is not null then 
								insert into level1
								values (v_l1.*);
							else	-- it is empty (i.e. no orders in the order book)
								insert into level1 (microtimestamp, exchange_id, pair_id)
								values (v_ob.ts, v_exchange_id, v_pair_id);
							end if;
							
							v_l1_before := v_l1;
							
						end if;
						
					end if;
					
					if v_ob.ts > e.first_level2 then
						if v_ob_before is not null then -- if e.starts equals to an era start then v_ob_before will be null 
						
							insert into level2
							select v_ob.ts, v_pair_id::smallint, v_exchange_id::smallint, 'r0'::character(2), d 
							from obanalytics._depth_change(v_ob_before.ob, v_ob.ob) d
							where d is not null;
							
						end if;
						
					end if;
					v_ob_before := v_ob;
				end loop;			
				
				select 'level1', p_pair, p_exchange, min(microtimestamp), max(microtimestamp), count(*) 
				from level1
				group by exchange_id, pair_id
				into summarized, pair, exchange, first_microtimestamp, last_microtimestamp, record_count;
				return next;
				
				select 'level2', p_pair, p_exchange, min(microtimestamp), max(microtimestamp), count(*) 
				from level2
				group by exchange_id, pair_id
				into summarized, pair, exchange, first_microtimestamp, last_microtimestamp, record_count;
				return next;
				
				with deleted as (
					delete from level1
					returning level1.*
				)
				insert into obanalytics.level1
				select * from deleted;
				
				with deleted as (
					delete from level2
					returning level2.*
				)
				insert into obanalytics.level2
				select * from deleted;
				
		exception
			when raise_exception then
				declare
					v_bad_episode timestamptz;
					v_fixed integer;
				begin
					select substring(sqlerrm from 'Invalid taker event: ([0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1]) (2[0-3]|[01][0-9]):[0-5][0-9]:[0-5][0-9](.[0-9]+|)(\+|1)[0-2][0-4])')
					into v_bad_episode;
					
					if v_bad_episode is not null then
						raise log '% % %', sqlerrm, e.starts, e.ends;
						select count(*) into v_fixed
						from obanalytics.fix_crossed_books(v_bad_episode, e.ends, v_pair_id, v_exchange_id);
						if v_fixed > 0 then 
							raise log 'Inserted/updated % for invalid taker at % till %', v_fixed, v_bad_episode, e.ends;
							exit;	-- We stop the summarization now. Next call this procedure will try to summarize this era again with the hope that the errors were fixed by the code above
						else
							-- We got stuck, so report an error!
							raise exception 'STUCK: inserted/updated % for invalid taker at % till % e.ends', v_fixed, v_bad_episode, e.ends;
						end if;
					else 
						raise exception '%', sqlerrm;	-- We caught an unexpected exception, re-throw it
					end if;
				end;
		end;

		if p_max_interval is not null then 
			p_max_interval := greatest('00:00:00'::interval, p_max_interval - (e.ends - least(e.first_level1,  e.first_level2)));

			if p_max_interval = '00:00:00'::interval then
				raise debug 'p_max_interval is 0, exiting ... ';
				exit;
			end if;

		end if;
		
	end loop;
	
	raise debug 'pga_summarize(%, %, %, %) exec time: %', p_exchange, p_pair, p_max_interval, p_ts_within_era, clock_timestamp() - v_current_timestamp;
	return;
end;

$$;


ALTER FUNCTION obanalytics.pga_summarize(p_exchange text, p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone, p_delay interval) OWNER TO "ob-analytics";

--
-- Name: propagate_microtimestamp_change(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.propagate_microtimestamp_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$begin
	update bitstamp.live_orders
	set microtimestamp = new.microtimestamp
	where order_type = case new.side when 's' then 'sell'::bitstamp.direction
								when 'b' then 'buy'::bitstamp.direction
				  end
	  and microtimestamp = old.microtimestamp
	  and order_id = old.order_id
	  and event_no = old.event_no;
	return null;
end;	  
$$;


ALTER FUNCTION obanalytics.propagate_microtimestamp_change() OWNER TO "ob-analytics";

--
-- Name: save_exchange_microtimestamp(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.save_exchange_microtimestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
begin
	-- It is assumed that the first-ever value of microtimestamp column is set by an exchange.
	-- If it is changed for the first time, then save it to exchange_microtimestamp.
	if old.exchange_microtimestamp is null then
		if old.microtimestamp is distinct from new.microtimestamp then
			new.exchange_microtimestamp := old.microtimestamp;
		end if;
	end if;		
	return new;
end;
	

$$;


ALTER FUNCTION obanalytics.save_exchange_microtimestamp() OWNER TO "ob-analytics";

--
-- Name: spread_by_episode(timestamp with time zone, timestamp with time zone, integer, integer, boolean, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean DEFAULT true, p_with_order_book boolean DEFAULT false) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, exchange_id smallint, order_book obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$
-- ARGUMENTS
--		p_start_time  - the start of the interval for the calculation of spreads
--		p_end_time	  - the end of the interval
--		p_pair_id	  - the pair for which spreads will be calculated
--		p_exchange_id - the exchange where spreads will be calculated for
--		p_only_different - whether to output a spread when it is different from the previous one
--		p_with_order_book - whether to output the order book which was used to calculate spread (slow, generates a lot of data!)

with spread as (
	select (obanalytics._spread_from_order_book(ts, ob)).*, case  when p_with_order_book then ob else null end as ob
	from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers := false)
)
select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id, ob
from (
	select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id, ob,
		    lag(best_bid_price) over w as p_best_bid_price, 
			lag(best_bid_qty) over w as p_best_bid_qty,
			lag(best_ask_price) over w as p_best_ask_price,
			lag(best_ask_qty) over w as p_best_ask_qty
	from spread
	window w as (order by microtimestamp)
) a
where microtimestamp is not null 
  and ( not p_only_different 
	   	 or best_bid_price is distinct from p_best_bid_price
	     or best_bid_qty is distinct from p_best_bid_qty
	     or best_ask_price is distinct from p_best_ask_price
	     or best_ask_qty is distinct from p_best_ask_qty
	   )
order by microtimestamp

$$;


ALTER FUNCTION obanalytics.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean, p_with_order_book boolean) OWNER TO "ob-analytics";

--
-- Name: spread_by_episode2(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.spread_by_episode2(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, exchange_id smallint, order_book obanalytics.level3[])
    LANGUAGE plpython2u STABLE
    AS $_$
from obadiah_db.orderbook import OrderBook
import logging
logging.basicConfig(filename='log/obadiah_db.log',level=logging.DEBUG)
logger = logging.getLogger(__name__)
def generator():
	spread = None
	for era in plpy.execute(
					plpy.prepare('''
								 with eras as (
									 select era as era_start, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'infinity') as era_end
									 from obanalytics.level3_eras
									 where pair_id = $3
									   and exchange_id = $4
								 )
								 select greatest(era_start, $1) as start_time, least(era_end, $2) as end_time
								 from eras
								 where era_start <= $2
								   and era_end >= $1
						   ''', ["timestamptz","timestamptz", "integer", "integer"]),
		[p_start_time, p_end_time, p_pair_id, p_exchange_id]):
		logger.debug('Calculating spreads for %s - %s', era["start_time"],  era["end_time"])
		ob=OrderBook(False) 
		if spread is None:
			r =	plpy.execute(
					plpy.prepare('''select ts, ob
									from obanalytics.order_book( $1, $2, $3, false, true, $4 )
								 ''', ["timestamptz", "integer", "integer", "boolean"]),
				[era["start_time"], p_pair_id, p_exchange_id, False])
			if r[0]["ts"] is not None:
				ob.update(r[0]["ob"])
			spread = ob.spread()
			spread["pair_id"] = p_pair_id
			spread["exchange_id"] = p_exchange_id
			spread["order_book"] = None

			spread["best_bid_price"] = None 
		
		for e in plpy.cursor(
			plpy.prepare('''	with level3 as (
									-- we take only the latest event per episode. In case an order was created and deleted within an episode it will be ignored completely ...
									select distinct on (microtimestamp, order_id) *	
									from obanalytics.level3
									where microtimestamp between $1 and $2
									  and pair_id = $3
									  and exchange_id = $4
									order by microtimestamp, order_id, event_no desc
								)
								select microtimestamp as ts, array_agg(level3) as episode
								from level3
								group by microtimestamp
								order by microtimestamp
						''',["timestamptz", "timestamptz", "integer", "integer"]),
			[era["start_time"], era["end_time"], p_pair_id, p_exchange_id]):
			ob.update(e["episode"])
			updated_spread = ob.spread()

			if 	updated_spread["best_bid_price"] != spread["best_bid_price"] or\
					updated_spread["best_ask_price"] != spread["best_ask_price"] or\
					updated_spread["best_bid_qty"] != spread["best_bid_qty"] or\
					updated_spread["best_ask_qty"] != spread["best_ask_qty"]:
				updated_spread["microtimestamp"] = e["ts"]
				updated_spread["pair_id"] = p_pair_id
				updated_spread["exchange_id"] = p_exchange_id
				updated_spread["order_book"] = None
				spread = updated_spread
				yield spread
return generator()

$_$;


ALTER FUNCTION obanalytics.spread_by_episode2(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: spread_by_episode3(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.spread_by_episode3(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level1
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'spread_by_episode';


ALTER FUNCTION obanalytics.spread_by_episode3(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: summary(text, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.summary(p_exchange text DEFAULT NULL::text, p_pair text DEFAULT NULL::text, p_start_time timestamp with time zone DEFAULT (now() - '02:00:00'::interval), p_end_time timestamp with time zone DEFAULT 'infinity'::timestamp with time zone) RETURNS TABLE(pair text, e_first text, e_last text, e_total bigint, e_per_sec numeric, t_first text, t_last text, t_total bigint, t_per_sec numeric, t_matched bigint, t_exchange bigint, exchange text, era text)
    LANGUAGE sql STABLE
    AS $$
		
with periods as (
	select exchange_id, pair_id, 
			case when p_starts < p_start_time then p_start_time else p_starts end as period_starts, 
			case when p_ends > p_end_time then p_end_time else p_ends end as period_ends, 	
			era
	from (
		select exchange_id, pair_id, era as p_starts, 
				coalesce(lead(era) over (partition by exchange_id, pair_id order by era) - '00:00:00.000001'::interval, 'infinity'::timestamptz) as p_ends, era
		from obanalytics.level3_eras
		where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange) )
		  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	) p 
	where p_ends >= p_start_time
   	  and p_starts <= p_end_time 
),
level3_base as (
	select * 
	from obanalytics.level3 
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	  and microtimestamp  between p_start_time and p_end_time
),
events as (		
	select exchange_id,
			pair_id,
			period_starts,
			period_ends,
			min(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as e_first, 
			max(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as e_last,
			count(*) filter (where microtimestamp between period_starts and period_ends) as e_total
	from periods join level3_base using (exchange_id, pair_id)
	where microtimestamp between period_starts and period_ends 	
	  
	group by exchange_id, pair_id, period_starts, period_ends
),
matches_base as (
	select *
	from obanalytics.matches
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	  and microtimestamp  between p_start_time and p_end_time
),
trades as (		
	select exchange_id,
			pair_id,
			period_starts,
			period_ends,
			min(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as t_first, 
			max(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as t_last,
			count(*) filter (where microtimestamp between period_starts and period_ends) as t_total,
			count(*) filter (where microtimestamp between period_starts and period_ends and (buy_order_id is not null or sell_order_id is not null )) as t_matched,
			count(*) filter (where microtimestamp between period_starts and period_ends and exchange_trade_id is not null) as t_exchange
	from periods join matches_base using (exchange_id, pair_id)
	where microtimestamp between period_starts and period_ends
	group by exchange_id, pair_id, period_starts, period_ends
)		
select pairs.pair, e_first::text, e_last::text, e_total, 
		case  when extract( epoch from e_last - e_first ) > 0 then round((e_total/extract( epoch from e_last - e_first ))::numeric,2)
	  		   else 0 
		end as e_per_sec,		
		t_first::text, t_last::text,
		t_total, 
		case  when extract( epoch from t_last - t_first ) > 0 then round((t_total/extract( epoch from t_last - t_first ))::numeric,2)
	  		   else 0 
		end as t_per_sec,		
		t_matched, t_exchange, exchanges.exchange, periods.era::text
from periods join obanalytics.pairs using (pair_id) join obanalytics.exchanges using (exchange_id) left join events using (exchange_id, pair_id, period_starts, period_ends)
		left join trades using (exchange_id, pair_id, period_starts, period_ends)
where e_first is not null							 
$$;


ALTER FUNCTION obanalytics.summary(p_exchange text, p_pair text, p_start_time timestamp with time zone, p_end_time timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: depth_change_agg(obanalytics.level3[]); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.depth_change_agg(obanalytics.level3[]) (
    SFUNC = obanalytics._depth_change_sfunc,
    STYPE = obanalytics.pair_of_ob,
    FINALFUNC = obanalytics._depth_change
);


ALTER AGGREGATE obanalytics.depth_change_agg(obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) (
    SFUNC = obanalytics._depth_summary_after_depth_change,
    STYPE = obanalytics.level2_depth_summary_internal_state,
    FINALFUNC = obanalytics._depth_summary
);


ALTER AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) OWNER TO "ob-analytics";

--
-- Name: draw_agg(timestamp with time zone, numeric, numeric, numeric); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.draw_agg(microtimestamp timestamp with time zone, price numeric, minimal_draw numeric, minimal_draw_decline numeric) (
    SFUNC = obanalytics._create_or_extend_draw,
    STYPE = obanalytics.draw_interim_price[]
);


ALTER AGGREGATE obanalytics.draw_agg(microtimestamp timestamp with time zone, price numeric, minimal_draw numeric, minimal_draw_decline numeric) OWNER TO "ob-analytics";

--
-- Name: order_book_agg(obanalytics.level3[], boolean); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) (
    SFUNC = obanalytics._order_book_after_episode,
    STYPE = obanalytics.level3[]
);


ALTER AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) OWNER TO "ob-analytics";

--
-- Name: restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer) (
    SFUNC = obanalytics._depth_after_depth_change,
    STYPE = obanalytics.level2_depth_record[]
);


ALTER AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer) OWNER TO "ob-analytics";

--
-- Name: exchanges; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.exchanges (
    exchange_id smallint NOT NULL,
    exchange text NOT NULL
);


ALTER TABLE obanalytics.exchanges OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level1 ATTACH PARTITION obanalytics.level1_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.level1_bitfinex OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_btcusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitfinex ATTACH PARTITION obanalytics.level1_bitfinex_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.level1_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_ltcusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitfinex ATTACH PARTITION obanalytics.level1_bitfinex_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.level1_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_ethusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitfinex ATTACH PARTITION obanalytics.level1_bitfinex_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.level1_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level1 ATTACH PARTITION obanalytics.level1_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.level1_bitstamp OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_btcusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.level1_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ltcusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.level1_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ethusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.level1_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_xrpusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.level1_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_bchusd (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_bchusd FOR VALUES IN ('5');


ALTER TABLE obanalytics.level1_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_btceur (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_btceur FOR VALUES IN ('6');


ALTER TABLE obanalytics.level1_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ethbtc; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ethbtc (
    best_bid_price numeric,
    best_bid_qty numeric,
    best_ask_price numeric,
    best_ask_qty numeric,
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 7 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level1_bitstamp ATTACH PARTITION obanalytics.level1_bitstamp_ethbtc FOR VALUES IN ('7');


ALTER TABLE obanalytics.level1_bitstamp_ethbtc OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level2 ATTACH PARTITION obanalytics.level2_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.level2_bitfinex OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitfinex ATTACH PARTITION obanalytics.level2_bitfinex_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.level2_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd ATTACH PARTITION obanalytics.level2_bitfinex_btcusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitfinex_btcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd ATTACH PARTITION obanalytics.level2_bitfinex_btcusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitfinex_btcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitfinex ATTACH PARTITION obanalytics.level2_bitfinex_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.level2_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd ATTACH PARTITION obanalytics.level2_bitfinex_ltcusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitfinex_ltcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd ATTACH PARTITION obanalytics.level2_bitfinex_ltcusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitfinex_ltcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitfinex ATTACH PARTITION obanalytics.level2_bitfinex_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.level2_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd ATTACH PARTITION obanalytics.level2_bitfinex_ethusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitfinex_ethusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd ATTACH PARTITION obanalytics.level2_bitfinex_ethusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitfinex_ethusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level2 ATTACH PARTITION obanalytics.level2_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.level2_bitstamp OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.level2_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd ATTACH PARTITION obanalytics.level2_bitstamp_btcusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_btcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd ATTACH PARTITION obanalytics.level2_bitstamp_btcusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_btcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.level2_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd ATTACH PARTITION obanalytics.level2_bitstamp_ltcusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_ltcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd ATTACH PARTITION obanalytics.level2_bitstamp_ltcusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_ltcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.level2_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd ATTACH PARTITION obanalytics.level2_bitstamp_ethusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_ethusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd ATTACH PARTITION obanalytics.level2_bitstamp_ethusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_ethusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_xrpusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.level2_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_xrpusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_xrpusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd ATTACH PARTITION obanalytics.level2_bitstamp_xrpusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_xrpusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_xrpusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_xrpusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd ATTACH PARTITION obanalytics.level2_bitstamp_xrpusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_xrpusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_bchusd (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_bchusd FOR VALUES IN ('5');


ALTER TABLE obanalytics.level2_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_bchusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_bchusd_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd ATTACH PARTITION obanalytics.level2_bitstamp_bchusd_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_bchusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_bchusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_bchusd_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd ATTACH PARTITION obanalytics.level2_bitstamp_bchusd_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_bchusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btceur (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_btceur FOR VALUES IN ('6');


ALTER TABLE obanalytics.level2_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btceur_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btceur_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur ATTACH PARTITION obanalytics.level2_bitstamp_btceur_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_btceur_p0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btceur_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btceur_r0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'r0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur ATTACH PARTITION obanalytics.level2_bitstamp_btceur_r0 FOR VALUES IN ('r0');
ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_btceur_r0 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethbtc; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethbtc (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 7 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY LIST ("precision");
ALTER TABLE ONLY obanalytics.level2_bitstamp ATTACH PARTITION obanalytics.level2_bitstamp_ethbtc FOR VALUES IN ('7');


ALTER TABLE obanalytics.level2_bitstamp_ethbtc OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethbtc_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethbtc_p0 (
    microtimestamp timestamp with time zone NOT NULL,
    pair_id smallint DEFAULT 7 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    "precision" character(2) DEFAULT 'p0'::bpchar NOT NULL,
    depth_change obanalytics.level2_depth_record[] NOT NULL
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc ATTACH PARTITION obanalytics.level2_bitstamp_ethbtc_p0 FOR VALUES IN ('p0');


ALTER TABLE obanalytics.level2_bitstamp_ethbtc_p0 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level3 ATTACH PARTITION obanalytics.level3_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.level3_bitfinex OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_btcusd FOR VALUES IN ('1');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ATTACH PARTITION obanalytics.level3_bitfinex_btcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ATTACH PARTITION obanalytics.level3_bitfinex_btcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd FOR VALUES IN ('2');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_ethusd FOR VALUES IN ('3');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ATTACH PARTITION obanalytics.level3_bitfinex_ethusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ATTACH PARTITION obanalytics.level3_bitfinex_ethusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd_s FOR VALUES IN ('s');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level3 ATTACH PARTITION obanalytics.level3_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.level3_bitstamp OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_btcusd FOR VALUES IN ('1');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd FOR VALUES IN ('2');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_ethusd FOR VALUES IN ('3');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd FOR VALUES IN ('4');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_bchusd FOR VALUES IN ('5');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_btceur FOR VALUES IN ('6');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ATTACH PARTITION obanalytics.level3_bitstamp_btceur_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ATTACH PARTITION obanalytics.level3_bitstamp_btceur_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur_s OWNER TO "ob-analytics";

--
-- Name: level3_eras_bitfinex; Type: VIEW; Schema: obanalytics; Owner: ob-analytics
--

CREATE VIEW obanalytics.level3_eras_bitfinex AS
 SELECT level3_eras.era,
    level3_eras.pair_id,
    level3_eras.exchange_id
   FROM obanalytics.level3_eras
  WHERE (level3_eras.exchange_id = ( SELECT exchanges.exchange_id
           FROM obanalytics.exchanges
          WHERE (exchanges.exchange = 'bitfinex'::text)));


ALTER TABLE obanalytics.level3_eras_bitfinex OWNER TO "ob-analytics";

--
-- Name: level3_eras_bitstamp; Type: VIEW; Schema: obanalytics; Owner: ob-analytics
--

CREATE VIEW obanalytics.level3_eras_bitstamp AS
 SELECT level3_eras.era,
    level3_eras.pair_id,
    level3_eras.exchange_id
   FROM obanalytics.level3_eras
  WHERE (level3_eras.exchange_id = ( SELECT exchanges.exchange_id
           FROM obanalytics.exchanges
          WHERE (exchanges.exchange = 'bitstamp'::text)));


ALTER TABLE obanalytics.level3_eras_bitstamp OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.matches ATTACH PARTITION obanalytics.matches_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitfinex OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_btcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ltcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ethusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.matches_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_xrpusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.matches_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.matches ATTACH PARTITION obanalytics.matches_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitstamp OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_btcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ltcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ethusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.matches_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_xrpusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.matches_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_bchusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_bchusd FOR VALUES IN ('5');


ALTER TABLE obanalytics.matches_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_btceur (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_btceur FOR VALUES IN ('6');


ALTER TABLE obanalytics.matches_bitstamp_btceur OWNER TO "ob-analytics";

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
    "P3" smallint,
    fmu smallint NOT NULL
);


ALTER TABLE obanalytics.pairs OWNER TO "ob-analytics";

--
-- Name: TABLE pairs; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON TABLE obanalytics.pairs IS 'pair_id values are meaningful: they are used in the names of partition tables';


--
-- Name: COLUMN pairs."R0"; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.pairs."R0" IS '-log10 of Fractional Monetary Unit (i.e. 2 for 0.01 of USD or 8 for 0.00000001 of Bitcoin) for the secopnd currency in the pair (i.e. USD in BTCUSD). To be used for rounding of floating-point prices';


--
-- Name: COLUMN pairs.fmu; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.pairs.fmu IS '-log10 of Fractional Monetary Unit (i.e. 2 for 0.01 of USD or 8 for 0.00000001 of Bitcoin) for the first currency in the pair (i.e. BTC in BTCUSD). To be used for rounding of floating-point quantities ';


--
-- Name: exchanges exchanges_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.exchanges
    ADD CONSTRAINT exchanges_pkey PRIMARY KEY (exchange_id);


--
-- Name: exchanges exchanges_unique_exchange; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.exchanges
    ADD CONSTRAINT exchanges_unique_exchange UNIQUE (exchange);


--
-- Name: level3_bitstamp level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp
    ADD CONSTRAINT level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd
    ADD CONSTRAINT level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd_b level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_b
    ADD CONSTRAINT level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd_s level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_s
    ADD CONSTRAINT level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur
    ADD CONSTRAINT level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur_b level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_b
    ADD CONSTRAINT level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur_s level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_s
    ADD CONSTRAINT level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd
    ADD CONSTRAINT level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd_b level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b
    ADD CONSTRAINT level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd_s level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s
    ADD CONSTRAINT level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd
    ADD CONSTRAINT level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd_b level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b
    ADD CONSTRAINT level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd_s level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s
    ADD CONSTRAINT level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd
    ADD CONSTRAINT level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd_b level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b
    ADD CONSTRAINT level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd_s level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s
    ADD CONSTRAINT level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd
    ADD CONSTRAINT level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd_b level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_b
    ADD CONSTRAINT level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd_s level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_s
    ADD CONSTRAINT level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_eras level3_eras_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_eras
    ADD CONSTRAINT level3_eras_pkey PRIMARY KEY (era, pair_id, exchange_id);


--
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


--
-- Name: level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3 check_microtimestamp_change; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE CONSTRAINT TRIGGER check_microtimestamp_change AFTER UPDATE OF microtimestamp ON obanalytics.level3 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE PROCEDURE obanalytics.check_microtimestamp_change();


--
-- Name: level3 propagate_microtimestamp_change; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER propagate_microtimestamp_change AFTER UPDATE OF microtimestamp ON obanalytics.level3 FOR EACH ROW WHEN ((old.exchange_id = 2)) EXECUTE PROCEDURE obanalytics.propagate_microtimestamp_change();


--
-- Name: level3 update_chain_after_delete; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_chain_after_delete AFTER DELETE ON obanalytics.level3 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_update_chain_after_delete();


--
-- Name: level1 update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level1 REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level1_update_level3_eras();


--
-- Name: level2 update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level2 REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level2_update_level3_eras();


--
-- Name: level3 update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level3 REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level3_update_level3_eras();


--
-- Name: level3_bitstamp update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level3_bitstamp REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level3_update_level3_eras();


--
-- Name: level3 level3_fkey_exchange_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.level3
    ADD CONSTRAINT level3_fkey_exchange_id FOREIGN KEY (exchange_id) REFERENCES obanalytics.exchanges(exchange_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3 level3_fkey_pair_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.level3
    ADD CONSTRAINT level3_fkey_pair_id FOREIGN KEY (pair_id) REFERENCES obanalytics.pairs(pair_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches live_trades_fkey_exchange_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.matches
    ADD CONSTRAINT live_trades_fkey_exchange_id FOREIGN KEY (exchange_id) REFERENCES obanalytics.exchanges(exchange_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches live_trades_fkey_pair_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.matches
    ADD CONSTRAINT live_trades_fkey_pair_id FOREIGN KEY (pair_id) REFERENCES obanalytics.pairs(pair_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: SCHEMA obanalytics; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA obanalytics TO obauser;


--
-- Name: TABLE exchanges; Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT SELECT ON TABLE obanalytics.exchanges TO obauser;


--
-- Name: TABLE pairs; Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT SELECT ON TABLE obanalytics.pairs TO obauser;


--
-- PostgreSQL database dump complete
--

