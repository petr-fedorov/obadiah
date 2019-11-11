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
#include "postgres.h"

#ifdef __cplusplus
}
#endif  // __cplusplus
#include "spi_allocator.h"
namespace obad {

void *
postgres_heap::operator new(size_t s, allocation_mode m) {
 if (m == allocation_mode::spi) return SPI_palloc(s);
 return palloc(s);
}
void
postgres_heap::operator delete(void *p, size_t s) {
 pfree(p);
};
}  // namespace obad
