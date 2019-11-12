// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 2 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#include "episode.h"
#include <vector>
#include "obadiah_db.h"

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

namespace obad {
const char *const episode::CURSOR = "level3";
const int episode::SPI_CURSOR_FETCH_COUNT = 1000;

episode::~episode() {
 SPI_connect();
 SPI_cursor_close(SPI_cursor_find(CURSOR));
 SPI_finish();
 if (events_deque) {
  events_deque->~deque();
  pfree(events_deque);
 }
};

std::vector<level3>
episode::initial(Datum start_time, Datum end_time, Datum pair_id,
                        Datum exchange_id, Datum frequency) {
 SPI_connect();
 events_deque = new (SPI_palloc(sizeof(level3_deque))) level3_deque;
 Oid types[5];
 types[0] = TIMESTAMPTZOID;
 types[1] = INT4OID;
 types[2] = INT4OID;

 Datum values[5];
 values[0] = start_time;
 values[1] = pair_id;
 values[2] = exchange_id;

 SPI_execute_with_args(
     "select ts, ob.* from obanalytics.order_book($1, $2, $3, false, "
     "true, "
     "false) join unnest(ob) ob on true order by price",
     3, types, values, NULL, true, 0);

 std::vector<level3> result{};
#if DEBUG_DEPTH
 elog(DEBUG2, "%s initial order book: SPI_processed: %lu", __PRETTY_FUNCTION__,
      SPI_processed);
#endif
 if (SPI_processed > 0 && SPI_tuptable != NULL) {
  for (uint64 j = 0; j < SPI_processed; j++) {
   result.push_back(level3{SPI_tuptable->vals[j], SPI_tuptable->tupdesc});
  }
 }

 types[0] = TIMESTAMPTZOID;
 types[1] = TIMESTAMPTZOID;
 types[2] = INT4OID;
 types[3] = INT4OID;
 types[4] = INTERVALOID;

 values[0] = start_time;
 values[1] = end_time;
 values[2] = pair_id;
 values[3] = exchange_id;
 values[4] = frequency;

 char nulls[5] = {' ', ' ', ' ', ' ', ' '};
 if (frequency == obad::NULL_FREQ) nulls[4] = 'n';

 SPI_cursor_open_with_args(CURSOR, R"QUERY(
        select get._date_ceiling(microtimestamp, $5) as microtimestamp,
               order_id, event_no, side, price, amount,
								     	 get._date_ceiling(next_microtimestamp, $5) as next_microtimestamp,
								       get._date_ceiling(price_microtimestamp, $5) as price_microtimestamp
        from obanalytics.level3
        where microtimestamp between $1 and $2
          and pair_id = $3
          and exchange_id = $4
        order by level3.microtimestamp, order_id, event_no)QUERY",
                           5, types, values, nulls, true, 0);
 SPI_finish();
 return result;
};

std::vector<level3>
episode::next() {
 std::vector<level3> result{};
 TimestampTz current_episode = 0;

 while (true) {
  if (events_deque->empty()) {
   SPI_connect();
   SPI_cursor_fetch(SPI_cursor_find(CURSOR), true, SPI_CURSOR_FETCH_COUNT);
#if DEBUG_DEPTH
   elog(DEBUG2, "%s SPI_processed: %lu", __PRETTY_FUNCTION__, SPI_processed);
#endif
   if (SPI_processed > 0 && SPI_tuptable != NULL) {
    for (uint64 j = 0; j < SPI_processed; j++) {
     level3 a{SPI_tuptable->vals[j], SPI_tuptable->tupdesc};
     events_deque->push_back(std::move(a));
    }
   }
   SPI_finish();
  }

  if (events_deque->empty()) {
   if (result.empty()) {
#if DEBUG_DEPTH
    elog(DEBUG2, "%s ends - no more data available", __PRETTY_FUNCTION__);
#endif
    throw 0;  // No more data available
   } else {
#if DEBUG_DEPTH
    elog(DEBUG2, "%s returns episode %s with %lu last level3 records",
         __PRETTY_FUNCTION__, timestamptz_to_str(current_episode),
         result.size());
#endif
    return result;
   }
  } else {
   if (!current_episode) {
    current_episode = events_deque->front().get_microtimestamp();
   }
   while (!events_deque->empty()) {
    if (current_episode != events_deque->front().get_microtimestamp()) {
#if DEBUG_DEPTH
     elog(DEBUG2, "%s returns episode %s with %lu level3 records",
          __PRETTY_FUNCTION__, timestamptz_to_str(current_episode),
          result.size());
#endif
     return result;
    }
    result.push_back(std::move(events_deque->front()));
    events_deque->pop_front();
   }
  }
 }
};

void
episode::done() {
 SPI_connect();
 Portal portal = SPI_cursor_find(CURSOR);
 if (portal) SPI_cursor_close(portal);
 SPI_finish();
};
}  // namespace obad
