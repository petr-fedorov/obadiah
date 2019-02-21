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
-- Name: level3_order_book_record; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level3_order_book_record AS (
	ts timestamp with time zone,
	price numeric,
	amount numeric,
	side character(1),
	is_maker boolean,
	microtimestamp timestamp with time zone,
	order_id bigint,
	event_no integer,
	price_microtimestamp timestamp with time zone,
	pair_id smallint,
	exchange_id smallint
);


ALTER TYPE obanalytics.level3_order_book_record OWNER TO "ob-analytics";

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
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
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
	v_statements[i] := v_statement || '_unique_trade_id unique (microtimestamp, order_id, event_no, trade_id)';
	
	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_enabled = TRUE,  autovacuum_vacuum_scale_factor= 0.0 , '||
		'autovacuum_analyze_scale_factor = 0.0 ,  autovacuum_analyze_threshold = 10000, autovacuum_vacuum_threshold = 10000)';
	
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
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_enabled = TRUE,  autovacuum_vacuum_scale_factor= 0.0 , '||
		'autovacuum_analyze_scale_factor = 0.0 ,  autovacuum_analyze_threshold = 10000, autovacuum_vacuum_threshold = 10000)';
	

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
-- Name: create_partitions(text, text, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.create_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin 
	perform obanalytics._create_level3_partition(p_exchange, 'b', p_pair, p_year, p_month);
	perform obanalytics._create_level3_partition(p_exchange, 's', p_pair, p_year, p_month);
	perform obanalytics._create_matches_partition(p_exchange, p_pair, p_year, p_month);
end;
$$;


ALTER FUNCTION obanalytics.create_partitions(p_exchange text, p_pair text, p_year integer, p_month integer) OWNER TO "ob-analytics";

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
-- Name: level3_order_book(timestamp with time zone, smallint, smallint, boolean, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_order_book(p_ts timestamp with time zone, p_pair_id smallint, p_exchange_id smallint, p_only_makers boolean, p_before boolean) RETURNS SETOF obanalytics.level3_order_book_record
    LANGUAGE sql STABLE
    AS $$

	with episode as (
			select microtimestamp as e, pair_id, (select max(era) from obanalytics.level3_eras where era <= p_ts and pair_id = p_pair_id ) as s, exchange_id
			from obanalytics.level3
			where microtimestamp >= (select max(era) from obanalytics.level3_eras where era <= p_ts and pair_id = p_pair_id )
			  and ( microtimestamp < p_ts or ( microtimestamp = p_ts and not p_before ) )
		      and pair_id = p_pair_id
			  and exchange_id = p_exchange_id
			order by microtimestamp desc
			limit 1
		), 
		orders as (
			select *, 
					coalesce(
						case side 
							when 'b' then price < min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
							when 's' then price > max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
						end,
					true )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are makers
					as is_maker
			from obanalytics.level3 join episode using (exchange_id, pair_id)
			where microtimestamp between episode.s and episode.e
			  and pair_id = p_pair_id				-- redundant, but will help query optimizer with partition elimination
			  and exchange_id = p_exchange_id		-- redundant, but will help query optimizer with partition elimination
			  and next_microtimestamp > episode.e
		)
	select e,
			price,
			amount,
			side,
			is_maker,
			microtimestamp,
			order_id,
			event_no,
			price_microtimestamp, 	
			pair_id,
			exchange_id
    from orders
	where is_maker OR NOT p_only_makers
	order by microtimestamp, order_id, event_no;	-- order by must be the same as in spread_after_episode. Change both!

$$;


ALTER FUNCTION obanalytics.level3_order_book(p_ts timestamp with time zone, p_pair_id smallint, p_exchange_id smallint, p_only_makers boolean, p_before boolean) OWNER TO "ob-analytics";

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
-- Name: exchanges; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.exchanges (
    exchange_id smallint NOT NULL,
    exchange text NOT NULL
);


ALTER TABLE obanalytics.exchanges OWNER TO "ob-analytics";

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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01001b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001b201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01001s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01001s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01001s201903 PARTITION OF obanalytics.level3_bitfinex_btcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01002b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002b201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01002s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01002s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01002s201903 PARTITION OF obanalytics.level3_bitfinex_ltcusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01003b201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003b201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003b201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_b
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01003s201902 OWNER TO "ob-analytics";

--
-- Name: level3_01003s201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_01003s201903 PARTITION OF obanalytics.level3_bitfinex_ethusd_s
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.level3_01003s201903 OWNER TO "ob-analytics";

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
-- Name: level3_eras; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_eras (
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL
);


ALTER TABLE obanalytics.level3_eras OWNER TO "ob-analytics";

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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


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
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01003201902 OWNER TO "ob-analytics";

--
-- Name: matches_01003201903; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_01003201903 PARTITION OF obanalytics.matches_bitfinex_ethusd
FOR VALUES FROM ('2019-03-01 00:00:00+03') TO ('2019-04-01 00:00:00+03')
WITH (autovacuum_enabled='true', autovacuum_vacuum_scale_factor='0.0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='10000', autovacuum_vacuum_threshold='10000');


ALTER TABLE obanalytics.matches_01003201903 OWNER TO "ob-analytics";

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
-- Name: level3_02001b201901 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN side SET DEFAULT NULL;


--
-- Name: level3_02001b201901 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN pair_id SET DEFAULT NULL;


--
-- Name: level3_02001b201901 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001b201901 ALTER COLUMN exchange_id SET DEFAULT NULL;


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
-- Name: level3_02001s201901 side; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN side SET DEFAULT NULL;


--
-- Name: level3_02001s201901 pair_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN pair_id SET DEFAULT NULL;


--
-- Name: level3_02001s201901 exchange_id; Type: DEFAULT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_02001s201901 ALTER COLUMN exchange_id SET DEFAULT NULL;


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
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


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
-- PostgreSQL database dump complete
--

