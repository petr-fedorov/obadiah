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

