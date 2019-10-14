# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


#' @import magrittr
#' @importFrom lubridate with_tz ymd_hms seconds ceiling_date floor_date now minutes duration round_date
#' @importFrom dplyr lead if_else filter select full_join rename mutate
#' @importFrom plyr . empty
#' @importFrom zoo na.locf
#' @importFrom reshape2 dcast melt
#' @importFrom magrittr  %>%
#' @importFrom purrr pmap_dfr
#' @importFrom tibble tibble
#' @useDynLib obadiah


.dummy <- function() {}

#' Securely connects to the OBADiah database
#'
#' Establishes a secure TCP/IP connection to the OBADiah database and returns a connection object.
#' The object is used to communicate with the database.
#'
#' @param sslcert path to the client's SSL certificate file, signed by OBADiah database owner
#' @param sslkey path to the clients' SSL private key
#' @param host name or IP address of the PostgreSQL server running the OBADiah database
#' @param port port
#' @param user user
#' @param dbname name of PostgreSQL database
#' @return the connection object as returned by DBI::dbConnect()
#'
#' @export
connect <- function(sslcert, sslkey, host, port, user="obademo",  dbname="ob-analytics-prod") {
  DBI::dbConnect(RPostgres::Postgres(),
                 user=user,
                 dbname=dbname,
                 host=host,
                 port=port,
                 sslmode="require",
                 sslrootcert=system.file('extdata/root.crt', package="obadiah"),
                 sslcert=sslcert,
                 sslkey=sslkey)
}



