#' @import futile.logger
#' @importFrom dplyr summarize group_by rename ungroup arrange filter



#' @export
getCachedPeriods <- function(cache, exchange, pair, type) {
  cache <- .leaf_cache(cache, exchange, pair,type)

  cache$periods %>%
    group_by(s,e) %>%
    summarize(cached.period.rows=nrow(cache[[.cache_leaf_key(s, e)]])) %>%
    rename(cached.period.start=s, cached.period.end=e) %>%
    ungroup()
}




.cache_leaf_key <- function(start.time, end.time) {
  stopifnot(inherits(start.time, "POSIXct"), inherits(end.time, "POSIXct"))
  start.time <- with_tz(start.time, tz='UTC')
  end.time <- with_tz(end.time, tz='UTC')
  fmt <- "%Y%m%d_%H%M%S%z"
  paste0(".", format(start.time, format=fmt),"#", format(end.time, format=fmt), collapse="")
}


.leaf_cache <- function(cache, exchange, pair, type) {
  stopifnot(inherits(cache, "environment"))
  if(is.null(cache[[exchange]])) {
    cache[[exchange]] <- new.env(parent=emptyenv())
  }

  if(is.null(cache[[exchange]][[pair]])) {
    cache[[exchange]][[pair]] <- new.env(parent=emptyenv())
  }
  if(is.null(cache[[exchange]][[pair]][[type]])) {
    cache[[exchange]][[pair]][[type]] <- new.env(parent=emptyenv())
    cache[[exchange]][[pair]][[type]]$type <- type
  }
  cache[[exchange]][[pair]][[type]]
}



.update_cache <- function(conn, start.time, end.time, exchange, pair, debug.query, loader, cache) {

  flog.debug(".update_cache(%s, %s, %s, %s, %s)", format(start.time), format(end.time), exchange, pair, cache$type, name="obanalyticsdb.cache")

  if( plyr::empty(cache$periods) ) {
    flog.debug('cache is empty, query & add to cache: %s - %s ', format(start.time), format(end.time), name="obanalyticsdb.cache")
    cache[[.cache_leaf_key(start.time, end.time)]] <- loader(conn, start.time, end.time, exchange, pair, debug.query)
    cache$periods <- rbind(cache$periods, data.frame(s=start.time, e=end.time))
  }
  else {

    if(plyr::empty(cache$periods %>% dplyr::filter( start.time>= s & start.time <= e & end.time >=s & end.time <= e ))) {
      # the requested interval [start.time, end.time] can not be served from cache, so cache has to be updated

      relevant <- cache$periods %>% dplyr::filter(s <= end.time & e >= start.time ) %>% dplyr::arrange(s, e)

      current.time <- start.time

      i <- 1

      new.cache.entry <- data.frame()

      while (current.time < end.time ) {
        flog.debug('current.time = %s', format(current.time), name="obanalyticsdb.cache")
        key <- .cache_leaf_key(relevant[i, "s"],relevant[i, "e"])

        if (i > nrow(relevant)) {
          new.cache.entry <- rbind(new.cache.entry,
                                   loader(conn, current.time, end.time, exchange, pair, debug.query),
                                   cache[[.cache_leaf_key(current.time, end.time)]]
          )
          flog.debug('nothing left in the cache, query, but not add to the cache yet %s - %s', format(current.time),format(end.time), name="obanalyticsdb.cache")
          current.time <- end.time
          update.cache <- TRUE

        } else {
          flog.debug('found relevant %s - %s', format(relevant[i, "s"]), format(relevant[i, "e"]), name="obanalyticsdb.cache")

          if(current.time < relevant[i, "s"]) {
            flog.debug('query, but not add to the cache yet: %s -%s', format(current.time), format(relevant[i, "s"]), name="obanalyticsdb.cache")

            new.cache.entry <- rbind(new.cache.entry,
                                     loader(conn, current.time, relevant[i, "s"], exchange, pair, debug.query),
                                     cache[[key]]
            )

            if (relevant[i, "e"] > end.time)
              end.time <- relevant[i, "e"] # the loop will stop


          }
          else {
            new.cache.entry <- rbind(new.cache.entry, cache[[key]])

            if (relevant[i, "s"] < start.time) {
              start.time <- relevant[i, "s"]
            }
          }

          cache$periods <- cache$periods %>% filter( !(s == relevant[i, "s"] & e == relevant[i, "e"]) )
          rm(list=key, envir = cache)
          flog.debug('removed from the cache %s - %s %s', format(relevant[i, "s"]), format(relevant[i, "e"]), key, name="obanalyticsdb.cache")

          current.time <- relevant[i, "e"]
          i <- i+1
        }

      }

      cache[[.cache_leaf_key(start.time, end.time)]] <- new.cache.entry
      cache$periods <- rbind(cache$periods, data.frame(s=start.time, e=end.time))
      flog.debug('added to cache %s - %s', format(start.time), format(end.time), name="obanalyticsdb.cache")

    }
    else
      flog.debug('the cache need not be updated', name="obanalyticsdb.cache")
  }

  flog.debug('Cached periods: ', name="obanalyticsdb.cache")
  plyr::a_ply(cache$periods, 1, function(x) {
    flog.debug('   %s - %s # of rows %i', format(x$s), format(x$e), nrow(cache[[.cache_leaf_key(x$s, x$e)]]), name="obanalyticsdb.cache")
    #flog.debug(ls(envir=cache, all.names=TRUE), name="obanalyticsdb.cache")
    } )
}

.load_from_cache <- function(start.time, end.time, cache) {

  flog.debug('.load_from_cache(%s, %s, %s)', format(start.time), format(end.time), cache$type, name="obanalyticsdb.cache")
  cached_interval <-cache$periods %>% filter( start.time>= s & start.time <= e & end.time >=s & end.time <= e )

  if (plyr::empty(cached_interval)) {
    flog.error('requested data are not found in the cache: %s %s', format(start.time), format(end.time), name="obanalyticsdb.cache")
    stop()
  }
  cached_data <- cache[[.cache_leaf_key(head(cached_interval)$s, head(cached_interval)$e)]]
  flog.debug('requested data are found in the cache period %s %s', format(head(cached_interval)$s), format(head(cached_interval)$e), name="obanalyticsdb.cache")
  cached_data %>%  filter(timestamp >= start.time & timestamp < end.time) %>% arrange(timestamp, -price)

}
