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
-- Name: get; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA get;


ALTER SCHEMA get OWNER TO "ob-analytics";

--
-- Name: draw_type; Type: TYPE; Schema: get; Owner: ob-analytics
--

CREATE TYPE get.draw_type AS ENUM (
    'bid',
    'ask',
    'mid-price'
);


ALTER TYPE get.draw_type OWNER TO "ob-analytics";

--
-- Name: _date_ceiling(timestamp with time zone, interval); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get._date_ceiling(base_date timestamp with time zone, round_interval interval) RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    AS $_$-- See date_round() there: //wiki.postgresql.org/wiki/Round_time
SELECT case when round_interval is not null and isfinite(base_date)  
				then TO_TIMESTAMP(
					(trunc(EXTRACT(epoch FROM $1 - '00:00:00.000001'::interval))::integer/trunc(EXTRACT(epoch FROM $2))::integer +1) * trunc(EXTRACT(epoch FROM $2))::integer)
				else base_date end;
$_$;


ALTER FUNCTION get._date_ceiling(base_date timestamp with time zone, round_interval interval) OWNER TO "ob-analytics";

--
-- Name: _date_floor(timestamp with time zone, interval); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get._date_floor(base_date timestamp with time zone, round_interval interval) RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    AS $_$-- See date_round() there: //wiki.postgresql.org/wiki/Round_time

SELECT case when round_interval is not null and isfinite(base_date)  
				then TO_TIMESTAMP(
					trunc(EXTRACT(epoch FROM $1))::integer/trunc(EXTRACT(epoch FROM $2))::integer * trunc(EXTRACT(epoch FROM $2))::integer)
				else base_date end;
$_$;


ALTER FUNCTION get._date_floor(base_date timestamp with time zone, round_interval interval) OWNER TO "ob-analytics";

