// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 1 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 01110-1301 USA.
#include <testthat.h>
#include "draw.h"
#include "log.h"

context("Test Type2Draw") {
 FILELog::ReportingLevel() = ldebug3;
 FILE* log_fd = fopen("test_obadiah_cpp.log", "a");
 Output2FILE::Stream() = log_fd;

 double min_draw = 0.01;    //
 double duration = 60;  //
 double tolerance = 0.5;         //
 double max_draw = 0.01;
 double timestamp[] = {0, 10, 20};
 double price[] = {100, 110, 90};
 obadiah::Type2Draw current_draw{timestamp[0],
                                  price[0],
                                  min_draw,
                                  duration,
                                  tolerance,
                                  max_draw};
 test_that(
     "a price change tolerance is not exceeded when direction of the draw has "
     "changed") {
  current_draw.extend(timestamp[1], price[1]);
  current_draw.extend(timestamp[2], price[2]);
  expect_false(current_draw.IsPriceChangeThresholdExceeded());
 }

 test_that(
     "a draw size tolerance is not exceeded when direction of the draw has "
     "changed") {
  current_draw.extend(timestamp[1], price[1]);
  current_draw.extend(timestamp[2], price[2]);
  expect_false(current_draw.IsDrawSizeToleranceExceeded());
 }
}
