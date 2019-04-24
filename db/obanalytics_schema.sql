--
-- PostgreSQL database dump
--

-- Dumped from database version 11.2
-- Dumped by pg_dump version 11.2

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
-- Name: obanalytics; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA obanalytics;


ALTER SCHEMA obanalytics OWNER TO "ob-analytics";

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
    CONSTRAINT price_is_positive CHECK ((price > (0)::numeric))
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.level3 OWNER TO "ob-analytics";

--
-- Name: COLUMN level3.exchange_microtimestamp; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.level3.exchange_microtimestamp IS 'An microtimestamp of an event as asigned by an exchange. Not null if different from ''microtimestamp''';


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
	v_statements[i] := 'create trigger ba_incorporate_new_event before insert on '||V_SCHEMA||v_table_name||
		' for each row execute procedure obanalytics.level3_incorporate_new_event()';

	i := i+1;
	v_statements[i] := 'create trigger bz_save_exchange_microtimestamp before update of microtimestamp on '||V_SCHEMA||v_table_name||
		' for each row execute procedure obanalytics.save_exchange_microtimestamp()';

	
							
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
	v_statements[i] := 'create trigger bz_save_exchange_microtimestamp before update of microtimestamp on '||V_SCHEMA||v_table_name||
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
-- Name: _depth_change(obanalytics.level3[], obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql
    AS $$

select array_agg(row(price, coalesce(af.amount, 0), side, null::integer)::obanalytics.level2_depth_record  order by price desc)
from (
	select a.price, sum(a.amount) as amount,a.side
	from unnest(p_ob_before) a 
	where a.is_maker 
	group by a.price, a.side, a.pair_id
) bf full join (
	select a.price, sum(a.amount) as amount, a.side
	from unnest(p_ob_after) a 
	where a.is_maker 
	group by a.price, a.side, a.pair_id
) af using (price, side)
where bf.amount is distinct from af.amount
	

$$;


ALTER FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) OWNER TO "ob-analytics";

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
-- Name: _in_milliseconds(timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._in_milliseconds(ts timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$

SELECT ( ( EXTRACT( EPOCH FROM (_in_milliseconds.ts - '1514754000 seconds'::interval) )::numeric(20,5) + 1514754000 )*1000 )::text;

$$;


ALTER FUNCTION obanalytics._in_milliseconds(ts timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: FUNCTION _in_milliseconds(ts timestamp with time zone); Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON FUNCTION obanalytics._in_milliseconds(ts timestamp with time zone) IS 'Since R''s POSIXct is not able to handle time with the precision higher than 0.1 of millisecond, this function converts timestamp to text with this precision to ensure that the timestamps are not mangled by an interface between Postgres and R somehow.';


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
    AS $$
begin
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
									when 'b' then price >= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
									when 's' then price <= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
								end,
							false )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are not crossed
							as is_crossed
					from latest_events
					where not is_deleted
				)
				select array(
					select orders::obanalytics.level3
					from orders
					where is_maker 
					    or not p_check_takers 
					    or obanalytics._is_valid_taker_event(microtimestamp, order_id, event_no, pair_id, exchange_id, next_microtimestamp)
					order by microtimestamp, order_id, event_no 
					-- order by must be the same as in obanalytics.order_book(). Change both!					
				));
end;   

$$;


ALTER FUNCTION obanalytics._order_book_after_episode(p_ob obanalytics.level3[], p_ep obanalytics.level3[], p_check_takers boolean) OWNER TO "ob-analytics";

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
	where is_maker
	group by exchange_id, pair_id,side, price
)
select b.price, b.qty, s.price, s.qty, p_ts, pair_id, exchange_id
from (select * from price_levels where side = 'b' and is_best) b full join 
	  (select * from price_levels where side = 's' and is_best) s using (exchange_id, pair_id);

$$;


ALTER FUNCTION obanalytics._spread_from_order_book(p_ts timestamp with time zone, p_order_book obanalytics.level3[]) OWNER TO "ob-analytics";

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

CREATE FUNCTION obanalytics.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(previous_uncrossed timestamp with time zone, next_uncrossed timestamp with time zone, pair_id smallint, exchange_id smallint)
    LANGUAGE sql STABLE
    AS $$

with base_order_books as (
	select ts, exists (select * from unnest(ob) where not is_maker) as is_crossed
	from  obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, false) ob
),
order_books as (
	select ts, is_crossed, 
	coalesce(max(ts) filter (where not is_crossed) over (order by ts), p_start_time - '00:00:00.000001'::interval ) as previous_uncrossed,
	min(ts) filter (where not is_crossed) over (order by ts desc) as next_uncrossed
	from base_order_books 
)
select distinct previous_uncrossed, next_uncrossed, p_pair_id::smallint, p_exchange_id::smallint
from order_books
where is_crossed 
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
-- Name: depth_change_by_episode(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level2
    LANGUAGE plpgsql STABLE
    AS $$

-- ARGUMENTS
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
	from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := true, p_before := true) 
	into v_ob_before;	-- so there will be a depth_change generated for the very first episode greater or equal to p_start_time
	
	for v_ob in select ts, ob from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id) 
	loop
		if v_ob_before is not null then -- if p_start_time equals to an era start then v_ob_before will be null 
										 -- so we don't generate depth_change for the era start
			return query 
				select v_ob.ts, p_pair_id::smallint, p_exchange_id::smallint, 'r0'::character(2), d
				from obanalytics._depth_change(v_ob_before.ob, v_ob.ob) d;
		end if;
		v_ob_before := v_ob;
	end loop;			
end;

$$;


ALTER FUNCTION obanalytics.depth_change_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

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
-- Name: level2_continuous(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level2
    LANGUAGE sql STABLE
    AS $$

-- NOTE:
--	When 'microtimestamp' in returned record 
--		1. equals to 'p_start_time' and equals to some 'era' from obanalytics.level3_eras then 'depth_change' is a full depth from obanalytics.order_book(microtimestamp)
--		2. equals to 'p_start_time' and in the middle of an era or 
--		   'microtimestamp' > p_start_time and <= p_end_time and equals to some 'era' then 
--			'depth_change' is _depth_change(ob1, ob2) where ob1 = order_book(microtimestamp - '00:00:00.000001') and ob2 = order_book(microtimestamp)
--		3. Otherwise 'depth_change' is from corresponding obanalytics.level2 record
--	It is not possible to use order_book(p_before :=true) as the start of an era since it will be empty!

with periods as (
	select greatest(era_start, p_start_time) as period_start, least(era_end, p_end_time) as period_end, era_start
	from (
		select era as era_start, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval , 'infinity') as era_end
		from obanalytics.level3_eras
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	) e
	where p_start_time <= era_end
	  and p_end_time >= era_start
),
starting_depth_change as (
	select period_start, p_pair_id::smallint, p_exchange_id::smallint, 'r0', c
	from periods join obanalytics.order_book(  case when era_start = p_start_time then null else period_start - '00:00:00.000001'::interval end,
												p_pair_id,p_exchange_id, true, false,false ) b on true 
				 join obanalytics.order_book( period_start, p_pair_id,p_exchange_id, true, false,false ) a on true 
				 join obanalytics._depth_change(b.ob, a.ob) c on true
)
select *
from starting_depth_change
union all
select level2.*
from periods join obanalytics.level2 on true 
where microtimestamp > period_start
  and microtimestamp <= period_end
  and level2.pair_id = p_pair_id
  and level2.exchange_id = p_exchange_id 
  and level2.precision = 'r0'
  and microtimestamp > p_start_time and microtimestamp <= p_end_time -- otherwise, the query optimizer produces a crazy plan!
  ;

$$;


ALTER FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

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

	for crossed_books in (select * from obanalytics.crossed_books(p_start_time, p_end_time, p_pair_id, p_exchange_id) where next_uncrossed is not null) loop
		return query with updated as (
						  update obanalytics.level3
							 set	microtimestamp = crossed_books.next_uncrossed	-- just merge all 'crossed' order books into the next uncrossed one 
/* 
						  select crossed_books.next_uncrossed as microtimestamp, order_id, event_no, side, price, amount, fill,
								 next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp, is_maker, is_crossed						 
						  from obanalytics.level3
*/			
						  where level3.pair_id = p_pair_id
			                and level3.exchange_id = p_exchange_id
							and level3.microtimestamp > crossed_books.previous_uncrossed
							and level3.microtimestamp < crossed_books.next_uncrossed
						  returning level3.*
						)
						select *
						from updated;
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
-- Name: oba_available_exchanges(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_available_exchanges(p_start_time timestamp with time zone, p_end_time timestamp with time zone) RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
with eras as (
	select exchange_id, pair_id, tstzrange(era,coalesce(level3,era)) as era
	from obanalytics.level3_eras
),
has_data as (
	select distinct exchange_id
	from eras
	where tstzrange(p_start_time, p_end_time) && era
)
select exchange 
from has_data join obanalytics.exchanges using (exchange_id)
$$;


ALTER FUNCTION obanalytics.oba_available_exchanges(p_start_time timestamp with time zone, p_end_time timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: oba_available_pairs(timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_available_pairs(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer) RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
with eras as (
	select exchange_id, pair_id, tstzrange(era, coalesce(level3,era)) as era
	from obanalytics.level3_eras
	where exchange_id = p_exchange_id
),
has_data as (
	select distinct pair_id
	from eras
	where tstzrange(p_start_time, p_end_time) && era
)
select pair
from has_data join obanalytics.pairs using (pair_id)
$$;


ALTER FUNCTION obanalytics.oba_available_pairs(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, integer, integer, boolean, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_starting_depth boolean DEFAULT true, p_depth_changes boolean DEFAULT true) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

with starting_depth as (
	select p_start_time as microtimestamp, side, price, volume 
	from obanalytics.order_book(p_start_time, 
								p_pair_id,
								p_exchange_id,
								p_only_makers := true,
								p_before :=true,		-- if p_start_time is a start of an era, 
														-- then this order book will be null - see comment below
								p_check_takers := false)
	join lateral ( select price, side, sum(amount) as volume from unnest(ob) group by price, side ) d on true
	where p_starting_depth 
),
level2 as (
	select microtimestamp, side, price, volume
	from obanalytics.level2_continuous(p_start_time, 	-- if p_start_time is a start of an era, then level2_continous 
									   					 -- will return full depth from order book - see comment above
									    p_end_time,
									    p_pair_id,
									    p_exchange_id) level2
		  join unnest(level2.depth_change) d on true
	where p_depth_changes
)
select microtimestamp, price, volume, case side 	
										when 'b' then 'bid'::text
										when 's' then 'ask'::text
									  end as side
from ( select * from starting_depth union all select * from level2) d
where price is not null   -- null might happen if an aggressor order_created event is not part of an episode, i.e. dirty data.
							-- But plotPriceLevels will fail if price is null, so we need to exclude such rows.
							-- 'not null' constraint is to be added to price and depth_change columns of obanalytics.depth table. Then this check
							-- will be redundant
  and coalesce(microtimestamp < p_end_time, TRUE) -- for the convenience of client-side caching right, boundary must not be inclusive i.e. [p_staart_time, p_end_time)

$$;


ALTER FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_starting_depth boolean, p_depth_changes boolean) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, integer, integer, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer DEFAULT 25, p_max_bps_level integer DEFAULT 500) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
with depth_summary as (
	select microtimestamp, 
			(unnest(obanalytics.depth_summary_agg(depth_change, microtimestamp, pair_id, exchange_id, p_bps_step, p_max_bps_level ) over (order by microtimestamp))).*
	from obanalytics.level2_continuous(p_start_time, p_end_time, p_pair_id, p_exchange_id)
)
select microtimestamp,
		price, 
		volume, 
		case side when 's' then 'ask'::text when 'b' then 'bid'::text end, 
		bps_level
from depth_summary;

$$;


ALTER FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) OWNER TO "ob-analytics";

