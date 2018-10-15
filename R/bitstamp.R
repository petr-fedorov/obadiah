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
