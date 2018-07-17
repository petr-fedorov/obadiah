#' @importFrom dplyr filter full_join select mutate
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
  df <- dbGetQuery(conn, paste0(  " SELECT starts_exchange_timestamp AS \"timestamp\"
                                   ,order_price AS price
                                   ,qty AS vol
                                   ,direction
                                   FROM (
                                   SELECT *, COALESCE(lag(order_price) OVER p, -1) AS lag_order_price,
                                             COALESCE(lag(qty) OVER p, -1) AS lag_qty
                                   FROM (
                                         SELECT snapshot_id, episode_no, starts_exchange_timestamp, order_price,
                                                SUM(order_qty) AS qty,
                                                CASE WHEN side = 'A' THEN 'ask'::text
                                                     ELSE 'bid'::text
                                                END AS direction
                                         FROM bitfinex.bf_active_orders_before_episode_v
                                         WHERE snapshot_id = ", snapshot_id,
                                             " AND lvl = 1
                                               AND episode_no BETWEEN ", min.episode_no," AND ", max.episode_no,
                                        " GROUP BY snapshot_id, episode_no, starts_exchange_timestamp, order_price, side
                                         ) a
                                     WINDOW p AS (PARTITION BY snapshot_id, direction ORDER BY episode_no)
                                    ) b
                                   WHERE order_price != lag_order_price OR qty != lag_qty
                                   ORDER BY episode_no ") )

  na.locf(dcast((select(df, -vol)), list(.(timestamp), .(paste0("best.",direction,".price"))), value.var="price") %>% full_join(dcast((select(df, -price)), list(.(timestamp), .(paste0("best.",direction,".vol"))), value.var="vol"), by="timestamp"))
}


#' @export
bfDepth <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647) {

  df <- dbGetQuery(conn, paste0(" SELECT 	exchange_timestamp AS timestamp
                                          , order_price AS price
                                          , SUM(order_qty) AS volume
                                          , CASE WHEN side='A' THEN 'ask'::text
                                                 ELSE 'bid'::text
                                            END AS side
                                  FROM (
                                    SELECT exchange_timestamp, order_price, order_qty, side
                                    FROM bitfinex.bf_order_book_events
                                    WHERE snapshot_id = ", snapshot_id,
                                    " AND episode_no BETWEEN ", min.episode_no," AND ", max.episode_no,
                                " UNION ALL
                                    SELECT exchange_timestamp,  prev_order_price AS order_price, 0::numeric AS order_qty, side
                                    FROM (
                                      SELECT exchange_timestamp, order_price,  COALESCE(lag(order_price) OVER o , order_price) AS prev_order_price, side
                                      FROM bitfinex.bf_order_book_events
                                      WHERE snapshot_id = ", snapshot_id,
                                    "   AND episode_no BETWEEN ", min.episode_no," AND ", max.episode_no,
                                    " WINDOW o AS (PARTITION BY snapshot_id, order_id ORDER BY episode_no)
                                        ) b
                                    WHERE order_price != prev_order_price
                                  ) a
                                  GROUP BY exchange_timestamp,  order_price, side
                                  ORDER BY 1" ))
  df
}

#' @export
bfOrderBook <- function(conn, snapshot_id, episode_no, max.levels = 0, bps.range = 0, min.bid = 0, max.ask = "'Infinity'::float") {

  ts <- dbGetQuery(conn, paste0(" SELECT starts_exchange_timestamp",
                                " FROM bitfinex.bf_order_book_episodes ",
                                " WHERE snapshot_id = ", snapshot_id,
                                " AND episode_no = ", episode_no ))$starts_exchange_timestamp

  where_cond <- paste0(" WHERE snapshot_id = ", snapshot_id,
                       " AND episode_no = ", episode_no )

  if (bps.range > 0 ) {
    where_cond <- paste0(where_cond, " AND bps <= ", bps.range)
  }

  if ( max.levels > 0 ) {
    where_cond <- paste0(where_cond, " AND lvl <= ", max.levels )
  }


  bids  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id
                                              , order_price AS price
                                              , order_qty AS volume
                                              , cumm_qty AS liquidity
                                              , bps
                                        FROM bitfinex.bf_active_orders_before_episode_v ",
                                     where_cond, " AND side = 'B' AND order_price >= ", min.bid))

  asks  <-    dbGetQuery(conn, paste0(" SELECT order_id AS id
                                              , order_price AS price
                                              , order_qty AS volume
                                              , cumm_qty AS liquidity
                                              , bps
                                        FROM bitfinex.bf_active_orders_before_episode_v ",
                                      where_cond, " AND side = 'A' AND order_price <= ", max.ask))

  list(timestamp=ts, asks=asks, bids=bids)
}

#' @export
bfTrades <- function(conn, snapshot_id, min.episode_no = 0, max.episode_no = 2147483647) {
  dbGetQuery(conn, paste0(" SELECT 	event_exchange_timestamp AS \"timestamp\", ",
                                  " price, ",
                                  " qty AS volume, ",
                                  " CASE WHEN direction = 'S' THEN 'sell'::text ",
                                       " ELSE 'buy'::text ",
                                  " END AS direction ",
                          " FROM bitfinex.bf_trades_v ",
                          " WHERE  event_exchange_timestamp IS NOT NULL ",
                            " AND snapshot_id = ", snapshot_id,
                            " AND episode_no BETWEEN ", min.episode_no, " AND ", max.episode_no,
                          " ORDER BY id "))
}
