load(system.file("extdata/testdata.rda", package = "obAnalyticsDb"))

context("Depth cache")

test_that('depth is added to an empty cache',{

  cache <- new.env(parent=emptyenv())
  con <- NULL
  start.time <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  end.time <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')
  exchange <- 'bitstamp'
  pair <- 'btcusd'
  expected <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )


  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) { expected },
    {
      obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache)
      actual <- cache[[exchange]][pair][.cache_leaf_key(start.time, end.time)]
      expect_equal( actual, expected )
    }
  )
})
