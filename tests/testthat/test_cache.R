load(system.file("extdata/testdata.rda", package = "obAnalyticsDb"))
flog.threshold(futile.logger::DEBUG)
flog.appender(appender.file('test.log'))


context("Depth cache")


test_that('an empty cache',{

  #skip('skip')
  cache <- new.env(parent=emptyenv())
  con <- NULL
  start.time <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  end.time <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'
  expected <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )

  flog.debug("# Check that the depth is downloaded ...")
  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) { expected },
      expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                    expected
                    )
  )

  flog.debug(" #... and then served from cache whenever requested range is appropriate (i.e. cached)")
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

  flog.debug("# Non-overlapping depth is downloaded from RDBMS")
  with_mock(
    `obAnalyticsDb::.depth` = function(con, start.time, end.time, exchange, pair, cache) { expected },
    expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                  expected
    )
  )

})



test_that('two queries to rdbms do not overlap',{

  # 1***
  #    2***

  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  e1 <- lubridate::ymd_hms('2019-04-13 01:15:00.1+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:15:59+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'

  expected  <- data.frame(s = c(s1, lubridate::ceiling_date(e1) + lubridate::seconds(1)),
                          e=c(lubridate::ceiling_date(e1), e2) )

  actual <- data.frame()

  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    actual <<- rbind(actual, data.frame(s=start.time, e=end.time))
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
    }

  with_mock(
    `obAnalyticsDb::.depth` = .depth,
    {
      flog.debug("# adding to cache ...")
      obAnalyticsDb::depth(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::depth(con,s2,e2, exchange, pair, cache = cache)

      flog.debug("# has to be served from cache (i.e. must not produce query)")
      obAnalyticsDb::depth(con,s1 + lubridate::seconds(1),e2, exchange, pair, cache = cache)

      expect_equal(actual$s, expected$s)
      expect_equal(actual$e, expected$e)
    }
  )

})


test_that('three queries to rdbms do not overlap',{

  # skip('skip')
  #   1***   2***
  #   3**********

  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  e1 <- lubridate::ymd_hms('2019-04-13 01:15:00.1+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:16:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:17:59+0300')


  exchange <- 'bitstamp'
  pair <- 'btcusd'

  expected  <- data.frame(s = c(s1, s2, lubridate::ceiling_date(e1) + lubridate::seconds(1)),
                          e=c(lubridate::ceiling_date(e1), e2,  s2) )

  actual <- data.frame()

  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    actual <<- rbind(actual, data.frame(s=start.time, e=end.time))
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
  }

  with_mock(
    `obAnalyticsDb::.depth` = .depth,
    {
      obAnalyticsDb::depth(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::depth(con,s2,e2, exchange, pair, cache = cache)
      obAnalyticsDb::depth(con,s1,e2, exchange, pair, cache = cache)

      # has to be served from cache (i.e. must not produce query)
      obAnalyticsDb::depth(con,s1 + lubridate::seconds(1),e2, exchange, pair, cache = cache)

      expect_equal(actual$s, expected$s)
      expect_equal(actual$e, expected$e)
    }
  )

})





