load(system.file("extdata/testdata.rda", package = "obAnalyticsDb"))
flog.threshold(futile.logger::DEBUG, 'obanalyticsdb')
flog.appender(appender.file('test.log'), name='obanalyticsdb')



context("Depth cache")


test_that('an empty cache',{

  #skip('skip')
  flog.debug('', name='obanalyticsdb')
  flog.debug('an empty cache\n', name='obanalyticsdb')
  cache <- new.env(parent=emptyenv())
  con <- NULL
  start.time <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  end.time <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'
  expected <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )

  flog.debug("# Check that the depth is downloaded ...", name='obanalyticsdb')
  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = function(con, start.time, end.time, exchange, pair, cache) { expected },
      expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                    expected
                    )
  )

  flog.debug(" #... and then served from cache whenever requested range is appropriate (i.e. cached)", name='obanalyticsdb')
  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = function(con, start.time, end.time, exchange, pair, cache) {
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

  flog.debug("# Non-overlapping depth is downloaded from RDBMS", name='obanalyticsdb')
  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = function(con, start.time, end.time, exchange, pair, cache) { expected },
    expect_equal( obAnalyticsDb::depth(con,start.time,end.time, exchange, pair, cache = cache),
                  expected
    )
  )

})



test_that('two queries to rdbms do not overlap',{

  # 1***
  #    2***

  flog.debug('', name='obanalyticsdb')
  flog.debug('two queries to rdbms do not overlap\n', name='obanalyticsdb')
  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  e1 <- lubridate::ymd_hms('2019-04-13 01:15:00.1+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:15:59+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'

  expected  <- data.frame(s = c(s1, lubridate::ceiling_date(e1)),
                          e=c(lubridate::ceiling_date(e1), e2) )

  actual <- data.frame()

  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    actual <<- rbind(actual, data.frame(s=start.time, e=end.time))
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
    }

  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = .depth,
    {
      flog.debug("# adding to cache ...", name='obanalyticsdb')
      obAnalyticsDb::depth(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::depth(con,s2,e2, exchange, pair, cache = cache)

      flog.debug("# has to be served from cache (i.e. must not produce query)", name='obanalyticsdb')
      obAnalyticsDb::depth(con,s1 + lubridate::seconds(1),e2, exchange, pair, cache = cache)

      expect_equal(actual$s, expected$s)
      expect_equal(actual$e, expected$e)
    }
  )

})


test_that('three queries to rdbms do not overlap',{

  #skip('skip')
  #   1***   2***
  #   3**********

  flog.debug('', name='obanalyticsdb')
  flog.debug('three queries to rdbms do not overlap\n', name='obanalyticsdb')

  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:00:00+0300") # we expect time to be rounded to seconds by cache functions
  e1 <- lubridate::ymd_hms('2019-04-13 01:15:00.1+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:16:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:17:59+0300')


  exchange <- 'bitstamp'
  pair <- 'btcusd'

  expected  <- data.frame(s = c(s1, s2, lubridate::ceiling_date(e1)),
                          e=c(lubridate::ceiling_date(e1), e2,  s2) )

  actual <- data.frame()

  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    actual <<- rbind(actual, data.frame(s=start.time, e=end.time))
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
  }

  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = .depth,
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


test_that('data returned from cache and from rdbms are the same',{

  # 1***
  #    2***

  flog.debug('', name='obanalyticsdb')
  flog.debug('data returned from cache and from rdbms are the same\n', name='obanalyticsdb')
  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:14:55+0300") # we expect time to be rounded to seconds by cache functions
  e1 <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:14:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:15:05+0300')

  exchange <- 'bitstamp'
  pair <- 'btcusd'

  expected  <- bitstamp_btcusd_depth %>% filter(timestamp >= s1 & timestamp < e2 )  # [s1, s2)

  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time ) # [start.time, end.time)
  }

  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = .depth,
    {
      flog.debug("# adding to cache ...", name='obanalyticsdb')
      obAnalyticsDb::depth(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::depth(con,s2,e2, exchange, pair, cache = cache)

      flog.debug("# data from cache ", name='obanalyticsdb')
      actual <- obAnalyticsDb::depth(con,s1 ,e2, exchange, pair, cache = cache)

      expect_equal(actual, expected)
    }
  )

})



test_that('cached periods are reported properly',{

  #   1***   2***
  #   3**********

  flog.debug('\n', name='obanalyticsdb')
  flog.debug(paste0('cached periods are reported properly','\n'), name='obanalyticsdb')

  cache <- new.env(parent=emptyenv())
  con <- NULL

  s1 <- lubridate::ymd_hms("2019-04-13 01:00:00+0300")
  e1 <- lubridate::ymd_hms('2019-04-13 01:05:00+0300')

  s2 <- lubridate::ymd_hms('2019-04-13 01:16:59+0300')
  e2 <- lubridate::ymd_hms('2019-04-13 01:17:59+0300')


  exchange <- 'bitstamp'
  pair <- 'btcusd'


  .depth <- function(con, start.time, end.time, exchange, pair, cache) {
    bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
  }

  with_mock(
    `obAnalyticsDb::.starting_depth` = function(...) { data.frame() },
    `obAnalyticsDb::.depth_changes` = .depth,
    {
      obAnalyticsDb::depth(con,s1,e1, exchange, pair, cache = cache)
      actual <- getCachedPeriods(cache, exchange, pair, 'depth')
      expected  <- data.frame(cached.period.start = c(s1),
                              cached.period.end = c(e1),
                              cached.period.rows= as.integer(1559)
                              )

      expect_equal(actual, expected)

      obAnalyticsDb::depth(con,s2,e2, exchange, pair, cache = cache)

      actual <- getCachedPeriods(cache, exchange, pair, 'depth')
      expected  <- data.frame(cached.period.start = c(s1, s2),
                              cached.period.end = c(e1, e2),
                              cached.period.rows= as.integer(c(1559, 294)))
      expect_equal(actual, expected)

    }
  )

})










