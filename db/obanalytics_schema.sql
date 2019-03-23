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
	side character(1)
);


ALTER TYPE obanalytics.level2_depth_record OWNER TO "ob-analytics";

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
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
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

	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp) ';  
	
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
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
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
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
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
-- Name: _depth_after_depth_change(obanalytics.level2_depth_record[], obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, character); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE plpgsql
    AS $_$
declare 
	v_precision integer;
begin 
	execute format('select %I 	from obanalytics.pairs	where pair_id = $1', upper(p_precision))
	into strict v_precision using p_pair_id;
	
	if p_depth is null then
		p_depth := array(	select row(round(price, v_precision), 
											sum(amount),
									   		side
										 )::obanalytics.level2_depth_record
								 from obanalytics.order_book( p_microtimestamp, p_pair_id, p_exchange_id,
															p_only_makers := true,p_before := true) join unnest(ob) on true
								 group by ts, round(price, v_precision), side
					  );
	end if;
	return array(  select row(price, volume, side)::obanalytics.level2_depth_record
					from (
						select coalesce(d.price, c.price) as price, coalesce(c.volume, d.volume) as volume, coalesce(d.side, c.side) as side
						from unnest(p_depth) d full join unnest(p_depth_change) c using (price, side)
					) a
					where volume <> 0
				);
end;
$_$;


