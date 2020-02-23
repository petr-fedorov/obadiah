-- FUNCTION: get.depth(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean, boolean)

-- DROP FUNCTION get.depth(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean, boolean);

CREATE OR REPLACE FUNCTION get.depth(
	p_start_time timestamp with time zone,
	p_end_time timestamp with time zone,
	p_pair_id integer,
	p_exchange_id integer,
	p_frequency interval DEFAULT NULL::interval,
	p_starting_depth boolean DEFAULT true,
	p_depth_changes boolean DEFAULT true)
    RETURNS TABLE("timestamp" timestamptz, price numeric, volume numeric, side text) 
    LANGUAGE 'sql'

    COST 100
    STABLE SECURITY DEFINER 
    ROWS 1000
AS $BODY$
with starting_depth as (
	select microtimestamp, side, price, volume from get._starting_depth(p_start_time, p_pair_id, p_exchange_id, p_frequency)
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

$BODY$;

ALTER FUNCTION get.depth(timestamp with time zone, timestamp with time zone, integer, integer, interval, boolean, boolean)
    OWNER TO "ob-analytics";
