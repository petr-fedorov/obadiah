#' @export
bsDepth <- function(conn, start.time, end.time, pair="BTCUSD", strict = FALSE, debug.query = FALSE) {


  query <- paste0(" SELECT bitstamp._in_milliseconds(timestamp) AS timestamp,
                           price, volume, side FROM bitstamp.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ",",
                  strict,
                  ") ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
  depth$side <- factor(depth$side, c("bid", "ask"))
  attr(depth$timestamp, 'tzone') <- ""
  depth
}


#' @export
bsTrades <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	bitstamp._in_milliseconds(timestamp) AS timestamp,
                    price, volume, direction,
                    \"maker.event.id\"::integer,
                    \"taker.event.id\"::integer,
                    maker::numeric,
                    taker::numeric,
                    \"real.trade.id\" FROM bitstamp.oba_trade(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- DBI::dbGetQuery(conn, query)
  trades$timestamp <- as.POSIXct(as.numeric(trades$timestamp)/1000, origin="1970-01-01")
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}


#' @export
bsSpread <- function(conn, start.time, end.time, pair="BTCUSD", strict = FALSE, debug.query = FALSE) {
  query <- paste0(" SELECT 	bitstamp._in_milliseconds(timestamp) AS timestamp,
                            \"best.bid.price\",
                            \"best.bid.volume\",
                            \"best.ask.price\",
                            \"best.ask.volume\"
                    FROM bitstamp.oba_spread(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair),", ",
                  "TRUE , ",
                  strict,
                  " ) ORDER BY 1")
  if(debug.query) cat(query)
  spread <- DBI::dbGetQuery(conn, query)
  spread$timestamp <- as.POSIXct(as.numeric(spread$timestamp)/1000, origin="1970-01-01")
  spread
}


#' @export
bsEvents <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	\"event.id\"::integer,
                  \"id\"::numeric,
                  bitstamp._in_milliseconds(timestamp) AS timestamp,
                  \"exchange.timestamp\",
                  price,
                  volume,
                  action,
                  direction,
                  fill,
                  \"matching.event\"::integer,
                  \"type\",
                  \"aggressiveness.bps\",
                  \"real.trade.id\"
                  FROM bitstamp.oba_event(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ")")
  if(debug.query) cat(query)
  events <- DBI::dbGetQuery(conn, query)
  events$timestamp <- as.POSIXct(as.numeric(events$timestamp)/1000, origin="1970-01-01")
  events$action <- factor(events$action, c("created", "changed", "deleted"))
  events$direction <- factor(events$direction, c("bid", "ask"))
  events$type <- factor(events$type, c("unknown", "flashed-limit",
                                       "resting-limit", "market-limit", "pacman", "market"))
  events
}


#' @export
bsExportEvents <- function(conn, start.time, end.time, pair="BTCUSD", file = "events.csv", debug.query = FALSE) {
  query <- paste0(" SELECT 	order_id AS id,
                            bitstamp._in_milliseconds(microtimestamp) AS timestamp,
                            bitstamp._in_milliseconds(datetime) AS \"exchange.timestamp\",
                            price,
                            round(amount,8) AS volume,
                            CASE event
                              WHEN 'order_created' THEN 'created'::text
                              WHEN 'order_changed' THEN 'changed'::text
                              WHEN 'order_deleted' THEN 'deleted'::text
                            END AS action,
                            CASE order_type
                              WHEN 'buy' THEN 'bid'::text
                              WHEN 'sell' THEN 'ask'::text
                            END AS direction
                  FROM bitstamp.live_orders JOIN bitstamp.pairs USING (pair_id)
                  WHERE microtimestamp BETWEEN ", shQuote(start.time), "  AND ", shQuote(end.time),
                  " AND pair = ", shQuote(pair),
                  " ORDER BY 2")
  if(debug.query) cat(query)
  events <- DBI::dbGetQuery(conn, query)
  write.csv(events, file = file, row.names = FALSE)
}


#' @export
bsDepthSummary <- function(conn, start.time, end.time, pair="BTCUSD", strict = FALSE, debug.query = FALSE) {

  query <- paste0("SELECT bitstamp._in_milliseconds(timestamp) AS timestamp,
                          side, bps_level, price, volume FROM bitstamp.oba_depth_summary(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ",",
                  strict,
                  ") WHERE COALESCE(bps_level,0) <= 500")
  if(debug.query) cat(query)
  df <- DBI::dbGetQuery(conn, query)
  df$timestamp <- as.POSIXct(as.numeric(df$timestamp)/1000, origin="1970-01-01")
  df <- df %>%
    filter(bps_level == 0) %>%
    select(-volume) %>%
    dcast(list(.(timestamp), .(paste0(side,'.price',bps_level, "bps"))), value.var="price")   %>%
    full_join(df %>%
                select(-price) %>%
                dcast(list(.(timestamp), .(paste0(side,'.vol',bps_level, "bps"))), value.var="volume")
              , by="timestamp" ) %>%  rename(best.ask.price = ask.price0bps,
                                             best.bid.price = bid.price0bps,
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
