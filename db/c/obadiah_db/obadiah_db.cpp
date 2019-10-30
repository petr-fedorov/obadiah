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

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus
#include "postgres.h"
#include "utils/timestamp.h"
#include "utils/numeric.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "catalog/pg_type_d.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(depth_change_by_episode);
PG_FUNCTION_INFO_V1(spread_by_episode);

#ifdef __cplusplus
}
#endif  // __cplusplus

#include <vector>
#include <string>
#include <map>
#include <set>
#include <sstream>
#include "spi_allocator.h"
#include "spread.h"

namespace obad {

using namespace std;

using spi_string = basic_string<char, char_traits<char>, spi_allocator<char>>;

template <class Key, class T, class Compare = less<Key>>
using spi_map = map<Key, T, Compare, spi_allocator<pair<const Key, T>>>;

template <class T>
using spi_vector = vector<T, spi_allocator<T>>;

struct level3 {
  TimestampTz microtimestamp;
  int64 order_id;
  int32 event_no;
  char side;
  spi_string price_str;
  spi_string amount_str;
  long double amount;
  TimestampTz price_microtimestamp;
  spi_string next_microtimestamp;

  unsigned long episode_seq_no;

  level3() {};

  level3(HeapTuple tuple, TupleDesc tupdesc) noexcept
      : price_str(SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "price"))),
        amount_str(SPI_getvalue(tuple, tupdesc,
                                SPI_fnumber(tupdesc, "amount"))),
        next_microtimestamp(SPI_getvalue(tuple, tupdesc,
                                         SPI_fnumber(tupdesc,
                                                     "next_microtimestamp"))) {
    bool is_null;
    Datum value;
    value = SPI_getbinval(tuple, tupdesc,
                          SPI_fnumber(tupdesc, "microtimestamp"), &is_null);
    if (!is_null) microtimestamp = DatumGetTimestampTz(value);

    value = SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "order_id"),
                          &is_null);
    if (!is_null) order_id = DatumGetInt64(value);

    value = SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "event_no"),
                          &is_null);
    if (!is_null) event_no = DatumGetInt32(value);

    side = SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "side"))[0];

    value = SPI_getbinval(
        tuple, tupdesc, SPI_fnumber(tupdesc, "price_microtimestamp"), &is_null);
    if (!is_null) price_microtimestamp = DatumGetTimestampTz(value);
    try {
      amount = stold(string{amount_str.c_str()});
    }
    catch (...) {
      elog(ERROR, "Couldn't convert amount %s", amount_str.c_str());
      amount = 0;
    }
    // elog(DEBUG1, "%s %Lf", amount_str.c_str(), amount);
  };

  level3(const level3 &e)
      : microtimestamp(e.microtimestamp),
        order_id(e.order_id),
        event_no(e.event_no),
        side(e.side),
        price_str(e.price_str),
        amount_str(e.amount_str),
        amount(e.amount),
        price_microtimestamp(e.price_microtimestamp),
        next_microtimestamp(e.next_microtimestamp),
        episode_seq_no(e.episode_seq_no) {};

  bool is_order_deleted() {
    return next_microtimestamp.compare("-infinity") == 0;
  }

  string __str__() const {
    stringstream stream;
    stream << "level3: " << timestamptz_to_str(microtimestamp) << " "
           << order_id << " " << event_no << " " << side << " " << price_str
           << " " << amount_str << " " << amount << " " << next_microtimestamp;
    return stream.str();
  }
};

struct level3_compare {
  bool operator()(const level3 *x, const level3 *y) const {
    if (x->price_microtimestamp != y->price_microtimestamp)
      return x->price_microtimestamp < y->price_microtimestamp;
    else if (x->microtimestamp != y->microtimestamp)
      return x->microtimestamp < y->microtimestamp;
    else
      return x->episode_seq_no < y->episode_seq_no;
  }
};

using same_price_level3 =
    set<level3 *, level3_compare, spi_allocator<level3 *>>;

