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
#include <limits>
#include <map>
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

  TimestampTz get_microtimestamp() {
    return m;
  }
  price get_price() {
    return p;
  };
  char get_side() {
    return s;
  };
  amount get_volume() {
    return v;
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
  elog(DEBUG3, "Created level2_impl from HeapTuple %s", __str__().c_str());
#endif
}
level2_impl::~level2_impl() {
#if ELOGS
  elog(DEBUG3, "Deleted level2_impl %s", __str__().c_str());
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

TimestampTz level2::get_microtimestamp() {
  if (p_impl)
    return p_impl->get_microtimestamp();
  else
    ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                    errmsg("Couldn't get_microtimestamp from an empty level2 ")));
};
amount level2::get_price() {
  if (p_impl)
    return p_impl->get_price();
  else
    ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                    errmsg("Couldn't get_price from an empty level2 ")));
};

char level2::get_side() {
  if (p_impl)
    return p_impl->get_side();
  else
    ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                    errmsg("Couldn't get_side from an empty level2 ")));
};

amount level2::get_volume() {
  if (p_impl)
    return p_impl->get_volume();
  else
    ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                    errmsg("Couldn't get_volume from an empty level2 ")));
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
  snprintf(values[0], BUFFER_SIZE, "%.5Lf", best_bid_price);
  snprintf(values[1], BUFFER_SIZE, "%.8Lf", best_bid_qty);
  snprintf(values[2], BUFFER_SIZE, "%.5Lf", best_ask_price);
  snprintf(values[3], BUFFER_SIZE, "%.8Lf", best_ask_qty);
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
  std::vector<level2> result;
  try {
    std::vector<level2> result{next()};
    SPI_cursor_close(portal);
    portal = nullptr;
    return result;
  }
  catch(...) { // we are fine, if the initial episode is an empty one 
    SPI_cursor_close(portal);
    portal = nullptr;
    return std::vector<level2>{};
  };  
}

level1 depth::spread() {
  return level1{best_bid_price, best_bid_qty, best_ask_price,  best_ask_qty, episode};
}

void depth::update_spread(level2 &l) {
  if (l.get_volume() > 0) {
    if (l.get_side() == 's' && l.get_price() <= best_ask_price) {
      best_ask_price = l.get_price();
      best_ask_qty = l.get_volume();
      return;
    }

    if (l.get_side() == 'b' && l.get_price() >= best_bid_price) {
      best_bid_price = l.get_price();
      best_bid_qty = l.get_volume();
      return;
    }
  } else {
    if (l.get_side() == 's' && l.get_price() == best_ask_price) {
      for (depth_map::iterator it = d.find(l.get_price()); it != d.end(); ++it)
        if (it->second.get_side() == 's' &&
            it->second.get_price() > best_ask_price) {
          best_ask_price = it->second.get_price();
          best_ask_qty = it->second.get_volume();
          return;
        }
      best_ask_price = std::numeric_limits<price>::max();
      best_ask_qty = 0;
      return;
    }
    if (l.get_side() == 'b' && l.get_price() == best_bid_price) {
      for (std::reverse_iterator<depth_map::iterator> it =
               std::make_reverse_iterator(d.find(l.get_price()));
           it != d.rend(); ++it)
        if (it->second.get_side() == l.get_side() &&
            it->second.get_price() < best_bid_price) {
          best_bid_price = it->second.get_price();
          best_bid_qty = it->second.get_volume();
          return;
        }
      best_bid_price = 0;
      best_bid_qty = 0;
      return;
    }
  }
};

level1 depth::update(std::vector<level2> v) {
  if(!v.empty())
    episode = v[0].get_microtimestamp();
  for (level2 &l : v) {
    update_spread(l);
    if (l.get_volume() > 0) 
      d[l.get_price()] = std::move(l);
    else 
      d.erase(l.get_price());
  }
  return spread();
};

depth::depth()
    : best_bid_price(0),
      best_bid_qty(0),
      best_ask_price(std::numeric_limits<price>::max()),
      best_ask_qty(0) {};

depth::~depth() { 
#if ELOGS
  elog(DEBUG1, "~depth"); 
#endif
}


void *depth::operator new(size_t s) {
  return palloc(s);
};

void depth::operator delete(void *p, size_t s) {
  pfree(p);
};
}
