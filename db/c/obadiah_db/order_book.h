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

#ifndef ORDER_BOOK_H
#define ORDER_BOOK_H

#include <deque>
#include <map>
#include <set>
#include <vector>
#include "level2.h"
#include "level3.h"
#include "spi_allocator.h"

namespace obad {

class order_book : public postgres_heap {
public:
 order_book();
 ~order_book();
 void update(std::vector<level3> &&, obad::deque<level2> *);

private:
 class order_book_side;
 inline order_book_side *by_side(const char s) const {
  return s == 'b' ? bids : asks;
 }

 order_book_side *bids;
 order_book_side *asks;
};
}  // namespace obad
#endif
