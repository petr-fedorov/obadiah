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

#ifndef LEVEL1_H
#define LEVEL1_H
#include <locale>  // must be before postgres.h to fix /usr/include/libintl.h:39:14: error: expected unqualified-id before ‘const’ error
#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "postgres.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "funcapi.h"
#include "utils/timestamp.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

#include "obadiah_db.h"

namespace obad {
struct level1 {
 price best_bid_price;
 amount best_bid_qty;
 price best_ask_price;
 amount best_ask_qty;
 TimestampTz microtimestamp;

 level1()
     : best_bid_price(-1),
       best_bid_qty(-1),
       best_ask_price(-1),
       best_ask_qty(-1),
       microtimestamp(0){};

 level1(price bbp, amount bbq, price bap, amount baq, TimestampTz m)
     : best_bid_price(bbp),
       best_bid_qty(bbq),
       best_ask_price(bap),
       best_ask_qty(baq),
       microtimestamp(m){};
 HeapTuple to_heap_tuple(AttInMetadata *, int32, int32);

 bool operator==(const level1 &c) {
  return (best_bid_price == c.best_bid_price) &&
         (best_bid_qty == c.best_bid_qty) &&
         (best_ask_price == c.best_ask_price) &&
         (best_ask_qty == c.best_ask_qty);
 };
 bool operator!=(const level1 &c) { return !(*this == c); };
};
}  // namespace obad
#endif
