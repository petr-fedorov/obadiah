#' @importFrom dplyr filter full_join select mutate rename
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
           FROM bitfinex.bf_spreads JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no)
           WHERE timing = 'B' AND snapshot_id = ", snapshot_id, " AND episode_no BETWEEN ",min.episode_no, " AND ", max.episode_no, "
           UNION ALL
           SELECT episode_no, best_bid_price, best_bid_qty, best_ask_price,
	  		        best_ask_qty, snapshot_id, exchange_timestamp + 0.001*'1 sec'::interval
           FROM bitfinex.bf_spreads JOIN bitfinex.bf_order_book_episodes USING (snapshot_id, episode_no)
           WHERE timing = 'A' AND snapshot_id = ", snapshot_id, " AND episode_no BETWEEN ",min.episode_no, " AND ", max.episode_no, "
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
bfDepth <- function(conn, start.time, end.time, pair="BTCUSD",price.aggregation = "P0", debug.query = FALSE) {


  query <- paste0(" SELECT \"timestamp\", price, avg(volume) AS volume, side FROM bitfinex.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ",",
                  shQuote(price.aggregation), ") GROUP BY 1, 2, 4 ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- dbGetQuery(conn, query)
  depth
}


#' @export
bfDepthSummary <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647,  debug.query = FALSE) {
  query <- paste0("SELECT exchange_timestamp AS timestamp, direction, bps_level, bps_vwap, volume
                   FROM bitfinex.bf_depth_summary_after_episode_v(",snapshot_id,", ", min.episode_no,", ", max.episode_no,")")
  if(debug.query) cat(query)
  df <- dbGetQuery(conn, query)
  df <- df %>%
    select(-volume) %>%
    dcast(list(.(timestamp), .(paste0(direction,'.vwap',bps_level, "bps"))), value.var="bps_vwap")   %>%
    full_join(df %>%
           select(-bps_vwap) %>%
           dcast(list(.(timestamp), .(paste0(direction,'.vol',bps_level, "bps"))), value.var="volume")
         , by="timestamp" ) %>%  rename(best.ask.price = ask.vwap0bps,
                                        best.bid.price = bid.vwap0bps,
                                        best.ask.vol = ask.vol0bps,
                                        best.bid.vol = bid.vol0bps)

  bid.names <- paste0("bid.vol", seq(from = 25, to = 500, by = 25),
                      "bps")
  ask.names <- paste0("ask.vol", seq(from = 25, to = 500, by = 25),
                      "bps")
  df[setdiff(bid.names, colnames(df))] <- 0
  df[setdiff(ask.names, colnames(df))] <- 0
  df[is.na(df)] <- 0
  df
}


#' @export
bfOrderBook <- function(conn, snapshot_id, episode_no, max.levels = 0, bps.range = 0, min.bid = 0, max.ask = "'Infinity'::float") {

  ts <- dbGetQuery(conn, paste0(" SELECT exchange_timestamp",
                                " FROM bitfinex.bf_order_book_episodes ",
                                " WHERE snapshot_id = ", snapshot_id,
                                " AND episode_no = ", episode_no ))$exchange_timestamp

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
                                        FROM bitfinex.bf_active_orders_after_episode_v ",
                                     where_cond, " AND side = 'B' AND order_price >= ", min.bid))

  asks  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id
                                              , order_price AS price
                                              , order_qty AS volume
                                              , cumm_qty AS liquidity
                                              , bps
                                        FROM bitfinex.bf_active_orders_after_episode_v ",
                                      where_cond, " AND side = 'A' AND order_price <= ", max.ask))

  list(timestamp=ts, asks=asks, bids=bids)
}

#' @export
bfTrades <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	timestamp, price, volume, direction FROM bitfinex.oba_trades(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- dbGetQuery(conn, query)
  trades
}


#' @export
bfEvents <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647,  debug.query = FALSE) {
  query <- paste0("SELECT snapshot_id*10000 + episode_no*100 + event_no AS \"event.id\",
                          order_id AS id,
		                      bf_order_book_events.exchange_timestamp AS \"timestamp\",
                          order_price AS price, abs(event_qty) AS volume, 'deleted'::text AS action,
                          CASE WHEN side = 'A' THEN 'ask'::text ELSE 'bid'::text END AS direction, 'flashed-limit'::text AS \"type\"
                    FROM bitfinex.bf_order_book_events LEFT JOIN bitfinex.bf_trades USING (snapshot_id, episode_no, event_no)
                    WHERE snapshot_id = ",snapshot_id,
                          " AND episode_no BETWEEN ",  min.episode_no ," AND ",max.episode_no,
                    " AND id IS NULL AND order_qty = 0
                    UNION ALL
                    SELECT snapshot_id*10000 + episode_no*100 + event_no AS \"event.id\",
                          order_id AS id,
		                      bf_order_book_events.exchange_timestamp AS \"timestamp\",
                          order_price AS price, abs(event_qty) AS volume, 'created'::text AS action,
                          CASE WHEN side = 'A' THEN 'ask'::text ELSE 'bid'::text END AS direction, 'flashed-limit'::text AS \"type\"
                    FROM bitfinex.bf_order_book_events LEFT JOIN bitfinex.bf_trades USING (snapshot_id, episode_no, event_no)
                    WHERE snapshot_id = ",snapshot_id,
                  " AND episode_no BETWEEN ",  min.episode_no ," AND ",max.episode_no,
                  " AND order_qty = event_qty AND event_price = order_price
                    ORDER BY 1")
  if(debug.query) cat(query)
  df <- dbGetQuery(conn, query)
  df
}

