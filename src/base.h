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

#ifndef OBADIAH_BASE_H
#define OBADIAH_BASE_H

#ifndef NDEBUG
#include <boost/log/attributes/scoped_attribute.hpp>
#include <boost/log/attributes/timer.hpp>
#include <boost/log/sources/severity_feature.hpp>
#include <boost/log/sources/severity_logger.hpp>
#endif

#include <cmath>
#include <map>
#include <ostream>
#include <string>
#include <unordered_map>
#include "severity_level.h"

#ifndef NDEBUG
namespace logging = boost::log;
namespace src = boost::log::sources;
namespace sinks = boost::log::sinks;
namespace keywords = boost::log::keywords;
namespace attrs = boost::log::attributes;
#endif

namespace obadiah {
namespace R {

struct Timestamp {
 Timestamp() : t(0){};
 Timestamp(double timestamp) : t(timestamp){};
 double t;
 inline operator double() { return t; }
 inline double operator-(Timestamp a) { return t - a.t; }
 inline bool operator==(Timestamp a) { return t == a.t; }
 inline bool operator>(Timestamp a) { return t > a.t; }
 operator char*();
 constexpr static double kMicrosecond =
     0.000001;  // the minimal difference between two Timestamps

 inline Timestamp& AlignUp(double frequency) {
  if (frequency) t = std::ceil((t - kMicrosecond) / frequency) * frequency;
  return *this;
 }

 inline Timestamp& AlignDown(double frequency) {
  if (frequency) t = std::floor((t + kMicrosecond) / frequency) * frequency;
  return *this;
 }
};

using Frequency = double;

using Price = double;
constexpr double kPricePrecision =
    0.00001;  // the (theoretical) minimal difference between consequitive
              // prices
constexpr double kPricePrecisionFraction =
    0.000001;  // must be strictly less than a half of kPricePrecision

inline static Price
AlignUp(Price price, Price tick_size) {
 return tick_size > kPricePrecision
            ? std::ceil((price - kPricePrecisionFraction) / tick_size) *
                  tick_size
            : price;
}

inline static Price
AlignDown(Price price, Price tick_size) {
 return tick_size > kPricePrecision
            ? std::floor((price + kPricePrecisionFraction) / tick_size) *
                  tick_size
            : price;
}
// R's NA value.
// See R source code: src/main/arithmetics.c R_ValueOfNA()
#define R_NAREAL std::nan("1954")

using Volume = double;

inline static bool
geq(Price first, Price second) {
 return first >= second ||
        (second - first) / second <= std::numeric_limits<Price>::epsilon();
}

struct less {
 bool operator()(const Price& lhs, const Price& rhs) const {
  return !geq(lhs, rhs);
 }
};

enum Side { kBid = 'b', kAsk = 'a' };

struct Level2 {
 Level2() : t(0), p(0), v(0){};
 Timestamp t;
 Price p;
 Volume v;
 Side s;
 inline explicit operator bool() { return t != 0 || p != 0 || v != 0; }
 inline void falsify() {
  t = 0;
  p = 0;
  v = 0;
 }
 explicit operator char*();
};

struct BidAskSpread {
 BidAskSpread() : t(0), p_bid(0), p_ask(0){};
 Timestamp t;
 Price p_bid;
 Price p_ask;
 inline explicit operator bool() { return t != 0 || p_bid != 0 || p_ask != 0; }

 inline bool eq(Price p1, Price p2) {
  return (std::abs(p1 - p2) < kPricePrecision) ||
         (std::isnan(p1) && std::isnan(p2));
  ;
 }