--
-- Name: oba_events(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("event.id" uuid, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, action text, direction text, fill numeric, "matching.event" uuid, type text, "aggressiveness.bps" numeric, event_no integer, is_aggressor boolean, is_created boolean, is_ever_resting boolean, is_ever_aggressor boolean, is_ever_filled boolean, is_deleted boolean, is_price_ever_changed boolean, best_bid_price numeric, best_ask_price numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

 with trades as (
		select * 
		from obanalytics.matches 
		where microtimestamp between p_start_time and p_end_time
	 	  and exchange_id = p_exchange_id
	      and pair_id = p_pair_id
	   ),
	  takers as (
		  select distinct buy_order_id as order_id
		  from trades
		  where side = 'b'
		  union	all 
		  select distinct sell_order_id as order_id
		  from trades
		  where side = 's'				
		),
	  makers as (
		  select distinct buy_order_id as order_id
		  from trades
		  where side = 's'
		  union all 
		  select distinct sell_order_id as order_id
		  from trades
		  where side = 'b'				
		),
	  spread_before as (
		  select lead(microtimestamp) over (order by microtimestamp) as microtimestamp, 
		  		  best_ask_price, best_bid_price
		  from obanalytics.level1 
		  where microtimestamp between p_start_time and p_end_time 
		    and pair_id = p_pair_id
		    and exchange_id = p_exchange_id
		  ),
      active_events as (
		select microtimestamp, order_id, event_no, next_microtimestamp = '-infinity' as is_deleted, side,price, amount, fill, pair_id, exchange_id, 
			price_microtimestamp
		from obanalytics.level3 
		where microtimestamp > p_start_time 
		  and microtimestamp <= p_end_time
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and not (amount = 0 and event_no = 1 and next_microtimestamp <>  '-infinity')		
		union all 
		select microtimestamp, order_id, event_no, false, side,price, amount, fill, pair_id, exchange_id, price_microtimestamp
		from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := false) join unnest(ob) on true
	  ),
	  base_events as (
		  select microtimestamp,
		  		  price,
		  		  amount,
		  		  side,
		  		  order_id,
		  		  is_deleted as is_deleted_event,
		  		  price_microtimestamp,
		  		  fill,
		  		  -- the columns below require 'first-last-agg' from pgxn to be installed
		  		  -- https://pgxn.org/dist/first_last_agg/doc/first_last_agg.html
		  		  last(best_ask_price) over (order by microtimestamp) as best_ask_price,	
		  		  last(best_bid_price) over (order by microtimestamp) as best_bid_price,	
		  		  -- coalesce below on the right handles the case of one-sided order book ...
		  		  case 
		  			when not is_deleted then
					  case side
						when 's' then price <= coalesce(last(best_bid_price) over (order by microtimestamp), price - 1)
						when 'b' then price >= coalesce(last(best_ask_price) over (order by microtimestamp) , price + 1 )
		 			  end
		  			else null
		  		  end as is_aggressor,		  
		  		  event_no
		  from active_events left join spread_before using(microtimestamp) 
	  ),
	  events as (
		select base_events.*,
		  		max(price) over o_all <> min(price) over o_all as is_price_ever_changed,
				bool_or(not is_aggressor) over o_all as is_ever_resting,
		  		bool_or(is_aggressor) over o_all as is_ever_aggressor, 	
		  		-- bool_or(coalesce(fill, case when not is_deleted_event then 1.0 else null end ) > 0.0 ) over o_all as is_ever_filled, 	-- BITSTAMP-specific version
		  		bool_or(coalesce(fill,0.0) > 0.0 ) over o_all as is_ever_filled,	-- we should classify an order event as fill only when we know fill amount. TODO: check how it will work with Bitstamp 
		  		bool_or(is_deleted_event) over o_all as is_deleted,			-- TODO: check whether this line works for Bitstamp
		  		-- first_value(is_deleted_event) over o_after as is_deleted,
		  		bool_or(event_no = 1 and not is_deleted_event) over o_all as is_created -- TODO: check whether this line works for Bitstamp
		  		--first_value(event_no) over o_before = 1 and not first_value(is_deleted_event) over o_before as is_created 
		from base_events left join makers using (order_id) left join takers using (order_id) 
  		
		window o_all as (partition by order_id)
		  		--, 
		  		-- o_after as (partition by order_id order by microtimestamp desc, event_no desc),
		  		--o_before as (partition by order_id order by microtimestamp, event_no)
	  ),
	  event_connection as (
		  select trades.microtimestamp, 
		   	      buy_event_no as event_no,
		  		  buy_order_id as order_id, 
		  		  obanalytics._level3_uuid(microtimestamp, sell_order_id, sell_event_no, p_pair_id::smallint, p_exchange_id::smallint) as event_id
		  from trades 
		  union all
		  select trades.microtimestamp, 
		  		  sell_event_no as event_no,
		  		  sell_order_id as order_id, 
		  		  obanalytics._level3_uuid(microtimestamp, buy_order_id, buy_event_no, p_pair_id::smallint, p_exchange_id::smallint)
		  from trades 
	  )
  select case when event_connection.microtimestamp is not null then obanalytics._level3_uuid(microtimestamp, order_id, event_no, p_pair_id::smallint, p_exchange_id::smallint)
  			    else null end as "event.id",
  		  order_id as id,
		  microtimestamp as "timestamp",
		  price_microtimestamp as "exchange.timestamp",
		  price, 
		  amount as volume,
		  case 
		  	when event_no = 1 and not is_deleted_event then 'created'::text
			when event_no > 1 and not is_deleted_event then 'changed'::text
			when is_deleted_event then 'deleted'::text
		  end as action,
		  case side
		  	when 'b' then 'bid'::text
			when 's' then 'ask'::text
		  end as direction,
		  case when fill > 0.0 then fill
		  		else 0.0
		  end as fill,
		  event_connection.event_id as "matching.event",
		  case when is_price_ever_changed then 'pacman'::text
		  	    when is_ever_resting and not is_ever_aggressor and not is_ever_filled and is_deleted then 'flashed-limit'::text
				when is_ever_resting and not is_ever_aggressor and not is_ever_filled and not is_deleted then 'resting-limit'::text
				when is_ever_resting and not is_ever_aggressor and is_ever_filled then 'resting-limit'::text
				when not is_ever_resting and is_ever_aggressor and is_deleted and is_ever_filled then 'market'::text
				-- when two market orders have been placed simulltaneously, the first might take all liquidity 
				-- so the second will not be executed and no change event will be generated for it so is_ever_resting will be 'false'.
				-- in spite of this it will be resting the order book for some time so its type is 'flashed-limit'.
				when not is_ever_resting and is_ever_aggressor and is_deleted and not is_ever_filled then 'flashed-limit'::text	
				when is_ever_resting and is_ever_aggressor then 'market-limit'::text
		  		else 'unknown'::text 
		  end as "type",
			case side
		  		when 's' then round((best_ask_price - price)/best_ask_price*10000)
		  		when 'b' then round((price - best_bid_price)/best_ask_price*10000)
		  	end as "aggressiveness.bps",
		event_no,
		is_aggressor,
		is_created,
		is_ever_resting,
		is_ever_aggressor,
		is_ever_filled,
		is_deleted,
		is_price_ever_changed,
		best_bid_price,
		best_ask_price
  from events left join event_connection using (microtimestamp, event_no, order_id) 

  order by 1;

$$;


ALTER FUNCTION obanalytics.oba_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: oba_exchange_id(text); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_exchange_id(p_exchange text) RETURNS smallint
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$select exchange_id from obanalytics.exchanges where exchange = lower(p_exchange)$$;


ALTER FUNCTION obanalytics.oba_exchange_id(p_exchange text) OWNER TO "ob-analytics";

--
-- Name: oba_export(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(id bigint, "timestamp" text, "exchange.timestamp" text, price numeric, volume numeric, action text, direction text)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

with active_events as (
	select 	microtimestamp, order_id, event_no, next_microtimestamp = '-infinity' as is_deleted, side,price, amount, price_microtimestamp
	from obanalytics.level3 
	where microtimestamp > p_start_time 
	  and microtimestamp <= p_end_time
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and not (amount = 0 and event_no = 1 and next_microtimestamp <>  '-infinity')		
	union all 
	select 	microtimestamp, order_id, event_no, false, side,price, amount, price_microtimestamp
	from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := false) join unnest(ob) on true
)
select order_id,
		obanalytics._in_milliseconds(microtimestamp),
		obanalytics._in_milliseconds(price_microtimestamp),
		price,
		round(amount,8),
		case 
		  when event_no = 1 and not is_deleted  then 'created'::text
		  when event_no > 1 and not is_deleted  then 'changed'::text
		  when is_deleted then 'deleted'::text
		end,
		case side
		  when 'b' then 'bid'::text
		  when 's' then 'ask'::text
		end
from active_events
  
$$;


ALTER FUNCTION obanalytics.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: oba_order_book(timestamp with time zone, integer, integer, integer, numeric, numeric, numeric); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer DEFAULT NULL::integer, p_bps_range numeric DEFAULT NULL::numeric, p_min_bid numeric DEFAULT NULL::numeric, p_max_ask numeric DEFAULT NULL::numeric) RETURNS TABLE(ts timestamp with time zone, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, liquidity numeric, bps numeric, side character)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

