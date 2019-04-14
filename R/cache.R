#' @importFrom dplyr between
#' @importFrom plyr empty




.cache_leaf_key <- function(start.time, end.time) {
  stopifnot(inherits(start.time, "POSIXct"), inherits(end.time, "POSIXct"), attr(start.time, "tzone") != "",attr(end.time, "tzone") != "" )
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
  }
  cache[[exchange]][[pair]][[type]]
}



.update_cache <- function(conn, start.time, end.time, exchange, pair, debug.query, loader, cache) {

  if( is.null(cache$periods) || empty(cache$periods %>% filter( start.time>= s & start.time <= e &  end.time >=s & end.time <= e ))) {
    cache[[.cache_leaf_key(start.time, end.time)]] <- loader(conn, start.time, end.time, exchange, pair, debug.query)
    cache$periods <- rbind(cache$periods, data.frame(s=start.time, e=end.time))
  }

}

.load_from_cache <- function(start.time, end.time, cache) {


  cached_interval <-cache$periods %>% filter( start.time>= s & start.time <= e & end.time >=s & end.time <= e )
  stopifnot(!empty(cached_interval))

  cached_data <- cache[[.cache_leaf_key(head(cached_interval)$s, head(cached_interval)$e)]]
  cached_data %>%  filter(between(timestamp, start.time, end.time))

}
