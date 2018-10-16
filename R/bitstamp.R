#' @export
bsDepth <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {


  query <- paste0(" SELECT \"timestamp\", price, avg(volume) AS volume, side FROM bitstamp.oba_depth(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair),
                  ") GROUP BY 1, 2, 4 ORDER BY 1, 2 DESC")
  if(debug.query) cat(query)
  depth <- DBI::dbGetQuery(conn, query)
  depth
}


#' @export
bsTrades <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	timestamp, price, volume, direction FROM bitstamp.oba_trades(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY timestamp")
  if(debug.query) cat(query)
  trades <- DBI::dbGetQuery(conn, query)
  trades
}


#' @export
bsSpread <- function(conn, start.time, end.time, pair="BTCUSD", debug.query = FALSE) {
  query <- paste0(" SELECT 	microtimestamp AS \"timestamp\",
                            best_bid_price AS \"best.bid.price\",
                            best_bid_qty AS \"best.bid.volume\",
                            best_ask_price AS \"best.ask.price\",
                            best_ask_qty AS \"best.ask.volume\"
                    FROM bitstamp.oba_spread(",
                  shQuote(start.time), ",",
                  shQuote(end.time), ",",
                  shQuote(pair), ") ORDER BY microtimestamp")
  if(debug.query) cat(query)
  spread <- DBI::dbGetQuery(conn, query)
  spread
}

