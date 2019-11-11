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
#include "catalog/pg_type_d.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "funcapi.h"
#include "postgres.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(depth_change_by_episode4);
PG_FUNCTION_INFO_V1(spread_by_episode);

#ifdef __cplusplus
}
#endif  // __cplusplus

#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include "depth.h"
#include "level2.h"
#include "level2episode.h"
#include "level3.h"
#include "level3episode.h"
#include "order_book.h"
#include "spi_allocator.h"

namespace obad {

struct multi_call_context : public obad::postgres_heap {
 multi_call_context() : d(nullptr), l2_result_set(nullptr) {
  l3 = new (allocation_mode::non_spi) obad::level3_episode{};
  ob = new (allocation_mode::non_spi) obad::order_book{};
  l2_result_set =
      new (palloc(sizeof(obad::deque<level2>))) obad::deque<level2>{};
 };

 ~multi_call_context() {
  if (l3) delete l3;
  if (ob) delete ob;
  if (l2_result_set) {
   l2_result_set->~deque();
   pfree(l2_result_set);
  }
 };

 obad::level3_episode *l3;
 obad::order_book *ob;
 obad::level2_episode *l2;
 obad::depth *d;
 obad::deque<obad::level2> *l2_result_set;
};
}  // namespace obad

Datum
depth_change_by_episode4(PG_FUNCTION_ARGS) {
 using namespace std;
 using namespace obad;

 FuncCallContext *funcctx;
 TupleDesc tupdesc;
 AttInMetadata *attinmeta;

 if (SRF_IS_FIRSTCALL()) {
  MemoryContext oldcontext;

  funcctx = SRF_FIRSTCALL_INIT();

  oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

  if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
   ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                   errmsg("function returning record called in context "
                          "that cannot accept type record")));
  if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2) || PG_ARGISNULL(3))
   ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
                   errmsg("p_start_time, p_end_time, pair_id, exchange_id must "
                          "not be NULL")));
#if DEBUG_DEPTH
  string p_start_time{timestamptz_to_str(PG_GETARG_TIMESTAMPTZ(0))};
  string p_end_time{timestamptz_to_str(PG_GETARG_TIMESTAMPTZ(1))};
  elog(DEBUG1, "depth_change_by_episode(%s, %s, %i, %i)", p_start_time.c_str(),
       p_end_time.c_str(), PG_GETARG_INT32(2), PG_GETARG_INT32(3));
#endif  // DEBUG_DEPTH
  attinmeta = TupleDescGetAttInMetadata(tupdesc);
  funcctx->attinmeta = attinmeta;
  multi_call_context *d = new (allocation_mode::non_spi) multi_call_context;

  Datum frequency = obad::NULL_FREQ;
  if (!PG_ARGISNULL(4)) frequency = PG_GETARG_DATUM(4);

  d->ob->update(
      d->l3->initial(PG_GETARG_DATUM(0), PG_GETARG_DATUM(1), PG_GETARG_DATUM(2),
                     PG_GETARG_DATUM(3), frequency),
      nullptr);  // nullptr == disard level2's generated

  funcctx->user_fctx = d;

  MemoryContextSwitchTo(oldcontext);
 }

 funcctx = SRF_PERCALL_SETUP();

 MemoryContext oldcontext;
 oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

 multi_call_context *d = static_cast<multi_call_context *>(funcctx->user_fctx);
 attinmeta = funcctx->attinmeta;
 try {
  if (d->l2_result_set->empty()) {
   while (true) {  // it is possible that some level3 episodes will not generate
                   // level2 changes. We'll skip them
    d->ob->update(d->l3->next(), d->l2_result_set);
    if (d->l2_result_set->empty()) {
#if DEBUG_DEPTH
     elog(DEBUG2,
          "%s got an empty leve2 result set, proceed to the next episode ...",
          __PRETTY_FUNCTION__);
#endif
    } else {
#if DEBUG_DEPTH
     elog(DEBUG2, "%s got a new level2 result set with %lu level2 records",
          __PRETTY_FUNCTION__, d->l2_result_set->size());
#endif
     break;
    }
   }
  }

  level2 result{std::move(d->l2_result_set->front())};
  d->l2_result_set->pop_front();

#if DEBUG_DEPTH
  elog(DEBUG3, "%s will return %s, remains %lu", __PRETTY_FUNCTION__,
       to_string<level2>(result).c_str(), d->l2_result_set->size());
#endif

  MemoryContextSwitchTo(oldcontext);

  HeapTuple tuple_out =
      result.to_heap_tuple(attinmeta, PG_GETARG_INT32(2), PG_GETARG_INT32(3));
  SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple_out));
 } catch (...) {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s ends", __PRETTY_FUNCTION__);
#endif
  MemoryContextSwitchTo(oldcontext);
  delete d;

  SRF_RETURN_DONE(funcctx);
 }
}
Datum
spread_by_episode(PG_FUNCTION_ARGS) {
 FuncCallContext *funcctx;
 TupleDesc tupdesc;
 AttInMetadata *attinmeta;
 MemoryContext oldcontext;
 obad::depth *d;

 if (SRF_IS_FIRSTCALL()) {
  funcctx = SRF_FIRSTCALL_INIT();

  oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
  d = new (obad::allocation_mode::non_spi) obad::depth();
  funcctx->user_fctx = d;

  if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
   ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                   errmsg("function returning record called in context "
                          "that cannot accept type record")));
  attinmeta = TupleDescGetAttInMetadata(tupdesc);
  funcctx->attinmeta = attinmeta;

  Datum frequency = obad::NULL_FREQ;
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
 } catch (...) {
  episode.done();
  SPI_finish();
  MemoryContextSwitchTo(oldcontext);
  delete d;
  SRF_RETURN_DONE(funcctx);
 }
}
