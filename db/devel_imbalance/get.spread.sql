-- FUNCTION: get.spread(timestamp with time zone, timestamp with time zone, integer, integer, interval)

-- DROP FUNCTION get.spread(timestamp with time zone, timestamp with time zone, integer, integer, interval);

CREATE OR REPLACE FUNCTION get.spread(
	p_start_time timestamp with time zone,
	p_end_time timestamp with time zone,
	p_pair_id integer,
	p_exchange_id integer,
	p_frequency interval DEFAULT NULL::interval)
    RETURNS TABLE("best.bid.price" numeric, "best.bid.volume" numeric, "best.ask.price" numeric, "best.ask.volume" numeric, "timestamp" timestamptz) 
    LANGUAGE 'sql'

    COST 100
    VOLATILE SECURITY DEFINER 
    ROWS 1000
AS $BODY$

-- ARGUMENTS
--	See obanalytics.spread_by_episode()

select * from get._validate_parameters('spread', p_start_time, p_end_time, p_pair_id, p_exchange_id);

select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp
from obanalytics.level1_continuous(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency);
	
$BODY$;

ALTER FUNCTION get.spread(timestamp with time zone, timestamp with time zone, integer, integer, interval)
    OWNER TO "ob-analytics";