struct price_level {
  long double bid;
  long double ask;

  price_level() : bid(-1), ask(-1) {};
};

struct order_book {
  order_book() : precision("r0"), episode_ts(0), episode_seq_no(0) {};

  price_level get_price_level(const string &price) noexcept {
    spi_string price_str{price.c_str()};
    price_level level{};
    for (auto event : by_price[price_str]) {
      if (event->side == 'b')
        if (level.bid > 0)
          level.bid += event->amount;
        else
          level.bid = event->amount;
      else if (level.ask > 0)
        level.ask += event->amount;
      else
        level.ask = event->amount;
    }
#if ELOGS
    elog(DEBUG2, "get_price_level(%s) returns (bid %Lf,  ask %Lf)",
         price_str.c_str(), level.bid, level.ask);
#endif

    return level;
  }

  inline void append_level3_to_episode(level3 &event) {
    event.episode_seq_no = episode_seq_no++;
    episode.push_back(event);
#if ELOGS
    elog(DEBUG3, "Added to episode %s, episode.size() %lu",
         event.__str__().c_str(), episode.size());
#endif  // ELOGS

    // level3 &inserted {by_order_id[event.order_id] = event};
    // by_price[event.price_str].insert(&inserted);
  }

  string end_episode() noexcept {
#if ELOGS
    elog(DEBUG2, "Ending episode %s", timestamptz_to_str(episode_ts));
    elog(DEBUG2, "get_price_level() before ...");
#endif
    map<string, price_level> depth_before{};

    for (auto &event : episode) {
      set<string> changed_prices{};
      changed_prices.insert(event.price_str.c_str());
      level3 *previous_event = nullptr;

      if (event.event_no > 1) {
        try {
          previous_event = &(by_order_id.at(event.order_id));
          changed_prices.insert(previous_event->price_str.c_str());
        }
        catch (...) {
#if ELOGS
          elog(DEBUG3, "No previous event for %s %lu %i",
               timestamptz_to_str(event.microtimestamp), event.order_id,
               event.event_no);
#endif
        };
      }

      for (auto price : changed_prices) {
        if (depth_before.find(price) == depth_before.end())
          depth_before[price] = get_price_level(price);
      }

      if (previous_event) {
#if ELOGS
        elog(DEBUG3, "OB deleted %s %lu %i %s",
             timestamptz_to_str(previous_event->microtimestamp),
             previous_event->order_id, previous_event->event_no,
             previous_event->price_str.c_str());
#endif
        by_price[previous_event->price_str].erase(previous_event);
        by_order_id.erase(previous_event->order_id);
      }
      if (!event.is_order_deleted()) {
        same_price_level3 &price_level = by_price[event.price_str];
        pair<same_price_level3::iterator, bool> result =
            price_level.insert(&(by_order_id[event.order_id] = event));
#if ELOGS
        if (!result.second) {
          elog(WARNING,
               "OB NOT added %s %lu %i %s. Events at the price_level: %lu",
               timestamptz_to_str(event.microtimestamp), event.order_id,
               event.event_no, event.price_str.c_str(), price_level.size());
          level3 *ptr = *result.first;
          elog(WARNING, "OB already there: %s %lu %i %s",
               timestamptz_to_str(ptr->microtimestamp), ptr->order_id,
               ptr->event_no, ptr->price_str.c_str());
        } else
          elog(DEBUG3, "OB added %s %lu %i %s. Events at the price_level: %lu",
               timestamptz_to_str(event.microtimestamp), event.order_id,
               event.event_no, event.price_str.c_str(), price_level.size());
#endif
      }
    }

    string depth_change_builder{"{"};
#if ELOGS
    elog(DEBUG2, "get_price_level() after ...");
#endif
    const int BUFFER_SIZE = 50;
    char buffer[BUFFER_SIZE];
    for (auto &depth : depth_before) {
      price_level after = get_price_level(depth.first);

      if (after.bid != depth.second.bid) {
        if (depth_change_builder.size() > 1) depth_change_builder.append(",");
        if (after.bid > 0)
          snprintf(buffer, BUFFER_SIZE, "%.8LF",
                   after.bid);  // amount = to_string(after.bid).c_str();
        else
          snprintf(buffer, BUFFER_SIZE, "%.8LF",
                   0.0L);  // amount = to_string(after.bid).c_str();
        depth_change_builder.append("\"(");
        depth_change_builder.append(depth.first);
        depth_change_builder.append(",");
        depth_change_builder.append(buffer);
        depth_change_builder.append(",b,)\"");
      }
      if (after.ask != depth.second.ask) {
        if (depth_change_builder.size() > 1) depth_change_builder.append(",");
        // const char *amount;
        if (after.ask > 0)  // amount = to_string(after.ask).c_str();
          snprintf(buffer, BUFFER_SIZE, "%.8LF",
                   after.ask);  // amount = to_string(after.bid).c_str();
        else  // amount = "0";
          snprintf(buffer, BUFFER_SIZE, "%.8LF",
                   0.0L);  // amount = to_string(after.bid).c_str();
        depth_change_builder.append("\"(");
        depth_change_builder.append(depth.first);
        depth_change_builder.append(",");
        depth_change_builder.append(buffer);
        depth_change_builder.append(",s,)\"");
      }
    }
    depth_change_builder.append("}");

    episode.clear();
    episode_seq_no = 0;
#if ELOGS
    elog(DEBUG1, "Ended episode %s", timestamptz_to_str(episode_ts));
    elog(DEBUG2, "Depth change: %s", depth_change_builder.c_str());
#endif

    return depth_change_builder;
  };

