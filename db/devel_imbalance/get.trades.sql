-- FUNCTION: get.trades(timestamp with time zone, timestamp with time zone, integer, integer)

-- DROP FUNCTION get.trades(timestamp with time zone, timestamp with time zone, integer, integer);

CREATE OR REPLACE FUNCTION get.trades(
	p_start_time timestamp with time zone,
	p_end_time timestamp with time zone,
	p_pair_id integer,
	p_exchange_id integer)
    RETURNS TABLE("timestamp" timestamptz, price numeric, volume numeric, direction text, "maker.event.id" uuid, "taker.event.id" uuid, maker bigint, taker bigint, "exchange.trade.id" bigint) 
    LANGUAGE 'sql'

    COST 100
    STABLE SECURITY DEFINER 
    ROWS 1000
AS $BODY$

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

$BODY$;

ALTER FUNCTION get.trades(timestamp with time zone, timestamp with time zone, integer, integer)
    OWNER TO "ob-analytics";
