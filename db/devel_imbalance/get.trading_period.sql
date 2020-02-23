-- FUNCTION: get.trading_period(timestamp with time zone, timestamp with time zone, integer, integer, double precision, interval)

-- DROP FUNCTION get.trading_period(timestamp with time zone, timestamp with time zone, integer, integer, double precision, interval);

CREATE OR REPLACE FUNCTION get.trading_period(
	p_start_time timestamp with time zone,
	p_end_time timestamp with time zone,
	p_pair_id integer,
	p_exchange_id integer,
	p_volume double precision,
	p_frequency interval DEFAULT NULL::interval)
    RETURNS TABLE("timestamp" timestamptz, "bid.price" double precision, "ask.price" double precision) 
    LANGUAGE 'c'

    COST 1
    VOLATILE 
    ROWS 1000
AS '$libdir/libobadiah_db.so.1', 'CalculateTradingPeriod'
;

ALTER FUNCTION get.trading_period(timestamp with time zone, timestamp with time zone, integer, integer, double precision, interval)
    OWNER TO "ob-analytics";
