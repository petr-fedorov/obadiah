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

#ifndef LEVEL3_H
#define LEVEL3_H

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

class level3_impl;

class level3 {
public:
 level3() { p_impl = nullptr; };
 ~level3();
 level3(HeapTuple, TupleDesc);
 level3(const level3 &m) = delete;
 level3(level3 &&m);
 level3 &operator=(level3 &&);
 TimestampTz get_microtimestamp() const;
 TimestampTz get_episode() const;
 uint64 get_order_id() const;
 uint32 get_event_no() const;
 price get_price() const;
 amount get_volume() const;
 char get_side() const;
 bool is_deleted() const;

private:
 friend std::ostream &operator<<(std::ostream &, const level3 &);
 level3_impl *p_impl;
};

std::ostream &
operator<<(std::ostream &, const level3 &);

}  // namespace obad
#endif