ALTER FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character) OWNER TO "ob-analytics";

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
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
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
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
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
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
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
-- Name: _oba_events_with_id(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._oba_events_with_id(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(event_id bigint, microtimestamp timestamp with time zone, order_id bigint, event_no integer, is_deleted boolean, side character, price numeric, amount numeric, fill numeric, pair_id smallint, exchange_id smallint, price_microtimestamp timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$

with active_events as (
	select microtimestamp, order_id, event_no, next_microtimestamp = '-infinity' as is_deleted, side, price, amount, fill, pair_id, exchange_id, price_microtimestamp
	from obanalytics.level3 
	where microtimestamp between p_start_time and p_end_time
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	union -- not all since we want to eliminate duplicated events from the first level3 episode and obanalytics.order_book()
	select microtimestamp, order_id, event_no, false as is_deleted, side, price, amount, fill, pair_id, exchange_id, price_microtimestamp
	from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := false) join unnest(ob) on true
)
select row_number() over (order by order_id, amount desc, event_no, microtimestamp ) as event_id,
		microtimestamp, order_id, event_no, is_deleted, side,price, amount, fill, pair_id, exchange_id, 
		price_microtimestamp
from active_events
where not (amount = 0 and event_no = 1 and not is_deleted)	

$$;


ALTER FUNCTION obanalytics._oba_events_with_id(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

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
							as is_maker
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
	perform obanalytics._create_level2_partition(p_exchange, p_pair, 'p0', p_year, p_month);
	perform obanalytics._create_level3_partition(p_exchange, 'b', p_pair, p_year, p_month);
	perform obanalytics._create_level3_partition(p_exchange, 's', p_pair, p_year, p_month);
	perform obanalytics._create_matches_partition(p_exchange, p_pair, p_year, p_month);
end;
$$;


ALTER FUNCTION obanalytics.create_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) OWNER TO "ob-analytics";

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
	
	for v_ob in select ts, ob from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id) 
	loop
		if v_ob_before is not null then 
			return query 
				select v_ob.ts, p_pair_id::smallint, p_exchange_id::smallint, 'r0'::character(2), array_agg(d.d)
				from (
					select row(price, coalesce(af.amount, 0), side)::obanalytics.level2_depth_record as d
					from (
						select a.price, sum(a.amount) as amount,a.side
						from unnest(v_ob_before.ob) a 
						where a.is_maker 
						group by a.price, a.side, a.pair_id
					) bf full join (
						select a.price, sum(a.amount) as amount, a.side
						from unnest(v_ob.ob) a 
						where a.is_maker 
						group by a.price, a.side, a.pair_id
					) af using (price, side)
					where bf.amount is distinct from af.amount
				) d;
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
-- Name: oba_depth(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

	with time_range as (
		select p_pair_id as pair_id, p_exchange_id as exchange_id, min(microtimestamp) as start_time
		from obanalytics.level2
		where microtimestamp >= p_start_time
		  and exchange_id = p_exchange_id
		  and pair_id = p_pair_id
	)
	select ts, price, amount, side
	from time_range 
		join lateral (
				select ts,
						pair_id,
						exchange_id,
						price, 
						sum(amount) as amount,
						case side 
							when 'b' then 'bid'::text
							when 's' then 'ask'::text
						end as side
				from obanalytics.order_book(start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := true) join unnest(ob) on true
				where is_maker 
				group by ts, price, side, pair_id, exchange_id
		) a using (pair_id, exchange_id)
	union all 
	select microtimestamp, price, volume, side::text
	from obanalytics.level2 join time_range using (pair_id, exchange_id) join unnest(level2.depth_change) d on true
	where microtimestamp between start_time and p_end_time 
	  and level2.pair_id = p_pair_id
	  and level2.exchange_id = p_exchange_id 
	  and microtimestamp >= p_start_time -- otherwise, the query optimizer produces a crazy plan!
	  and price is not null;   -- null might happen if an aggressor order_created event is not part of an episode, i.e. dirty data.
	  							-- But plotPriceLevels will fail if price is null, so we need to exclude such rows.
								-- 'not null' constraint is to be added to price and depth_change columns of obanalytics.depth table. Then this check
								-- will be redundant

$$;


ALTER FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: oba_depth_summary(timestamp with time zone, timestamp with time zone, integer, integer, character, numeric); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character, p_bps_step numeric DEFAULT 25) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

with
depth as (
	select microtimestamp as ts, pair_id, (unnest(d)).*
	from (
		select microtimestamp, pair_id, obanalytics.restore_depth_agg(depth_change, microtimestamp, pair_id, exchange_id, p_precision ) over (order by microtimestamp) as d
		from obanalytics.level2
		where microtimestamp between p_start_time and p_end_time 
		  and exchange_id = p_exchange_id
		  and pair_id = p_pair_id
		  and precision = p_precision
		) a 
),
depth_with_best_prices as (
	select min(price) filter(where side = 's') over (partition by ts) as best_ask_price, 
			max(price) filter(where side = 'b') over (partition by ts) as best_bid_price, 
			ts, price, volume as amount, side, pair_id
	from depth
),
depth_with_bps_levels as (
	select ts, 
			amount, 
			price,
			side,
			case side
				when 's' then ceiling((price-best_ask_price)/best_ask_price/p_bps_step*10000)::bigint
				when 'b' then ceiling((best_bid_price - price)/best_bid_price/p_bps_step*10000)::bigint
			end as bps_level,
			best_ask_price,
			best_bid_price,
			pair_id
	from depth_with_best_prices
),
depth_with_price_adjusted as (
	select ts,
			amount,
			case side
				when 's' then round(best_ask_price*(1 + bps_level*p_bps_step/10000), case p_precision 
																						when 'r0' then pairs."R0" 
																						when 'p0' then pairs."P0" 
																						when 'p1' then pairs."P1"
																						when 'p2' then pairs."P2"
																						when 'p3' then pairs."P3"
																						end )
				when 'b' then round(best_bid_price*(1 - bps_level*p_bps_step/10000),  case p_precision 
																						when 'r0' then pairs."R0" 
																						when 'p0' then pairs."P0" 
																						when 'p1' then pairs."P1"
																						when 'p2' then pairs."P2"
																						when 'p3' then pairs."P3"
																						end ) 
			end as price,
			side,
			bps_level,
			rank() over (partition by obanalytics._in_milliseconds(ts) order by ts desc) as r
	from depth_with_bps_levels join obanalytics.pairs using (pair_id)
)
select ts, 
		price, 
		sum(amount) as volume, 
		case side when 's' then 'ask'::text when 'b' then 'bid'::text end, 
		bps_level*p_bps_step::bigint
from depth_with_price_adjusted
where r = 1	-- if rounded to milliseconds ts are not unique, we'll take the LasT one and will drop the first silently
			 -- this is a workaround for the inability of R to handle microseconds in POSIXct 
group by 1, 2, 4, 5

$$;


ALTER FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character, p_bps_step numeric) OWNER TO "ob-analytics";

