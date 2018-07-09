#' @importFrom dplyr filter
#' @importFrom magrittr  %>%


#' @export
bfEpisodes <- function(con, snapshot_id) {
  stop("Not yet implemented.")
}


#' @export
bfOrderBook <- function(conn, snapshot_id, episode_no, max.levels = 0, bps.range = 0, min.bid = 0, max.ask = Inf) {

  ts <- dbGetQuery(conn, paste0(" SELECT exchange_timestamp ",
                                " FROM bitfinex.bf_order_book_episodes_v ",
                                " WHERE snapshot_id = ", snapshot_id,
                                " AND episode_no = ", episode_no ))$exchange_timestamp

  where_cond <- paste0(" WHERE snapshot_id = ", snapshot_id,
                       " AND episode_no = ", episode_no )

  if (bps.range > 0 ) {
    where_cond <- paste0(where_cond, " AND bps <= ", bps.range)
  }

  if ( max.levels > 0 ) {
    where_cond <- paste0(where_cond, " AND lvl <= ", max.levels )
  }


  lob  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id ",
                                     ", order_price AS price ",
                                     ", order_qty AS volume ",
                                     ", cumm_qty AS liquidity ",
                                     ", bps ",
                                     " FROM bitfinex.bf_active_orders_before_episode_v ",
                                     where_cond))

  bids <- lob %>% filter( volume > 0 & price >= min.bid )
  asks <- lob %>% filter( volume < 0 & price <= max.ask ) %>% mutate(volume = abs(volume),
                                                 liquidity = abs(liquidity))
  list(timestamp=ts, asks=asks, bids=bids)
}

