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

context("Draws integration testing")

setup({
  futile.logger::flog.appender(futile.logger::appender.file('test_draws.log'), name='obadiah')
  futile.logger::flog.threshold(futile.logger::DEBUG, 'obadiah')
})

teardown({
  futile.logger::flog.appender(NULL, name='obadiah')
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

  spread <- obadiah::spread(db, start.time, end.time, exchange, pair)

  gamma_0 <- 0
  theta <- 0

  d_cpp <- obadiah::draws(spread, gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, gamma_0 = gamma_0, theta = theta)

  cols <- c("timestamp", "draw.end")

  expect_equal(d_cpp[, ..cols],d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))


  gamma_0 <- 10
  theta <- 0.0025

  d_cpp <- obadiah::draws(spread, gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, gamma_0 = gamma_0, theta = theta)

  expect_equal(d_cpp[, ..cols], d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))

  # bid
  d_cpp <- obadiah::draws(spread, draw.type = 'bid', gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, draw.type = 'bid', gamma_0 = gamma_0, theta = theta)

  expect_equal(d_cpp[, ..cols], d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))


  # ask
  d_cpp <- obadiah::draws(spread, draw.type = 'ask', gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, draw.type = 'ask', gamma_0 = gamma_0, theta = theta)


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


  start.time <- '2019-11-22 07:07:20.456+03'
  end.time <- '2019-11-22 09:14:05.274+03'
  frequency <- 10

  spread <- obadiah::spread(db, start.time, end.time, exchange, pair, frequency=frequency)

  gamma_0 <- 0
  theta <- 0

  d_cpp <- obadiah::draws(spread, gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, gamma_0 = gamma_0, theta = theta, frequency=frequency)

  cols <- c("timestamp", "draw.end")

  expect_equal(d_cpp[, ..cols],d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))


  gamma_0 <- 10
  theta <- 0.0025

  # mid-price
  d_cpp <- obadiah::draws(spread, gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, gamma_0 = gamma_0, theta = theta, frequency=frequency)

  expect_equal(d_cpp[, ..cols], d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))

  # bid
  d_cpp <- obadiah::draws(spread, draw.type = 'bid', gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, draw.type = 'bid', gamma_0 = gamma_0, theta = theta, frequency=frequency)

  expect_equal(d_cpp[, ..cols], d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))


  # ask
  d_cpp <- obadiah::draws(spread, draw.type = 'ask', gamma_0 = gamma_0, theta = theta)
  d_sql <- obadiah::draws(db, start.time, end.time, exchange, pair, draw.type = 'ask', gamma_0 = gamma_0, theta = theta, frequency=frequency)

  expect_equal(d_cpp[, ..cols], d_sql[, ..cols], info = paste0("gamma_0=", gamma_0, " theta=", theta))


  obadiah::disconnect(db)

})



