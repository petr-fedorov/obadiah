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
#include "order_book_investigation.h"
#include <unordered_map>

namespace obadiah {
 namespace R {

TickSizeType
GetTickSizeType(const std::string s) {
 static std::unordered_map<std::string, TickSizeType> str_to_enum{
     {"ABSOLUTE", TickSizeType::kAbsolute},
     {"LOGRELATIVE", TickSizeType::kLogRelative}};
 try {
  return str_to_enum.at(s);
 } catch (const std::out_of_range &) {
  return TickSizeType::kAbsolute;
 }
}
}
};  // namespace obadiah
