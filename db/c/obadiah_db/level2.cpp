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
#include "level2.h"
#include <limits>
#include <map>
#include <sstream>
#include <string>
#include "spi_allocator.h"

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

namespace obad {

struct level2_impl : public postgres_heap {
 level2_impl(HeapTuple tuple, TupleDesc tupdesc);
 level2_impl(TimestampTz p_m, char p_s, price p_p, amount p_a)
     : p(p_p), s(p_s), v(p_a), m(p_m){};

 bool operator<(const level2_impl &) const;

 price p;
 char s;
 amount v;
 TimestampTz m;
};

level2::level2(HeapTuple tuple, TupleDesc tupdesc) {
 p_impl = new (allocation_mode::spi) level2_impl{tuple, tupdesc};
#if DEBUG_DEPTH
 elog(DEBUG3, "%s created %s", __PRETTY_FUNCTION__, to_string<level2>(*this).c_str());
#endif
};

std::ostream &
operator<<(std::ostream &stream, const level2_impl &l2) {
 stream << "(level2: " << timestamptz_to_str(l2.m) << " "
        << std::setprecision(15) << l2.s << " " << l2.p << " " << l2.v << ")";
 return stream;
};

std::ostream &
operator<<(std::ostream &stream, const level2 &l2) {
 if (l2.p_impl)
  stream << *l2.p_impl;
 else
  stream << "(level2 empty)";
 return stream;
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
}

level2::level2(TimestampTz m, char s, price p, amount a) {
 p_impl = new (allocation_mode::non_spi) level2_impl{m, s, p, a};
#if DEBUG_DEPTH
 elog(DEBUG3, "%s created %s", __PRETTY_FUNCTION__, to_string<level2>(*this).c_str());
#endif
}

level2::level2(level2 &&o) {
#if DEBUG_DEPTH
 elog(DEBUG3, "%s moved %s", __PRETTY_FUNCTION__, to_string<level2>(o).c_str());
#endif
 p_impl = o.p_impl;
 o.p_impl = nullptr;
};

level2 &
level2::operator=(level2 &&o) {
#if DEBUG_DEPTH
 elog(DEBUG3, "%s moved %s", __PRETTY_FUNCTION__, to_string<level2>(o).c_str());
#endif
 if (p_impl) delete p_impl;
 p_impl = o.p_impl;
 o.p_impl = nullptr;
 return *this;
};

TimestampTz
level2::get_microtimestamp() const {
 if (p_impl)
  return p_impl->m;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("Couldn't get_microtimestamp from an empty level2 ")));
};
amount
level2::get_price() const {
 if (p_impl)
  return p_impl->p;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("Couldn't get_price from an empty level2 ")));
};

char
level2::get_side() const {
 if (p_impl)
  return p_impl->s;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("Couldn't get_side from an empty level2 ")));
};

amount
level2::get_volume() const {
 if (p_impl)
  return p_impl->v;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("Couldn't get_volume from an empty level2 ")));
};

void
level2::set_volume(amount volume) {
 if (p_impl)
  p_impl->v = volume;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("Couldn't set_volume for an empty level2 ")));
#if DEBUG_DEPTH
 elog(DEBUG3, "%s %s", __PRETTY_FUNCTION__, to_string<level2>(*this).c_str());
#endif
};

level2::~level2() {
 if (p_impl) {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s %s", __PRETTY_FUNCTION__, to_string<level2>(*this).c_str());
#endif
  delete p_impl;
 }
};

bool
level2::operator<(const level2 &o) const {
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

bool
level2_impl::operator<(const level2_impl &o) const {
 if (p != o.p) {
  return p < o.p;
 } else {
  if (s != o.s)
   return s < o.s;
  else
   return false;  // level2's are considered the same
 }
}

HeapTuple
level2::to_heap_tuple(AttInMetadata *attinmeta, int32 pair_id,
                      int32 exchange_id) {
 char **values = (char **)palloc(8 * sizeof(char *));
 static const int BUFFER_SIZE = 128;
 values[0] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[1] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[2] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[3] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[4] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[5] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[6] = (char *)palloc(BUFFER_SIZE * sizeof(char));
 values[7] = nullptr;
 snprintf(values[0], BUFFER_SIZE, "%s",
          timestamptz_to_str(p_impl->m));
 snprintf(values[1], BUFFER_SIZE, "%i", pair_id);
 snprintf(values[2], BUFFER_SIZE, "%i", exchange_id);
 snprintf(values[3], BUFFER_SIZE, "%s", "r0");
 snprintf(values[4], BUFFER_SIZE, "%.5Lf", p_impl->p);
 snprintf(values[5], BUFFER_SIZE, "%.8Lf", p_impl->v);
 snprintf(values[6], BUFFER_SIZE, "%c", p_impl->s);

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

}  // namespace obad