#' @export
depth <- function(conn, start.time, end.time, exchange, pair, frequency=NULL, cache=NULL, debug.query=getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {


  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))
  stopifnot(is.null(frequency) || is.numeric(frequency))

  flog.debug(paste0("depth(conn,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  starting_depth <- .starting_depth(conn, start.time, exchange, pair, debug.query)
  if(is.null(cache) || start.time > cache.bound)
    depth_changes <- .depth_changes(conn, start.time, end.time, exchange, pair, frequency, debug.query)
  else {
    if(is.null(frequency)) {
      cache_key <- "depth"
      loader <- .depth_changes
    }
    else {
      cache_key <- paste0("depth",frequency)
      loader <- function(conn, start.time, end.time, exchange, pair, debug.query) {
        .depth_changes(conn, start.time, end.time, exchange, pair, frequency, debug.query)
      }
    }
    if(end.time <= cache.bound )
      depth_changes <- .load_cached(conn, start.time, end.time, exchange, pair, debug.query, loader, .leaf_cache(cache, exchange, pair, cache_key))
    else
      depth_changes <- rbind(.load_cached(conn, start.time, cache.bound, exchange, pair, debug.query, loader, .leaf_cache(cache, exchange, pair, cache_key) ),
                             loader(conn, cache.bound, end.time, exchange, pair, debug.query)
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


.depth_changes <- function(conn, start.time, end.time, exchange, pair, frequency = NULL, debug.query = FALSE)   {
  if(is.null(frequency))
    query <- paste0(" SELECT get._in_milliseconds(timestamp) AS timestamp,
                    price, volume, side FROM get.depth(",
                    shQuote(format(start.time, usetz=T)), ",",
                    shQuote(format(end.time, usetz=T)), ",",
                    "get.pair_id(",shQuote(pair),"), " ,
                    "get.exchange_id(", shQuote(exchange), "), ",
                    "p_starting_depth := false, p_depth_changes := true) ORDER BY 1, 2 DESC")
  else
    query <- paste0(" SELECT get._in_milliseconds(timestamp) AS timestamp,
                    price, volume, side FROM get.depth(",
                    shQuote(format(start.time, usetz=T)), ",",
                    shQuote(format(end.time, usetz=T)), ",",
                    "get.pair_id(",shQuote(pair),"), " ,
                    "get.exchange_id(", shQuote(exchange), "), ",
                    "p_frequency :=", shQuote(paste0(frequency, " seconds ")), ",",
                    "p_starting_depth := false, p_depth_changes := true) ORDER BY 1, 2 DESC")
  if(debug.query) cat(query, "\n", file=stderr())
  depth <- DBI::dbGetQuery(conn, query)
  if(!empty(depth)) {
    depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
    depth$side <- factor(depth$side, c("bid", "ask"))
  }
  depth
}


.starting_depth <- function(conn, start.time, exchange, pair, debug.query = FALSE)   {

  query <- paste0(" SELECT get._in_milliseconds(timestamp) AS timestamp,
                  price, volume, side FROM get.depth(",
                  shQuote(format(start.time,usetz=T)), ", NULL, ",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), "), ",
                  "p_starting_depth := true, p_depth_changes := false) ORDER BY 1, 2 DESC")
  if(debug.query) cat(query, "\n", file=stderr())
  depth <- DBI::dbGetQuery(conn, query)
  depth$timestamp <- as.POSIXct(as.numeric(depth$timestamp)/1000, origin="1970-01-01")
  depth$side <- factor(depth$side, c("bid", "ask"))
  depth
}


#' @export
depth2spread <- function(depth, tz='UTC') {
  spread <- with(depth, spread_from_depth(timestamp, price, volume, side))
  if(!empty(spread)) {
    spread$timestamp <- with_tz(spread$timestamp, tz)
  }
  spread
}



#' @export
spread <- function(conn, start.time, end.time, exchange, pair, by.interval=NULL, cache=NULL, debug.query = getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("spread(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')


  if (is.null(by.interval)) {
    from_rdbms <- .spread
    spread_type <- "spread"
    before <- seconds(10)

  }
  else {
    stopifnot(inherits(by.interval, 'Duration'))

    by.interval <- duration(round(as.numeric(by.interval)), 'seconds')

    if(by.interval > seconds(60))
      before <- by.interval
    else
      before <- seconds(round(60/as.integer(by.interval)+1)*as.integer(by.interval))

    start.time <- round_date(start.time, 'second')
    end.time <- round_date(end.time, 'second')



    from_rdbms <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
      .spread_by_interval(conn, start.time, end.time, exchange, pair, by.interval=paste0(as.numeric(by.interval), ' seconds'), debug.query)
    }
    spread_type <- paste0("spread_by_",as.numeric(by.interval))
  }


  pmap_dfr(tibble(pair, exchange), function(pair, exchange) {

    if(is.null(cache) || start.time > cache.bound) {
      spread <- from_rdbms(conn, start.time - before, end.time, exchange, pair, debug.query)
    }
    else {
      if(end.time <= cache.bound )
        spread <- .load_cached(conn, start.time - before, end.time, exchange, pair, debug.query, from_rdbms, .leaf_cache(cache, exchange, pair, spread_type))
      else
        spread <- rbind(.load_cached(conn, start.time - before, cache.bound, exchange, pair, debug.query, from_rdbms, .leaf_cache(cache, exchange, pair, spread_type) ),
                        from_rdbms(conn, cache.bound, end.time, exchange, pair, debug.query)
        )
    }

    if(!empty(spread)) {
      # Assign timezone of start.time, if any, to timestamp column
      spread$timestamp <- with_tz(spread$timestamp, tzone)
      spread<- spread  %>%
        arrange(timestamp) %>%
        filter(lead(timestamp) > start.time & timestamp <= end.time) %>%
        mutate(timestamp=if_else(timestamp > start.time, timestamp, start.time),
               pair=toupper(pair),
               exchange=tolower(exchange)
               )
      if(!empty(spread)) {
        last_spread <- tail(spread, 1)
        if(last_spread$timestamp < end.time) {
          last_spread$timestamp <- end.time
          spread <- rbind(spread,last_spread)
        }
      }
    }
    spread
  })

}

.spread <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {

  query <- paste0(" SELECT distinct on (get._in_milliseconds(timestamp) )	get._in_milliseconds(timestamp) AS timestamp,
                  \"best.bid.price\",
                  \"best.bid.volume\",
                  \"best.ask.price\",
                  \"best.ask.volume\"
                  FROM get.spread(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ") ",
                  ") ORDER BY 1, timestamp desc")
  if(debug.query) cat(query, "\n", file=stderr())
  spread <- DBI::dbGetQuery(conn, query)
  spread$timestamp <- as.POSIXct(as.numeric(spread$timestamp)/1000, origin="1970-01-01")
  spread
}

.spread_by_interval <- function(conn, start.time, end.time, exchange, pair, by.interval , debug.query = FALSE) {

  query <- paste0(" select distinct on (get._in_milliseconds(timestamp) )	get._in_milliseconds(timestamp) AS timestamp,",
                  "\"best.bid.price\",
                  \"best.bid.volume\",
                  \"best.ask.price\",
                  \"best.ask.volume\",
                  \"era\"
                  from get.spread_by_interval(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), "), ",
                  shQuote(by.interval), "::interval",
                  ") ",
                  " where \"best.bid.price\" is not null or \"best.bid.volume\" is not null or ",
                  " \"best.ask.price\" is not null or \"best.ask.volume\" is not null",
                  " order by 1, timestamp desc")
  if(debug.query) cat(query, "\n", file=stderr())
  spread <- DBI::dbGetQuery(conn, query)
  spread$timestamp <- as.POSIXct(as.numeric(spread$timestamp)/1000, origin="1970-01-01")
  spread
}




#' @export
events <- function(conn, start.time, end.time, exchange, pair, cache=NULL, debug.query = getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("events(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

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
                  get._in_milliseconds(timestamp) AS timestamp,
                  \"exchange.timestamp\",
                  price,
                  volume,
                  action,
                  direction,
                  fill,
                  \"matching.event\",
                  \"type\",
                  \"aggressiveness.bps\"
                  FROM get.events(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ")",
                  ")")
  if(debug.query) cat(query, "\n", file=stderr())
  events <- DBI::dbGetQuery(conn, query)
  events$action <- factor(events$action, c("created", "changed", "deleted"))
  events$direction <- factor(events$direction, c("bid", "ask"))
  events$type <- factor(events$type, c("market", "market-limit", "pacman", "flashed-limit",
                                       "resting-limit", "unknown"))
  events$timestamp <- as.POSIXct(as.numeric(events$timestamp)/1000, origin="1970-01-01")
  events
}

#' @export
trades <- function(conn, start.time, end.time, exchange, pair, cache=NULL,  debug.query = getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {

  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("trades(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

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

  query <- paste0(" SELECT 	get._in_milliseconds(timestamp) AS timestamp,
                  price, volume, direction,
                  \"maker.event.id\",
                  \"taker.event.id\",
                  maker::numeric,
                  taker::numeric,
                  \"exchange.trade.id\" FROM get.trades(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ")",
                  ") ORDER BY timestamp")
  if(debug.query) cat(query, "\n", file=stderr())
  trades <- DBI::dbGetQuery(conn, query)
  trades$timestamp <- as.POSIXct(as.numeric(trades$timestamp)/1000, origin="1970-01-01")
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}


#' @export
depth_summary <- function(conn, start.time, end.time, exchange, pair, cache=NULL, debug.query = getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("spread(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')


  if(is.null(cache) || start.time > cache.bound)
    ds <- .depth_summary(conn, start.time, end.time, exchange, pair, debug.query)
  else
    if(end.time <= cache.bound )
      ds <- .load_cached(conn, start.time, end.time, exchange, pair, debug.query, .depth_summary, .leaf_cache(cache, exchange, pair, "depth_summary"))
  else
    ds <- rbind(.load_cached(conn, start.time, cache.bound, exchange, pair, debug.query, .trades, .leaf_cache(cache, exchange, pair, "depth_summary") ),
                    .depth_summary(conn, cache.bound, end.time, exchange, pair, debug.query)
    )

  ds <- ds %>%
    filter(bps_level == 0) %>%
    select(-volume) %>%
    dcast(list(.(timestamp), .(paste0(side,'.price',bps_level, "bps"))), value.var="price")   %>%
    full_join(ds %>%
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
  ds[setdiff(bid.names, colnames(ds))] <- 0
  ds[setdiff(ask.names, colnames(ds))] <- 0
  ds[is.na(ds)] <- 0

  if(!empty(ds)) {
    # Assign timezone of start.time, if any, to timestamp column
    ds$timestamp <- with_tz(ds$timestamp, tzone)
  }
  ds
}


.depth_summary <- function(conn, start.time, end.time, exchange, pair, debug.query = FALSE) {
  query <- paste0(" with depth_summary as (
                  	        select timestamp,
                                   price,
                                   volume,
                                   side,
                                   bps_level,
                                   rank() over (partition by get._in_milliseconds(timestamp) order by timestamp desc) as r
                            from get.depth_summary(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ") ",
                  " ))
                          select get._in_milliseconds(timestamp) as timestamp,
                                 side,
                                 bps_level,
                                 price,
                                 volume
                          from depth_summary
                          where r=1 -- if rounded to milliseconds 'microtimestamp's are not unique, we'll take the LasT one and will drop the first silently
                                    -- this is a workaround for the inability of R to handle microseconds in POSIXct

                          order by 1, 2 desc")
  if(debug.query) cat(query, "\n", file=stderr())
  df <- DBI::dbGetQuery(conn, query)
  df$timestamp <- as.POSIXct(as.numeric(df$timestamp)/1000, origin="1970-01-01")
  df

}


#' @export
order_book <- function(conn, tp, exchange, pair, max.levels = NA, bps.range = NA, min.bid = NA, max.ask = NA, debug.query = getOption("obadiah.debug.query", FALSE), tz='UTC') {

  if(is.character(tp)) start.time <- ymd_hms(start.time)

  stopifnot(inherits(tp, 'POSIXt'))

  flog.debug(paste0("order_book(con,", format(tp, usetz=T), "," , exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

  if (is.na(max.levels)) max.levels <- "NULL"
  if (is.na(bps.range)) bps.range <- "NULL"
  if (is.na(min.bid)) min.bid <- "NULL"
  if (is.na(max.ask)) max.ask <- "NULL"


  query <- paste0("select ts, \"timestamp\", id, price, volume, liquidity, bps, side, \"exchange.timestamp\"
                   from get.order_book(",
                  shQuote(format(tp, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), "), ",
                  max.levels,  ",",
                  bps.range,  ",",
                  min.bid,  ",",
                  max.ask, ")")
  if(debug.query) cat(query, "\n", file=stderr())
  full_book <- DBI::dbGetQuery(conn, query)
  cols <- c("id","timestamp", "exchange.timestamp", "price", "volume", "liquidity", "bps")
  bids <- full_book[which(full_book$side == 'b'), cols ]
  asks <- full_book[which(full_book$side == 's'), cols ]
  ts <- full_book$ts[1]
  ts <- with_tz(ts, tzone)
  list(timestamp=ts, asks=asks, bids=bids)
}




#' @export
export <- function(conn, start.time, end.time, exchange, pair, file = "events.csv", debug.query = FALSE) {
  start.time <- format(start.time, usetz=T)
  end.time <- format(end.time, usetz=T)

  query <- paste0(" select * from get.export(", shQuote(start.time),
                  ", ",
                  shQuote(format(end.time, usetz=T)), ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ") ",
                  ") order by timestamp")
  if(debug.query) cat(query, "\n", file=stderr())
  events <- DBI::dbGetQuery(conn, query)
  write.csv(events, file = file, row.names = FALSE)
}


#' @export
draws <- function(conn, start.time, end.time, exchange, pair, minimal.draw.pct, draw.type='mid-price', cache=NULL, debug.query = getOption("obadiah.debug.query", FALSE), cache.bound = now(tz='UTC') - minutes(15), tz='UTC') {
  if(is.character(start.time)) start.time <- ymd_hms(start.time)
  if(is.character(end.time)) end.time <- ymd_hms(end.time)

  stopifnot(inherits(start.time, 'POSIXt') & inherits(end.time, 'POSIXt'))

  flog.debug(paste0("draws(con,", format(start.time, usetz=T), "," , format(end.time, usetz=T),",", exchange, ", ", pair,")" ), name="obadiah")

  tzone <- tz

  # Convert to UTC, so internally only UTC is used
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')

  before <- seconds(10)

  if(is.null(cache) || start.time > cache.bound)
    draws <- .draws(conn, start.time - before, end.time,  exchange, pair, minimal.draw.pct, draw.type, debug.query)
  else
    if(end.time <= cache.bound )
      draws <- .load_cached(conn, start.time - before, end.time, exchange, pair, debug.query,
                            function(conn, start.time, end.time, exchange, pair, debug.query) {
                              .draws(conn, start.time, end.time, exchange, pair, minimal.draw.pct, draw.type, debug.query)
                              },
                            .leaf_cache(cache, exchange, pair, paste0("draws_",substr(draw.type,1,3),'_', minimal.draw.pct)))
  else
    draws <- rbind(.load_cached(conn, start.time - before, cache.bound, exchange, pair, debug.query,
                                function(conn, start.time, end.time, exchange, pair, debug.query) {
                                  .draws(conn, start.time, end.time, exchange, pair, minimal.draw.pct, draw.type,  debug.query)
                                },
                                .leaf_cache(cache, exchange, pair, paste0("draws_",substr(draw.type,1,3),'_', minimal.draw.pct))),
                    .draws(conn, cache.bound, end.time, exchange, pair,minimal.draw.pct, draw.type, debug.query)
    )

  if(!empty(draws)) {
    # Assign timezone of start.time, if any, to timestamp column
    draws$timestamp <- with_tz(draws$timestamp, tzone)
    draws$draw.end <- with_tz(draws$draw.end, tzone)
    draws<- draws  %>%
       arrange(timestamp) %>%
       filter((lead(timestamp) > start.time | is.na(lead(timestamp))) & timestamp <= end.time) %>%
       mutate(timestamp=if_else(timestamp > start.time, timestamp, start.time ))
  }
  draws
}

.draws <- function(conn, start.time, end.time, exchange, pair, minimal.draw.pct, draw.type, debug.query = FALSE) {

  query <- paste0(" select get._in_milliseconds(\"timestamp\") AS \"timestamp\",
                  get._in_milliseconds(\"draw.end\") AS \"draw.end\",
                  \"start.price\",
                  \"end.price\",
                  \"draw.size\",
                  \"draw.speed\"
                  FROM get.draws(",
                  shQuote(format(start.time, usetz=T)), ",",
                  shQuote(format(end.time, usetz=T)), ",",
                  shQuote(draw.type), ",",
                  minimal.draw.pct, ",",
                  "get.pair_id(",shQuote(pair),"), " ,
                  "get.exchange_id(", shQuote(exchange), ") ",
                  ") order by 1")
  if(debug.query) cat(query, "\n", file=stderr())
  draws <- DBI::dbGetQuery(conn, query)
  draws$timestamp <- as.POSIXct(as.numeric(draws$timestamp)/1000, origin="1970-01-01")
  draws$draw.end <- as.POSIXct(as.numeric(draws$draw.end)/1000, origin="1970-01-01")
  draws
}


#' @export
intervals <- function(conn, start.time=NULL, end.time=NULL, exchange = NULL, pair = NULL, debug.query = getOption("obadiah.debug.query", FALSE), tz='UTC') {

  if(!is.null(start.time)) {
    if(is.character(start.time)) start.time <- ymd_hms(start.time)
    stopifnot(inherits(start.time, 'POSIXt'))
    start.time <- with_tz(start.time, tz='UTC')
    start.time <- shQuote(format(start.time,"%Y-%m-%d %H:%M:%S%z")) # ISO 8601 format which is understood by both: Postgres and ymd_hms()
  }
  else
    start.time <- "NULL"

  if(!is.null(end.time)) {
    if(is.character(end.time)) end.time <- ymd_hms(end.time)
    stopifnot(inherits(end.time, 'POSIXt'))
    end.time <- with_tz(end.time, tz='UTC')
    end.time <- shQuote(format(end.time,"%Y-%m-%d %H:%M:%S%z"))
  }
  else
    end.time <- "NULL"

  if(!is.null(pair)) pair <- paste0(" get.pair_id(",shQuote(pair),") ") else pair <- "NULL"
  if(!is.null(exchange)) exchange <- paste0(" get.exchange_id(", shQuote(exchange), ") ") else exchange <- "NULL"


  pmap_dfr(tibble(pair, exchange),function(pair, exchange) {

    # Various PostgreSQL-drivers in R are not able to handle timezone conversion correctly/consistently
    # So we use EXTRACT epoch and then convert the epoch to POSIXct on the R side

    query <- paste0("select exchange_id, pair_id,
                          extract(epoch from interval_start) as interval_start,
                          extract(epoch from interval_end) as interval_end,
                          case when events and depth then 'G' when events then 'Y' else 'R' end as c,
                          exchange, pair,
                          extract(epoch from era) as era
                  from get.events_intervals( ",
                    " p_pair_id => ", pair,
                    ", ",
                    " p_exchange_id => ", exchange,
                    ")",
                    " where interval_end > coalesce( ", start.time, " , interval_end - '1 second'::interval ) ",
                    "   and interval_start < coalesce( ", end.time, " , interval_start + '1 second'::interval ) "
    )

    if(debug.query) cat(query, "\n", file=stderr())
    intervals <- DBI::dbGetQuery(conn, query)

    intervals <- intervals %>%
      mutate(interval_start=as.POSIXct(interval_start, origin="1970-01-01"),
             interval_end=as.POSIXct(interval_end, origin="1970-01-01"),
             era=as.POSIXct(era, origin="1970-01-01")
      )

    if(start.time != "NULL") {
      start.time <- ymd_hms(start.time)
      intervals <- intervals %>% mutate(interval_start=if_else(interval_start < start.time, start.time, interval_start))
    }
    if(end.time != "NULL") {
      end.time <- ymd_hms(end.time)
      intervals <- intervals %>% mutate(interval_end=if_else(interval_end > end.time, end.time, interval_end))
    }

    intervals$interval_start <- with_tz(intervals$interval_start, tz)
    intervals$interval_end <- with_tz(intervals$interval_end, tz)
    intervals$era <- with_tz(intervals$era, tz)

    intervals
  } )

}