--
-- Name: _in_milliseconds(timestamp with time zone); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get._in_milliseconds(ts timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$

SELECT ( ( EXTRACT( EPOCH FROM (_in_milliseconds.ts - '1514754000 seconds'::interval) )::numeric(20,5) + 1514754000 )*1000 )::text;

$$;


ALTER FUNCTION get._in_milliseconds(ts timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: FUNCTION _in_milliseconds(ts timestamp with time zone); Type: COMMENT; Schema: get; Owner: ob-analytics
--

COMMENT ON FUNCTION get._in_milliseconds(ts timestamp with time zone) IS 'Since R''s POSIXct is not able to handle time with the precision higher than 0.1 of millisecond, this function converts timestamp to text with this precision to ensure that the timestamps are not mangled by an interface between Postgres and R somehow.';


--
-- Name: _validate_parameters(text, timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get._validate_parameters(p_request text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$declare
	MAXIMUM_PERIOD constant interval default '1 month 1 minute';
begin
	if p_start_time + MAXIMUM_PERIOD < p_end_time then 
		raise exception '[%, %) for %, %, % exceeds %', p_start_time, p_end_time,  p_request, p_pair_id, p_exchange_id, MAXIMUM_PERIOD;
	end if;
end;
$$;


ALTER FUNCTION get._validate_parameters(p_request text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: available_exchanges(); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.available_exchanges() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
select distinct exchange 
from obanalytics.level3_eras join obanalytics.exchanges using (exchange_id)
where level3 is not null

$$;


ALTER FUNCTION get.available_exchanges() OWNER TO "ob-analytics";

--
-- Name: available_pairs(integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.available_pairs(p_exchange_id integer) RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
select distinct pair
from obanalytics.level3_eras join obanalytics.pairs using (pair_id)
where exchange_id = p_exchange_id 

$$;


ALTER FUNCTION get.available_pairs(p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: available_period(integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.available_period(p_exchange_id integer, p_pair_id integer) RETURNS TABLE(s timestamp with time zone, e timestamp with time zone)
    LANGUAGE sql SECURITY DEFINER
    AS $$ select min(era), max(level3)
 from obanalytics.level3_eras
 where exchange_id = p_exchange_id
   and pair_id = p_pair_id
$$;


ALTER FUNCTION get.available_period(p_exchange_id integer, p_pair_id integer) OWNER TO "ob-analytics";

--
-- Name: data_overview(text, text, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.data_overview(p_exchange text DEFAULT NULL::text, p_pair text DEFAULT NULL::text, p_r integer DEFAULT NULL::integer) RETURNS TABLE(level2_delay interval, pair text, pair_id smallint, exchange text, exchange_id smallint, era timestamp with time zone, level3 timestamp with time zone, level2 timestamp with time zone, level1 timestamp with time zone)
    LANGUAGE sql
    AS $$
with eras as (
	select level3_eras, pair, exchange, era, level3, level2, level1, pair_id, exchange_id,
			row_number() over (partition by pair_id, exchange_id order by era desc) as r,
			coalesce(lead(era) over (partition by pair_id, exchange_id order by era), 'infinity') as next_era
	from obanalytics.level3_eras join obanalytics.exchanges using (exchange_id) join obanalytics.pairs using (pair_id)
	where pair = coalesce(upper(p_pair), pair) 
	  and exchange = coalesce(lower(p_exchange),exchange)
)
select coalesce(level3, era) - coalesce(level2, era),
		pair, pair_id, exchange, exchange_id, era, level3, level2, level1
from eras
where r <= coalesce(p_r, r)
order by era desc;
$$;


ALTER FUNCTION get.data_overview(p_exchange text, p_pair text, p_r integer) OWNER TO "ob-analytics";

--
-- Name: depth(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean, boolean); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval, p_starting_depth boolean DEFAULT true, p_depth_changes boolean DEFAULT true) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$with starting_depth as (
	select period_start as microtimestamp, side, price, volume 
	from (select period_start 
		  from obanalytics._periods_within_eras(p_start_time,
												p_start_time + coalesce(p_frequency, '00:00:00.000001'::interval),
												p_pair_id, p_exchange_id, p_frequency)
		  where previous_period_end is null ) p
	join lateral obanalytics.order_book( period_start,  p_pair_id,p_exchange_id, p_only_makers := false,
											p_before :=true,		-- if period_start is an exact start of an era, 
																	-- then this order book will be null - see comment below
								p_check_takers := false) on true
	join lateral ( select price, side, sum(amount) as volume from unnest(ob) group by price, side ) d on true
	where p_starting_depth 
),
level2 as (
	select microtimestamp, side, price, volume
	from obanalytics.level2_continuous(get._date_floor(p_start_time, p_frequency), 	-- if p_start_time is a start of an era, then level2_continous 
									   					 -- will return full depth from order book - see comment above
									    get._date_ceiling(p_end_time, p_frequency),
									    p_pair_id,
									    p_exchange_id,
									  	p_frequency) level2
		  join unnest(level2.depth_change) d on true
	where p_depth_changes
)
select microtimestamp, price, volume, case side 	
										when 'b' then 'bid'::text
										when 's' then 'ask'::text
									  end as side
from ( select * from starting_depth union all select * from level2) d
where price is not null   -- null might happen when order created and deleted within the same episode
							-- plotPriceLevels will fail if price is null, so we need to exclude such rows.
  and case when p_frequency is null 
  				then coalesce(microtimestamp < p_end_time, TRUE) -- for the convenience of client-side caching the right-boundary event (if any!) must NOT BE included and will go to the start of the next period
			when p_frequency is not null
				then coalesce(microtimestamp <= get._date_ceiling(p_end_time, p_frequency), TRUE) -- for the client-side caching right-boundary interval MUST BE included
	  end				

$$;


ALTER FUNCTION get.depth(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval, p_starting_depth boolean, p_depth_changes boolean) OWNER TO "ob-analytics";

--
-- Name: depth_summary(timestamp with time zone, timestamp with time zone, integer, integer, integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer DEFAULT 25, p_max_bps_level integer DEFAULT 500) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, side text, bps_level integer)
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


ALTER FUNCTION get.depth_summary(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) OWNER TO "ob-analytics";

--
-- Name: draws(timestamp with time zone, timestamp with time zone, get.draw_type, numeric, integer, integer, interval, boolean); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.draws(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_draw_type get.draw_type, p_minimal_draw_pct numeric, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval, p_skip_crossed boolean DEFAULT true) RETURNS TABLE("timestamp" timestamp with time zone, "draw.end" timestamp with time zone, "start.price" numeric, "end.price" numeric, "draw.size" numeric, "draw.speed" numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$

	select start_microtimestamp, end_microtimestamp, start_price, end_price, draw_size,
			round(draw_size/extract(epoch from end_microtimestamp-start_microtimestamp)::numeric, 2)
	from obanalytics.draws_from_spread(	p_start_time, p_end_time, p_exchange_id, p_pair_id, p_draw_type::text, p_frequency, p_skip_crossed, p_minimal_draw_pct);
	
$$;


ALTER FUNCTION get.draws(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_draw_type get.draw_type, p_minimal_draw_pct numeric, p_pair_id integer, p_exchange_id integer, p_frequency interval, p_skip_crossed boolean) OWNER TO "ob-analytics";

--
-- Name: events(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("event.id" uuid, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, action text, direction text, fill numeric, "matching.event" uuid, type text, "aggressiveness.bps" numeric, event_no integer, is_aggressor boolean, is_created boolean, is_ever_resting boolean, is_ever_aggressor boolean, is_ever_filled boolean, is_deleted boolean, is_price_ever_changed boolean, best_bid_price numeric, best_ask_price numeric)
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
				  case side
					when 's' then price <= coalesce(last(best_bid_price) over (order by microtimestamp), price - 1)
					when 'b' then price >= coalesce(last(best_ask_price) over (order by microtimestamp) , price + 1 )
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
				when (is_ever_resting or not is_deleted) and is_ever_aggressor then 'market-limit'::text
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


ALTER FUNCTION get.events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: events_intervals(integer, integer, interval); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.events_intervals(p_pair_id integer DEFAULT NULL::integer, p_exchange_id integer DEFAULT NULL::integer, p_min_duration interval DEFAULT NULL::interval) RETURNS TABLE(era timestamp with time zone, exchange_id smallint, pair_id smallint, interval_start timestamp with time zone, interval_end timestamp with time zone, events boolean, duration interval, exchange text, pair text)
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
with level3_eras as (
	select level3_eras.*, lead(era) over (partition by exchange_id, pair_id order by era) as next_era
	from obanalytics.level3_eras 
	where pair_id = coalesce(p_pair_id, pair_id)
	  and exchange_id = coalesce(p_exchange_id, exchange_id)
),
greens as (
         select era, exchange_id, pair_id, era as s, level3 as e, true as l3
           from level3_eras
          where level3 is not null
        ),
reds as (
         select era, exchange_id, pair_id, level3 as s,
				 coalesce(next_era, now()) as e, 
				 false as l3
         from level3_eras
		 where level3 is not null
		 union all
         select era, exchange_id, pair_id, era as s,
				 coalesce(next_era, now()) as e, 
				 false as l3
         from level3_eras
		 where level3 is null
        ),
all_colours as (
         select era, exchange_id, pair_id, s, e, l3
		 from greens
        union all
         select era, exchange_id, pair_id, s, e, l3
           from reds
        )
select era, exchange_id, pair_id, s, e, l3, justify_interval(e - s) as d, exchange, pair
from all_colours join obanalytics.pairs using (pair_id) join obanalytics.exchanges using (exchange_id)
where e - s >= coalesce(p_min_duration, e - s)
order by exchange_id, pair_id, s desc
$$;


ALTER FUNCTION get.events_intervals(p_pair_id integer, p_exchange_id integer, p_min_duration interval) OWNER TO "ob-analytics";

--
-- Name: exchange_id(text); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.exchange_id(p_exchange text) RETURNS smallint
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$select exchange_id from obanalytics.exchanges where exchange = lower(p_exchange)$$;


ALTER FUNCTION get.exchange_id(p_exchange text) OWNER TO "ob-analytics";

--
-- Name: export(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(id bigint, "timestamp" text, "exchange.timestamp" text, price numeric, volume numeric, action text, direction text)
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
		get._in_milliseconds(microtimestamp),
		get._in_milliseconds(price_microtimestamp),
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


ALTER FUNCTION get.export(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: order_book(timestamp with time zone, integer, integer, integer, numeric, numeric, numeric); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer DEFAULT NULL::integer, p_bps_range numeric DEFAULT NULL::numeric, p_min_bid numeric DEFAULT NULL::numeric, p_max_ask numeric DEFAULT NULL::numeric) RETURNS TABLE(ts timestamp with time zone, id bigint, "timestamp" timestamp with time zone, "exchange.timestamp" timestamp with time zone, price numeric, volume numeric, liquidity numeric, bps numeric, side character)
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
	select ts, order_id, microtimestamp, price_microtimestamp,  price,
			coalesce(amount,0) as amount,
			sum(coalesce(amount,0)) over w as liquidity, 
			round((price-best_ask_price)/best_ask_price*10000,2) as bps, side,
			dense_rank() over (order by price) as lvl,
			row_number() over w as o
	from order_book
	where side = 's'
	window w as (order by price, microtimestamp, order_id)
	union all
	select ts, order_id,  microtimestamp, price_microtimestamp, price, 
			coalesce(amount,0) as amount, sum(coalesce(amount,0)) over w as liquidity, 
			round((best_bid_price-price)/best_bid_price*10000,2) as bps, side, 
			dense_rank() over (order by price desc),
			-row_number() over w as o
	from order_book
	where side = 'b'
	window w as (order by price desc, microtimestamp, order_id)
)
select ts, order_id, microtimestamp, price_microtimestamp, price, amount, liquidity, bps, side 
from order_book_bps_lvl
where bps <= coalesce(p_bps_range, bps)
  and lvl <= coalesce(p_max_levels, lvl)
  and ( (side = 'b' and price >= coalesce(p_min_bid, price)) or (side = 's' and price <= coalesce(p_max_ask, price)))
order by o desc
  
  ;

$$;


ALTER FUNCTION get.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_max_levels integer, p_bps_range numeric, p_min_bid numeric, p_max_ask numeric) OWNER TO "ob-analytics";

--
-- Name: pair_id(text); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.pair_id(p_pair text) RETURNS smallint
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$select pair_id from obanalytics.pairs where pair = upper(p_pair)$$;


ALTER FUNCTION get.pair_id(p_pair text) OWNER TO "ob-analytics";

--
-- Name: spread(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval, p_skip_crossed boolean DEFAULT true) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone)
    LANGUAGE sql SECURITY DEFINER
    AS $$-- ARGUMENTS
--	See obanalytics.spread_by_episode()

select * from get._validate_parameters('spread', p_start_time, p_end_time, p_pair_id, p_exchange_id);

select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
from obanalytics.level1_continuous(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency, p_skip_crossed)
	
$$;


ALTER FUNCTION get.spread(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval, p_skip_crossed boolean) OWNER TO "ob-analytics";

--
-- Name: spread_by_interval(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.spread_by_interval(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_interval interval) RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamp with time zone, era timestamp with time zone)
    LANGUAGE sql SECURITY DEFINER
    AS $$-- ARGUMENTS
--	p_interval interval 

with spread_changes as (
	select distinct on (get._date_ceiling(timestamp, p_interval ))
			get._date_ceiling(timestamp, p_interval ) AS timestamp,
			"best.bid.price",
		    "best.bid.volume",
		    "best.ask.price",
		    "best.ask.volume"
	from get.spread(p_start_time, p_end_time, p_pair_id, p_exchange_id ) 
),
all_timestamps as (
	select get._date_ceiling(timestamp, p_interval ) as timestamp
	from generate_series(p_start_time,p_end_time, p_interval) timestamp
),
eras as (
	select *, least(get._date_ceiling(coalesce(level1, era), p_interval), coalesce(lead(era) over (order by era) - '00:00:00.000001'::interval, 'infinity')) as era_end
	from obanalytics.level3_eras
	where exchange_id = p_exchange_id and pair_id = p_pair_id 
)
select coalesce("best.bid.price", last("best.bid.price") over e) as "best.bid.price",
	    coalesce("best.bid.volume",last("best.bid.volume") over e) as "best.bid.volume",
	    coalesce("best.ask.price", last("best.ask.price") over e) as "best.ask.price",
	    coalesce("best.ask.volume",last("best.ask.volume") over e) as "best.ask.volume",
		timestamp,
		era
from all_timestamps left join spread_changes using (timestamp) join eras on	timestamp between era and era_end
window e as (partition by era order by timestamp)
order by timestamp


	
$$;


ALTER FUNCTION get.spread_by_interval(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_interval interval) OWNER TO "ob-analytics";

--
-- Name: trades(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: get; Owner: ob-analytics
--

CREATE FUNCTION get.trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE("timestamp" timestamp with time zone, price numeric, volume numeric, direction text, "maker.event.id" uuid, "taker.event.id" uuid, maker bigint, taker bigint, "exchange.trade.id" bigint)
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


ALTER FUNCTION get.trades(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: SCHEMA get; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA get TO obauser;


--
-- PostgreSQL database dump complete
--