-- select * from obanalytics.oba_order_book('2019-03-28 13:30:00+03', 1,2)
with order_book as (
	select ts,
			d.*,
			min(price) filter(where side = 's') over (partition by ts) as best_ask_price, 
			max(price) filter(where side = 'b') over (partition by ts) as best_bid_price 
	from  obanalytics.order_book(p_ts, p_pair_id, p_exchange_id, p_only_makers := true, p_before := false, p_check_takers := false) 
		  join unnest(ob) d on true
),
order_book_bps_lvl as (
	select ts, order_id, microtimestamp, price_microtimestamp,  price, amount, sum(amount) over (order by price) as liquidity, 
			round((price-best_ask_price)/best_ask_price*10000,2) as bps, side, row_number() over (order by price) as lvl
	from order_book
	where side = 's'
	union all
	select ts, order_id,  microtimestamp, price_microtimestamp, price, amount, sum(amount) over (order by price desc) as liquidity,
			round((best_bid_price-price)/best_bid_price*10000,2) as bps, side, row_number() over (order by price)
	from order_book
	where side = 'b'
	order by side, price desc
)
select ts, order_id, microtimestamp, price_microtimestamp, price, amount, liquidity, bps, side 
from order_book_bps_lvl
where bps <= coalesce(p_bps_range, bps)
  and lvl <= coalesce(p_max_levels, lvl)
  and ( (side = 'b' and price >= coalesce(p_min_bid, price)) or (side = 's' and price <= coalesce(p_max_ask, price)));

$$;


ALTER FUNCTION obanalytics.oba_order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer, p_bps_range numeric, p_min_bid numeric, p_max_ask numeric) OWNER TO "ob-analytics";

--
-- Name: oba_pair_id(text); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_pair_id(p_pair text) RETURNS smallint
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$select pair_id from obanalytics.pairs where pair = upper(p_pair)$$;


ALTER FUNCTION obanalytics.oba_pair_id(p_pair text) OWNER TO "ob-analytics";

--
-- Name: oba_spread(timestamp with time zone, timestamp with time zone, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean DEFAULT true) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

-- ARGUMENTS
--	See obanalytics.spread_by_episode()

	select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
	from obanalytics.level1 
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp between p_start_time and p_end_time
	union all
	select *
	from (
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, p_start_time
		from obanalytics.level1 
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and microtimestamp = (select max(microtimestamp) 
								from obanalytics.level1 
								where pair_id = p_pair_id
								 and exchange_id = p_exchange_id
								 and microtimestamp < p_start_time
								 and microtimestamp >= ( select max(era)
													   	  from obanalytics.level3_eras
													      where pair_id = p_pair_id 
													        and exchange_id = p_exchange_id
													        and era < p_start_time )
							    )
	) a
	union all
	select *
	from (
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, p_end_time 
		from obanalytics.level1 
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and microtimestamp = (select max(microtimestamp) 
								from obanalytics.level1 
								where pair_id = p_pair_id
								 and exchange_id = p_exchange_id
								 and microtimestamp <= p_end_time
								 and microtimestamp >= ( select max(era)
													   	  from obanalytics.level3_eras
													      where pair_id = p_pair_id 
													        and exchange_id = p_exchange_id
													        and era <= p_end_time )								
							    )
	) a
	
$$;


ALTER FUNCTION obanalytics.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean) OWNER TO "ob-analytics";

--
-- Name: oba_trades(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, direction text, "maker.event.id" uuid, "taker.event.id" uuid, maker bigint, taker bigint, "exchange.trade.id" bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

select microtimestamp,
		price,
		amount,
	  	case side when 'b' then 'buy'::text when 's' then 'sell'::text end,
	  	case side
			when 'b' then obanalytics._level3_uuid(microtimestamp, sell_order_id, sell_event_no, p_pair_id::smallint, p_exchange_id::smallint)
			when 's' then obanalytics._level3_uuid(microtimestamp, buy_order_id, buy_event_no, p_pair_id::smallint, p_exchange_id::smallint)
	  	end,
	  	case side
			when 'b' then obanalytics._level3_uuid(microtimestamp, buy_order_id, buy_event_no, p_pair_id::smallint, p_exchange_id::smallint)
			when 's' then obanalytics._level3_uuid(microtimestamp, sell_order_id, sell_event_no, p_pair_id::smallint, p_exchange_id::smallint)
	  	end,
	  	case side
			when 'b' then sell_order_id
			when 's' then buy_order_id
	  	end,
	  	case side
			when 'b' then buy_order_id
			when 's' then sell_order_id
	  	end,
	  	exchange_trade_id 
from obanalytics.matches 
where microtimestamp between p_start_time and p_end_time
  and pair_id = p_pair_id
  and exchange_id = p_exchange_id

order by 1

$$;


ALTER FUNCTION obanalytics.oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

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
							when 'b' then price >= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
							when 's' then price <= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
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
			array_agg(orders::obanalytics.level3 order by microtimestamp, order_id, event_no) 	
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
select microtimestamp as ts, obanalytics.order_book_agg(episode, p_check_takers) over (order by microtimestamp)  as ob
from (
	select microtimestamp, array_agg(level3) as episode
	from obanalytics.level3
	where microtimestamp between p_start_time and p_end_time
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	group by microtimestamp  
) a
order by ts

$$;


ALTER FUNCTION obanalytics.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: pga_summarize(text, text, interval, timestamp with time zone, boolean); Type: PROCEDURE; Schema: obanalytics; Owner: ob-analytics
--

CREATE PROCEDURE obanalytics.pga_summarize(p_exchange text, p_pair text, p_max_interval interval DEFAULT '04:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone, p_commit_each_era boolean DEFAULT true)
    LANGUAGE plpgsql
    AS $$
declare 
	v_current_timestamp timestamptz;
	
	v_start timestamptz;
	v_end timestamptz;
	
	v_first timestamptz;
	
	v_pair_id obanalytics.pairs.pair_id%type;
	v_exchange_id obanalytics.exchanges.exchange_id%type;
	
	e record;
	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs 
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);
	
	if p_ts_within_era is null then	-- we start from the latest era where level1 and level2 have already been calculated.
									 -- If a new era has started this start point will ensure that we'll calculate remaining 
									 -- level1 and level2 for the old era(s) as well as the new one(s)
		select max(era) into p_ts_within_era
		from obanalytics.level3_eras 
		where pair_id = v_pair_id
		   and exchange_id = v_exchange_id
		   and level1 is not null and level2 is not null;
	end if;
	
	select starts, ends into v_start, v_end
	from (select era as starts, coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'infinity') as ends
		   from obanalytics.level3_eras
		   where pair_id = v_pair_id
			 and exchange_id = v_exchange_id
		 ) a
	where p_ts_within_era between starts and ends;
	
	raise debug 'p_ts_within_era: %, v_start: %, v_end: %', p_ts_within_era, v_start, v_end;
	
	select coalesce(max(microtimestamp) + '00:00:00.000001'::interval, v_start) into v_start
	from obanalytics.level1 
	where microtimestamp between v_start and v_end
	  and exchange_id = v_exchange_id
	  and pair_id = v_pair_id;
	  
	raise debug 'start: %, end: %', v_start, v_start + p_max_interval;	  

	for e in   select starts, least(ends, v_start + p_max_interval) as ends
				from (
					select era as starts,
							coalesce(level3, 
								coalesce(lead(era) over (order by era)  - '00:00:00.000001'::interval, 'infinity'::timestamptz)
									) as ends
					from obanalytics.level3_eras 
					where pair_id = v_pair_id
					  and exchange_id = v_exchange_id
				) a
				where a.ends >= v_start
				  and starts <= v_start + p_max_interval
				order by starts loop

		-- theoretically the microtimestamp below should always be equal to level3_eras.level1
		select coalesce(max(microtimestamp) + '00:00:00.000001'::interval, e.starts) into v_first
		from obanalytics.level1 
		where microtimestamp between e.starts and e.ends
	  	  and exchange_id = v_exchange_id
	  	  and pair_id = v_pair_id;
		  
		raise debug 'level1 (spread) e.starts: %, v_first: %, e.ends: %, v_pair_id: %, v_exchange_id: % ', e.starts, v_first, e.ends, v_pair_id, v_exchange_id;	  
		
		insert into obanalytics.level1 (best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id)
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id
		from obanalytics.spread_by_episode(v_first, e.ends, v_pair_id, v_exchange_id, p_with_order_book := false);
		
		-- theoretically the microtimestamp below should always be equal to level3_eras.level2
		select coalesce(max(microtimestamp) + '00:00:00.000001'::interval, e.starts) into v_first
		from obanalytics.level2
		where microtimestamp between e.starts and e.ends
		  and precision = 'r0'
	  	  and exchange_id = v_exchange_id
	  	  and pair_id = v_pair_id;
		  
		raise debug 'level2 (depth) e.starts: %, v_first: %, e.ends: %, v_pair_id: %, v_exchange_id: % ', e.starts, v_first, e.ends, v_pair_id, v_exchange_id;	  
		
		insert into obanalytics.level2 (microtimestamp, pair_id, exchange_id, precision, depth_change)
		select microtimestamp, pair_id, exchange_id, precision, coalesce(depth_change, '{}')
		from obanalytics.depth_change_by_episode(v_first, e.ends, v_pair_id, v_exchange_id);
		
		if p_commit_each_era then
			commit;
			raise debug 'era commited e.starts: %, e.ends: %, v_pair_id: %, v_exchange_id: % ', e.starts, e.ends, v_pair_id, v_exchange_id;	  
		end if;
		
	end loop;
	
	raise debug 'pga_summarize() exec time: %', clock_timestamp() - v_current_timestamp;
	return;
end;

$$;


ALTER PROCEDURE obanalytics.pga_summarize(p_exchange text, p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone, p_commit_each_era boolean) OWNER TO "ob-analytics";

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
	from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id)
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
-- Name: FUNCTION spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean, p_with_order_book boolean); Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON FUNCTION obanalytics.spread_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean, p_with_order_book boolean) IS 'Calculates the best bid and ask prices and quantities (so called "spread") after each episode in the ''level3'' table that hits the interval between p_start_time and p_end_time for the given "pair". The spread is calculated using all available data before p_start_time';


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
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(p_exchange, exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(p_pair, pair))
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
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(p_exchange, exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(p_pair, pair))
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
-- Name: depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) (
    SFUNC = obanalytics._depth_summary_after_depth_change,
    STYPE = obanalytics.level2_depth_summary_internal_state,
    FINALFUNC = obanalytics._depth_summary
);


