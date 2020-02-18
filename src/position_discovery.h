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
#ifndef OBADIAH_POSITION_DISCOVERY_H
#define OBADIAH_POSITION_DISCOVERY_H

#include "base.h"
#include <cmath>
#include <exception>
#include <ostream>
#include <map>

namespace obadiah {
 namespace R {

std::ostream&
operator<<(std::ostream& stream, Position& p);

class TradingStrategy : public ObjectStream<Position> {
public:
 TradingStrategy(ObjectStream<BidAskSpread>* period, double phi, double rho);
 ObjectStream<Position>& operator >> (Position&);

private:
 inline double Interest(InstantPrice a, InstantPrice b) {
  return rho_ * std::abs(b.t - a.t);
 }

 inline double Commission() { return 2 * phi_; }

 double rho_;
 double phi_;
 ObjectStream<BidAskSpread>* trading_period_;

 InstantPrice sl_;  // start long
 InstantPrice el_;  // end long

 InstantPrice ss_;  // start short
 InstantPrice es_;  // end short

#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

}
}  // namespace obadiah
#endif
