setup({
   flog.threshold(futile.logger::DEBUG, 'obadiah')
   flog.appender(appender.file('test_cache_other.log'), name='obadiah')
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
    `obadiah::.events` = .rdbms_query_mock,
    {
      obadiah::events(con,s1,e1, exchange, pair, cache = cache)
      obadiah::events(con,s2,e2, exchange, pair, cache = cache)
      obadiah::events(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obadiah::events(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obadiah::events(con,s1,e2, exchange, pair)  # i.e. without cache
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
    `obadiah::.trades` = .rdbms_query_mock,
    {
      obadiah::trades(con,s1,e1, exchange, pair, cache = cache)
      obadiah::trades(con,s2,e2, exchange, pair, cache = cache)
      obadiah::trades(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obadiah::trades(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obadiah::trades(con,s1,e2, exchange, pair)  # i.e. without cache
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
    `obadiah::.spread` = .rdbms_query_mock,
    {
      obadiah::spread(con,s1,e1, exchange, pair, cache = cache)
      obadiah::spread(con,s2,e2, exchange, pair, cache = cache)
      obadiah::spread(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obadiah::spread(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obadiah::spread(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})




context("Depth summary cache")


test_that('depth_summary returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  data <- 'bitstamp_btcusd_depth_summary'

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
    `obadiah::.depth_summary` = .rdbms_query_mock,
    {
      obadiah::depth_summary(con,s1,e1, exchange, pair, cache = cache)
      obadiah::depth_summary(con,s2,e2, exchange, pair, cache = cache)
      obadiah::depth_summary(con,s1,e2, exchange, pair, cache = cache)

      from_cache <- obadiah::depth_summary(con,s1,e2, exchange, pair, cache = cache)
      from_rdbms <- obadiah::depth_summary(con,s1,e2, exchange, pair)  # i.e. without cache
    }
  )
  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})


context("Draws cache")


test_that('draws returned from the cache and from RDBMS are the same',{

  #   1***   2***
  #   3**********

  data <- 'bitstamp_btcusd_draws_mid_price_2'

  eval(fixture)

  s1 <- ymd_hms("2019-04-12 21:00:00", tz="UTC")
  e1 <- ymd_hms('2019-04-12 21:11:00', tz="UTC")

  s2 <- ymd_hms('2019-04-12 21:16:59', tz="UTC")
  e2 <- ymd_hms('2019-04-12 21:17:59', tz="UTC")


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
    `obadiah::.draws` = .rdbms_query_mock,
    {
      obadiah::draws(con,s1,e1, exchange, pair, 2, 'mid-price', cache = cache)
      obadiah::draws(con,s2,e2, exchange, pair, 2, 'mid-price', cache = cache)
      obadiah::draws(con,s1,e2, exchange, pair, 2, 'mid-price', cache = cache)

      from_cache <- obadiah::draws(con,s1,e2,exchange, pair,2, 'mid-price', cache = cache)
      from_rdbms <- obadiah::draws(con,s1,e2,exchange, pair,2, 'mid-price' )  # i.e. without cache
    }
  )

  expect_equal(queries, expected_queries)
  expect_equal(from_cache$timestamp, from_rdbms$timestamp)
  expect_equal(from_cache, from_rdbms)

})


test_that('different draw type is queried from RDBMS',{

  #   1***   mid-price minimal.draw = 2
  #   2***   mid-price minimal.draw = 3
  #   3***   bid minimal.draw = 3

  data <- 'bitstamp_btcusd_draws_mid_price_2'

  eval(fixture)

  s1 <- ymd_hms("2019-04-12 21:00:00", tz="UTC")
  e1 <- ymd_hms('2019-04-12 21:11:00', tz="UTC")


  # internally all time objects have to be explicitly converted to UTC
  expected_queries  <- data.frame(start.time = c(with_tz(s1, tz='UTC') - seconds(10),
                                                 with_tz(s1, tz='UTC') - seconds(10),
                                                 with_tz(s1, tz='UTC') - seconds(10) ),
                                  end.time=c(with_tz(ceiling_date(e1), tz='UTC'),
                                             with_tz(ceiling_date(e1), tz='UTC'),
                                             with_tz(ceiling_date(e1), tz='UTC') ),
                                  exchange = exchange,
                                  pair=pair)


  with_mock(
    `obadiah::.draws` = .rdbms_query_mock,
    {
      obadiah::draws(con,s1,e1, exchange, pair, 2, 'mid-price', cache = cache)
      obadiah::draws(con,s1,e1, exchange, pair, 3, 'mid-price', cache = cache)
      obadiah::draws(con,s1,e1, exchange, pair, 3, 'bid', cache = cache)
    }
  )
  expect_equal(queries, expected_queries)

})





