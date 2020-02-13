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

#include <deque>
#include "base.h"

#ifndef NDEBUG
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_feature.hpp>
#include <boost/log/sources/severity_logger.hpp>
#endif

namespace obadiah {

template <template <typename> class Allocator = std::allocator>
struct OrderBookSnapshot {
 using DepthVolumes = std::vector<Volume, Allocator<Volume>>;
 Timestamp t;
 Price bid_price;
 Price ask_price;
 DepthVolumes bids;
 DepthVolumes asks;
};

template <template <typename> class Allocator = std::allocator>
class InstrumentedOrderBook : public obadiah::OrderBook<Allocator> {
 using Pair = std::pair<const Price, Volume>;

public:
 Volume GetVolume(Price p, Side s);
 Volume GetVolume(Price p, Side s, Price tick_size);
 inline void GetSnapshot(OrderBookSnapshot<Allocator>& ds,
                         const Price tick_size, const std::size_t max_levels) {
  GetBidsSnapshot(ds, tick_size, max_levels);
  GetAsksSnapshot(ds, tick_size, max_levels);
 }

protected:
 void GetBidsSnapshot(OrderBookSnapshot<Allocator>&, const Price tick_size,
                      const std::size_t max_levels);
 void GetAsksSnapshot(OrderBookSnapshot<Allocator>&, const Price tick_size,
                      const std::size_t max_levels);
};

template <template <typename> class Allocator>
void
InstrumentedOrderBook<Allocator>::GetBidsSnapshot(
    OrderBookSnapshot<Allocator>& ds, const Price tick_size,
    const std::size_t max_levels) {
 auto it = OrderBook<Allocator>::bids_.crbegin();
 if (it != this->bids_.crend())
  ds.bid_price = std::floor(it->first / tick_size) * tick_size;
 else
  ds.bid_price = R_NAREAL;

 ds.bids.clear();
 ds.bids.reserve(max_levels);
 ds.bids.shrink_to_fit();

 for (std::size_t lvl = 0; lvl < max_levels; ++lvl) {
  Volume vol = 0.0;
  Price delta = lvl * tick_size;
  for (; it != this->bids_.crend(); ++it)
   if (it->first >= ds.bid_price - delta)
    vol += it->second;
   else
    break;
  ds.bids.push_back(vol);
 }
}

template <template <typename> class Allocator>
void
InstrumentedOrderBook<Allocator>::GetAsksSnapshot(
    OrderBookSnapshot<Allocator>& ds, const Price tick_size,
    const std::size_t max_levels) {
 auto it = this->asks_.cbegin();
 if (it != this->asks_.cend())
  ds.ask_price = std::ceil(it->first / tick_size) * tick_size;
 else
  ds.ask_price = R_NAREAL;

 ds.asks.clear();
 ds.asks.reserve(max_levels);
 ds.asks.shrink_to_fit();

 for (std::size_t lvl = 0; lvl < max_levels; ++lvl) {
  Volume vol = 0.0;
  Price delta = lvl * tick_size;
  for (; it != this->asks_.cend(); ++it)
   if (it->first <= ds.ask_price + delta)
    vol += it->second;
   else
    break;
  ds.asks.push_back(vol);
 }
}

template <template <typename> class Allocator>
Volume
InstrumentedOrderBook<Allocator>::GetVolume(Price p, Side s) {
 if (s == Side::kBid)
  return OrderBook<Allocator>::bids_.at(p);
 else
  return OrderBook<Allocator>::asks_.at(p);
}

template <template <typename> class Allocator>
Volume
InstrumentedOrderBook<Allocator>::GetVolume(Price p, Side s, Price tick_size) {
 Volume volume = 0.0;
 if (s == Side::kBid) {
  auto price_from = std::floor(p / tick_size) * tick_size;
  auto price_to = (std::floor(p / tick_size) + 1) * tick_size;
  for (auto it = this->bids_.lower_bound(price_from); it != this->bids_.end();
       ++it) {
   if (it->first >= price_to) break;
   volume += it->second;
  }
#ifndef NDEBUG
  BOOST_LOG_SEV(this->lg, obadiah::SeverityLevel::kDebug5)
      << "Price: " << p << " Side: " << static_cast<char>(s)
      << " Volume: " << volume;
#endif
  return volume;
 } else {
  auto price_from = (std::ceil(p / tick_size) - 1) * tick_size;
  auto price_to = std::ceil(p / tick_size) * tick_size;
  for (auto it = this->asks_.upper_bound(price_from); it != this->asks_.end();
       ++it) {
   if (it->first > price_to) break;
   volume += it->second;
  }
#ifndef NDEBUG
  BOOST_LOG_SEV(this->lg, obadiah::SeverityLevel::kDebug5)
      << "Price: " << p << " Side: " << static_cast<char>(s)
      << " Volume: " << volume;
#endif
  return volume;
 }
}

using ChainId = int;

struct OrderBookChange : public Level2 {
 ChainId id;
};

template <template <typename> class Allocator = std::allocator>
class OrderBookChanges : public ObjectStream<OrderBookChange> {
public:
 OrderBookChanges(ObjectStream<Level2>* depth_changes)
     : depth_changes_{depth_changes}, next_chain_id_{1} {
  ObjectStream<OrderBookChange>::is_all_processed_ =
      false;  // static_cast<bool>(*depth_changes);
 };
 OrderBookChanges<Allocator>& operator>>(OrderBookChange&);

protected:
 ChainId GetChainId(const OrderBookChange&);