--
-- Name: oba_events(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("event.id" bigint, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, action text, direction text, fill numeric, "matching.event" bigint, type text, "aggressiveness.bps" numeric, event_no integer, is_aggressor boolean, is_created boolean, is_ever_resting boolean, is_ever_aggressor boolean, is_ever_filled boolean, is_deleted boolean, is_price_ever_changed boolean, best_bid_price numeric, best_ask_price numeric)
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
		  union	-- not all, unique
		  select distinct sell_order_id as order_id
		  from trades
		  where side = 's'				
		),
	  makers as (
		  select distinct buy_order_id as order_id
		  from trades
		  where side = 's'
		  union -- not all, unique
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
	  base_events as (
		  select event_id,
		  		  microtimestamp,
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
		  from obanalytics._oba_events_with_id(p_start_time, p_end_time, p_pair_id, p_exchange_id) left join spread_before using(microtimestamp) 
	  ),
	  events as (
		select base_events.*,
		  		max(price) over o_all <> min(price) over o_all as is_price_ever_changed,
				bool_or(not is_aggressor) over o_all as is_ever_resting,
		  		bool_or(is_aggressor) over o_all as is_ever_aggressor, 	
		  		-- bool_or(coalesce(fill, case when not is_deleted_event then 1.0 else null end ) > 0.0 ) over o_all as is_ever_filled, 	-- BITSTAMP-specific version
		  		bool_or(coalesce(fill,0.0) > 0.0 ) over o_all as is_ever_filled,	-- we should classify an order event as fill only when we know fill amount. TODO: check how it will work with Bitstamp 
		  		first_value(is_deleted_event) over o_after as is_deleted,
		  		first_value(event_no) over o_before = 1 and not first_value(is_deleted_event) over o_before as is_created
		from base_events left join makers using (order_id) left join takers using (order_id) 
  		
		window o_all as (partition by order_id), 
		  		o_after as (partition by order_id order by microtimestamp desc, event_no desc),
		  		o_before as (partition by order_id order by microtimestamp, event_no)
	  ),
	  event_connection as (
		  select trades.microtimestamp, 
		   	      buy_event_no as event_no,
		  		  buy_order_id as order_id, 
		  		  events.event_id
		  from trades join events on trades.microtimestamp = events.microtimestamp and sell_order_id = order_id and sell_event_no = event_no
		  union all
		  select trades.microtimestamp, 
		  		  sell_event_no as event_no,
		  		  sell_order_id as order_id, 
		  		  events.event_id
		  from trades join events on trades.microtimestamp = events.microtimestamp and buy_order_id = order_id and buy_event_no = event_no
	  )
  select events.event_id as "event.id",
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
from obanalytics._oba_events_with_id(p_start_time, p_end_time, p_pair_id, p_exchange_id)
  
$$;


ALTER FUNCTION obanalytics.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

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
		  and microtimestamp < p_start_time
		order by microtimestamp desc
		limit 1
	) a
	union all
	select *
	from (
		select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, p_end_time 
		from obanalytics.level1 
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and microtimestamp <= p_end_time
		order by microtimestamp desc
		limit 1
	) a
	
$$;


ALTER FUNCTION obanalytics.oba_spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean) OWNER TO "ob-analytics";

