#' @export
depth <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {


  query <- paste0(" SELECT obanalytics._in_milliseconds(timestamp) AS timestamp,
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
                  obanalytics._in_milliseconds(timestamp) AS timestamp,
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
  query <- paste0(" SELECT 	obanalytics._in_milliseconds(timestamp) AS timestamp,
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


#' @export
depth_summary <- function(conn, start.time, end.time, exchange, pair, precision='r0', debug.query = FALSE) {

  query <- paste0("SELECT obanalytics._in_milliseconds(timestamp) AS timestamp,
                  side, bps_level, price, volume FROM obanalytics.oba_depth_summary(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), "), ",
                  shQuote(precision),
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


#' @export
export <- function(conn, start.time, end.time, exchange, pair, file = "events.csv", debug.query = FALSE) {
  query <- paste0(" select * from obanalytics.oba_export(", shQuote(start.time),
                  ", ",
                  shQuote(end.time), ", ",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ") ",
                  ") order by timestamp")
  if(debug.query) cat(query)
  events <- DBI::dbGetQuery(conn, query)
  write.csv(events, file = file, row.names = FALSE)
}