 InstrumentedOrderBook<Allocator> ob_;
 ObjectStream<Level2>* depth_changes_;
 using ChainIds = std::map<Volume, ChainId, std::less<Volume>,
                           Allocator<std::pair<const Volume, ChainId>>>;
 ChainIds bid_chains_;
 ChainIds ask_chains_;
 ChainId next_chain_id_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator>
ChainId
OrderBookChanges<Allocator>::GetChainId(const OrderBookChange& ob_change) {
 ChainIds* chain_ids;
 if (ob_change.s == Side::kBid)
  chain_ids = &bid_chains_;
 else
  chain_ids = &ask_chains_;
 auto chain = chain_ids->find(std::abs(ob_change.v));
 if (chain != chain_ids->end()) {
  return chain->second;
 } else {
  return (*chain_ids)[std::abs(ob_change.v)] = next_chain_id_++;
 }
}

template <template <typename> class Allocator>
OrderBookChanges<Allocator>&
OrderBookChanges<Allocator>::operator>>(OrderBookChange& ob_change) {
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

template <template <typename> class Allocator = std::allocator>
class TickSizeChanger : public ObjectStream<Level2> {
public:
 TickSizeChanger(ObjectStream<Level2>* depth_changes, Price tick_size)
     : depth_changes_{depth_changes}, tick_size_{tick_size} {
  if (*depth_changes >> unprocessed_) is_all_processed_ = false;
 }
 TickSizeChanger<Allocator>& operator>>(Level2&);

private:
 void ProcessNextEpisode();

 InstrumentedOrderBook<Allocator> ob_;
 ObjectStream<Level2>* depth_changes_;
 Price tick_size_;
 Level2 unprocessed_;
 std::deque<Level2, Allocator<Level2>> output_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator>
void
TickSizeChanger<Allocator>::ProcessNextEpisode() {
 if (unprocessed_) {
  std::set<Price, std::less<Price>, Allocator<Price>> bid_prices;
  std::set<Price, std::less<Price>, Allocator<Price>> ask_prices;
  Timestamp current = unprocessed_.t;
  do {
   if (!(current == unprocessed_.t)) break;
   if (unprocessed_.s == Side::kBid) {
    bid_prices.insert(std::floor(unprocessed_.p / tick_size_) * tick_size_);
   } else {
    ask_prices.insert(std::ceil(unprocessed_.p / tick_size_) * tick_size_);
   }
   ob_ << unprocessed_;
   unprocessed_.falsify();
  } while (*depth_changes_ >> unprocessed_);
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug4)
      << "TickSizeChanger " << static_cast<char*>(current);
#endif

  for (auto price = ask_prices.rbegin(); price != ask_prices.rend(); ++price) {
   Level2 o;
   o.t = current;
   o.p = *price;
   o.v = ob_.GetVolume(*price, Side::kAsk, tick_size_);
   o.s = Side::kAsk;
   output_.push_front(o);
  }
  for (auto price = bid_prices.rbegin(); price != bid_prices.rend(); ++price) {
   Level2 o;
   o.t = current;
   o.p = *price;
   o.v = ob_.GetVolume(*price, Side::kBid, tick_size_);
   o.s = Side::kBid;
   output_.push_front(o);
  }
 }
}

template <template <typename> class Allocator>
TickSizeChanger<Allocator>&
TickSizeChanger<Allocator>::operator>>(Level2& out) {
 if (!is_all_processed_) {
  if (output_.empty()) ProcessNextEpisode();

  if (!output_.empty()) {
   out = output_.back();
   output_.pop_back();
  } else {
   is_all_processed_ = true;
  }
 }
 return *this;
}

template <template <typename> class Allocator = std::allocator>
class DepthToSnapshots
    : public EpisodeProcessor<Allocator, OrderBookSnapshot<Allocator>> {
public:
 DepthToSnapshots(ObjectStream<Level2>* depth_changes, const Price tick_size,
                  const std::size_t max_levels)
     : EpisodeProcessor<Allocator, OrderBookSnapshot<Allocator>>{depth_changes},
       tick_size_{tick_size},
       max_levels_{max_levels} {};
 DepthToSnapshots<Allocator>& operator>>(OrderBookSnapshot<Allocator>&);

protected:
 InstrumentedOrderBook<Allocator> ob_;
 Price tick_size_;
 std::size_t max_levels_;
};

template <template <typename> class Allocator>
DepthToSnapshots<Allocator>&
DepthToSnapshots<Allocator>::operator>>(
    OrderBookSnapshot<Allocator>& to_be_returned) {
 if (!this->is_all_processed_) {
  Timestamp current_timestamp = this->unprocessed_.t;
  if (this->ProcessNextEpisode(ob_)) {
   ob_.GetSnapshot(to_be_returned, tick_size_, max_levels_);
   to_be_returned.t = current_timestamp.t;
  }
  else
   this->is_all_processed_ = true;
 }
 return *this;
}
}  // namespace obadiah
#endif

