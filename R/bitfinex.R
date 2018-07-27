#' @importFrom dplyr filter full_join select mutate
#' @importFrom plyr .
#' @importFrom magrittr  %>%
#' @importFrom zoo na.locf
#' @importFrom reshape2 dcast melt


#' @export
bfEpisodes <- function(conn, snapshot_id) {
  stop("Not yet implemented.")
}


#' @export
bfSpread <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647, debug.query = FALSE) {
  query <- paste0(
" SELECT 	exchange_timestamp AS \"timestamp\",
		      best_bid_price AS \"best.bid.price\",
		      best_bid_qty AS \"best.bid.vol\",
		      best_ask_price AS \"best.ask.price\",
		      best_ask_qty AS \"best.ask.vol\",
		      episode_no,
		      snapshot_id
  FROM (
    SELECT *, COALESCE(lag(best_bid_price) OVER p, -1) AS lag_bbp,
              COALESCE(lag(best_bid_qty) OVER p, -1) AS lag_bbq,
		          COALESCE(lag(best_ask_price) OVER p, -1) AS lag_bap,
              COALESCE(lag(best_ask_qty) OVER p, -1) AS lag_baq
    FROM ( SELECT episode_no, best_bid_price, best_bid_qty, best_ask_price,
	  		        best_ask_qty, snapshot_id, exchange_timestamp
           FROM bitfinex.bf_spread_before_period_starts_v(", snapshot_id, " , ",min.episode_no, " , ", max.episode_no, ")
           UNION ALL
           SELECT episode_no, best_bid_price, best_bid_qty, best_ask_price,
	  		        best_ask_qty, snapshot_id, exchange_timestamp + 0.001*'1 sec'::interval
           FROM bitfinex.bf_spread_after_period_starts_v(", snapshot_id, " , ",min.episode_no, " , ", max.episode_no, ")
         ) v
    WINDOW p AS (PARTITION BY snapshot_id  ORDER BY episode_no)
  ) a
  WHERE best_bid_price != lag_bbp
     OR best_bid_qty != lag_bbq
     OR best_ask_price != lag_bap
     OR best_ask_qty != lag_baq
  ")
  if(debug.query) cat(query)
  dbGetQuery(conn,query)

}


#' @export
bfDepth <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647, debug.query = FALSE) {

  query <- paste0(" SELECT starts_exchange_timestamp AS \"timestamp\",
                            order_price AS price,
                            sum(order_qty) AS volume
                    FROM bitfinex.bf_active_orders_after_period_starts_v
                    WHERE snapshot_id = ",snapshot_id ,
                  "   AND episode_no BETWEEN ",min.episode_no, " AND ", max.episode_no,
                  " GROUP BY starts_exchange_timestamp, order_price " )
  if(debug.query) cat(query)
  df <- dbGetQuery(conn, query)
  depth <- melt(dcast(df,timestamp ~ price, value.var = "volume", fill=0), id.vars="timestamp", variable.name="price", value.name = "volume")
  depth$price <- as.numeric(levels(depth$price)[depth$price])
  depth <- depth[ with(depth, order(timestamp, -price)), ]
  depth
}

#' @export
bfOrderBook <- function(conn, snapshot_id, episode_no, max.levels = 0, bps.range = 0, min.bid = 0, max.ask = "'Infinity'::float") {

  ts <- dbGetQuery(conn, paste0(" SELECT starts_exchange_timestamp",
                                " FROM bitfinex.bf_order_book_episodes ",
                                " WHERE snapshot_id = ", snapshot_id,
                                " AND episode_no = ", episode_no ))$starts_exchange_timestamp

  where_cond <- paste0(" WHERE snapshot_id = ", snapshot_id,
                       " AND episode_no = ", episode_no )

  if (bps.range > 0 ) {
    where_cond <- paste0(where_cond, " AND bps <= ", bps.range)
  }

  if ( max.levels > 0 ) {
    where_cond <- paste0(where_cond, " AND lvl <= ", max.levels )
  }


  bids  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id
                                              , order_price AS price
                                              , order_qty AS volume
                                              , cumm_qty AS liquidity
                                              , bps
                                        FROM bitfinex.bf_active_orders_after_period_starts_v ",
                                     where_cond, " AND side = 'B' AND order_price >= ", min.bid))

  asks  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id
                                              , order_price AS price
                                              , order_qty AS volume
                                              , cumm_qty AS liquidity
                                              , bps
                                        FROM bitfinex.bf_active_orders_after_period_starts_v ",
                                      where_cond, " AND side = 'A' AND order_price <= ", max.ask))

  list(timestamp=ts, asks=asks, bids=bids)
}

#' @export
bfTrades <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647) {
  dbGetQuery(conn, paste0(" SELECT 	event_exchange_timestamp AS \"timestamp\", ",
                                  " price, ",
                                  " qty AS volume, ",
                                  " CASE WHEN direction = 'S' THEN 'sell'::text ",
                                       " ELSE 'buy'::text ",
                                  " END AS direction ",
                          " FROM bitfinex.bf_trades_v ",
                          " WHERE  event_exchange_timestamp IS NOT NULL ",
                            " AND snapshot_id = ", snapshot_id,
                            " AND episode_no BETWEEN ", min.episode_no, " AND ", max.episode_no,
                          " ORDER BY id "))
}
