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
#include "severity_level.h"
#include <unordered_map>

namespace obadiah {
namespace R {
static std::unordered_map<std::string, SeverityLevel> str_to_enum{
    {"DEBUG5", SeverityLevel::kDebug5},   {"DEBUG4", SeverityLevel::kDebug4},
    {"DEBUG3", SeverityLevel::kDebug3},   {"DEBUG2", SeverityLevel::kDebug2},
    {"DEBUG1", SeverityLevel::kDebug1},   {"LOG", SeverityLevel::kLog},
    {"INFO", SeverityLevel::kInfo},       {"NOTICE", SeverityLevel::kNotice},
    {"WARNING", SeverityLevel::kWarning}, {"ERROR", SeverityLevel::kError},
};

SeverityLevel
GetSeverityLevel(const std::string s) {
 return str_to_enum.at(s);
}

std::string
ToString(SeverityLevel level) {
 for (auto it = str_to_enum.begin(); it != str_to_enum.end(); ++it)
  if (it->second == level) {
   return it->first;
  }
 return std::string{};
}

std::ostream&
operator<<(std::ostream& strm, SeverityLevel level) {
 strm << ToString(level);
 return strm;
}
}  // namespace R
}  // namespace obadiah
