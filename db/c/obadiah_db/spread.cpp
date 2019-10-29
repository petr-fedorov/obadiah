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
#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif  // __cplusplus
#include <string>
#include <sstream>
#include <iomanip>
#include <set>
#include "spread.h"
namespace obad {

class level2_impl {
 public:
  level2_impl(HeapTuple tuple, TupleDesc tupdesc);
  ~level2_impl();
  void *operator new(size_t s) {
    return SPI_palloc(s);
  };
  void operator delete(void *p, size_t s) {
    SPI_pfree(p);
  };

  bool operator<(const level2_impl &) const;

  std::string __str__() const {
    std::stringstream stream;
    stream << "level2: " << timestamptz_to_str(m) << " "
           << std::setprecision(15) << s << " " << p << " " << v;
    return stream.str();
  };

 private:
  price p;
  char s;
  amount v;
  TimestampTz m;
};

level2::level2(HeapTuple tuple, TupleDesc tupdesc) {
  p_impl = new level2_impl{tuple, tupdesc};
};

level2_impl::level2_impl(HeapTuple tuple, TupleDesc tupdesc) {
  p = strtold(SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "price")),
              nullptr);
  v = strtold(SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "volume")),
              nullptr);
  s = SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "side"))[0];
  bool is_null;
  Datum value = SPI_getbinval(tuple, tupdesc,
                              SPI_fnumber(tupdesc, "microtimestamp"), &is_null);
  if (!is_null)
    m = DatumGetTimestampTz(value);
  else
    ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                    errmsg("Couldn't get microtimestamp %Lf %Lf %c", p, v, s)));
#if ELOGS
  elog(DEBUG1, "Created level2_impl from HeapTuple %s", __str__().c_str());
#endif
}
level2_impl::~level2_impl() {
#if ELOGS
  elog(DEBUG1, "Deleted level2_impl %s", __str__().c_str());
#endif
};

level2::level2(level2 &&o) {
  p_impl = o.p_impl;
  o.p_impl = nullptr;
};

level2 &level2::operator=(level2 &&o) {
  if (p_impl) delete p_impl;
  p_impl = o.p_impl;
  o.p_impl = nullptr;
  return *this;
};

level2::~level2() {
  if (p_impl) delete p_impl;
};

bool level2::operator<(const level2 &o) const {
  if (p_impl) {
    if (o.p_impl)
      return *p_impl < *o.p_impl;
    else
      return false;
  } else {
    if (o.p_impl)
      return true;
    else
      return false;
  }
};

bool level2_impl::operator<(const level2_impl &o) const {
  if (p != o.p) {
    return p < o.p;
  } else {
    if (s != o.s)
      return s < o.s;
    else
      return false;  // level2's are considered the same
  }
}


HeapTuple level1::to_heap_tuple(AttInMetadata *attinmeta, int32 pair_id,
                                int32 exchange_id) {
  char **values = (char **)palloc(7 * sizeof(char *));
  static const int BUFFER_SIZE = 128;
  values[0] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[1] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[2] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[3] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[4] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[5] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  values[6] = (char *)palloc(BUFFER_SIZE * sizeof(char));
  snprintf(values[0], BUFFER_SIZE, "%Lf", best_bid_price);
  snprintf(values[1], BUFFER_SIZE, "%Lf", best_bid_qty);
  snprintf(values[2], BUFFER_SIZE, "%Lf", best_ask_price);
  snprintf(values[3], BUFFER_SIZE, "%Lf", best_ask_qty);
  snprintf(values[4], BUFFER_SIZE, "%s", timestamptz_to_str(microtimestamp));
  snprintf(values[5], BUFFER_SIZE, "%i", pair_id);
  snprintf(values[6], BUFFER_SIZE, "%i", exchange_id);
  HeapTuple tuple = BuildTupleFromCStrings(attinmeta, values);
  pfree(values[0]);
  pfree(values[1]);
  pfree(values[2]);
  pfree(values[3]);
  pfree(values[4]);
  pfree(values[5]);
  pfree(values[6]);
  pfree(values);
  return tuple;
};

level2_episode::level2_episode(Datum start_time, Datum end_time, Datum pair_id,
                               Datum exchange_id, Datum frequency) {

  char nulls[5] = {' ', ' ', ' ', ' ', ' '};
  if (frequency == NULL_FREQ) nulls[4] = 'n';

#if ELOGS
  std::string p_start_time{timestamptz_to_str(DatumGetTimestampTz(start_time))};
  std::string p_end_time{timestamptz_to_str(DatumGetTimestampTz(end_time))};
  std::string p_frequency{frequency == NULL_FREQ ? "NULL" : "Not NULL"};
  elog(DEBUG1, "spread_change_by_episode(%s, %s, %i, %i, %s)",
       p_start_time.c_str(), p_end_time.c_str(), DatumGetInt32(pair_id),
       DatumGetInt32(exchange_id), p_frequency.c_str());
#endif  // ELOGS

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
  select  microtimestamp, dc.price, dc.side, dc.volume,
          row_number() over (partition by microtimestamp order by price, side) as episode_seq_no,
          count(*) over (partition by microtimestamp) as episode_size
  from obanalytics.depth_change_by_episode3($1, $2, $3, $4, $5) join unnest(depth_change) dc on true
  order by microtimestamp, price, side 
  )QUERY",
                            5, types, values, nulls, true, 0);
}

level2_episode::level2_episode() { portal = SPI_cursor_find(CURSOR); }

std::vector<level2> level2_episode::next() {
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
#if ELOGS
      ereport(DEBUG1,
              (errmsg("episode=%s %lu",
                      SPI_getvalue(
                          SPI_tuptable->vals[0], SPI_tuptable->tupdesc,
                          SPI_fnumber(SPI_tuptable->tupdesc, "microtimestamp")),
                      episode_size)));
#endif
      result.push_back(level2{SPI_tuptable->vals[0], SPI_tuptable->tupdesc});
      if (episode_size > 1) {
        SPI_cursor_fetch(portal, true, episode_size - 1);
        for (uint64 j = 0; j < SPI_processed; j++)
          result.push_back(
              level2{SPI_tuptable->vals[j], SPI_tuptable->tupdesc});
      }
      return result;
    } else
      ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                      errmsg("Couldn't get episode_size")));
  } else
    throw 0;
}

std::vector<level2> level2_episode::initial() {
  std::vector<level2> result{next()};
  SPI_cursor_close(portal);
  portal = nullptr;
  return result;
}

level1 depth::spread() {
  level1 result{};
  result.best_bid_price = 1;
  return result;
}

level1 depth::update(std::vector<level2> v) {
  for (level2 &l : v) {
    std::pair<depth_set::iterator, bool> ret = depth.insert(std::move(l));
    if (!ret.second) {  // The value of the elements in a set cannot be modified
                        // once in the container (the elements are always
                        // const), but they can be inserted or removed from the
                        // container.
      depth_set::iterator hint = ret.first;
      hint++;
      depth.erase(ret.first);
      depth.insert(hint, std::move(l));
    }
  }
  return level1{};
};

depth::~depth() { elog(DEBUG1, "~depth"); }

void *depth::operator new(size_t s) {
  return palloc(s);
};

void depth::operator delete(void *p, size_t s) {
  pfree(p);
};
}
