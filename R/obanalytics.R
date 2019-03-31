#' @export
depth <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")
  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

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
  attr(depth$timestamp, 'tzone') <- tzone
  depth
}


#' @export
spread <- function(conn, start.time, end.time, exchange, pair,  only.different = TRUE, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")

  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0(" SELECT 	obanalytics._in_milliseconds(timestamp) AS timestamp,
                  \"best.bid.price\",
                  \"best.bid.volume\",
                  \"best.ask.price\",
                  \"best.ask.volume\"
                  FROM obanalytics.oba_spread(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), "), ",
                  only.different,
                  " ) ORDER BY 1")
  if(debug.query) cat(query)
  spread <- DBI::dbGetQuery(conn, query)
  spread$timestamp <- as.POSIXct(as.numeric(spread$timestamp)/1000, origin="1970-01-01", tz=tzone)
  spread
}



#' @export
events <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")

  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0(" SELECT 	\"event.id\",
                  \"id\"::numeric,
                  obanalytics._in_milliseconds(timestamp) AS timestamp,
                  \"exchange.timestamp\",
                  price,
                  volume,
                  action,
                  direction,
                  fill,
                  \"matching.event\",
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
  events$timestamp <- as.POSIXct(as.numeric(events$timestamp)/1000, origin="1970-01-01", tz=tzone)
  events$action <- factor(events$action, c("created", "changed", "deleted"))
  events$direction <- factor(events$direction, c("bid", "ask"))
  events$type <- factor(events$type, c("unknown", "flashed-limit",
                                       "resting-limit", "market-limit", "pacman", "market"))
  events
}

#' @export
trades <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")

  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0(" SELECT 	obanalytics._in_milliseconds(timestamp) AS timestamp,
                  price, volume, direction,
                  \"maker.event.id\",
                  \"taker.event.id\",
                  maker::numeric,
                  taker::numeric,
                  \"exchange.trade.id\" FROM obanalytics.oba_trades(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ")",
                  ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- DBI::dbGetQuery(conn, query)
  trades$timestamp <- as.POSIXct(as.numeric(trades$timestamp)/1000, origin="1970-01-01", tz=tzone)
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}


#' @export
depth_summary <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")
  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0("SELECT obanalytics._in_milliseconds(timestamp) AS timestamp,
                  side, bps_level, price, volume FROM obanalytics.oba_depth_summary(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ") ",
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
  attr(df$timestamp, 'tzone') <- tzone
  df
}


#' @export
order_book <- function(conn, tp, exchange, pair, max.levels = NA, bps.range = NA, min.bid = NA, max.ask = NA, debug.query = FALSE) {

  tzone <- attr(tp, "tzone")
  tp <- format(tp, usetz=T)
  if (is.na(max.levels)) max.levels <- "NULL"
  if (is.na(bps.range)) bps.range <- "NULL"
  if (is.na(min.bid)) min.bid <- "NULL"
  if (is.na(max.ask)) max.ask <- "NULL"


  query <- paste0("select ts, \"timestamp\", id, price, volume, liquidity, bps, side, \"exchange.timestamp\"
                   from obanalytics.oba_order_book(",
                  shQuote(tp), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), "), ",
                  max.levels,  ",",
                  bps.range,  ",",
                  min.bid,  ",",
                  max.ask, ")")
  if(debug.query) cat(query)
  full_book <- DBI::dbGetQuery(conn, query)
  cols <- c("id","timestamp", "exchange.timestamp", "price", "volume", "liquidity", "bps")
  bids <- full_book[which(full_book$side == 'b'), cols ]
  asks <- full_book[which(full_book$side == 's'), cols ]
  ts <- full_book$ts[1]
  attr(ts, "tzone") <- tzone
  list(timestamp=ts, asks=asks, bids=bids)
}




#' @export
export <- function(conn, start.time, end.time, exchange, pair, file = "events.csv", debug.query = FALSE) {
  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

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