  spi_string &get_precision() { return precision; }

  spi_string precision;

  // map<int64, level3, less<int64>, spi_allocator<level3>> by_order_id;
  spi_map<int64, level3> by_order_id;
  spi_map<spi_string, same_price_level3> by_price;
  spi_vector<level3> episode;
  TimestampTz episode_ts;
  spi_string previous_depth_change;

  unsigned long episode_seq_no;
};
}

Datum depth_change_by_episode(PG_FUNCTION_ARGS) {
  using namespace std;
  using namespace obad;

  FuncCallContext *funcctx;
  TupleDesc tupdesc;
  AttInMetadata *attinmeta;

  TimestampTz episode_microtimestamp{0};

  if (SRF_IS_FIRSTCALL()) {
    MemoryContext oldcontext;

    funcctx = SRF_FIRSTCALL_INIT();

    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
      ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                      errmsg(
                          "function returning record called in context "
                          "that cannot accept type record")));
    if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2) ||
        PG_ARGISNULL(3))
      ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
                      errmsg(
                          "p_start_time, p_end_time, pair_id, exchange_id must "
                          "not be NULL")));
#if ELOGS
    string p_start_time{timestamptz_to_str(PG_GETARG_TIMESTAMPTZ(0))};
    string p_end_time{timestamptz_to_str(PG_GETARG_TIMESTAMPTZ(1))};
    elog(DEBUG1, "depth_change_by_episode(%s, %s, %i, %i)",
         p_start_time.c_str(), p_end_time.c_str(), PG_GETARG_INT32(2),
         PG_GETARG_INT32(3));
