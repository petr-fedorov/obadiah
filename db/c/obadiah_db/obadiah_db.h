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

#ifndef OBADIAH_H
#define OBADIAH_H

#include <cmath>
#include <sstream>
namespace obad {
static constexpr long unsigned NULL_FREQ = 0;
using price = long double;
using amount = long double;

static constexpr double MINIMAL_PRICE_CHANGE = 1.e-5;
inline bool
prices_are_equal(price a, price b) {
 return std::fabs(a - b) < MINIMAL_PRICE_CHANGE;
}
static constexpr double MINIMAL_AMOUNT_CHANGE = 1.e-12;
inline bool
amounts_are_equal(amount a, amount b) {
 return std::fabs(a - b) < MINIMAL_AMOUNT_CHANGE;
}
template <typename T>
std::string
to_string(const T& value) {
 std::ostringstream ss;
 ss << value;
 return ss.str();
}
};  // namespace obad
#endif