--
-- Name: oba_trades(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, direction text, "maker.event.id" bigint, "taker.event.id" bigint, maker bigint, taker bigint, "real.trade.id" bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

 with trades as (
		select * 
		from obanalytics.matches 
		where microtimestamp between p_start_time and p_end_time
	      and pair_id = p_pair_id
	 	  and exchange_id = p_exchange_id
	),
 events as (
	 select *
	 from obanalytics._oba_events_with_id(p_start_time, p_end_time, p_pair_id, p_exchange_id) 
 )
  select trades.microtimestamp,
  		  trades.price,
		  trades.amount,
		  case trades.side when 'b' then 'buy'::text when 's' then 'sell'::text end,
		  case trades.side
		  	when 'b' then s.event_id
			when 's' then b.event_id
		  end,
		  case trades.side
		  	when 'b' then b.event_id
			when 's' then s.event_id
		  end,
		  case trades.side
		  	when 'b' then sell_order_id
			when 's' then buy_order_id
		  end,
		  case trades.side
		  	when 'b' then buy_order_id
			when 's' then sell_order_id
		  end,
		  trades.exchange_trade_id 
  from trades left join events b on trades.microtimestamp = b.microtimestamp and buy_order_id = b.order_id and buy_event_no = b.event_no
  		left join events s on trades.microtimestamp = s.microtimestamp and sell_order_id = s.order_id  and sell_event_no = s.event_no
  order by 1

$$;


ALTER FUNCTION obanalytics.oba_trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: order_book(timestamp with time zone, integer, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean DEFAULT false) RETURNS TABLE(ts timestamp with time zone, ob obanalytics.level3[])
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
					as is_maker
			from obanalytics.level3 
			where microtimestamp >= ( select max(era) as s
				 					   from obanalytics.level3_eras 
				 					   where era <= p_ts 
				    					 and pair_id = p_pair_id 
				   						 and exchange_id = p_exchange_id ) 
			  and case when p_before then  microtimestamp < p_ts and next_microtimestamp >= p_ts 
						when not p_before then microtimestamp <= p_ts and next_microtimestamp > p_ts 
		  	      end
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


ALTER FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean) OWNER TO "ob-analytics";

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
-- Name: pga_depth(text, text, interval, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.pga_depth(p_exchange text, p_pair text, p_max_interval interval DEFAULT '04:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_last_depth timestamptz;
	
	v_pair_id obanalytics.pairs.pair_id%type;
	v_exchange_id obanalytics.exchanges.exchange_id%type;
	v_precision constant character(2) default 'r0';

	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs 
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges 
	where exchange = lower(p_exchange);
	
	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from obanalytics.level3_eras 
		where pair_id = v_pair_id
		  and exchange_id = v_exchange_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from obanalytics.level3_eras
										 where pair_id = v_pair_id 
									       and exchange_id = v_exchange_id
									 ) ) between era_starts and era_ends;
									 
	select coalesce(max(microtimestamp), v_start) into v_last_depth
	from obanalytics.level2 
	where microtimestamp between v_start and v_end
	  and pair_id = v_pair_id
	  and precision = v_precision
	  and exchange_id = v_exchange_id;
	
	-- delete the latest depth because it could be calculated using incomplete data
	
	delete from obanalytics.level2
	where microtimestamp = v_last_depth
	  and pair_id = v_pair_id
	  and precision = v_precision
	  and exchange_id = v_exchange_id;
	  
	if v_end > v_last_depth + p_max_interval then
		v_end := v_last_depth + p_max_interval;
	end if;
	
	raise debug 'pga_depth(): from: %  till: %', v_last_depth, v_end;
	  
	insert into obanalytics.level2 (microtimestamp, pair_id, exchange_id, precision, depth_change)
	select microtimestamp, pair_id, exchange_id, precision, coalesce(depth_change, '{}')
	from obanalytics.depth_change_by_episode(v_last_depth, v_end, v_pair_id, v_exchange_id);
	
	raise debug 'pga_depth() exec time: %', clock_timestamp() - v_current_timestamp;
	
	return;
end;

$$;


ALTER FUNCTION obanalytics.pga_depth(p_exchange text, p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: pga_spread(text, text, interval, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.pga_spread(p_exchange text, p_pair text, p_max_interval interval DEFAULT '04:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE(o_start timestamp with time zone, o_end timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
declare 
	v_current_timestamp timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_last_spread timestamptz;
	
	v_pair_id obanalytics.pairs.pair_id%type;
	v_exchange_id obanalytics.exchanges.exchange_id%type;
	
begin 
	v_current_timestamp := clock_timestamp();
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs 
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges 
	where exchange = lower(p_exchange);

	select era_starts, era_ends into v_start, v_end
	from (
		select era as era_starts,
				coalesce(lead(era) over (order by era), 'infinity'::timestamptz) - '00:00:00.000001'::interval as era_ends
		from obanalytics.level3_eras 
		where pair_id = v_pair_id
		  and exchange_id = v_exchange_id
	) a
	where coalesce(p_ts_within_era,  ( select max(era) 
										 from obanalytics.level3_eras 
										 where pair_id = v_pair_id
									       and exchange_id = v_exchange_id
									 ) ) between era_starts and era_ends;

	select coalesce(max(microtimestamp), v_start) into v_last_spread
	from obanalytics.level1 
	where microtimestamp between v_start and v_end
	  and exchange_id = v_exchange_id
	  and pair_id = v_pair_id;
	  
	if v_end > v_last_spread + p_max_interval then
		v_end := v_last_spread + p_max_interval;
	end if;	  
	
	-- delete the latest spread because it could be calculated using incomplete data
	
	delete from obanalytics.level1
	where microtimestamp = v_last_spread
	  and exchange_id = v_exchange_id
	  and pair_id = v_pair_id;
	  
	insert into obanalytics.level1 (best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id)
    select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id
	from obanalytics.spread_by_episode(v_last_spread, v_end, v_pair_id, v_exchange_id, p_with_order_book := false);
	
	raise debug 'pga_spread() exec time: %', clock_timestamp() - v_current_timestamp;
	o_start := v_last_spread;
	o_end := v_end;
	return next;
	return;
end;

$$;


ALTER FUNCTION obanalytics.pga_spread(p_exchange text, p_pair text, p_max_interval interval, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

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
-- Name: order_book_agg(obanalytics.level3[], boolean); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) (
    SFUNC = obanalytics._order_book_after_episode,
    STYPE = obanalytics.level3[]
);


ALTER AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) OWNER TO "ob-analytics";

--
-- Name: restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, character); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, character) (
    SFUNC = obanalytics._depth_after_depth_change,
    STYPE = obanalytics.level2_depth_record[]
);


