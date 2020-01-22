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

#include "base.h"
#include <chrono>
#include <cstdio>
#include <ctime>

namespace obadiah {

using namespace std;
using namespace std::chrono;

Level2::operator char *() {
 const size_t kBufferSize = 100;
 static char buffer[kBufferSize];
 snprintf(buffer, kBufferSize, "L2 t: %s p: %.6lf s:%c", static_cast<char *>(t),
          p, static_cast<char>(s));
 return buffer;
}

BidAskSpread::operator char *() {
 const size_t kBufferSize = 100;
 static char buffer[kBufferSize];
 snprintf(buffer, kBufferSize,
          "TM t: %s bid: %.5lf ask: %.5lf",
          static_cast<char *>(t), p_bid, p_ask);
 return buffer;
}

Timestamp::operator char *() {
 const size_t kBufferSize = 50;
 static char buffer[kBufferSize];
 duration<double> d(t);
 std::time_t t = d.count();
 size_t count = strftime(buffer, kBufferSize - 1, "%F %T", std::localtime(&t));
 count += sprintf(buffer + count, ".%.6zu",
                  (duration_cast<microseconds>(d).count() % 1000000));
 return buffer;
}


}  // namespace obadiah