ALTER AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) OWNER TO "ob-analytics";

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

CREATE TABLE obanalytics.level1_bitfinex PARTITION OF obanalytics.level1
FOR VALUES IN ('1')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level1_bitfinex OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_btcusd PARTITION OF obanalytics.level1_bitfinex
FOR VALUES IN ('1')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level1_01001201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01001201903 PARTITION OF obanalytics.level1_bitfinex_btcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01001201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01001201903 OWNER TO "ob-analytics";

--
-- Name: level1_01001201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01001201904 PARTITION OF obanalytics.level1_bitfinex_btcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01001201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01001201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_ltcusd PARTITION OF obanalytics.level1_bitfinex
FOR VALUES IN ('2')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level1_01002201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01002201903 PARTITION OF obanalytics.level1_bitfinex_ltcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01002201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01002201903 OWNER TO "ob-analytics";

--
-- Name: level1_01002201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01002201904 PARTITION OF obanalytics.level1_bitfinex_ltcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01002201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01002201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitfinex_ethusd PARTITION OF obanalytics.level1_bitfinex
FOR VALUES IN ('3')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level1_01003201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01003201903 PARTITION OF obanalytics.level1_bitfinex_ethusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01003201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01003201903 OWNER TO "ob-analytics";

--
-- Name: level1_01003201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_01003201904 PARTITION OF obanalytics.level1_bitfinex_ethusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_01003201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_01003201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp PARTITION OF obanalytics.level1
FOR VALUES IN ('2')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level1_bitstamp OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_btcusd PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('1')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level1_02001201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02001201903 PARTITION OF obanalytics.level1_bitstamp_btcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02001201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02001201903 OWNER TO "ob-analytics";

--
-- Name: level1_02001201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02001201904 PARTITION OF obanalytics.level1_bitstamp_btcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02001201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02001201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ltcusd PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('2')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level1_02002201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02002201903 PARTITION OF obanalytics.level1_bitstamp_ltcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02002201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02002201903 OWNER TO "ob-analytics";

--
-- Name: level1_02002201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02002201904 PARTITION OF obanalytics.level1_bitstamp_ltcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02002201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02002201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ethusd PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('3')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level1_02003201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02003201903 PARTITION OF obanalytics.level1_bitstamp_ethusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02003201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02003201903 OWNER TO "ob-analytics";

--
-- Name: level1_02003201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02003201904 PARTITION OF obanalytics.level1_bitstamp_ethusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02003201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02003201904 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_xrpusd PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('4')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level1_02004201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02004201903 PARTITION OF obanalytics.level1_bitstamp_xrpusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02004201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02004201903 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_bchusd PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('5')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level1_02005201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02005201903 PARTITION OF obanalytics.level1_bitstamp_bchusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02005201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02005201903 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_btceur PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('6')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level1_02006201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02006201903 PARTITION OF obanalytics.level1_bitstamp_btceur
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02006201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02006201903 OWNER TO "ob-analytics";

--
-- Name: level1_bitstamp_ethbtc; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_bitstamp_ethbtc PARTITION OF obanalytics.level1_bitstamp
FOR VALUES IN ('7')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level1_bitstamp_ethbtc OWNER TO "ob-analytics";

--
-- Name: level1_02007201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level1_02007201903 PARTITION OF obanalytics.level1_bitstamp_ethbtc
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level1_02007201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level1_02007201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex PARTITION OF obanalytics.level2
FOR VALUES IN ('1')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level2_bitfinex OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd PARTITION OF obanalytics.level2_bitfinex
FOR VALUES IN ('1')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd_p0 PARTITION OF obanalytics.level2_bitfinex_btcusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_btcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_01001p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01001p0201903 PARTITION OF obanalytics.level2_bitfinex_btcusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01001p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01001p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_btcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_btcusd_r0 PARTITION OF obanalytics.level2_bitfinex_btcusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_btcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_01001r0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01001r0201903 PARTITION OF obanalytics.level2_bitfinex_btcusd_r0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01001r0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01001r0201903 OWNER TO "ob-analytics";

--
-- Name: level2_01001r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01001r0201904 PARTITION OF obanalytics.level2_bitfinex_btcusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01001r0201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01001r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd PARTITION OF obanalytics.level2_bitfinex
FOR VALUES IN ('2')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd_p0 PARTITION OF obanalytics.level2_bitfinex_ltcusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_ltcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_01002p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01002p0201903 PARTITION OF obanalytics.level2_bitfinex_ltcusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01002p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01002p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ltcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ltcusd_r0 PARTITION OF obanalytics.level2_bitfinex_ltcusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_ltcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_01002r0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01002r0201903 PARTITION OF obanalytics.level2_bitfinex_ltcusd_r0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01002r0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01002r0201903 OWNER TO "ob-analytics";

--
-- Name: level2_01002r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01002r0201904 PARTITION OF obanalytics.level2_bitfinex_ltcusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01002r0201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01002r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd PARTITION OF obanalytics.level2_bitfinex
FOR VALUES IN ('3')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd_p0 PARTITION OF obanalytics.level2_bitfinex_ethusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_ethusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_01003p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01003p0201903 PARTITION OF obanalytics.level2_bitfinex_ethusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01003p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01003p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitfinex_ethusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitfinex_ethusd_r0 PARTITION OF obanalytics.level2_bitfinex_ethusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitfinex_ethusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_01003r0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01003r0201903 PARTITION OF obanalytics.level2_bitfinex_ethusd_r0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01003r0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01003r0201903 OWNER TO "ob-analytics";

--
-- Name: level2_01003r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_01003r0201904 PARTITION OF obanalytics.level2_bitfinex_ethusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_01003r0201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_01003r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp PARTITION OF obanalytics.level2
FOR VALUES IN ('2')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level2_bitstamp OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('1')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd_p0 PARTITION OF obanalytics.level2_bitstamp_btcusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_btcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02001p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02001p0201903 PARTITION OF obanalytics.level2_bitstamp_btcusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02001p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02001p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_02001p0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02001p0201904 PARTITION OF obanalytics.level2_bitstamp_btcusd_p0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02001p0201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02001p0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btcusd_r0 PARTITION OF obanalytics.level2_bitstamp_btcusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_btcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_02001r0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02001r0201903 PARTITION OF obanalytics.level2_bitstamp_btcusd_r0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02001r0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02001r0201903 OWNER TO "ob-analytics";

--
-- Name: level2_02001r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02001r0201904 PARTITION OF obanalytics.level2_bitstamp_btcusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level2_02001r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('2')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd_p0 PARTITION OF obanalytics.level2_bitstamp_ltcusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_ltcusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02002p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02002p0201903 PARTITION OF obanalytics.level2_bitstamp_ltcusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02002p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02002p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ltcusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ltcusd_r0 PARTITION OF obanalytics.level2_bitstamp_ltcusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_ltcusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_02002r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02002r0201904 PARTITION OF obanalytics.level2_bitstamp_ltcusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level2_02002r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('3')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd_p0 PARTITION OF obanalytics.level2_bitstamp_ethusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_ethusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02003p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02003p0201903 PARTITION OF obanalytics.level2_bitstamp_ethusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02003p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02003p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethusd_r0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethusd_r0 PARTITION OF obanalytics.level2_bitstamp_ethusd
FOR VALUES IN ('r0')
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_r0 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_bitstamp_ethusd_r0 OWNER TO "ob-analytics";

--
-- Name: level2_02003r0201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02003r0201904 PARTITION OF obanalytics.level2_bitstamp_ethusd_r0
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level2_02003r0201904 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_xrpusd PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('4')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_xrpusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_xrpusd_p0 PARTITION OF obanalytics.level2_bitstamp_xrpusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_xrpusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02004p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02004p0201903 PARTITION OF obanalytics.level2_bitstamp_xrpusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02004p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02004p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_bchusd PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('5')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_bchusd_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_bchusd_p0 PARTITION OF obanalytics.level2_bitstamp_bchusd
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_bchusd_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02005p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02005p0201903 PARTITION OF obanalytics.level2_bitstamp_bchusd_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02005p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02005p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btceur PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('6')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_btceur_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_btceur_p0 PARTITION OF obanalytics.level2_bitstamp_btceur
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_btceur_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02006p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02006p0201903 PARTITION OF obanalytics.level2_bitstamp_btceur_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02006p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02006p0201903 OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethbtc; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethbtc PARTITION OF obanalytics.level2_bitstamp
FOR VALUES IN ('7')
PARTITION BY LIST ("precision");


ALTER TABLE obanalytics.level2_bitstamp_ethbtc OWNER TO "ob-analytics";

--
-- Name: level2_bitstamp_ethbtc_p0; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_bitstamp_ethbtc_p0 PARTITION OF obanalytics.level2_bitstamp_ethbtc
FOR VALUES IN ('p0')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level2_bitstamp_ethbtc_p0 OWNER TO "ob-analytics";

--
-- Name: level2_02007p0201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level2_02007p0201903 PARTITION OF obanalytics.level2_bitstamp_ethbtc_p0
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level2_02007p0201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level2_02007p0201903 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex PARTITION OF obanalytics.level3
FOR VALUES IN ('1')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level3_bitfinex OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd PARTITION OF obanalytics.level3_bitfinex
FOR VALUES IN ('1')
PARTITION BY LIST (side);


ALTER TABLE obanalytics.level3_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_b PARTITION OF obanalytics.level3_bitfinex_btcusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_01001b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001b201902 PARTITION OF obanalytics.level3_bitfinex_btcusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001b201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001b201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001b201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001b201903 OWNER TO "ob-analytics";

--
-- Name: level3_01001b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001b201904 PARTITION OF obanalytics.level3_bitfinex_btcusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_s PARTITION OF obanalytics.level3_bitfinex_btcusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_01001s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001s201902 PARTITION OF obanalytics.level3_bitfinex_btcusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001s201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001s201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001s201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001s201903 OWNER TO "ob-analytics";

--
-- Name: level3_01001s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001s201904 PARTITION OF obanalytics.level3_bitfinex_btcusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01001s201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01001s201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd PARTITION OF obanalytics.level3_bitfinex
FOR VALUES IN ('2')
PARTITION BY LIST (side);


ALTER TABLE obanalytics.level3_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_b PARTITION OF obanalytics.level3_bitfinex_ltcusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_01002b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002b201902 PARTITION OF obanalytics.level3_bitfinex_ltcusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002b201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002b201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002b201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002b201903 OWNER TO "ob-analytics";

