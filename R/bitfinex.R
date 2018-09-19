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
  spread <- DBI::dbGetQuery(conn, query)
  spread
}


#' @export
bfDepth <- function(conn, start.time, end.time, pair="BTCUSD",price.aggregation = "P0", debug.query = FALSE) {


  query <- paste0(" SELECT \"timestamp\", price, avg(volume) AS volume, side, episode_no FROM bitfinex.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ",",
                  shQuote(price.aggregation), ") GROUP BY 1, 2, 4, 5 ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
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
  df <- DBI::dbGetQuery(conn, query)
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
bfOrderBook <- function(conn, tp, pair="BTCUSD", max.levels = NA, bps.range = NA, min.bid = NA, max.ask = NA, debug.query = FALSE) {

  if (is.na(max.levels)) max.levels <- "NULL"
  if (is.na(bps.range)) bps.range <- "NULL"
  if (is.na(min.bid)) min.bid <- "NULL"
  if (is.na(max.ask)) max.ask <- "NULL"


  query <- paste0("SELECT order_id AS id, order_price AS price, order_qty AS volume,
                            cumm_qty AS liquidity, bps, side, exchange_timestamp
                    FROM bitfinex.oba_order_book(",
                    shQuote(tp), ",",
                    shQuote(pair), ",",
                    max.levels,  ",",
                    bps.range,  ",",
                    min.bid,  ",",
                    max.ask, ")")
    if(debug.query) cat(query)
    full_book <- DBI::dbGetQuery(conn, query)
    cols <- c("id", "price", "volume", "liquidity")
    bids <- full_book[which(full_book$side == 'B'), cols ]
    asks <- full_book[which(full_book$side == 'A'), cols ]
    ts <- full_book$exchange_timestamp[1]
    list(timestamp=ts, asks=asks, bids=bids)
}


#' @export
bfTrades <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	timestamp, price, volume, direction FROM bitfinex.oba_trades(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- DBI::dbGetQuery(conn, query)
  trades
}


#' @export
bfEvents <- function(conn,start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0("SELECT \"event.id\", id, \"timestamp\", price, volume, action, direction, type FROM bitfinex.oba_events(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair),") ORDER BY 1")
  if(debug.query) cat(query)
  df <- DBI::dbGetQuery(conn, query)
  df
}

