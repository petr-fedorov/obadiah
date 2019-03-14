#' @export
depth <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {


  query <- paste0(" SELECT bitstamp._in_milliseconds(timestamp) AS timestamp,
                  price, volume, side FROM obanalytics.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ")",
                  ") ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
  depth$side <- factor(depth$side, c("bid", "ask"))
  attr(depth$timestamp, 'tzone') <- ""
  depth
}


#' @export
events <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
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
                  \"aggressiveness.bps\"
                  FROM obanalytics.oba_events(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ")",
                  ")")
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
trades <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  query <- paste0(" SELECT 	bitstamp._in_milliseconds(timestamp) AS timestamp,
                  price, volume, direction,
                  \"maker.event.id\"::integer,
                  \"taker.event.id\"::integer,
                  maker::numeric,
                  taker::numeric,
                  \"real.trade.id\" FROM obanalytics.oba_trades(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ")",
                  ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- DBI::dbGetQuery(conn, query)
  trades$timestamp <- as.POSIXct(as.numeric(trades$timestamp)/1000, origin="1970-01-01")
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}