ALTER AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, character) OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level1_01001201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level1_01002201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level1_01003201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level1_02001201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level2_01001r0201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level2_01002r0201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level2_01003r0201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level2_02001p0201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01001b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001b201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01001b201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01001s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001s201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01001s201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01002b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002b201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01002b201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01002s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002s201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01002s201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01003b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003b201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01003b201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_01003s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003s201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01003s201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_02001b201901 OWNER TO "ob-analytics";

--
-- Name: level3_02001b201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201902 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02001b201902 OWNER TO "ob-analytics";

--
-- Name: level3_02001b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001b201903 PARTITION OF obanalytics.level3_bitstamp_btcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02001b201903 OWNER TO "ob-analytics";

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


ALTER TABLE obanalytics.level3_02001s201901 OWNER TO "ob-analytics";

--
-- Name: level3_02001s201902; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201902 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-02-01 00:00:00+03') TO ('2019-03-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02001s201902 OWNER TO "ob-analytics";

--
-- Name: level3_02001s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_02001s201903 PARTITION OF obanalytics.level3_bitstamp_btcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_02001s201903 OWNER TO "ob-analytics";

--
-- Name: level3_eras; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_eras (
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL
);


ALTER TABLE obanalytics.level3_eras OWNER TO "ob-analytics";

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
-- Name: level1_01002201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903 ALTER COLUMN pair_id SET DEFAULT 2;


--
-- Name: level1_01002201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_01003201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903 ALTER COLUMN pair_id SET DEFAULT 3;


--
-- Name: level1_01003201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903 ALTER COLUMN exchange_id SET DEFAULT 1;


--
-- Name: level1_02001201903 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903 ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_02001201903 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903 ALTER COLUMN exchange_id SET DEFAULT 2;


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
-- Name: level1_bitstamp_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level1_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


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
-- Name: level3_bitstamp_btcusd pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitstamp_btcusd exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_btcusd_b side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN side SET DEFAULT 'b'::bpchar;


--
-- Name: level3_bitstamp_btcusd_b pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitstamp_btcusd_b exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN exchange_id SET DEFAULT 2;


--
-- Name: level3_bitstamp_btcusd_s side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN side SET DEFAULT 's'::bpchar;


--
-- Name: level3_bitstamp_btcusd_s pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN pair_id SET DEFAULT 1;


--
-- Name: level3_bitstamp_btcusd_s exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN exchange_id SET DEFAULT 2;


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
-- Name: level1_01002201903 level1_01002201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01002201903
    ADD CONSTRAINT level1_01002201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_01003201903 level1_01003201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_01003201903
    ADD CONSTRAINT level1_01003201903_pkey PRIMARY KEY (microtimestamp);


--
-- Name: level1_02001201903 level1_02001201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level1_02001201903
    ADD CONSTRAINT level1_02001201903_pkey PRIMARY KEY (microtimestamp);


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
-- Name: level2_02001p0201903 level2_02001p0201903_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level2_02001p0201903
    ADD CONSTRAINT level2_02001p0201903_pkey PRIMARY KEY (microtimestamp);


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
-- Name: level3_02001b201901 level3_02b001201901_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901
    ADD CONSTRAINT level3_02b001201901_pkey PRIMARY KEY (microtimestamp, order_id, event_no);


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
-- Name: SCHEMA obanalytics; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA obanalytics TO obauser;


--
-- Name: FUNCTION oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) TO obauser;


--
-- Name: FUNCTION oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character, p_bps_step numeric); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_precision character, p_bps_step numeric) TO obauser;


--
-- Name: FUNCTION oba_exchange_id(p_exchange text); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_exchange_id(p_exchange text) TO obauser;


--
-- Name: FUNCTION oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT ALL ON FUNCTION obanalytics.oba_export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) TO obauser;


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

