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
#include <limits>
#include <set>
#include <vector>
#include "base.h"

#ifndef NDEBUG
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_feature.hpp>
#include <boost/log/sources/severity_logger.hpp>
#endif

namespace obadiah {
namespace R {
template <template <typename> class Allocator = std::allocator>
struct OrderBookQueues {
 using Queues = std::vector<Volume, Allocator<Volume>>;
 Timestamp t;
 Price bid_price;
 Price ask_price;
 Queues bids;
 Queues asks;
};

enum class TickSizeType { kAbsolute, kLogRelative };
TickSizeType
GetTickSizeType(const std::string s);

template <template <typename> class Allocator = std::allocator>
class InstrumentedOrderBook : public OrderBook<Allocator> {
 using Pair = std::pair<const Price, Volume>;

public:
 using LevelNo = unsigned;
 Volume GetVolume(Price p, Side s);
 Volume GetVolume(Price p, Side s, Price tick_size);
 inline void GetQueues(OrderBookQueues<Allocator>& ds, const Price tick_size,
                       LevelNo first_tick, LevelNo last_tick,
                       TickSizeType type) {
  switch (type) {
   case TickSizeType::kAbsolute:
    GetBidsQueues(ds, first_tick, last_tick, AbsoluteBidPriceLevel{tick_size});
    GetAsksQueues(ds, first_tick, last_tick, AbsoluteAskPriceLevel{tick_size});
    break;
   case TickSizeType::kLogRelative:
    GetBidsQueues(ds, first_tick, last_tick,
                  LogRelativeBidPriceLevel{tick_size});
    GetAsksQueues(ds, first_tick, last_tick,
                  LogRelativeAskPriceLevel{tick_size});
    break;
  }
 }

protected:
 inline static bool geq(Price first, Price second) {
  return first >= second ||
         (second - first) / second <= std::numeric_limits<Price>::epsilon();
 }

 inline static Price AlignUp(Price price, Price tick) {
  Price result = std::round(price/tick)*tick;
  if(!geq(result, price))
   result += tick;
  return result;
 }
 inline static Price AlignDown(Price price, Price tick) {
  Price result = std::round(price/tick)*tick;
  if(!geq(price, result))
   result -= tick;
  return result;
 }

 class LogRelativeBidPriceLevel {
 public:
  LogRelativeBidPriceLevel(Price tick_size)
      : tick_size_{tick_size},
        price_{std::numeric_limits<Price>::infinity()} {};
  Price set(Price price, LevelNo lvl) {
   price_ = AlignUp(std::log(price) - lvl*tick_size_, tick_size_);
   return std::exp(price_);
  }
  inline bool encompass(Price price) {
   price = std::log(price);
   return geq(price, price_);
  }

  inline Price BestBidPrice(Price actual_bid) {
   return std::exp(AlignDown(std::log(actual_bid), tick_size_));
  }

 private:
  Price tick_size_;
  Price price_;
 };
 class AbsoluteBidPriceLevel {
 public:
  AbsoluteBidPriceLevel(Price tick_size)
      : tick_size_{tick_size},
        price_{std::numeric_limits<Price>::infinity()} {};
  Price set(Price price, LevelNo lvl) {
   price_ = AlignUp(price - lvl * tick_size_, tick_size_);
   return price_;
  }
  inline bool encompass(Price price) { return geq(price, price_); }
  inline Price BestBidPrice(Price actual_bid) {
   return AlignDown(actual_bid, tick_size_);
  }

 private:
  Price tick_size_;
  Price price_;
 };
 class LogRelativeAskPriceLevel {
 public:
  LogRelativeAskPriceLevel(Price tick_size)
      : tick_size_{tick_size},
        price_{-std::numeric_limits<Price>::infinity()} {};
  Price set(Price price, LevelNo lvl) {
   price_ = AlignDown(std::log(price) + lvl*tick_size_, tick_size_);
   return std::exp(price_);
  }
  inline bool encompass(Price price) {
   price = std::log(price);
   return geq(price_, price);
  }
  inline Price BestAskPrice(Price actual_ask) {
   return std::exp(AlignUp(std::log(actual_ask), tick_size_));
  }

 private:
  Price tick_size_;
  Price price_;
 };
 class AbsoluteAskPriceLevel {
 public:
  AbsoluteAskPriceLevel(Price tick_size)
      : tick_size_{tick_size},
        price_{-std::numeric_limits<Price>::infinity()} {};
  Price set(Price price, LevelNo lvl) {
   price_ = AlignDown(price + lvl * tick_size_, tick_size_);
   return price_;
  }
  inline bool encompass(Price price) { return geq(price_, price); }
  inline Price BestAskPrice(Price actual_ask) {
   return AlignUp(actual_ask, tick_size_);
  }