--
-- Name: level3_01002b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002b201904 PARTITION OF obanalytics.level3_bitfinex_ltcusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_s PARTITION OF obanalytics.level3_bitfinex_ltcusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_01002s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002s201902 PARTITION OF obanalytics.level3_bitfinex_ltcusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002s201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002s201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002s201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002s201903 OWNER TO "ob-analytics";

--
-- Name: level3_01002s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002s201904 PARTITION OF obanalytics.level3_bitfinex_ltcusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01002s201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01002s201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd PARTITION OF obanalytics.level3_bitfinex
FOR VALUES IN ('3')
PARTITION BY LIST (side);


ALTER TABLE obanalytics.level3_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_b PARTITION OF obanalytics.level3_bitfinex_ethusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_01003b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003b201902 PARTITION OF obanalytics.level3_bitfinex_ethusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003b201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003b201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003b201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003b201903 OWNER TO "ob-analytics";

--
-- Name: level3_01003b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003b201904 PARTITION OF obanalytics.level3_bitfinex_ethusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_s PARTITION OF obanalytics.level3_bitfinex_ethusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_01003s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003s201902 PARTITION OF obanalytics.level3_bitfinex_ethusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003s201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003s201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003s201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003s201903 OWNER TO "ob-analytics";

--
-- Name: level3_01003s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003s201904 PARTITION OF obanalytics.level3_bitfinex_ethusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01003s201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01003s201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd PARTITION OF obanalytics.level3_bitfinex
FOR VALUES IN ('4')
PARTITION BY LIST (side);


ALTER TABLE obanalytics.level3_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_b PARTITION OF obanalytics.level3_bitfinex_xrpusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_b OWNER TO "ob-analytics";

--
-- Name: level3_01004b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01004b201902 PARTITION OF obanalytics.level3_bitfinex_xrpusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01004b201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01004b201902 OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_s PARTITION OF obanalytics.level3_bitfinex_xrpusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_s OWNER TO "ob-analytics";

--
-- Name: level3_01004s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01004s201902 PARTITION OF obanalytics.level3_bitfinex_xrpusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_01004s201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_01004s201902 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp PARTITION OF obanalytics.level3
FOR VALUES IN ('2')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.level3_bitstamp OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd PARTITION OF obanalytics.level3_bitstamp
FOR VALUES IN ('1')
PARTITION BY LIST (side);


ALTER TABLE obanalytics.level3_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_b PARTITION OF obanalytics.level3_bitstamp_btcusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitstamp_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_02001b201901; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201901 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-01-01 00:00:00+03') TO ('2019-02-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001b201901 OWNER TO "ob-analytics";

--
-- Name: level3_02001b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201902 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001b201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001b201902 OWNER TO "ob-analytics";

--
-- Name: level3_02001b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201903 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001b201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001b201903 OWNER TO "ob-analytics";

--
-- Name: level3_02001b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201904 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_s PARTITION OF obanalytics.level3_bitstamp_btcusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitstamp_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_02001s201901; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201901 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-01-01 00:00:00+03') TO ('2019-02-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001s201901 OWNER TO "ob-analytics";

--
-- Name: level3_02001s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201902 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001s201902 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001s201902 OWNER TO "ob-analytics";

--
-- Name: level3_02001s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201903 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001s201903 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001s201903 OWNER TO "ob-analytics";

--
-- Name: level3_02001s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201904 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02001s201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02001s201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd PARTITION OF obanalytics.level3_bitstamp
FOR VALUES IN ('2')
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_b PARTITION OF obanalytics.level3_bitstamp_ltcusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_02002b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02002b201904 PARTITION OF obanalytics.level3_bitstamp_ltcusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02002b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02002b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_s PARTITION OF obanalytics.level3_bitstamp_ltcusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_02002s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02002s201904 PARTITION OF obanalytics.level3_bitstamp_ltcusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02002s201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd PARTITION OF obanalytics.level3_bitstamp
FOR VALUES IN ('3')
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_b PARTITION OF obanalytics.level3_bitstamp_ethusd
FOR VALUES IN ('b')
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_02003b201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02003b201904 PARTITION OF obanalytics.level3_bitstamp_ethusd_b
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');
ALTER TABLE ONLY obanalytics.level3_02003b201904 ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_02003b201904 OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_s PARTITION OF obanalytics.level3_bitstamp_ethusd
FOR VALUES IN ('s')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.level3_bitstamp_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_02003s201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02003s201904 PARTITION OF obanalytics.level3_bitstamp_ethusd_s
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02003s201904 OWNER TO "ob-analytics";

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

CREATE TABLE obanalytics.matches_bitfinex PARTITION OF obanalytics.matches
FOR VALUES IN ('1')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.matches_bitfinex OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_btcusd PARTITION OF obanalytics.matches_bitfinex
FOR VALUES IN ('1')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_01001201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01001201902 PARTITION OF obanalytics.matches_bitfinex_btcusd
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01001201902 OWNER TO "ob-analytics";

--
-- Name: matches_01001201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01001201903 PARTITION OF obanalytics.matches_bitfinex_btcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01001201903 OWNER TO "ob-analytics";

--
-- Name: matches_01001201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01001201904 PARTITION OF obanalytics.matches_bitfinex_btcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01001201904 OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ltcusd PARTITION OF obanalytics.matches_bitfinex
FOR VALUES IN ('2')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_01002201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01002201902 PARTITION OF obanalytics.matches_bitfinex_ltcusd
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01002201902 OWNER TO "ob-analytics";

--
-- Name: matches_01002201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01002201903 PARTITION OF obanalytics.matches_bitfinex_ltcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01002201903 OWNER TO "ob-analytics";

--
-- Name: matches_01002201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01002201904 PARTITION OF obanalytics.matches_bitfinex_ltcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01002201904 OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ethusd PARTITION OF obanalytics.matches_bitfinex
FOR VALUES IN ('3')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_01003201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01003201902 PARTITION OF obanalytics.matches_bitfinex_ethusd
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01003201902 OWNER TO "ob-analytics";

--
-- Name: matches_01003201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01003201903 PARTITION OF obanalytics.matches_bitfinex_ethusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01003201903 OWNER TO "ob-analytics";

--
-- Name: matches_01003201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01003201904 PARTITION OF obanalytics.matches_bitfinex_ethusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01003201904 OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_xrpusd PARTITION OF obanalytics.matches_bitfinex
FOR VALUES IN ('4')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: matches_01004201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01004201902 PARTITION OF obanalytics.matches_bitfinex_xrpusd
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01004201902 OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp PARTITION OF obanalytics.matches
FOR VALUES IN ('2')
PARTITION BY LIST (pair_id);


