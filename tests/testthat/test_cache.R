load(system.file("extdata/testdata.rda", package = "obAnalyticsDb"))

context("Depth cache")

test_that('requested depth is cached in an empty cache',{

  cache <- new.env(parent=emptyenv())
  con <- NULL
  start.time <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  end.time <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'
  expected <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )

  # Check that the depth is downloaded ...
  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) { expected },
      expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                    expected
                    )
  )

  #  ... and then served from cache whenever requested range is appropriate (i.e. cached)
  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) {
      stop(paste('An unexpected query to RDBMS: depth',
           start.time,
           end.time,
           exchange,
           pair,
           sep = " "
           )
           )
      },
    {
      expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                    expected, info=paste0(start.time, end.time, collapse=" ")
                    )

      start.time <- start.time + lubridate::minutes(1)
      end.time <- end.time - lubridate::minutes(1)

      expected <- expected %>% filter(timestamp >= start.time & timestamp <= end.time )

      expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                    expected,
                    info=paste0(start.time, end.time, collapse=" ")
                    )
    }
  )


  start.time <- lubridate::ymd_hms("2019-04-13 01:15:00+0300")
  end.time <- lubridate::ymd_hms('2019-04-13 01:25:10+0300')

  expected <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )

  # Non-overlapping depth is downloaded from RDBMS
  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) { expected },
    expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                  expected
    )
  )

})
