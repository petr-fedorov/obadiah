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

#ifndef LEVEL3EPISODE_H
#define LEVEL3EPISODE_H
#include <locale> // must be before postgres.h to fix /usr/include/libintl.h:39:14: error: expected unqualified-id before ‘const’ error
#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus
#include "postgres.h"
#ifdef __cplusplus
}
#endif  // __cplusplus

#include <string>
#include "level3.h"
#include "spi_allocator.h"

namespace obad {

class level3_episode : public postgres_heap {
public:
 level3_episode() : events_deque{nullptr} {};
 ~level3_episode();
 std::vector<level3> initial(Datum start_time, Datum end_time, Datum pair_id,
                             Datum exchange_id, Datum frequency);
 std::vector<level3> next();
 void done();

private:
 static const char *const CURSOR;
 static const int SPI_CURSOR_FETCH_COUNT;

 using level3_deque = std::deque<level3, spi_allocator<level3>>;

 level3_deque *events_deque;
};
}  // namespace obad
#endif

