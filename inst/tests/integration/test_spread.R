# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

context("Spread integration testing")

setup({
  futile.logger::flog.appender(futile.logger::appender.file('test_spread.log'), name='obadiah')
  futile.logger::flog.threshold(futile.logger::DEBUG, 'obadiah')
})

teardown({
  futile.logger::flog.appender(NULL, name='obadiah')
})

test_that('Bitstamp, btcusd, a full short era, all data',{

  skip_if_not(BITSTAMP)
  skip_if_not(SHORT)
  skip_if(SINGLE)

  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)

  exchange <- 'bitstamp'
  pair <- 'btcusd'


  start.time <- '2019-11-12 10:39:23.162505+03'
  end.time <- '2019-11-12 12:28:04.734674+03'

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})

test_that('Bitstamp, btcusd, a full short era, every 5 seconds',{

  skip_if_not(BITSTAMP)
  skip_if_not(SHORT)
  skip_if(SINGLE)

  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)

  exchange <- 'bitstamp'
  pair <- 'btcusd'


  start.time <- '2019-11-12 10:39:23.162505+03'
  end.time <- '2019-11-12 12:28:04.734674+03'
  frequency <- 5

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair, frequency = frequency)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair, frequency = frequency)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})



test_that('Bitstamp, btcusd, across of one era boundary, all data',{

  skip_if_not(BITSTAMP)
  skip_if_not(SHORT)
  skip_if(SINGLE)

  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)

  exchange <- 'bitstamp'
  pair <- 'btcusd'


  start.time <- '2019-11-14 01:47:24.997861+03'
  end.time <- '2019-11-14 04:53:02.600933+03'

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})



test_that('Bitstamp, btcusd, across of two era boundaries, all data',{

  skip_if_not(BITSTAMP)
  skip_if_not(LONG)
  skip_if(SINGLE)

  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)

  exchange <- 'bitstamp'
  pair <- 'btcusd'


  start.time <- '2019-11-14 01:47:24.997861+03'
  end.time <- '2019-11-15 11:28:02.276231+03'

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})



test_that('Bitfinex, ethusd, a full short era, all data',{

  skip_if_not(BITFINEX)
  skip_if_not(SHORT)
  skip_if(SINGLE)


  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)
  exchange <- 'bitfinex'
  pair <- 'ethusd'


  start.time <- '2019-11-22 07:07:20.456+03'
  end.time <- '2019-11-22 09:14:05.274+03'

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})


test_that('Bitfinex, ethusd, a full short era, 10 seconds',{

  skip_if_not(BITFINEX)
  skip_if_not(SHORT)
  skip_if(SINGLE)


  config <- config::get()
  db <- obadiah::connect(user=config$user,dbname=config$dbname, host=config$host,port=config$port, sslrootcert=config$sslrootcert, sslcert=config$sslcert,sslkey=config$sslkey)
  exchange <- 'bitfinex'
  pair <- 'ethusd'
  frequency <- 10


  start.time <- '2019-11-22 07:07:20.456+03'
  end.time <- '2019-11-22 09:14:05.274+03'

  depth <- obadiah::depth(db, start.time, end.time, exchange, pair, frequency=frequency)

  spread_cpp <- obadiah::spread(depth)
  spread_sql <- obadiah::spread(db, start.time, end.time, exchange, pair, frequency=frequency)

  expect_equal(spread_cpp,spread_sql)

  obadiah::disconnect(db)

})

