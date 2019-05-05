#' @import lubridate
#' @importFrom dplyr lead if_else


#' @export
depth <- function(conn, start.time, end.time, exchange, pair, cache=NULL, debug.query = FALSE, cache.bound = now(tz='UTC') - minutes(15)) {


  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("depth(conn,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obanalyticsdb")

  tzone <- tz(start.time)

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  starting_depth <- .starting_depth(conn, start.time, exchange, pair, debug.query)
  if(is.null(cache) || start.time > cache.bound)
    depth_changes <- .depth_changes(conn, start.time, end.time, exchange, pair, debug.query)
  else {
    if(end.time <= cache.bound )
      depth_changes <- .load_cached(conn, start.time, end.time, exchange, pair, debug.query, .depth_changes, .leaf_cache(cache, exchange, pair, "depth"))
    else
      depth_changes <- rbind(.load_cached(conn, start.time, cache.bound, exchange, pair, debug.query, .depth_changes, .leaf_cache(cache, exchange, pair, "depth") ),
                             .depth_changes(conn, cache.bound, end.time, exchange, pair, debug.query)
                            )
  }
  depth <- rbind(starting_depth, depth_changes)

  if(!empty(depth)) {
    # Assign timezone of start.time, if any, to timestamp column
    depth$timestamp <- with_tz(depth$timestamp, tzone)
  }
  depth %>% arrange(timestamp, -price)
}


.load_cached <- function(conn, start.time, end.time, exchange, pair, debug.query, loader, cache) {

  .update_cache(conn, floor_date(start.time), ceiling_date(end.time), exchange, pair, debug.query, loader, cache)
  .load_from_cache(start.time, end.time, cache)
}


