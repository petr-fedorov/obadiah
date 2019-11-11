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

#include "level1.h"

namespace obad {

HeapTuple
level1::to_heap_tuple(AttInMetadata *attinmeta, int32 pair_id,
                      int32 exchange_id) {
 char **values = (char **)palloc(7 * sizeof(char *));
 static const int BUFFER_SIZE = 128;
 if (best_bid_price > 0) {
  values[0] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[1] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  snprintf(values[0], BUFFER_SIZE, "%.5Lf", best_bid_price);
  snprintf(values[1], BUFFER_SIZE, "%.8Lf", best_bid_qty);
 } else {
  values[0] = nullptr;
  values[1] = nullptr;
 }
 if (best_ask_price > 0) {
  values[2] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[3] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  snprintf(values[2], BUFFER_SIZE, "%.5Lf", best_ask_price);
  snprintf(values[3], BUFFER_SIZE, "%.8Lf", best_ask_qty);
 } else {
  values[2] = nullptr;
  values[3] = nullptr;
 }
 values[4] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[5] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[6] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 snprintf(values[4], BUFFER_SIZE, "%s", timestamptz_to_str(microtimestamp));
 snprintf(values[5], BUFFER_SIZE, "%i", pair_id);
 snprintf(values[6], BUFFER_SIZE, "%i", exchange_id);
 HeapTuple tuple = BuildTupleFromCStrings(attinmeta, values);

 if (best_bid_price > 0) {
  pfree(values[0]);
  pfree(values[1]);
 }
 if (best_ask_price > 0) {
  pfree(values[2]);
  pfree(values[3]);
 }
 pfree(values[4]);
 pfree(values[5]);
 pfree(values[6]);
 pfree(values);
 return tuple;
};
}  // namespace obad