 // Note that Timestamp t is EXCLUDED from the comparison
 inline bool operator!=(const BidAskSpread& a) {
  return !eq(p_bid, a.p_bid) || !eq(p_ask, a.p_ask);
 }
 explicit operator char*();
};

struct InstantPrice {
 InstantPrice() : p(0), t(0){};
 InstantPrice(double price, double time) : p(price), t(time){};
 Price p;
 Timestamp t;
 double operator-(const InstantPrice& e) { return std::log(p) - std::log(e.p); }
 bool operator==(const InstantPrice& e) { return p == e.p && t == e.t; }
};

struct Position {
 InstantPrice s;
 InstantPrice e;
 inline int d() { return s.p > e.p ? 1 : -1; }
};

std::ostream&
operator<<(std::ostream& stream, InstantPrice& p);

// Source of Level2's and BidAskSpread's
template <typename O>
class ObjectStream {
public:
 explicit ObjectStream() : is_all_processed_(true){};
 virtual explicit operator bool();
 virtual ObjectStream<O>& operator>>(O&) = 0;
 virtual ~ObjectStream(){};

protected:
 bool is_all_processed_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <typename O>
ObjectStream<O>::operator bool() {
 return !is_all_processed_;
}

template <template <typename> class Allocator>
class OrderBook {
public:
 OrderBook<Allocator>& operator<<(const Level2&);
 BidAskSpread GetBidAskSpread(Volume) const;

 template <template <typename> class A>
 friend std::ostream& operator<<(std::ostream&, const OrderBook<A>&);

protected:
 using PriceVolumeMap =
     std::map<Price, Volume, less, Allocator<std::pair<const Price, Volume>>>;
 PriceVolumeMap bids_;
 PriceVolumeMap asks_;
 Timestamp latest_timestamp_;
#ifndef NDEBUG
 src::severity_logger<SeverityLevel> lg;
#endif
};

template <template <typename> class Allocator, class Output>
class EpisodeProcessor : public ObjectStream<Output> {
public:
 EpisodeProcessor(ObjectStream<Level2>* depth_changes);

protected:
 bool ProcessNextEpisode(OrderBook<Allocator>&);

