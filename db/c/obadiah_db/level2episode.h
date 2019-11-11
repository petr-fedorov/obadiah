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

#ifndef LEVEL2EPISODE_H
#define LEVEL2EPISODE_H

#include <locale>  // must be before postgres.h to fix /usr/include/libintl.h:39:14: error: expected unqualified-id before ‘const’ error
#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "postgres.h"
#include "utils/timestamp.h"
//#include "funcapi.h"
#include "executor/spi.h"
//#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif  // __cplusplus

#include <vector>
#include "level2.h"

namespace obad {

class level2_episode {
public:
 level2_episode();
 level2_episode(Datum start_time, Datum end_time, Datum pair_id,
                Datum exchange_id, Datum frequency);
 std::vector<level2> initial();
 std::vector<level2> next();
 void done();
 TimestampTz microtimestamp();

private:
 static const char *const INITIAL;
 static const char *const CURSOR;
 Portal portal;
};

}  // namespace obad
#endif