#endif  // ELOGS
    attinmeta = TupleDescGetAttInMetadata(tupdesc);
    funcctx->attinmeta = attinmeta;

    SPI_connect();
    funcctx->user_fctx =
        new ((order_book *)SPI_palloc(sizeof(order_book))) order_book{};

    Oid types[5];
    types[0] = TIMESTAMPTZOID;
    types[1] = INT4OID;
    types[2] = INT4OID;

    Datum values[5];
    values[0] = PG_GETARG_TIMESTAMPTZ(0);
    values[1] = PG_GETARG_INT32(2);
    values[2] = PG_GETARG_INT32(3);

    SPI_execute_with_args(
        "select ts, ob.* from obanalytics.order_book($1, $2, $3, false, true, "
        "false) join unnest(ob) ob on true order by price",
        3, types, values, NULL, true, 0);

    if (SPI_processed > 0 && SPI_tuptable != NULL) {
      order_book *current_depth = (order_book *)funcctx->user_fctx;
      for (uint64 j = 0; j < SPI_processed; j++) {
        level3 event{SPI_tuptable->vals[j], SPI_tuptable->tupdesc};
        current_depth->append_level3_to_episode(event);
      }
      bool is_null;
      Datum value;
      value = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc,
                            SPI_fnumber(SPI_tuptable->tupdesc, "ts"), &is_null);
      if (!is_null) current_depth->episode_ts = DatumGetTimestampTz(value);
      current_depth->end_episode();

      current_depth->episode_ts = 0;
    }

    types[0] = TIMESTAMPTZOID;
    types[1] = TIMESTAMPTZOID;
    types[2] = INT4OID;
    types[3] = INT4OID;

    values[0] = PG_GETARG_TIMESTAMPTZ(0);
    values[1] = PG_GETARG_TIMESTAMPTZ(1);
    values[2] = PG_GETARG_INT32(2);
    values[3] = PG_GETARG_INT32(3);

    if (PG_ARGISNULL(4)) {
      SPI_cursor_open_with_args(
          "level3",
          "select microtimestamp, order_id, event_no, side,\
                                                      price, amount, next_microtimestamp, price_microtimestamp\
                                               from obanalytics.level3\
                                               where microtimestamp between $1 and $2\
                                                 and pair_id = $3\
                                                 and exchange_id = $4\
                                               order by microtimestamp, order_id, event_no",
          4, types, values, NULL, true, 0);
    } else {
      types[4] = INTERVALOID;
      values[4] = PG_GETARG_DATUM(4);
      SPI_cursor_open_with_args(
          "level3",
          "select get._date_ceiling(microtimestamp, $5) as microtimestamp,\
                                                      order_id, event_no, side, price, amount,\
								     	get._date_ceiling(next_microtimestamp, $5) as next_microtimestamp,\
								      get._date_ceiling(price_microtimestamp, $5) as price_microtimestamp\
                                               from obanalytics.level3\
                                               where microtimestamp between $1 and $2\
                                                 and pair_id = $3\
                                                 and exchange_id = $4\
                                               order by level3.microtimestamp, order_id, event_no",
          5, types, values, NULL, true, 0);
    }

    SPI_finish();
    MemoryContextSwitchTo(oldcontext);
  }

  funcctx = SRF_PERCALL_SETUP();

  MemoryContext oldcontext;
  oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

  attinmeta = funcctx->attinmeta;
  order_book *current_depth = (order_book *)funcctx->user_fctx;

  SPI_connect();
  Portal portal = SPI_cursor_find("level3");

  SPI_cursor_fetch(portal, true, 1);

  string depth_change{"{}"};
  bool is_done = true;

  while (SPI_processed == 1 && SPI_tuptable != NULL) {

    level3 event{SPI_tuptable->vals[0], SPI_tuptable->tupdesc};

    if (episode_microtimestamp == 0) {
      if (current_depth->episode_ts != 0)
        episode_microtimestamp = current_depth->episode_ts;
      else {
        episode_microtimestamp = event.microtimestamp;
        current_depth->episode_ts = event.microtimestamp;
      }
    }

    if (episode_microtimestamp ==
        event.microtimestamp) {  // Continue accumulation of events for the
                                 // current episode
      current_depth->append_level3_to_episode(event);
    } else {
      depth_change = current_depth->end_episode();
      current_depth->episode_ts = event.microtimestamp;
      current_depth->append_level3_to_episode(event);
      is_done = false;
      break;
    }
    SPI_cursor_fetch(portal, true, 1);
  }

  if (is_done && current_depth->episode.size() > 0) {  // The last episode
    depth_change = current_depth->end_episode();
    episode_microtimestamp = current_depth->episode_ts;
    is_done = false;
#if ELOGS
    elog(DEBUG1, "The last episode ended");
#endif  // ELOGS
  }

  if (!is_done) {
    SPI_finish();
    MemoryContextSwitchTo(oldcontext);

    char **values = (char **)palloc(
        5 * sizeof(char *));  // obanalytics.level2 has 5 columns

    string microtimestamp{timestamptz_to_str(episode_microtimestamp)};
    string pair_id(to_string(PG_GETARG_INT32(2)));
    string exchange_id{to_string(PG_GETARG_INT32(3))};

    values[0] = (char *)palloc(sizeof(char) * (microtimestamp.size() + 1));
    strcpy(values[0], microtimestamp.c_str());
    values[1] = (char *)palloc(sizeof(char) * (pair_id.size() + 1));
    strcpy(values[1], pair_id.c_str());
    values[2] = (char *)palloc(sizeof(char) * (exchange_id.size() + 1));
    strcpy(values[2], exchange_id.c_str());
    values[3] = (char *)palloc(sizeof(char) *
                               (current_depth->get_precision().size() + 1));
    strcpy(values[3], current_depth->get_precision().c_str());
    values[4] = (char *)palloc(sizeof(char) * (depth_change.size() + 1));
    strcpy(values[4], depth_change.c_str());
#if ELOGS
    elog(DEBUG2, "BuildTupleFromCStrings:  %s %s %s %s %s", values[0],
         values[1], values[2], values[3], values[4]);
#endif

    HeapTuple tuple_out = BuildTupleFromCStrings(attinmeta, values);
    Datum result = HeapTupleGetDatum(tuple_out);

    SRF_RETURN_NEXT(funcctx, result);
  }

