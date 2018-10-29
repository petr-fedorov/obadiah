#' @export
bsDepth <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {


  query <- paste0(" SELECT \"timestamp\", price, volume, side FROM bitstamp.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair),
                  ")")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth
}


#' @export
bsTrades <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	timestamp, price, volume, direction,
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
  trades$direction <- factor(trades$direction, c("buy", "sell"))

  trades
}


#' @export
bsSpread <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	\"timestamp\",
                            \"best.bid.price\",
                            \"best.bid.volume\",
                            \"best.ask.price\",
                            \"best.ask.volume\"
                    FROM bitstamp.oba_spread(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY 1")
  if(debug.query) cat(query)
  spread <- DBI::dbGetQuery(conn, query)
  spread
}


#' @export
bsEvents <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	\"event.id\"::integer,
                  \"id\"::numeric,
                  \"timestamp\",
                  \"exchange.timestamp\",
                  price,
                  volume,
                  action,
                  direction,
                  fill,
                  \"matching.event\"::integer,
                  \"type\",
                  \"aggressiveness.bps\"
                  FROM bitstamp.oba_event(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ")")
  if(debug.query) cat(query)
  events <- DBI::dbGetQuery(conn, query)
  events$action <- factor(events$action, c("created", "changed", "deleted"))
  events$direction <- factor(events$direction, c("bid", "ask"))
  events
}


#' @export
bsExportEvents <- function(conn, start.time, end.time, pair="BTCUSD", file = "events.csv", debug.query = FALSE) {
  query <- paste0(" SELECT 	order_id AS id,
                            EXTRACT(EPOCH FROM microtimestamp)*1000 AS timestamp,
                            EXTRACT(EPOCH FROM datetime)*1000 AS \"exchange.timestamp\",
                            price,
                            amount AS volume,
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
                  " ORDER BY microtimestamp")
  if(debug.query) cat(query)
  events <- DBI::dbGetQuery(conn, query)
  write.csv(events, file = file, row.names = FALSE)
}


