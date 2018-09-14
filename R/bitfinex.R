#' @importFrom dplyr filter full_join select mutate rename
#' @importFrom plyr .
#' @importFrom magrittr  %>%
#' @importFrom zoo na.locf
#' @importFrom reshape2 dcast melt



#' @export
bfSpread <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	\"timestamp\", \"best.bid.price\", \"best.bid.volume\", \"best.ask.price\", \"best.ask.volume\" FROM bitfinex.oba_spread(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY timestamp")
  if(debug.query) cat(query)
  spread <- dbGetQuery(conn, query)
  spread
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
bfDepthSummary <- function(conn, start.time, end.time, pair="BTCUSD",price.aggregation = "P1", debug.query = FALSE) {
  query <- paste0("SELECT timestamp, direction, bps_level, bps_vwap, volume FROM bitfinex.oba_depth_summary(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ",",
                  shQuote(price.aggregation),")")
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
bfEvents <- function(conn,start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0("SELECT \"event.id\", id, \"timestamp\", price, volume, action, direction, type FROM bitfinex.oba_events(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair),") ORDER BY 1")
  if(debug.query) cat(query)
  df <- dbGetQuery(conn, query)
  df
}

