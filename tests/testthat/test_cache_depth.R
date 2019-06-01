context("Generic cache functionality & depth")


setup({
   flog.threshold(futile.logger::DEBUG, 'obadiah')
   flog.appender(appender.file('test_cache_depth.log'), name='obadiah')
})

teardown({
  # flog.appender(NULL, name='obadiah')
})

# A common test fixture for all test_that functions below. To be evaluated by eval() within test_that()

fixture <- quote({

  load(system.file("extdata/testdata.rda", package = "obadiah")) # gets 'bitstamp_btcusd_depth'

  cache <- new.env(parent=emptyenv()) # is shared between tests below
  con <- NULL

  exchange <- 'bitstamp'
  pair <- 'btcusd'

  queries <- data.frame()

  # mock .depth_changes function that (i) logs queries to RDBMS into 'queries' data frame and (ii) returns data as from RDBMS

  .depth_changes_mock <- function(con, start.time, end.time, exchange, pair, ...) {
    queries <<- rbind(queries, data.frame(start.time=start.time, end.time = end.time, exchange=exchange, pair=pair))
    bitstamp_btcusd_depth  %>% filter(timestamp >= start.time & timestamp < end.time) # [start.time, end.time)
    }

  })


test_that('the depth is downloaded from RDBMS and timestamps are in UTC time zone',{

  eval(fixture)

  start.time <- with_tz(min(bitstamp_btcusd_depth$timestamp)) # no time zone!
  end.time <- max(bitstamp_btcusd_depth$timestamp)

  expected_data <- bitstamp_btcusd_depth %>% filter(timestamp < end.time ) # timestamp >= end.time must not be returned, i.e. [start.time, end.time)
  expected_data$timestamp <- with_tz(expected_data$timestamp, tz='UTC') # start.time is WITHOUT tzone, so 'UTC' must be returned

  # All queries are supposed to be done in UTC time zone and start.time and end.time have to be rounded to seconds

  expected_queries <- data.frame(start.time=floor_date(with_tz(start.time, tz='UTC')),
                                 end.time = ceiling_date(with_tz(end.time, tz='UTC')),
                                 exchange=exchange, pair=pair)

  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      actual <- obadiah::depth(con, start.time, end.time, exchange, pair, cache = cache)
    }
  )

  expect_equal(actual, expected_data, info="Data")
  expect_equal(queries$start.time, expected_queries$start.time, info="Query: start.time")
  expect_equal(queries$end.time, expected_queries$end.time, info="Query: end.time")
  expect_equal(queries, expected_queries, info="Queries")

})


test_that('the depth is downloaded from RDBMS and timestamps are in Europe/Moscow time zone',{

  eval(fixture)

  tzone <- "Europe/Moscow"

  start.time <- ymd_hms("2019-04-13 01:00:00", tz=tzone)
  end.time <- ymd_hms("2019-04-13 01:14:59", tz=tzone)

  expected_data <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time & timestamp < end.time )
  expected_data$timestamp <- with_tz(expected_data$timestamp, tz=tzone) # start.time in Europe/Moscow, so returned data has to be in the same time zone

  # All queries are supposed to be done in UTC time zone, no matter what is time zone of the parameters of depth()
  expected_queries <- data.frame(start.time=with_tz(start.time, tz='UTC'),
                                 end.time = with_tz(end.time, tz='UTC'),
                                 exchange=exchange, pair=pair)

  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      actual <- obadiah::depth(con, start.time,end.time, exchange, pair, cache = cache, tz=tzone)
    }
  )

  expect_equal(actual, expected_data, info="Data")
  expect_equal(queries, expected_queries, info="Query")

})


test_that('depth is served from cache whenever requested range is cached',  {


  eval(fixture)

  start.time <- ymd_hms("2019-04-13 01:00:00+0300")
  end.time <- ymd_hms('2019-04-13 01:14:59+0300')

  expected_data <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time + minutes(1) & timestamp < end.time - minutes(1) )
  expected_data$timestamp <- with_tz(expected_data$timestamp, tz='UTC')

  # We cache [start.time, end.time) interval and then request [start.time + minutes(1), end.time - minutes(1)) from cache
  # So there must be only one query for  [start.time, end.time) interval

  expected_queries <- data.frame(start.time=with_tz(start.time, tz='UTC'),
                                 end.time = with_tz(end.time, tz='UTC'),
                                 exchange=exchange, pair=pair)


  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      obadiah::depth(con,start.time,end.time, exchange, pair, cache = cache)
      actual <- obadiah::depth(con,
                                     start.time + minutes(1), # i.e. an interval within the one cached earlier
                                     end.time - minutes(1),
                                     exchange, pair, cache = cache)
    }
  )

  expect_equal(actual, expected_data, info="Data")
  expect_equal(queries$start.time, expected_queries$start.time, info="Query: start.time")
  expect_equal(queries$end.time, expected_queries$end.time, info="Query: end.time")
  expect_equal(queries, expected_queries, info="Queries")

})