 ObjectStream<Level2>* depth_changes_;
 Level2 unprocessed_;
};

template <template <typename> class Allocator>
class TradingPeriod : public EpisodeProcessor<Allocator, BidAskSpread> {
public:
 TradingPeriod(ObjectStream<Level2>* depth_changes, double volume)
     : EpisodeProcessor<Allocator, BidAskSpread>{depth_changes},
       volume_(volume) {
  if (volume_ < 0) {
#ifndef NDEBUG
   BOOST_LOG_SEV(this->lg, SeverityLevel::kWarning)
       << "A wrong value for volume (" << volume_
       << ") was provided. Will use 0.0 instead";
#endif
   volume_ = 0;
  }
 };
 TradingPeriod<Allocator>& operator>>(BidAskSpread&);

protected:
 OrderBook<Allocator> ob_;
 Volume volume_;
 BidAskSpread current_;
};

template <template <typename> class Allocator>
std::ostream&
operator<<(std::ostream& stream, const OrderBook<Allocator>& ob) {
 stream << " Bids: " << ob.bids_.size() << " Asks: " << ob.asks_.size();
 return stream;
}

template <template <typename> class Allocator>
OrderBook<Allocator>&
OrderBook<Allocator>::operator<<(const Level2& next_depth) {
 latest_timestamp_ = next_depth.t;
 PriceVolumeMap* side;
 switch (next_depth.s) {
  case Side::kBid:
   side = &bids_;
   break;
  case Side::kAsk:
   side = &asks_;
   break;
 }
 if (next_depth.v == 0.0) {
  auto search = side->find(next_depth.p);
  if (search != side->end()) {
   side->erase(search);
#ifndef NDEBUG
   BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug5)
       << "From OB " << next_depth.p << " " << static_cast<char>(next_depth.s)
       << " (" << side->size() << ")";
#endif
  }
#ifndef NDEBUG
  else
   BOOST_LOG_SEV(this->lg, SeverityLevel::kWarning)
       << "From OB(NOT FOUND!)" << next_depth.p << " "
       << static_cast<char>(next_depth.s) << " (" << side->size() << ")";
#endif

 } else {
  (*side)[next_depth.p] = next_depth.v;
#ifndef NDEBUG
  BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug5)
      << "In OB " << next_depth.p << " " << static_cast<char>(next_depth.s)
      << " (" << side->size() << ")";
#endif
 }
 return *this;
};

template <template <typename> class Allocator>
BidAskSpread
OrderBook<Allocator>::GetBidAskSpread(Volume volume) const {
 // R's NA value.
 // See R source code: src/main/arithmetics.c R_ValueOfNA()
 const double kR_NaReal = std::nan("1954");
 BidAskSpread to_be_returned;
 to_be_returned.t = latest_timestamp_;
 if (volume) {
  if (!bids_.empty()) {
   double v = 0.0;
   for (auto it = bids_.rbegin(); it != bids_.rend(); it++) {
    if (v + it->second >= volume) {
     to_be_returned.p_bid += (volume - v) * it->first;
     v = volume;
     break;
    } else {
     to_be_returned.p_bid += it->first * it->second;
     v += it->second;
    }
   }
   if (v >= volume || std::isinf(volume))
    to_be_returned.p_bid /= v;
   else {
    to_be_returned.p_bid = kR_NaReal;
   }
  } else {
   to_be_returned.p_bid = kR_NaReal;
  }
  if (!asks_.empty()) {
   double v = 0.0;
   for (auto it = asks_.begin(); it != asks_.end(); it++) {
    if (v + it->second >= volume) {
     to_be_returned.p_ask += (volume - v) * it->first;
     v = volume;
     break;
    } else {
     to_be_returned.p_ask += it->first * it->second;
     v += it->second;
    }
   }
   if (v >= volume || std::isinf(volume))
    to_be_returned.p_ask /= v;
   else
    to_be_returned.p_ask = kR_NaReal;
  } else {
   to_be_returned.p_ask = kR_NaReal;
  }
 } else {
  if (!bids_.empty()) {
   to_be_returned.p_bid = bids_.rbegin()->first;
  } else {
   to_be_returned.p_bid = kR_NaReal;
  }
  if (!asks_.empty()) {
   to_be_returned.p_ask = asks_.begin()->first;
  } else {
   to_be_returned.p_ask = kR_NaReal;
  }
 }
 return to_be_returned;
};

template <template <typename> class Allocator, class Output>
EpisodeProcessor<Allocator, Output>::EpisodeProcessor(
    ObjectStream<Level2>* depth_changes)
    : depth_changes_{depth_changes} {
 if (*depth_changes_ >> unprocessed_) this->is_all_processed_ = false;
}

template <template <typename> class Allocator, class Output>
bool
EpisodeProcessor<Allocator, Output>::ProcessNextEpisode(
    OrderBook<Allocator>& ob) {
 if (unprocessed_) {
  Timestamp current_timestamp = unprocessed_.t;
  bool is_unprocessed_ = false;
  ob << unprocessed_;
  while (*depth_changes_ >> unprocessed_) {
   if (unprocessed_.t == current_timestamp)
    ob << unprocessed_;
   else {
    is_unprocessed_ = true;
    break;
   }
  }
  if (!is_unprocessed_) unprocessed_.falsify();
  return true;
 } else
  return false;
};

template <template <typename> class Allocator>
TradingPeriod<Allocator>&
TradingPeriod<Allocator>::operator>>(BidAskSpread& to_be_returned) {
 if (!this->is_all_processed_) {
  to_be_returned = current_;
#ifndef NDEBUG
  BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug2)
      << "Previous=" << static_cast<char*>(current_);
#endif
  while (this->ProcessNextEpisode(ob_)) {
   current_ = ob_.GetBidAskSpread(volume_);
#ifndef NDEBUG
   BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug3)
       << "Current=" << static_cast<char*>(current_) << ob_;
#endif
   if (current_ != to_be_returned) break;
  }
  if (current_ != to_be_returned) {
#ifndef NDEBUG
   BOOST_LOG_SEV(this->lg, SeverityLevel::kDebug2)
       << "Returned=" << static_cast<char*>(current_);
#endif
   to_be_returned = current_;
  } else
   this->is_all_processed_ = true;
 }
 return *this;
}
}  // namespace R
}  // namespace obadiah
#endif
