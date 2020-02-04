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

#ifndef OBADIAH_SEVERITY_LEVEL_H
#define OBADIAH_SEVERITY_LEVEL_H
#include <ostream>
namespace obadiah {
enum class SeverityLevel {
 kDebug5 = -6,
 kDebug4 = -5,
 kDebug3 = -4,
 kDebug2 = -3,
 kDebug1 = -2,
 kLog = -1,
 kInfo = 0,
 kNotice = 1,
 kWarning = 2,
 kError = 3
};

SeverityLevel
GetSeverityLevel(const std::string s);
std::string ToString(SeverityLevel l);
std::ostream& operator<< (std::ostream& strm, SeverityLevel level);

}  // namespace obadiah
#endif