test_that("non-overlapping depths are downloaded from RDBMS", {
  eval(fixture)

  tzone1 <- "Europe/London"
  start.time1 <- ymd_hms("2019-04-13 01:00:00", tz=tzone1)
  end.time1 <- ymd_hms('2019-04-13 01:14:59', tz=tzone1)

  tzone2 <- "Europe/Moscow"
  start.time2 <- ymd_hms("2019-04-13 01:00:00", tz=tzone2)
  end.time2 <- ymd_hms('2019-04-13 01:14:59', tz=tzone2)


  expected_data2 <- bitstamp_btcusd_depth %>% filter(timestamp >= start.time2 & timestamp < end.time2 )

  expected_data2$timestamp <- with_tz(expected_data2$timestamp, tz=tzone2)  # must be the same tzone as time zone of start.time2

  expected_queries <- data.frame(start.time=c(with_tz(start.time1, tz='UTC'),with_tz(start.time2, tz='UTC')),
                                 end.time = c(with_tz(end.time1, tz='UTC'),with_tz(end.time2, tz='UTC')),
                                 exchange=exchange, pair=pair)


  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock, {
    actual1 <- obadiah::depth(con,start.time1, end.time1, exchange, pair, cache = cache, tz=tzone1)
    actual2 <- obadiah::depth(con,start.time2, end.time2, exchange, pair, cache = cache, tz=tzone2)
    }
    )
  expect_true(empty(actual1))
  expect_equal(actual2, expected_data2)
  expect_equal(queries, expected_queries)
  })


test_that('two queries to RDBMS do not overlap when requested periods overlap',{
  # 1***
  #    2***

  eval(fixture)


  s1 <- ymd_hms("2019-04-13 01:00:10", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:10.1', tz="Europe/Moscow")  # to test that celing_date() is actually used by cache

  s2 <- ymd_hms('2019-04-13 01:14:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:15:59', tz="Europe/Moscow")



  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC'), with_tz(ceiling_date(e1), tz='UTC')),
                                  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),with_tz(e2, tz='UTC')),
                                  exchange = exchange,
                                  pair=pair)

  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      obadiah::depth(con,s1,e1, exchange, pair, cache = cache)
      obadiah::depth(con,s2,e2, exchange, pair, cache = cache)
    }
  )

  expect_equal(queries$start.time, expected_queries$start.time, info="Query: start.time")
  expect_equal(queries$end.time, expected_queries$end.time, info="Query: end.time")

  expect_equal(queries, expected_queries)

})


test_that('three queries to RDBMS do not overlap when requested periods overlap',{

  #   1***   2***
  #   3**********

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")


  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC'),with_tz(s2, tz='UTC'), with_tz(ceiling_date(e1), tz='UTC')),
                                  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),with_tz(e2, tz='UTC'), with_tz(s2, tz='UTC')),
                                  exchange = exchange,
                                  pair=pair)

  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      obadiah::depth(con,s1,e1, exchange, pair, cache = cache)
      obadiah::depth(con,s2,e2, exchange, pair, cache = cache)
      obadiah::depth(con,s1,e2, exchange, pair, cache = cache)

      # has to be served from cache (i.e. must not produce query)
      obadiah::depth(con,s1 + seconds(1),e2, exchange, pair, cache = cache)
    }
  )
  expect_equal(queries, expected_queries)


})



test_that('data returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")



  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      obadiah::depth(con,s1,e1, exchange, pair, cache = cache)
      obadiah::depth(con,s2,e2, exchange, pair, cache = cache)
      obadiah::depth(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obadiah::depth(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obadiah::depth(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(from_cache, from_rdbms)

})



test_that('cached periods are reported properly',{

  #   1***   2***
  #   3**********

  eval(fixture)

  s1 <- ymd_hms("2019-04-13 01:00:00", tz="Europe/Moscow")
  e1 <- ymd_hms('2019-04-13 01:15:00.1', tz="Europe/Moscow")

  s2 <- ymd_hms('2019-04-13 01:16:59', tz="Europe/Moscow")
  e2 <- ymd_hms('2019-04-13 01:17:59', tz="Europe/Moscow")



  with_mock(
    `obadiah::.starting_depth` = function(...) { data.frame() },
    `obadiah::.depth_changes` = .depth_changes_mock,
    {
      obadiah::depth(con,s1,e1, exchange, pair, cache = cache)
      actual1 <- getCachedPeriods(cache, exchange, pair, 'depth')
      obadiah::depth(con,s2,e2, exchange, pair, cache = cache)
      actual2 <- getCachedPeriods(cache, exchange, pair, 'depth')
      obadiah::depth(con,s1,e2, exchange, pair, cache = cache)
      actual3 <- getCachedPeriods(cache, exchange, pair, 'depth')
    }
  )
  expect_equal(actual1, data.frame(cached.period.start=c(with_tz(s1, tz='UTC')),
                                    cached.period.end=c(with_tz(ceiling_date(e1), tz='UTC')),
                                    cached.period.rows=as.integer(c(4872)))
                )
  expect_equal(actual2, data.frame(cached.period.start=c(with_tz(s1, tz='UTC'),with_tz(s2, tz='UTC')),
                                   cached.period.end=c(with_tz(ceiling_date(e1), tz='UTC'), with_tz(ceiling_date(e2), tz='UTC')),
                                   cached.period.rows=as.integer(c(4872, 294)))
  )

  expect_equal(actual3, data.frame(cached.period.start=c(with_tz(s1, tz='UTC')),
                                   cached.period.end=c(with_tz(ceiling_date(e2), tz='UTC')),
                                   cached.period.rows=as.integer(c(5999)))
  )

})