#if ELOGS
  elog(DEBUG1, "End!");
#endif
  SPI_cursor_close(SPI_cursor_find("level3"));
  current_depth->~order_book();
  SPI_pfree(current_depth);
  SPI_finish();
  MemoryContextSwitchTo(oldcontext);
  SRF_RETURN_DONE(funcctx);
}

Datum spread_by_episode(PG_FUNCTION_ARGS) {
  FuncCallContext *funcctx;
  TupleDesc tupdesc;
  AttInMetadata *attinmeta;
  MemoryContext oldcontext;
  obad::depth *d;

  if (SRF_IS_FIRSTCALL()) {

    funcctx = SRF_FIRSTCALL_INIT();

    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
    d = new obad::depth();
    funcctx->user_fctx = d;

    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
      ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                      errmsg(
                          "function returning record called in context "
                          "that cannot accept type record")));
    attinmeta = TupleDescGetAttInMetadata(tupdesc);
    funcctx->attinmeta = attinmeta;

    Datum frequency = obad::level2_episode::NULL_FREQ;
    if (!PG_ARGISNULL(4)) frequency = PG_GETARG_DATUM(4);

    SPI_connect();
    obad::level2_episode episode{PG_GETARG_DATUM(0), PG_GETARG_DATUM(1),
                                 PG_GETARG_DATUM(2), PG_GETARG_DATUM(3),
                                 frequency};
    d->update(episode.initial());
    SPI_finish();

    MemoryContextSwitchTo(oldcontext);
  }

  funcctx = SRF_PERCALL_SETUP();
  d = static_cast<obad::depth *>(funcctx->user_fctx);

  oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
  SPI_connect();

  obad::level2_episode episode{};
  try {
    obad::level1 previous{d->spread()};
    obad::level1 next{};
    do {
      next = d->update(episode.next());
    } while (previous == next);

    SPI_finish();
    MemoryContextSwitchTo(oldcontext);

    SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(next.to_heap_tuple(
                                 funcctx->attinmeta, PG_GETARG_INT32(2),
                                 PG_GETARG_INT32(3))));
  }
  catch (...) {
    episode.done();
    SPI_finish();
    MemoryContextSwitchTo(oldcontext);
    delete d;
    SRF_RETURN_DONE(funcctx);
  }
}
