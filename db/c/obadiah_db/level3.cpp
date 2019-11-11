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

#include <cstdlib>
#include <iomanip>
#include <sstream>
#include <string>

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus
#include "postgres.h"
#include "utils/timestamp.h"
#ifdef __cplusplus
}
#endif  // __cplusplus

#include "level2.h"
#include "level3.h"
#include "spi_allocator.h"

namespace obad {

struct level3_impl : public postgres_heap {
 level3_impl(HeapTuple, TupleDesc);
 std::string __str__() const {
  std::stringstream stream;
  return stream.str();
 };

 TimestampTz microtimestamp;
 int64 order_id;
 int32 event_no;
 char side;
 price p;
 amount a;
 TimestampTz price_microtimestamp;
 TimestampTz next_microtimestamp;
};

std::ostream &
operator<<(std::ostream &stream, const level3_impl &l3) {
 stream << "(level3: " << timestamptz_to_str(l3.microtimestamp) << " " << l3.order_id
        << " " << l3.event_no << " "
        << " " << l3.side << " " << std::setprecision(15) << l3.p << " " << l3.a << ")";
 return stream;
};

std::ostream &
operator<<(std::ostream &stream, const level3 &l3) {
 if (l3.p_impl)
  stream << *l3.p_impl;
 else
  stream << "(level3 empty)";
 return stream;
};

level3_impl::level3_impl(HeapTuple tuple, TupleDesc tupdesc) {
 bool is_null;
 Datum value;
 value = SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "microtimestamp"),
                       &is_null);
 if (!is_null) microtimestamp = DatumGetTimestampTz(value);

 value =
     SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "order_id"), &is_null);
 if (!is_null) order_id = DatumGetInt64(value);

 value =
     SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "event_no"), &is_null);
 if (!is_null) event_no = DatumGetInt32(value);

 side = SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "side"))[0];

 value = SPI_getbinval(tuple, tupdesc,
                       SPI_fnumber(tupdesc, "price_microtimestamp"), &is_null);
 if (!is_null) price_microtimestamp = DatumGetTimestampTz(value);

 value = SPI_getbinval(tuple, tupdesc,
                       SPI_fnumber(tupdesc, "next_microtimestamp"), &is_null);
 if (!is_null) next_microtimestamp = DatumGetTimestampTz(value);

 try {
  p = strtold(SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "price")),
              nullptr);
 } catch (...) {
  elog(ERROR, "Couldn't convert price %s %lu",
       timestamptz_to_str(microtimestamp), order_id);
  p = 0;
 }

 try {
  a = strtold(SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "amount")),
              nullptr);
 } catch (...) {
  elog(ERROR, "Couldn't convert amount %s %lu",
       timestamptz_to_str(microtimestamp), order_id);
  a = 0;
 }
};

level3::level3(HeapTuple tuple, TupleDesc tupdesc) {
 p_impl = new (allocation_mode::spi) level3_impl(tuple, tupdesc);
#if DEBUG_DEPTH
 elog(DEBUG3, "%s created %s", __PRETTY_FUNCTION__, to_string<level3_impl>(*p_impl).c_str());
#endif
}

level3::level3(level3 &&m) {
#if DEBUG_DEPTH
 elog(DEBUG3, "%s moved %s", __PRETTY_FUNCTION__, to_string<level3>(m).c_str());
#endif
 p_impl = m.p_impl;
 m.p_impl = nullptr;
}

level3::~level3() {
 if (p_impl) {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s %s", __PRETTY_FUNCTION__, to_string<level3_impl>(*p_impl).c_str());
#endif
  delete p_impl;
 }
}

level3 &
level3::operator=(level3 &&l3) {
 if (p_impl) {
  // We allow assignment only to the empty level3
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("%s assignment of %s to %s", __PRETTY_FUNCTION__,
                         to_string<level3>(l3).c_str(), to_string<level3_impl>(*p_impl).c_str())));
 }
 p_impl = l3.p_impl;
 l3.p_impl = nullptr;
 return *this;
};

TimestampTz
level3::get_microtimestamp() const {
 if (p_impl)
  return p_impl->microtimestamp;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

TimestampTz
level3::get_episode() const {
 if (p_impl)
  return p_impl->microtimestamp;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

char
level3::get_side() const {
 if (p_impl)
  return p_impl->side;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

amount
level3::get_volume() const {
 if (p_impl)
  return p_impl->a;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

price
level3::get_price() const {
 if (p_impl)
  return p_impl->p;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

uint32
level3::get_event_no() const {
 if (p_impl)
  return p_impl->event_no;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

uint64
level3::get_order_id() const {
 if (p_impl)
  return p_impl->order_id;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};

bool
level3::is_deleted() const {
 if (p_impl)
  return p_impl->next_microtimestamp == DT_NOBEGIN;
 else
  ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                  errmsg("get from an empty level3")));
};
}  // namespace obad
