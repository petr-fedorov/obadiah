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

#ifndef LEVEL2_H
#define LEVEL2_H
#include <iomanip>

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
#include "funcapi.h"
#include "utils/timestamp.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

#include <ostream>
#include "obadiah_db.h"

namespace obad {

class level2_impl;  // is supposed to have an SPI-aware new and delete operators
                    // ...

class level2 {
public:
 level2() { p_impl = nullptr; };
 level2(TimestampTz, char, price, amount);

 level2(HeapTuple, TupleDesc);

 level2(const level2 &m) = delete;
 level2(level2 &&m);

 level2 &operator=(level2 &&);

 ~level2();

 TimestampTz get_microtimestamp() const;
 price get_price() const;
 amount get_volume() const;
 void set_volume(amount);
 char get_side() const;

 bool operator<(const level2 &) const;
 HeapTuple to_heap_tuple(AttInMetadata *attinmeta, int32 pair_id,
                         int32 exchange_id);

private:
 friend std::ostream &operator<<(std::ostream &, const level2 &);
 level2_impl *p_impl;
};

std::ostream &
operator<<(std::ostream &, const level2 &);

}  // namespace obad
#endif
