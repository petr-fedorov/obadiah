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

