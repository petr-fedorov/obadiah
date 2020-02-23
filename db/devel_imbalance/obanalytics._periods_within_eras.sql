-- FUNCTION: obanalytics._periods_within_eras(timestamp with time zone, timestamp with time zone, integer, integer, interval)

-- DROP FUNCTION obanalytics._periods_within_eras(timestamp with time zone, timestamp with time zone, integer, integer, interval);

CREATE OR REPLACE FUNCTION obanalytics._periods_within_eras(
	p_start_time timestamp with time zone,
	p_end_time timestamp with time zone,
	p_pair_id integer,
	p_exchange_id integer,
	p_frequency interval)
    RETURNS TABLE(period_start timestamp with time zone, period_end timestamp with time zone, previous_period_end timestamp with time zone) 
    LANGUAGE 'sql'

    COST 100
    VOLATILE 
    ROWS 1000
AS $BODY$	select period_start, period_end, lag(period_end) over (order by period_start) as previous_period_end
	from (
		select period_start, period_end
		from (
			select greatest(get._date_ceiling(era, p_frequency),
							  get._date_floor(p_start_time, p_frequency)
						   ) as period_start, 
					least(
						least(	-- if get._date_ceiling(level3, p_frequency) overlaps with the next era, will effectively take get._date_floor(level3, p_frequency)!
							coalesce( get._date_ceiling(level3, p_frequency),
								   	   get._date_ceiling(era, p_frequency)
									  ),
							get._date_floor( coalesce( lead(era) over (order by era), 'infinity') , p_frequency)
						),
						get._date_floor(p_end_time, p_frequency)
					) as period_end
			from obanalytics.level3_eras
			where pair_id = p_pair_id
			  and exchange_id = p_exchange_id
			  and get._date_floor(p_start_time, p_frequency) <= coalesce(get._date_floor(level3, p_frequency), get._date_ceiling(era, p_frequency))
			  and get._date_floor(p_end_time, p_frequency) >= get._date_ceiling(era, p_frequency)
		) e
		where get._date_floor(period_end, p_frequency) > get._date_floor(period_start, p_frequency)
	) p
$BODY$;

ALTER FUNCTION obanalytics._periods_within_eras(timestamp with time zone, timestamp with time zone, integer, integer, interval)
    OWNER TO "ob-analytics";
