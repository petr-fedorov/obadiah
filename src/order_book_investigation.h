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

using ChainId = int;

struct OrderBookChange : public Level2 {
 ChainId id;
};

template <template <typename> class Allocator,
          typename T = std::pair<const Price, Volume>>
class OrderBookChanges : public ObjectStream<OrderBookChange> {
public:
 OrderBookChanges(ObjectStream<Level2>* depth_changes)
     : depth_changes_{depth_changes}, next_chain_id_{1} {
  ObjectStream<OrderBookChange>::is_all_processed_ =
      false;  // static_cast<bool>(*depth_changes);
 };
 OrderBookChanges<Allocator, T>& operator>>(OrderBookChange&);

protected:
 ChainId GetChainId(const OrderBookChange&);

 InstrumentedOrderBook<Allocator, T> ob_;
 ObjectStream<Level2>* depth_changes_;
 using ChainIds = std::map<Volume, ChainId, std::less<Volume>, Allocator<T>>;
 ChainIds bid_chains_;
 ChainIds ask_chains_;
 ChainId next_chain_id_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator, typename T>
ChainId
OrderBookChanges<Allocator, T>::GetChainId(const OrderBookChange& ob_change) {
 ChainIds *chain_ids;
 if(ob_change.s == Side::kBid)
  chain_ids = &bid_chains_;
 else
  chain_ids = &ask_chains_;
 auto chain = chain_ids->find(std::abs(ob_change.v));
 if(chain != chain_ids->end()) {
  return chain->second;
 }
 else {
  return (*chain_ids)[std::abs(ob_change.v)] = next_chain_id_++;
 }
}

template <template <typename> class Allocator, typename T>
OrderBookChanges<Allocator, T>&
OrderBookChanges<Allocator, T>::operator>>(OrderBookChange& ob_change) {
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
  ob_change.id = GetChainId(ob_change);
  ob_ << depth_change;
 } else
  is_all_processed_ = true;
 return *this;
}
}  // namespace obadiah
#endif