ALTER TABLE obanalytics.matches_bitstamp OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_btcusd PARTITION OF obanalytics.matches_bitstamp
FOR VALUES IN ('1')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_02001201901; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02001201901 PARTITION OF obanalytics.matches_bitstamp_btcusd
FOR VALUES FROM ('2019-01-01 00:00:00+03') TO ('2019-02-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02001201901 OWNER TO "ob-analytics";

--
-- Name: matches_02001201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02001201902 PARTITION OF obanalytics.matches_bitstamp_btcusd
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02001201902 OWNER TO "ob-analytics";

--
-- Name: matches_02001201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02001201903 PARTITION OF obanalytics.matches_bitstamp_btcusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02001201903 OWNER TO "ob-analytics";

--
-- Name: matches_02001201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02001201904 PARTITION OF obanalytics.matches_bitstamp_btcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02001201904 OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ltcusd PARTITION OF obanalytics.matches_bitstamp
FOR VALUES IN ('2')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_02002201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02002201904 PARTITION OF obanalytics.matches_bitstamp_ltcusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02002201904 OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ethusd PARTITION OF obanalytics.matches_bitstamp
FOR VALUES IN ('3')
PARTITION BY RANGE (microtimestamp);


ALTER TABLE obanalytics.matches_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_02003201904; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_02003201904 PARTITION OF obanalytics.matches_bitstamp_ethusd
FOR VALUES FROM ('2019-04-01 00:00:00+03') TO ('2019-05-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_02003201904 OWNER TO "ob-analytics";

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
-- Name: level1_01001201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_01001201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01001201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_01001201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01002201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_01002201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01002201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_01002201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01003201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_01003201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01003201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_01003201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_02001201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_02001201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02001201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_02001201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02002201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_02002201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02002201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_02002201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02003201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_02003201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02003201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_02003201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02004201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02004201903 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level1_02004201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02004201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02005201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02005201903 ALTER COLUMN pair_id SET DEFAULT 5;


--
-- Name: level1_02005201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02005201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02006201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02006201903 ALTER COLUMN pair_id SET DEFAULT 6;


--
-- Name: level1_02006201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02006201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_02007201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02007201903 ALTER COLUMN pair_id SET DEFAULT 7;


--
-- Name: level1_02007201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02007201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitfinex exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_bitfinex_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_bitfinex_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_btcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_bitfinex_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_bitfinex_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_ethusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_bitfinex_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_bitfinex_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitfinex_ltcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_bitstamp exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_bchusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_bchusd ALTER COLUMN pair_id SET DEFAULT 5;


--
-- Name: level1_bitstamp_bchusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_bchusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_btceur pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btceur ALTER COLUMN pair_id SET DEFAULT 6;


--
-- Name: level1_bitstamp_btceur exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btceur ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_ethbtc pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ethbtc ALTER COLUMN pair_id SET DEFAULT 7;


--
-- Name: level1_bitstamp_ethbtc exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ethbtc ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_bitstamp_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ethusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_ltcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level1_bitstamp_xrpusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_xrpusd ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level1_bitstamp_xrpusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_xrpusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_01001p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001p0201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_01001p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001p0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01001p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_01001r0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_01001r0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01001r0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201903 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_01001r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_01001r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01001r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_01002p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002p0201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_01002p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002p0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01002p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_01002r0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_01002r0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01002r0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201903 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_01002r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_01002r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01002r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_01003p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003p0201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_01003p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003p0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01003p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_01003r0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_01003r0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01003r0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201903 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_01003r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_01003r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_01003r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_02001p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_02001p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02001p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02001p0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_02001p0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02001p0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201904 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02001r0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_02001r0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02001r0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201903 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_02001r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_02001r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02001r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_02002p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002p0201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_02002p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02002p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02002r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002r0201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_02002r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002r0201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02002r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_02003p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003p0201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_02003p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02003p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02003r0201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003r0201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_02003r0201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003r0201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02003r0201904 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003r0201904 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_02004p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02004p0201903 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level2_02004p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02004p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02004p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02004p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02005p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02005p0201903 ALTER COLUMN pair_id SET DEFAULT 5;


--
-- Name: level2_02005p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02005p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02005p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02005p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02006p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02006p0201903 ALTER COLUMN pair_id SET DEFAULT 6;


--
-- Name: level2_02006p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02006p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02006p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02006p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_02007p0201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02007p0201903 ALTER COLUMN pair_id SET DEFAULT 7;


--
-- Name: level2_02007p0201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02007p0201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_02007p0201903 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02007p0201903 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitfinex exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_p0 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_p0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitfinex_btcusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_r0 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_r0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_btcusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_btcusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitfinex_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitfinex_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ethusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_p0 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitfinex_ethusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_p0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ethusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitfinex_ethusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_r0 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitfinex_ethusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_r0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ethusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ethusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitfinex_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitfinex_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ltcusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_p0 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitfinex_ltcusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_p0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ltcusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitfinex_ltcusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_r0 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitfinex_ltcusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_r0 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level2_bitfinex_ltcusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitfinex_ltcusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitstamp exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_bchusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd ALTER COLUMN pair_id SET DEFAULT 5;


--
-- Name: level2_bitstamp_bchusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_bchusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd_p0 ALTER COLUMN pair_id SET DEFAULT 5;


--
-- Name: level2_bitstamp_bchusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_bchusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_bchusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_btceur pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur ALTER COLUMN pair_id SET DEFAULT 6;


--
-- Name: level2_bitstamp_btceur exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_btceur_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur_p0 ALTER COLUMN pair_id SET DEFAULT 6;


--
-- Name: level2_bitstamp_btceur_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_btceur_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btceur_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_btcusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_p0 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitstamp_btcusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_btcusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_btcusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_r0 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level2_bitstamp_btcusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_r0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_btcusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_btcusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitstamp_ethbtc pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc ALTER COLUMN pair_id SET DEFAULT 7;


--
-- Name: level2_bitstamp_ethbtc exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ethbtc_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc_p0 ALTER COLUMN pair_id SET DEFAULT 7;


--
-- Name: level2_bitstamp_ethbtc_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ethbtc_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethbtc_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitstamp_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ethusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_p0 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitstamp_ethusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ethusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_ethusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_r0 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level2_bitstamp_ethusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_r0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ethusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ethusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitstamp_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_p0 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level2_bitstamp_ltcusd_r0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_r0 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd_r0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_r0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_ltcusd_r0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_ltcusd_r0 ALTER COLUMN "precision" SET DEFAULT 'r0'::bpchar;


--
-- Name: level2_bitstamp_xrpusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level2_bitstamp_xrpusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_xrpusd_p0 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd_p0 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level2_bitstamp_xrpusd_p0 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd_p0 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level2_bitstamp_xrpusd_p0 precision; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_bitstamp_xrpusd_p0 ALTER COLUMN "precision" SET DEFAULT 'p0'::bpchar;


--
-- Name: level3_01001b201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01001b201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001b201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01001b201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01001b201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001b201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01001b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01001b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01001s201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01001s201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001s201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01001s201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01001s201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001s201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01001s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01001s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_01001s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002b201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01002b201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002b201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002b201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01002b201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002b201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01002b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002s201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01002s201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002s201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002s201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01002s201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002s201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01002s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01002s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_01002s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003b201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01003b201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003b201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003b201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01003b201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003b201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01003b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003s201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01003s201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003s201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003s201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01003s201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003s201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01003s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01003s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_01003s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01004b201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_01004b201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level3_01004b201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_01004s201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_01004s201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level3_01004s201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_02001b201901 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02001b201901 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001b201901 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001b201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02001b201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001b201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001b201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02001b201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001b201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02001b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001s201901 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02001s201901 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001s201901 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001s201902 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02001s201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001s201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001s201903 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02001s201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001s201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02001s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02001s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_02001s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02002b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02002b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_02002b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02002s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02002s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_02002s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02003b201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904 ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_02003b201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_02003b201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_02003s201904 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904 ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_02003s201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_02003s201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitfinex exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitfinex_btcusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_b ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_b ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitfinex_btcusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_s ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_btcusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_s ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitfinex_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ethusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitfinex_ethusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_b ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitfinex_ethusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_b ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ethusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitfinex_ethusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_s ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitfinex_ethusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_s ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitfinex_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ltcusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitfinex_ltcusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_b ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitfinex_ltcusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_b ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_ltcusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitfinex_ltcusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_s ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitfinex_ltcusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_s ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_xrpusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level3_bitfinex_xrpusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_xrpusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitfinex_xrpusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_b ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level3_bitfinex_xrpusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_b ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitfinex_xrpusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitfinex_xrpusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_s ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: level3_bitfinex_xrpusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd_s ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level3_bitstamp exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_btcusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_btcusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitstamp_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ethusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitstamp_ethusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitstamp_ethusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ethusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitstamp_ethusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level3_bitstamp_ethusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitstamp_ltcusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitstamp_ltcusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_ltcusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_01001201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01001201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_01001201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01001201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_01001201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01001201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_01002201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01002201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201902 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: matches_01002201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01002201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: matches_01002201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01002201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: matches_01003201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01003201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201902 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_01003201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01003201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_01003201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201904 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01003201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_01004201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01004201902 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_01004201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01004201902 ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: matches_02001201901 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201901 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02001201901 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201901 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_02001201902 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201902 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02001201902 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201902 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_02001201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201903 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02001201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_02001201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02001201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201904 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_02002201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02002201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02002201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02002201904 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: matches_02003201904 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02003201904 ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_02003201904 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02003201904 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_bitfinex exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_btcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_ethusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_bitfinex_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_ltcusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: matches_bitfinex_xrpusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_xrpusd ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: matches_bitfinex_xrpusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitfinex_xrpusd ALTER COLUMN pair_id SET DEFAULT 4;


--
-- Name: matches_bitstamp exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_bitstamp_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: matches_bitstamp_ethusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_ethusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_bitstamp_ethusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_ethusd ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: matches_bitstamp_ltcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_ltcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: matches_bitstamp_ltcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_bitstamp_ltcusd ALTER COLUMN pair_id SET DEFAULT 2;


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
-- Name: level1_01001201903 level1_01001201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201903
    ADD CONSTRAINT level1_01001201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01001201904 level1_01001201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01001201904
    ADD CONSTRAINT level1_01001201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01002201903 level1_01002201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903
    ADD CONSTRAINT level1_01002201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01002201904 level1_01002201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201904
    ADD CONSTRAINT level1_01002201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01003201903 level1_01003201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903
    ADD CONSTRAINT level1_01003201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01003201904 level1_01003201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201904
    ADD CONSTRAINT level1_01003201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02001201903 level1_02001201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903
    ADD CONSTRAINT level1_02001201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02001201904 level1_02001201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201904
    ADD CONSTRAINT level1_02001201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02002201903 level1_02002201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201903
    ADD CONSTRAINT level1_02002201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02002201904 level1_02002201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02002201904
    ADD CONSTRAINT level1_02002201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02003201903 level1_02003201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201903
    ADD CONSTRAINT level1_02003201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02003201904 level1_02003201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02003201904
    ADD CONSTRAINT level1_02003201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02004201903 level1_02004201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02004201903
    ADD CONSTRAINT level1_02004201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02005201903 level1_02005201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02005201903
    ADD CONSTRAINT level1_02005201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02006201903 level1_02006201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02006201903
    ADD CONSTRAINT level1_02006201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02007201903 level1_02007201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02007201903
    ADD CONSTRAINT level1_02007201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01001p0201903 level2_01001p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001p0201903
    ADD CONSTRAINT level2_01001p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01001r0201903 level2_01001r0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201903
    ADD CONSTRAINT level2_01001r0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01001r0201904 level2_01001r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01001r0201904
    ADD CONSTRAINT level2_01001r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01002p0201903 level2_01002p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002p0201903
    ADD CONSTRAINT level2_01002p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01002r0201903 level2_01002r0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201903
    ADD CONSTRAINT level2_01002r0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01002r0201904 level2_01002r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01002r0201904
    ADD CONSTRAINT level2_01002r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01003p0201903 level2_01003p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003p0201903
    ADD CONSTRAINT level2_01003p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01003r0201903 level2_01003r0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201903
    ADD CONSTRAINT level2_01003r0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_01003r0201904 level2_01003r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_01003r0201904
    ADD CONSTRAINT level2_01003r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02001p0201903 level2_02001p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201903
    ADD CONSTRAINT level2_02001p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02001p0201904 level2_02001p0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201904
    ADD CONSTRAINT level2_02001p0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02001r0201903 level2_02001r0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201903
    ADD CONSTRAINT level2_02001r0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02001r0201904 level2_02001r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001r0201904
    ADD CONSTRAINT level2_02001r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02002p0201903 level2_02002p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002p0201903
    ADD CONSTRAINT level2_02002p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02002r0201904 level2_02002r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02002r0201904
    ADD CONSTRAINT level2_02002r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02003p0201903 level2_02003p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003p0201903
    ADD CONSTRAINT level2_02003p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02003r0201904 level2_02003r0201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02003r0201904
    ADD CONSTRAINT level2_02003r0201904_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02004p0201903 level2_02004p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02004p0201903
    ADD CONSTRAINT level2_02004p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02005p0201903 level2_02005p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02005p0201903
    ADD CONSTRAINT level2_02005p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02006p0201903 level2_02006p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02006p0201903
    ADD CONSTRAINT level2_02006p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level2_02007p0201903 level2_02007p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02007p0201903
    ADD CONSTRAINT level2_02007p0201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level3_01001b201903 level3_01001b201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903
    ADD CONSTRAINT level3_01001b201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001b201903 level3_01001b201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903
    ADD CONSTRAINT level3_01001b201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201904 level3_01001b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904
    ADD CONSTRAINT level3_01001b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001b201904 level3_01001b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904
    ADD CONSTRAINT level3_01001b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201903 level3_01001s201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903
    ADD CONSTRAINT level3_01001s201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001s201903 level3_01001s201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903
    ADD CONSTRAINT level3_01001s201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201904 level3_01001s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904
    ADD CONSTRAINT level3_01001s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001s201904 level3_01001s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904
    ADD CONSTRAINT level3_01001s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201903 level3_01002b201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903
    ADD CONSTRAINT level3_01002b201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002b201903 level3_01002b201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903
    ADD CONSTRAINT level3_01002b201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201904 level3_01002b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904
    ADD CONSTRAINT level3_01002b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002b201904 level3_01002b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904
    ADD CONSTRAINT level3_01002b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201903 level3_01002s201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903
    ADD CONSTRAINT level3_01002s201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002s201903 level3_01002s201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903
    ADD CONSTRAINT level3_01002s201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201904 level3_01002s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904
    ADD CONSTRAINT level3_01002s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002s201904 level3_01002s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904
    ADD CONSTRAINT level3_01002s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201903 level3_01003b201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903
    ADD CONSTRAINT level3_01003b201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003b201903 level3_01003b201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903
    ADD CONSTRAINT level3_01003b201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201904 level3_01003b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904
    ADD CONSTRAINT level3_01003b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003b201904 level3_01003b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904
    ADD CONSTRAINT level3_01003b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201903 level3_01003s201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903
    ADD CONSTRAINT level3_01003s201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003s201903 level3_01003s201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903
    ADD CONSTRAINT level3_01003s201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201904 level3_01003s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904
    ADD CONSTRAINT level3_01003s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003s201904 level3_01003s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904
    ADD CONSTRAINT level3_01003s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004b201902 level3_01004b201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902
    ADD CONSTRAINT level3_01004b201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01004b201902 level3_01004b201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902
    ADD CONSTRAINT level3_01004b201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004s201902 level3_01004s201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902
    ADD CONSTRAINT level3_01004s201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01004s201902 level3_01004s201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902
    ADD CONSTRAINT level3_01004s201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201902 level3_01b001201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902
    ADD CONSTRAINT level3_01b001201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001b201902 level3_01b001201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902
    ADD CONSTRAINT level3_01b001201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201902 level3_01b002201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902
    ADD CONSTRAINT level3_01b002201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002b201902 level3_01b002201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902
    ADD CONSTRAINT level3_01b002201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201902 level3_01b003201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902
    ADD CONSTRAINT level3_01b003201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003b201902 level3_01b003201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902
    ADD CONSTRAINT level3_01b003201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201902 level3_01s001201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902
    ADD CONSTRAINT level3_01s001201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01001s201902 level3_01s001201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902
    ADD CONSTRAINT level3_01s001201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201902 level3_01s002201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902
    ADD CONSTRAINT level3_01s002201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01002s201902 level3_01s002201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902
    ADD CONSTRAINT level3_01s002201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201902 level3_01s003201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902
    ADD CONSTRAINT level3_01s003201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_01003s201902 level3_01s003201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902
    ADD CONSTRAINT level3_01s003201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_bitstamp level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp
    ADD CONSTRAINT level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


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
-- Name: level3_02001b201901 level3_02001b201901_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02001b201901_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201902 level3_02001b201902_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902
    ADD CONSTRAINT level3_02001b201902_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201902 level3_02001b201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902
    ADD CONSTRAINT level3_02001b201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201902 level3_02001b201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902
    ADD CONSTRAINT level3_02001b201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201903 level3_02001b201903_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903
    ADD CONSTRAINT level3_02001b201903_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201903 level3_02001b201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903
    ADD CONSTRAINT level3_02001b201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201903 level3_02001b201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903
    ADD CONSTRAINT level3_02001b201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201904 level3_02001b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904
    ADD CONSTRAINT level3_02001b201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201904 level3_02001b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904
    ADD CONSTRAINT level3_02001b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001b201904 level3_02001b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904
    ADD CONSTRAINT level3_02001b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_bitstamp_btcusd_s level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s
    ADD CONSTRAINT level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201901 level3_02001s201901_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901
    ADD CONSTRAINT level3_02001s201901_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201902 level3_02001s201902_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902
    ADD CONSTRAINT level3_02001s201902_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201902 level3_02001s201902_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902
    ADD CONSTRAINT level3_02001s201902_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201902 level3_02001s201902_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902
    ADD CONSTRAINT level3_02001s201902_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201903 level3_02001s201903_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903
    ADD CONSTRAINT level3_02001s201903_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201903 level3_02001s201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903
    ADD CONSTRAINT level3_02001s201903_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201903 level3_02001s201903_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903
    ADD CONSTRAINT level3_02001s201903_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201904 level3_02001s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904
    ADD CONSTRAINT level3_02001s201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201904 level3_02001s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904
    ADD CONSTRAINT level3_02001s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201904 level3_02001s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904
    ADD CONSTRAINT level3_02001s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


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
-- Name: level3_02002b201904 level3_02002b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904
    ADD CONSTRAINT level3_02002b201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02002b201904 level3_02002b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904
    ADD CONSTRAINT level3_02002b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02002b201904 level3_02002b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904
    ADD CONSTRAINT level3_02002b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_bitstamp_ltcusd_s level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s
    ADD CONSTRAINT level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02002s201904 level3_02002s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904
    ADD CONSTRAINT level3_02002s201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02002s201904 level3_02002s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904
    ADD CONSTRAINT level3_02002s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02002s201904 level3_02002s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904
    ADD CONSTRAINT level3_02002s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


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
-- Name: level3_02003b201904 level3_02003b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904
    ADD CONSTRAINT level3_02003b201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02003b201904 level3_02003b201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904
    ADD CONSTRAINT level3_02003b201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02003b201904 level3_02003b201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904
    ADD CONSTRAINT level3_02003b201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_bitstamp_ethusd_s level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s
    ADD CONSTRAINT level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02003s201904 level3_02003s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904
    ADD CONSTRAINT level3_02003s201904_pair_id_side_microtimestamp_order_id_ev_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_02003s201904 level3_02003s201904_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904
    ADD CONSTRAINT level3_02003s201904_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02003s201904 level3_02003s201904_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904
    ADD CONSTRAINT level3_02003s201904_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201901 level3_02b001201901_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02b001201901_pkey PRIMARY KEY (microtimestamp, order_id, event_no);

ALTER TABLE obanalytics.level3_02001b201901 CLUSTER ON level3_02b001201901_pkey;


--
-- Name: level3_02001b201901 level3_02b001201901_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02b001201901_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201901 level3_02s001201901_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901
    ADD CONSTRAINT level3_02s001201901_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


--
-- Name: level3_02001s201901 level3_02s001201901_unique_next; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901
    ADD CONSTRAINT level3_02s001201901_unique_next UNIQUE (next_microtimestamp, order_id, next_event_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_eras level3_eras_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_eras
    ADD CONSTRAINT level3_eras_pkey PRIMARY KEY (era, pair_id, exchange_id);


--
-- Name: matches_01001201902 matches_01001201902_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201902
    ADD CONSTRAINT matches_01001201902_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01001201903 matches_01001201903_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201903
    ADD CONSTRAINT matches_01001201903_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01001201904 matches_01001201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201904
    ADD CONSTRAINT matches_01001201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01002201902 matches_01002201902_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201902
    ADD CONSTRAINT matches_01002201902_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01002201903 matches_01002201903_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201903
    ADD CONSTRAINT matches_01002201903_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01002201904 matches_01002201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201904
    ADD CONSTRAINT matches_01002201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01003201902 matches_01003201902_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201902
    ADD CONSTRAINT matches_01003201902_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01003201903 matches_01003201903_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201903
    ADD CONSTRAINT matches_01003201903_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01003201904 matches_01003201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201904
    ADD CONSTRAINT matches_01003201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_01004201902 matches_01004201902_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01004201902
    ADD CONSTRAINT matches_01004201902_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02001201901 matches_02001201901_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201901
    ADD CONSTRAINT matches_02001201901_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02001201902 matches_02001201902_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201902
    ADD CONSTRAINT matches_02001201902_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02001201903 matches_02001201903_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201903
    ADD CONSTRAINT matches_02001201903_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02001201904 matches_02001201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201904
    ADD CONSTRAINT matches_02001201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02002201904 matches_02002201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02002201904
    ADD CONSTRAINT matches_02002201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: matches_02003201904 matches_02003201904_unique_order_ids_combination; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02003201904
    ADD CONSTRAINT matches_02003201904_unique_order_ids_combination UNIQUE (buy_order_id, sell_order_id);


--
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


--
-- Name: level3_02001b201901_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001b201901_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001b201902_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001b201902_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001b201903_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001b201903_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001b201904_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001s201901_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001s201901_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001s201902_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001s201902_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001s201903_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001s201903_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02001s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02001s201904_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02002b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02002b201904_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02002s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02002s201904_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02003b201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02003b201904_pair_id_side_microtimestamp_order_id_ev_key;


--
-- Name: level3_02003s201904_pair_id_side_microtimestamp_order_id_ev_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key ATTACH PARTITION obanalytics.level3_02003s201904_pair_id_side_microtimestamp_order_id_ev_key;


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
-- Name: level3_01001b201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001s201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003b201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003s201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002b201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002s201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001b201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001s201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002b201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002s201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003b201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003s201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001b201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001s201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01004b201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01004b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01004s201902 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01004s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001b201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001s201903 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01001s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01002s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01002s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01003s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_01003s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02001s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02001s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02002b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02002b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02002s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02002s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02003b201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02003b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_02003s201904 ba_incorporate_new_event; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER ba_incorporate_new_event BEFORE INSERT ON obanalytics.level3_02003s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_incorporate_new_event();


--
-- Name: level3_01001b201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01001s201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003b201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003s201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002b201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002s201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01001b201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01001s201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002b201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002s201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003b201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003s201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001b201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001s201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01001201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01001201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01001201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01001201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01002201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01002201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01002201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01002201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01003201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01003201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01003201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01003201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01004b201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01004b201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01004s201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01004s201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01004201902 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01004201902 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001b201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001b201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001s201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001s201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_02001201903 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_02001201903 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01001b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01001s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01001s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01001201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01001201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01002s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01002s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01002201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01002201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_01003s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_01003s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_01003201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_01003201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02001s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02001s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_02001201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_02001201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02002b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02002b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02002s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02002s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_02002201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_02002201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02003b201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02003b201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: level3_02003s201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.level3_02003s201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


--
-- Name: matches_02003201904 bz_save_exchange_microtimestamp; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER bz_save_exchange_microtimestamp BEFORE UPDATE OF microtimestamp ON obanalytics.matches_02003201904 FOR EACH ROW EXECUTE PROCEDURE obanalytics.save_exchange_microtimestamp();


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
-- Name: level3_01001b201903 level3_01001b201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903
    ADD CONSTRAINT level3_01001b201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201903 level3_01001b201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201903
    ADD CONSTRAINT level3_01001b201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201904 level3_01001b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904
    ADD CONSTRAINT level3_01001b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201904 level3_01001b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201904
    ADD CONSTRAINT level3_01001b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201903 level3_01001s201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903
    ADD CONSTRAINT level3_01001s201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201903 level3_01001s201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201903
    ADD CONSTRAINT level3_01001s201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201904 level3_01001s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904
    ADD CONSTRAINT level3_01001s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201904 level3_01001s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201904
    ADD CONSTRAINT level3_01001s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201903 level3_01002b201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903
    ADD CONSTRAINT level3_01002b201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201903 level3_01002b201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201903
    ADD CONSTRAINT level3_01002b201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201904 level3_01002b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904
    ADD CONSTRAINT level3_01002b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201904 level3_01002b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201904
    ADD CONSTRAINT level3_01002b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201903 level3_01002s201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903
    ADD CONSTRAINT level3_01002s201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201903 level3_01002s201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201903
    ADD CONSTRAINT level3_01002s201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201904 level3_01002s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904
    ADD CONSTRAINT level3_01002s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201904 level3_01002s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201904
    ADD CONSTRAINT level3_01002s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201903 level3_01003b201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903
    ADD CONSTRAINT level3_01003b201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201903 level3_01003b201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201903
    ADD CONSTRAINT level3_01003b201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201904 level3_01003b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904
    ADD CONSTRAINT level3_01003b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201904 level3_01003b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201904
    ADD CONSTRAINT level3_01003b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201903 level3_01003s201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903
    ADD CONSTRAINT level3_01003s201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201903 level3_01003s201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201903
    ADD CONSTRAINT level3_01003s201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201904 level3_01003s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904
    ADD CONSTRAINT level3_01003s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201904 level3_01003s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201904
    ADD CONSTRAINT level3_01003s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004b201902 level3_01004b201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902
    ADD CONSTRAINT level3_01004b201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01004b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004b201902 level3_01004b201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004b201902
    ADD CONSTRAINT level3_01004b201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01004b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004s201902 level3_01004s201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902
    ADD CONSTRAINT level3_01004s201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01004s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01004s201902 level3_01004s201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01004s201902
    ADD CONSTRAINT level3_01004s201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01004s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201902 level3_01b001201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902
    ADD CONSTRAINT level3_01b001201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001b201902 level3_01b001201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001b201902
    ADD CONSTRAINT level3_01b001201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201902 level3_01b002201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902
    ADD CONSTRAINT level3_01b002201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002b201902 level3_01b002201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002b201902
    ADD CONSTRAINT level3_01b002201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201902 level3_01b003201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902
    ADD CONSTRAINT level3_01b003201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003b201902 level3_01b003201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003b201902
    ADD CONSTRAINT level3_01b003201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201902 level3_01s001201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902
    ADD CONSTRAINT level3_01s001201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01001s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01001s201902 level3_01s001201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01001s201902
    ADD CONSTRAINT level3_01s001201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01001s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201902 level3_01s002201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902
    ADD CONSTRAINT level3_01s002201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01002s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01002s201902 level3_01s002201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01002s201902
    ADD CONSTRAINT level3_01s002201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01002s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201902 level3_01s003201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902
    ADD CONSTRAINT level3_01s003201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_01003s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_01003s201902 level3_01s003201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_01003s201902
    ADD CONSTRAINT level3_01s003201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_01003s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201902 level3_02001b201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902
    ADD CONSTRAINT level3_02001b201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201902 level3_02001b201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201902
    ADD CONSTRAINT level3_02001b201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001b201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201903 level3_02001b201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903
    ADD CONSTRAINT level3_02001b201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201903 level3_02001b201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201903
    ADD CONSTRAINT level3_02001b201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001b201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201904 level3_02001b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904
    ADD CONSTRAINT level3_02001b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201904 level3_02001b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201904
    ADD CONSTRAINT level3_02001b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201902 level3_02001s201902_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902
    ADD CONSTRAINT level3_02001s201902_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201902 level3_02001s201902_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201902
    ADD CONSTRAINT level3_02001s201902_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001s201902(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201903 level3_02001s201903_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903
    ADD CONSTRAINT level3_02001s201903_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201903 level3_02001s201903_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201903
    ADD CONSTRAINT level3_02001s201903_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001s201903(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201904 level3_02001s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904
    ADD CONSTRAINT level3_02001s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201904 level3_02001s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201904
    ADD CONSTRAINT level3_02001s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02001s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02002b201904 level3_02002b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904
    ADD CONSTRAINT level3_02002b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02002b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02002b201904 level3_02002b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002b201904
    ADD CONSTRAINT level3_02002b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02002b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02002s201904 level3_02002s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904
    ADD CONSTRAINT level3_02002s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02002s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02002s201904 level3_02002s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02002s201904
    ADD CONSTRAINT level3_02002s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02002s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02003b201904 level3_02003b201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904
    ADD CONSTRAINT level3_02003b201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02003b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02003b201904 level3_02003b201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003b201904
    ADD CONSTRAINT level3_02003b201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02003b201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02003s201904 level3_02003s201904_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904
    ADD CONSTRAINT level3_02003s201904_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02003s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02003s201904 level3_02003s201904_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02003s201904
    ADD CONSTRAINT level3_02003s201904_fkey_level3_price FOREIGN KEY (price_microtimestamp, order_id, price_event_no) REFERENCES obanalytics.level3_02003s201904(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201901 level3_02b001201901_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02b001201901_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001b201901(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001b201901 level3_02b001201901_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02b001201901_fkey_level3_price FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001b201901(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201901 level3_02s001201901_fkey_level3_next; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901
    ADD CONSTRAINT level3_02s001201901_fkey_level3_next FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001s201901(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3_02001s201901 level3_02s001201901_fkey_level3_price; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901
    ADD CONSTRAINT level3_02s001201901_fkey_level3_price FOREIGN KEY (next_microtimestamp, order_id, next_event_no) REFERENCES obanalytics.level3_02001s201901(microtimestamp, order_id, event_no) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


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
-- Name: matches_01001201902 matches_01001201902_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201902
    ADD CONSTRAINT matches_01001201902_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01001b201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01001201902 matches_01001201902_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201902
    ADD CONSTRAINT matches_01001201902_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01001s201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01001201903 matches_01001201903_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201903
    ADD CONSTRAINT matches_01001201903_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01001b201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01001201903 matches_01001201903_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201903
    ADD CONSTRAINT matches_01001201903_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01001s201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01001201904 matches_01001201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201904
    ADD CONSTRAINT matches_01001201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01001b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01001201904 matches_01001201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01001201904
    ADD CONSTRAINT matches_01001201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01001s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201902 matches_01002201902_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201902
    ADD CONSTRAINT matches_01002201902_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01002b201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201902 matches_01002201902_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201902
    ADD CONSTRAINT matches_01002201902_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01002s201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201903 matches_01002201903_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201903
    ADD CONSTRAINT matches_01002201903_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01002b201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201903 matches_01002201903_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201903
    ADD CONSTRAINT matches_01002201903_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01002s201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201904 matches_01002201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201904
    ADD CONSTRAINT matches_01002201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01002b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01002201904 matches_01002201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01002201904
    ADD CONSTRAINT matches_01002201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01002s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201902 matches_01003201902_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201902
    ADD CONSTRAINT matches_01003201902_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01003b201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201902 matches_01003201902_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201902
    ADD CONSTRAINT matches_01003201902_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01003s201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201903 matches_01003201903_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201903
    ADD CONSTRAINT matches_01003201903_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01003b201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201903 matches_01003201903_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201903
    ADD CONSTRAINT matches_01003201903_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01003s201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201904 matches_01003201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201904
    ADD CONSTRAINT matches_01003201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01003b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01003201904 matches_01003201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01003201904
    ADD CONSTRAINT matches_01003201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01003s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01004201902 matches_01004201902_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01004201902
    ADD CONSTRAINT matches_01004201902_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_01004b201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_01004201902 matches_01004201902_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_01004201902
    ADD CONSTRAINT matches_01004201902_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_01004s201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201901 matches_02001201901_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201901
    ADD CONSTRAINT matches_02001201901_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02001b201901(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201901 matches_02001201901_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201901
    ADD CONSTRAINT matches_02001201901_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02001s201901(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201902 matches_02001201902_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201902
    ADD CONSTRAINT matches_02001201902_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02001b201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201902 matches_02001201902_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201902
    ADD CONSTRAINT matches_02001201902_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02001s201902(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201903 matches_02001201903_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201903
    ADD CONSTRAINT matches_02001201903_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02001b201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201903 matches_02001201903_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201903
    ADD CONSTRAINT matches_02001201903_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02001s201903(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201904 matches_02001201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201904
    ADD CONSTRAINT matches_02001201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02001b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02001201904 matches_02001201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02001201904
    ADD CONSTRAINT matches_02001201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02001s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02002201904 matches_02002201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02002201904
    ADD CONSTRAINT matches_02002201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02002b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02002201904 matches_02002201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02002201904
    ADD CONSTRAINT matches_02002201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02002s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02003201904 matches_02003201904_fkey_level3_buys; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02003201904
    ADD CONSTRAINT matches_02003201904_fkey_level3_buys FOREIGN KEY (buy_event_no, microtimestamp, buy_order_id) REFERENCES obanalytics.level3_02003b201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches_02003201904 matches_02003201904_fkey_level3_sells; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.matches_02003201904
    ADD CONSTRAINT matches_02003201904_fkey_level3_sells FOREIGN KEY (sell_event_no, microtimestamp, sell_order_id) REFERENCES obanalytics.level3_02003s201904(event_no, microtimestamp, order_id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: SCHEMA obanalytics; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA obanalytics TO obauser;


--
-- Name: FUNCTION oba_available_exchanges(p_start_time timestamp with time zone, p_end_time timestamp with time zone); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_available_exchanges(p_start_time timestamp with time zone, p_end_time timestamp with time zone) TO obauser;


--
-- Name: FUNCTION oba_available_pairs(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_available_pairs(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_exchange_id integer) TO obauser;


--
-- Name: FUNCTION oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_starting_depth boolean, p_depth_changes boolean); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_starting_depth boolean, p_depth_changes boolean) TO obauser;


--
-- Name: FUNCTION oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) TO obauser;


--
-- Name: FUNCTION oba_exchange_id(p_exchange text); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_exchange_id(p_exchange text) TO obauser;


--
-- Name: FUNCTION oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) TO obauser;


--
-- Name: FUNCTION oba_order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer, p_bps_range numeric, p_min_bid numeric, p_max_ask numeric); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer, p_bps_range numeric, p_min_bid numeric, p_max_ask numeric) TO obauser;


--
-- Name: FUNCTION oba_pair_id(p_pair text); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_pair_id(p_pair text) TO obauser;


--
-- Name: FUNCTION oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean) TO obauser;


--
-- Name: FUNCTION oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) TO obauser;


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

