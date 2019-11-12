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

#ifndef DEPTH_H
#define DEPTH_H
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

#include "funcapi.h"
#include "utils/timestamp.h"
//#include "executor/spi.h"
//#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

#include <map>
#include "level1.h"
#include "level2.h"
#include "obadiah_db.h"
#include "spi_allocator.h"

namespace obad {

class depth : public postgres_heap {
public:
 ~depth();
 level1 spread();
 level1 update(obad::deque<obad::level2> *); 
 level1 update(std::vector<level2>);

private:
 void update_spread(level2&);
 TimestampTz episode;
 obad::map<price, level2> bid;
 obad::map<price, level2> ask;
};

}  // namespace obad
#endif
