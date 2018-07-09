#' @importFrom dplyr filter full_join select
#' @importFrom plyr .
#' @importFrom magrittr  %>%
#' @importFrom zoo na.locf
#' @importFrom reshape2 dcast


#' @export
bfEpisodes <- function(conn, snapshot_id) {
  stop("Not yet implemented.")
}


#' @export
bfSpread <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647) {
  df <- dbGetQuery(conn, paste0(  " SELECT exchange_timestamp AS \"timestamp\"",
                                  " ,order_price AS price ",
                                  " ,qty AS vol ",
                                  " ,direction ",
                                  " FROM ( ",
                                  " SELECT *, COALESCE(lag(order_price) OVER p, -1) AS lag_order_price, ",
                                            " COALESCE(lag(qty) OVER p, -1) AS lag_qty ",
                                  " FROM (",
                                        " SELECT snapshot_id, episode_no, exchange_timestamp, order_price, ",
                                        " ABS(SUM(order_qty)) AS qty,",
                                        " CASE WHEN SUM(order_qty) <0 THEN 'ask'::text ",
                                              "ELSE 'bid'::text ",
                                        " END AS direction ",
                                        " FROM bitfinex.bf_active_orders_before_episode_v ",
                                        " WHERE snapshot_id = ", snapshot_id,
                                              " AND lvl = 1 ",
                                              " AND episode_no BETWEEN ", min.episode_no," AND ", max.episode_no,
                                        " GROUP BY snapshot_id, episode_no, exchange_timestamp, order_price ",
                                        ") a ",
                                    " WINDOW p AS (PARTITION BY snapshot_id, direction ORDER BY episode_no) ",
                                    ") b ",
                                  " WHERE order_price != lag_order_price OR qty != lag_qty ",
                                  " ORDER BY episode_no ") )

  na.locf(dcast((select(df, -vol)), list(.(timestamp), .(paste0("best.",direction,".price"))), value.var="price") %>% full_join(dcast((select(df, -price)), list(.(timestamp), .(paste0("best.",direction,".vol"))), value.var="vol"), by="timestamp"))
}


#' @export
bfDepth <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647) {

  df <- dbGetQuery(conn, paste0(" SELECT 	exchange_timestamp AS timestamp ",
                                " , order_price AS price ",
                                " , ABS(SUM(order_qty)) AS volume, ",
                                " CASE WHEN ABS(SUM(order_qty)) < 0 THEN 'ask'::text ",
                                      " ELSE 'bid'::text ",
                                " END AS side",
                                " FROM bitfinex.bf_order_book_events_v ",
                                " WHERE snapshot_id = ", snapshot_id,
                                  " AND episode_no BETWEEN ", min.episode_no, " AND ", max.episode_no,
                                " GROUP BY exchange_timestamp,  order_price, pair ",
                                " ORDER BY 1" ))
  df
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

