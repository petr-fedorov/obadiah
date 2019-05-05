setup({
   flog.threshold(futile.logger::DEBUG, 'obanalyticsdb')
   flog.appender(appender.file('test_cache_other.log'), name='obanalyticsdb')
})

teardown({
  # flog.appender(NULL, name='obanalyticsdb')
})

# A common test fixture for all test_that functions below. To be evaluated by eval() within test_that()

fixture <- quote({

  load(system.file("extdata/testdata.rda", package = "obAnalyticsDb")) # gets 'bitstamp_btcusd_depth'

  cache <- new.env(parent=emptyenv()) # is shared between tests below
  con <- NULL

  exchange <- 'bitstamp'
  pair <- 'btcusd'

  queries <- data.frame()

  # mock .depth_changes function that (i) logs queries to RDBMS into 'queries' data frame and (ii) returns data as from RDBMS

  .rdbms_query_mock <- function(con, start.time, end.time, exchange, pair, ...) {
    queries <<- rbind(queries, data.frame(start.time=start.time, end.time = end.time, exchange=exchange, pair=pair))
    # 'data' below is either "bitstamp_btcusd_events" or bitstamp_btcusd_trades or "bitstamp_btcusd_spread". Has to be assigned BEFORE eval(fixture)
    get(data)  %>% filter(timestamp >= start.time & timestamp < end.time) # [start.time, end.time)
    }

  })


context("Events cache")


test_that('events returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  data <- 'bitstamp_btcusd_events'

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")


  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC'),
                                                 with_tz(s2, tz='UTC'),
                                                 with_tz(ceiling_date(e1), tz='UTC'),
                                                 with_tz(s1, tz='UTC')
                                                 ),
                                  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),
                                             with_tz(e2, tz='UTC'),
                                             with_tz(s2, tz='UTC'),
                                             with_tz(e2, tz='UTC')),
                                  exchange = exchange,
                                  pair=pair)


  with_mock(
    `obAnalyticsDb::.events` = .rdbms_query_mock,
    {
      obAnalyticsDb::events(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::events(con,s2,e2, exchange, pair, cache = cache)
      obAnalyticsDb::events(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obAnalyticsDb::events(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obAnalyticsDb::events(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})


context("Trades cache")


test_that('trades returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  data <- 'bitstamp_btcusd_trades'

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")


  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC'),
                                                 with_tz(s2, tz='UTC'),
                                                 with_tz(ceiling_date(e1), tz='UTC'),
                                                 with_tz(s1, tz='UTC')
  ),
  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),
             with_tz(e2, tz='UTC'),
             with_tz(s2, tz='UTC'),
             with_tz(e2, tz='UTC')),
  exchange = exchange,
  pair=pair)


  with_mock(
    `obAnalyticsDb::.trades` = .rdbms_query_mock,
    {
      obAnalyticsDb::trades(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::trades(con,s2,e2, exchange, pair, cache = cache)
      obAnalyticsDb::trades(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obAnalyticsDb::trades(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obAnalyticsDb::trades(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})



context("Spread cache")


test_that('spread returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  data <- 'bitstamp_btcusd_spread'

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")


  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC') - seconds(10),
                                                 with_tz(s2, tz='UTC') - seconds(10),
                                                 with_tz(ceiling_date(e1), tz='UTC'),
                                                 with_tz(s1 - seconds(10), tz='UTC')
                                                 ),
                                  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),
                                               with_tz(e2, tz='UTC'),
                                               with_tz(s2 - seconds(10), tz='UTC'),
                                               with_tz(e2, tz='UTC')),
                                  exchange = exchange,
                                  pair=pair)


  with_mock(
    `obAnalyticsDb::.spread` = .rdbms_query_mock,
    {
      obAnalyticsDb::spread(con,s1,e1, exchange, pair, cache = cache)
      obAnalyticsDb::spread(con,s2,e2, exchange, pair, cache = cache)
      obAnalyticsDb::spread(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obAnalyticsDb::spread(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obAnalyticsDb::spread(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})



