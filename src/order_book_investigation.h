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

#ifndef OBADIAH_ORDER_BOOK_INVESTIGATION_H
#define OBADIAH_ORDER_BOOK_INVESTIGATION_H

#include "base.h"

#ifndef NDEBUG
#include <boost/log/sources/severity_feature.hpp>
#include <boost/log/sources/severity_logger.hpp>
#endif

namespace obadiah {

template <template <typename> class Allocator,
          typename T = std::pair<const Price, Volume>>
class InstrumentedOrderBook : public obadiah::OrderBook<Allocator, T> {
public:
 Volume GetVolume(Price p, Side s);
};

template <template <typename> class Allocator, typename T>
Volume
InstrumentedOrderBook<Allocator, T>::GetVolume(Price p, Side s) {
 if (s == Side::kBid)
  return OrderBook<Allocator, T>::bids_.at(p);
 else
  return OrderBook<Allocator, T>::asks_.at(p);
}

template <template <typename> class Allocator,
          typename T = std::pair<const Price, Volume>>
class OrderBookChanges : public ObjectStream<Level2> {
public:
 OrderBookChanges(ObjectStream<Level2>* depth_changes)
     : depth_changes_{depth_changes} {
  ObjectStream<Level2>::is_all_processed_ = false; //static_cast<bool>(*depth_changes);
 };
 OrderBookChanges<Allocator, T>& operator>>(Level2&);

protected:
 InstrumentedOrderBook<Allocator, T> ob_;
 ObjectStream<Level2>* depth_changes_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator, typename T>
OrderBookChanges<Allocator, T>&
OrderBookChanges<Allocator, T>::operator>>(Level2& ob_change) {
 Level2 depth_change;
 if (*depth_changes_ >> depth_change) {
  ob_change.t = depth_change.t;
  ob_change.p = depth_change.p;
  ob_change.s = depth_change.s;
  try {
   ob_change.v = depth_change.v - ob_.GetVolume(depth_change.p, depth_change.s);
  } catch (const std::out_of_range&) {
   ob_change.v = depth_change.v;
  }
  ob_ << depth_change;
 } else
  is_all_processed_ = true;
 return *this;
}
}  // namespace obadiah
#endif