 private:
  Price tick_size_;
  Price price_;
 };
 template <typename T>
 void GetBidsQueues(OrderBookQueues<Allocator>&, LevelNo, LevelNo,
                    T&& price_level);
 template <typename T>
 void GetAsksQueues(OrderBookQueues<Allocator>&, LevelNo, LevelNo,
                    T&& price_level);
};

template <template <typename> class Allocator>
template <typename T>
void
InstrumentedOrderBook<Allocator>::GetBidsQueues(OrderBookQueues<Allocator>& ds,
                                                LevelNo first_tick,
                                                LevelNo last_tick,
                                                T&& price_level) {
 auto it = OrderBook<Allocator>::bids_.crbegin();
 if (it != this->bids_.crend()) 
  ds.bid_price = price_level.BestBidPrice(it->first);
 else
  ds.bid_price = R_NAREAL;

 ds.bids.clear();
 ds.bids.reserve(last_tick - first_tick + 1);
 ds.bids.shrink_to_fit();

 Price start = std::numeric_limits<Price>::infinity();
 if (this->asks_.cbegin() != this->asks_.cend())
  start = this->asks_.cbegin()->first;
 it = typename OrderBook<Allocator>::PriceVolumeMap::reverse_iterator{
     this->bids_.lower_bound(price_level.set(start, first_tick - 1))};
 for (auto lvl = first_tick; lvl <= last_tick; ++lvl) {
  Volume vol = 0.0;
  price_level.set(start, lvl);
  for (; it != this->bids_.crend(); ++it)
   if (price_level.encompass(it->first))
    vol += it->second;
   else
    break;
  ds.bids.push_back(vol);
 }
}

template <template <typename> class Allocator>
template <typename T>
void
InstrumentedOrderBook<Allocator>::GetAsksQueues(OrderBookQueues<Allocator>& ds,
                                                LevelNo first_tick,
                                                LevelNo last_tick,
                                                T&& price_level) {
 auto it = this->asks_.cbegin();
 if (it != this->asks_.cend())
  ds.ask_price = price_level.BestAskPrice(it->first);
 else
  ds.ask_price = R_NAREAL;

 ds.asks.clear();
 ds.asks.reserve(last_tick - first_tick + 1);
 ds.asks.shrink_to_fit();

 Price start = -std::numeric_limits<Price>::infinity();
 if (this->bids_.crbegin() != this->bids_.crend())
  start = this->bids_.crbegin()->first;
 it = this->asks_.upper_bound(price_level.set(start, first_tick - 1));
 for (auto lvl = first_tick; lvl <= last_tick; ++lvl) {
  Volume vol = 0.0;
  price_level.set(start, lvl);
  for (; it != this->asks_.cend(); ++it)
   if (price_level.encompass(it->first))
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
  BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug5)
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
  BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug5)
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
  BOOST_LOG_SEV(lg, SeverityLevel::kDebug4)
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
class DepthToQueues
    : public EpisodeProcessor<Allocator, OrderBookQueues<Allocator>> {
public:
 using LevelNo = typename InstrumentedOrderBook<Allocator>::LevelNo;

 DepthToQueues(ObjectStream<Level2>* depth_changes, const Price tick_size,
               LevelNo first_tick, LevelNo last_tick, std::string type)
     : EpisodeProcessor<Allocator, OrderBookQueues<Allocator>>{depth_changes},
       tick_size_{tick_size},
       first_tick_{first_tick},
       last_tick_{last_tick},
       type_{GetTickSizeType(type)} {};
 DepthToQueues<Allocator>& operator>>(OrderBookQueues<Allocator>&);

protected:
 InstrumentedOrderBook<Allocator> ob_;
 Price tick_size_;
 LevelNo first_tick_;
 LevelNo last_tick_;
 TickSizeType type_;
};

template <template <typename> class Allocator>
DepthToQueues<Allocator>&
DepthToQueues<Allocator>::operator>>(
    OrderBookQueues<Allocator>& to_be_returned) {
 if (!this->is_all_processed_) {
  Timestamp current_timestamp = this->unprocessed_.t;
  if (this->ProcessNextEpisode(ob_)) {
   ob_.GetQueues(to_be_returned, tick_size_, first_tick_, last_tick_, type_);
   to_be_returned.t = current_timestamp.t;
  } else
   this->is_all_processed_ = true;
 }
 return *this;
}
}  // namespace R
}  // namespace obadiah
#endif