.depth_changes <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE)   {

  query <- paste0(" SELECT obanalytics._in_milliseconds(timestamp) AS timestamp,
                  price, volume, side FROM obanalytics.oba_depth(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), "), ",
                  "p_starting_depth := false, p_depth_changes := true) ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
  depth$side <- factor(depth$side, c("bid", "ask"))
  depth
}


.starting_depth <- function(conn, start.time, exchange, pair, debug.query = FALSE)   {

  query <- paste0(" SELECT obanalytics._in_milliseconds(timestamp) AS timestamp,
                  price, volume, side FROM obanalytics.oba_depth(",
                  shQuote(format(start.time,usetz=T)), ", NULL, ",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), "), ",
                  "p_starting_depth := true, p_depth_changes := false) ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
  depth$side <- factor(depth$side, c("bid", "ask"))
  depth
}



#' @export
spread <- function(conn, start.time, end.time, exchange, pair, cache=NULL, debug.query = FALSE, cache.bound = now(tz='UTC') - minutes(15)) {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("spread(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obanalyticsdb")

  tzone <- tz(start.time)

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  before <- seconds(10)

  if(is.null(cache) || start.time > cache.bound)
    spread <- .spread(conn, start.time - before, end.time, exchange, pair, debug.query)
  else
    if(end.time <= cache.bound )
      spread <- .load_cached(conn, start.time - before, end.time, exchange, pair, debug.query, .spread, .leaf_cache(cache, exchange, pair, "spread"))
  else
    spread <- rbind(.load_cached(conn, start.time - before, cache.bound, exchange, pair, debug.query, .spread, .leaf_cache(cache, exchange, pair, "spread") ),
                    .spread(conn, cache.bound, end.time, exchange, pair, debug.query)
    )

  if(!empty(spread)) {
    # Assign timezone of start.time, if any, to timestamp column
    spread$timestamp <- with_tz(spread$timestamp, tzone)
  }
  spread<- spread  %>%
    arrange(timestamp) %>%
    filter(lead(timestamp) > start.time & timestamp <= end.time) %>%
    mutate(timestamp=if_else(timestamp > start.time, timestamp, start.time))
  last_spread <- tail(spread, 1)
  last_spread$timestamp <- end.time
  rbind(spread,last_spread)
}

.spread <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {

  query <- paste0(" SELECT distinct on (obanalytics._in_milliseconds(timestamp) )	obanalytics._in_milliseconds(timestamp) AS timestamp,
                  \"best.bid.price\",
                  \"best.bid.volume\",
                  \"best.ask.price\",
                  \"best.ask.volume\"
                  FROM obanalytics.oba_spread(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                  "obanalytics.oba_exchange_id(", shQuote(exchange), ") ",
                  ") ORDER BY 1, timestamp desc ")
  if(debug.query) cat(query)
  spread <- DBI::dbGetQuery(conn, query)
  spread$timestamp <- as.POSIXct(as.numeric(spread$timestamp)/1000, origin="1970-01-01")
  spread
}



#' @export
events <- function(conn, start.time, end.time, exchange, pair, cache=NULL, debug.query = FALSE, cache.bound = now(tz='UTC') - minutes(15)) {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("events(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obanalyticsdb")

  tzone <- tz(start.time)

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  if(is.null(cache) || start.time > cache.bound)
    events <- .events(conn, start.time, end.time, exchange, pair, debug.query)
  else
    if(end.time <= cache.bound )
      events <- .load_cached(conn, start.time, end.time, exchange, pair, debug.query, .events, .leaf_cache(cache, exchange, pair, "events"))
    else
      events <- rbind(.load_cached(conn, start.time, cache.bound, exchange, pair, debug.query, .events, .leaf_cache(cache, exchange, pair, "events") ),
                             .events(conn, cache.bound, end.time, exchange, pair, debug.query)
      )

  if(!empty(events)) {
    # Assign timezone of start.time, if any, to timestamp column
    events$timestamp <- with_tz(events$timestamp, tzone)
  }
  events  %>% arrange(event.id)
}



.events <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {

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
  events$action <- factor(events$action, c("created", "changed", "deleted"))
  events$direction <- factor(events$direction, c("bid", "ask"))
  events$type <- factor(events$type, c("unknown", "flashed-limit",
                                       "resting-limit", "market-limit", "pacman", "market"))
  events$timestamp <- as.POSIXct(as.numeric(events$timestamp)/1000, origin="1970-01-01")
  events
}

#' @export
trades <- function(conn, start.time, end.time, exchange, pair, cache=NULL,  debug.query = FALSE, cache.bound = now(tz='UTC') - minutes(15)) {

  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("trades(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obanalyticsdb")

  tzone <- tz(start.time)

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  if(is.null(cache) || start.time > cache.bound)
    trades <- .trades(conn, start.time, end.time, exchange, pair, debug.query)
  else
    if(end.time <= cache.bound )
      trades <- .load_cached(conn, start.time, end.time, exchange, pair, debug.query, .trades, .leaf_cache(cache, exchange, pair, "trades"))
  else
    trades <- rbind(.load_cached(conn, start.time, cache.bound, exchange, pair, debug.query, .trades, .leaf_cache(cache, exchange, pair, "trades") ),
                    .trades(conn, cache.bound, end.time, exchange, pair, debug.query)
    )

  if(!empty(trades)) {
    # Assign timezone of start.time, if any, to timestamp column
    trades$timestamp <- with_tz(trades$timestamp, tzone)
  }
  trades  %>% arrange(timestamp)
}


.trades <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {

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
  trades$timestamp <- as.POSIXct(as.numeric(trades$timestamp)/1000, origin="1970-01-01")
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}


#' @export
depth_summary <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  tzone <- attr(end.time, "tzone")
  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0(" with depth_summary as (
                  	        select timestamp,
                                   price,
                                   volume,
                                   side,
                                   bps_level,
                                   rank() over (partition by obanalytics._in_milliseconds(timestamp) order by timestamp desc) as r
                            from obanalytics.oba_depth_summary(",
                                  shQuote(start.time), ",",
                                  shQuote(end.time), ",",
                                  "obanalytics.oba_pair_id(",shQuote(pair),"), " ,
                                  "obanalytics.oba_exchange_id(", shQuote(exchange), ") ",
                          " ))
                          select obanalytics._in_milliseconds(timestamp) as timestamp,
                                 side,
                                 bps_level,
                                 price,
                                 volume
                          from depth_summary
                          where r=1 -- if rounded to milliseconds 'microtimestamp's are not unique, we'll take the LasT one and will drop the first silently
                                    -- this is a workaround for the inability of R to handle microseconds in POSIXct

                          order by 1, 2 desc")
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


