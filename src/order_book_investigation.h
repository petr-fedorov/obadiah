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
 Volume GetVolume(Price p, Side s, Price tick_size) noexcept;
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
 class LogRelativeBidPriceLevel {
 public:
  LogRelativeBidPriceLevel(Price tick_size)
      : tick_size_{tick_size},
        price_{std::numeric_limits<Price>::infinity()} {};
  Price set(Price price, LevelNo lvl) {
   price_ = AlignUp(std::log(price) - lvl * tick_size_, tick_size_);
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
   price_ = AlignDown(std::log(price) + lvl * tick_size_, tick_size_);
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
InstrumentedOrderBook<Allocator>::GetVolume(Price p, Side s,
                                            Price tick_size) noexcept {
 Volume volume = 0.0;
 if (!tick_size) try {
   return GetVolume(p, s);
  } catch (const std::out_of_range&) {
   return 0;
  }
 if (s == Side::kBid) {
  auto price_from = AlignDown(p, tick_size);
  auto price_to = price_from + tick_size;
  for (auto it = this->bids_.lower_bound(price_from); it != this->bids_.end();
       ++it) {
   if (geq(it->first, price_to)) break;
   volume += it->second;
  }
#ifndef NDEBUG
  BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug5)
      << "Price: " << p << " Side: " << static_cast<char>(s)
      << " Volume: " << volume;
#endif
  return volume;
 } else {
  auto price_to = AlignUp(p, tick_size);
  auto price_from = price_to - tick_size;
  for (auto it = this->asks_.upper_bound(price_from); it != this->asks_.end();
       ++it) {
   if (!geq(price_to, it->first)) break;
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

struct DepthChange : public Level2 {
 ChainId id;
 Price bid_price;
 Price ask_price;
};

template <template <typename> class Allocator = std::allocator>
class DepthChanges : public ObjectStream<DepthChange> {
public:
 DepthChanges(ObjectStream<Level2>* depth_updates)
     : depth_updates_{depth_updates}, next_chain_id_{1}, current_{0} {
  ObjectStream<DepthChange>::is_all_processed_ =
      false;  // static_cast<bool>(*depth_updates);
  spread_.p_bid = R_NAREAL;
  spread_.p_ask = R_NAREAL;
 };
 DepthChanges<Allocator>& operator>>(DepthChange&);

protected:
 ChainId GetChainId(const DepthChange&);

 InstrumentedOrderBook<Allocator> ob_;
 ObjectStream<Level2>* depth_updates_;
 using ChainIds = std::map<Volume, ChainId, std::less<Volume>,
                           Allocator<std::pair<const Volume, ChainId>>>;
 ChainIds bid_chains_;
 ChainIds ask_chains_;
 ChainId next_chain_id_;
 Timestamp current_;
 BidAskSpread spread_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator>
ChainId
DepthChanges<Allocator>::GetChainId(const DepthChange& depth_change) {
 ChainIds* chain_ids;
 if (depth_change.s == Side::kBid)
  chain_ids = &bid_chains_;
 else
  chain_ids = &ask_chains_;
 auto chain = chain_ids->find(std::abs(depth_change.v));
 if (chain != chain_ids->end()) {
  return chain->second;
 } else {
  return (*chain_ids)[std::abs(depth_change.v)] = next_chain_id_++;
 }
}

template <template <typename> class Allocator>
DepthChanges<Allocator>&
DepthChanges<Allocator>::operator>>(DepthChange& depth_change) {
 Level2 depth_update;
 if (*depth_updates_ >> depth_update) {
  if (!(current_ == depth_update.t)) {
   spread_ = ob_.GetBidAskSpread(0);
   current_ = depth_update.t;
  }
  depth_change.t = depth_update.t;
  depth_change.p = depth_update.p;
  depth_change.s = depth_update.s;
  try {
   depth_change.v =
       depth_update.v - ob_.GetVolume(depth_update.p, depth_update.s);
  } catch (const std::out_of_range&) {
   depth_change.v = depth_update.v;
  }
  depth_change.id = GetChainId(depth_change);
  depth_change.bid_price = spread_.p_bid;
  depth_change.ask_price = spread_.p_ask;
  ob_ << depth_update;
 } else
  is_all_processed_ = true;
 return *this;
}

template <template <typename> class Allocator = std::allocator>
class DepthResampler : public ObjectStream<Level2> {
public:
 DepthResampler(ObjectStream<Level2>* depth_updates, Price tick_size,
                Timestamp start_time, Timestamp end_time, Frequency frequency)
     : depth_updates_{depth_updates},
       tick_size_{tick_size},
       start_time_{start_time},
       end_time_{end_time},
       frequency_{frequency} {
  if (*depth_updates >> unprocessed_) is_all_processed_ = false;
  start_time_.AlignUp(frequency);
  end_time_.AlignDown(frequency);
  if (start_time_ > end_time_) unprocessed_.falsify();
 }
 DepthResampler<Allocator>& operator>>(Level2&);

private:
 void ProcessNextEpisode();

 InstrumentedOrderBook<Allocator> ob_;
 ObjectStream<Level2>* depth_updates_;
 Price tick_size_;
 Timestamp start_time_;
 Timestamp end_time_;
 Level2 unprocessed_;
 Frequency frequency_;
 std::deque<Level2, Allocator<Level2>> output_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator>
void
DepthResampler<Allocator>::ProcessNextEpisode() {
 if (unprocessed_) {
  std::set<Price, less, Allocator<Price>> bid_prices;
  std::set<Price, less, Allocator<Price>> ask_prices;
  do {
   if (unprocessed_.t > start_time_) {
    break;
   }
   if (unprocessed_.s == Side::kBid) {
    Price aligned = AlignDown(unprocessed_.p, tick_size_);
    bid_prices.insert(aligned);
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug5)
        << "BID: timestamp: " << static_cast<char*>(start_time_)
        << " price: " << unprocessed_.p << " AlignedDown: " << aligned
        << " bid_prices.size() " << bid_prices.size();
#endif
   } else {
    Price aligned = AlignUp(unprocessed_.p, tick_size_);
    ask_prices.insert(aligned);
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug5)
        << "ASK: timestamp: " << static_cast<char*>(start_time_)
        << " price: " << unprocessed_.p << " AlignedUp: " << aligned
        << " ask_prices.size() " << ask_prices.size();
    ;
#endif
   }
   ob_ << unprocessed_;
   unprocessed_.falsify();
  } while (*depth_updates_ >> unprocessed_);
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, SeverityLevel::kDebug4)
      << "DepthResampler " << static_cast<char*>(start_time_);
#endif

  for (auto price = ask_prices.rbegin(); price != ask_prices.rend(); ++price) {
   Level2 o;
   o.t = start_time_;
   o.p = *price;
   o.v = ob_.GetVolume(*price, Side::kAsk, tick_size_);
   o.s = Side::kAsk;
   output_.push_front(o);
  }
  for (auto price = bid_prices.rbegin(); price != bid_prices.rend(); ++price) {
   Level2 o;
   o.t = start_time_;
   o.p = *price;
   o.v = ob_.GetVolume(*price, Side::kBid, tick_size_);
   o.s = Side::kBid;
   output_.push_front(o);
  }
  start_time_ = unprocessed_.t;
  start_time_.AlignUp(frequency_);
  if (start_time_ > end_time_)
   unprocessed_
       .falsify();  // Level2's is beyond end_time_, so processing is stopped
 }
}

template <template <typename> class Allocator>
DepthResampler<Allocator>&
DepthResampler<Allocator>::operator>>(Level2& out) {
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

 DepthToQueues(ObjectStream<Level2>* depth_updates, const Price tick_size,
               LevelNo first_tick, LevelNo last_tick, std::string type)
     : EpisodeProcessor<Allocator, OrderBookQueues<Allocator>>{depth_updates},
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

