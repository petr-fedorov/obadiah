// Copyright (C) 2020 Petr Fedorov <petr.fedorov@phystech.edu>

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
#ifndef OBADIAH_EPSILON_DRAWUPDOWNS_H
#define OBADIAH_EPSILON_DRAWUPDOWNS_H
#include <ostream>
#include "base.h"
namespace obadiah {
namespace R {
class EpsilonDrawUpDowns : public ObjectStream<Position> {
public:
 EpsilonDrawUpDowns(ObjectStream<InstantPrice>* period, double epsilon);
 ObjectStream<Position>& operator>>(Position&);
 friend std::ostream& operator<<(std::ostream& stream, EpsilonDrawUpDowns& p);

private:
 ObjectStream<InstantPrice>* trading_period_;
 double epsilon_;

 InstantPrice st_;  // start
 InstantPrice tp_;  // turning point
 InstantPrice en_;  // end

#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};
}  // namespace R
}  // namespace obadiah
#endif

