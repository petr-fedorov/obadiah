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

#include "level2episode.h"
#include "obadiah_db.h"

namespace obad {

const char *const level2_episode::INITIAL = "initial";
const char *const level2_episode::CURSOR = "level2";

void
level2_episode::done() {
 SPI_cursor_close(portal);
};

level2_episode::level2_episode(Datum start_time, Datum end_time, Datum pair_id,
                               Datum exchange_id, Datum frequency) {
 char nulls[5] = {' ', ' ', ' ', ' ', ' '};
 if (frequency == obad::NULL_FREQ) nulls[4] = 'n';

#if DEBUG_SPREAD
 std::string p_start_time{timestamptz_to_str(DatumGetTimestampTz(start_time))};
 std::string p_end_time{timestamptz_to_str(DatumGetTimestampTz(end_time))};
 std::string p_frequency{frequency == NULL_FREQ ? "NULL" : "Not NULL"};
 elog(DEBUG1, "spread_change_by_episode(%s, %s, %i, %i, %s)",
      p_start_time.c_str(), p_end_time.c_str(), DatumGetInt32(pair_id),
      DatumGetInt32(exchange_id), p_frequency.c_str());
#endif  // DEBUG_SPREAD

 Oid types[5];
 types[0] = TIMESTAMPTZOID;
 types[1] = INT4OID;
 types[2] = INT4OID;

 Datum values[5];
 values[0] = start_time;
 values[1] = pair_id;
 values[2] = exchange_id;
 portal = SPI_cursor_open_with_args(INITIAL, R"QUERY(
					  select  ts as microtimestamp, ob.price, ob.side, sum(ob.amount) as volume,
                    row_number() over (partition by ts order by price, side) as episode_seq_no,
                    count(*) over (partition by ts) as episode_size
					  from obanalytics.order_book($1, $2, $3, p_only_makers := false, p_before := true, p_check_takers := false) join unnest(ob) ob on true
					  group by 1,2,3
					  order by price
						)QUERY",
                                    4, types, values, NULL, true, 0);

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

 SPI_cursor_open_with_args(CURSOR, R"QUERY(
  select  microtimestamp, price, side, volume,
          row_number() over (partition by microtimestamp order by price, side) as episode_seq_no,
          count(*) over (partition by microtimestamp) as episode_size
  from obanalytics.depth_change_by_episode4($1, $2, $3, $4, $5)
  order by microtimestamp, price, side 
  )QUERY",
                           5, types, values, nulls, true, 0);
}

level2_episode::level2_episode() { portal = SPI_cursor_find(CURSOR); }

std::vector<level2>
level2_episode::next() {
 SPI_cursor_fetch(portal, true, 1);
 if (SPI_processed > 0) {
  bool is_null;
  Datum value = SPI_getbinval(
      SPI_tuptable->vals[0], SPI_tuptable->tupdesc,
      SPI_fnumber(SPI_tuptable->tupdesc, "episode_size"), &is_null);
  if (!is_null) {
   int64 episode_size = DatumGetInt64(value);
   std::vector<level2> result;
   result.reserve(episode_size);
#if DEBUG_SPREAD
   ereport(DEBUG1,
           (errmsg("episode microtimestamp=%s size=%lu",
                   SPI_getvalue(
                       SPI_tuptable->vals[0], SPI_tuptable->tupdesc,
                       SPI_fnumber(SPI_tuptable->tupdesc, "microtimestamp")),
                   episode_size)));
#endif
   result.push_back(level2{SPI_tuptable->vals[0], SPI_tuptable->tupdesc});
   if (episode_size > 1) {
    SPI_cursor_fetch(portal, true, episode_size - 1);
    for (uint64 j = 0; j < SPI_processed; j++)
     result.push_back(level2{SPI_tuptable->vals[j], SPI_tuptable->tupdesc});
   }
   return result;
  } else
   ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                   errmsg("Couldn't get episode_size")));
 } else
  throw 0;
}

std::vector<level2>
level2_episode::initial() {
 std::vector<level2> result;
 try {
  std::vector<level2> result{next()};
  SPI_cursor_close(portal);
  portal = nullptr;
  return result;
 } catch (...) {  // we are fine, if the initial episode is an empty one
  SPI_cursor_close(portal);
  portal = nullptr;
  return std::vector<level2>{};
 };
}
}  // namespace obad
