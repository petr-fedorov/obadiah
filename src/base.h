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
#include <boost/log/sources/severity_feature.hpp>
#include <boost/log/sources/severity_logger.hpp>
#include <cmath>
#include <map>
#include <ostream>
#include <string>
#include <unordered_map>
#include "severity_level.h"

namespace logging = boost::log;
namespace src = boost::log::sources;
namespace sinks = boost::log::sinks;
namespace keywords = boost::log::keywords;
namespace obadiah {


struct Timestamp {
 Timestamp() : t(0){};
 Timestamp(double timestamp) : t(timestamp){};
 double t;
 inline operator double() { return t; }
 inline double operator-(Timestamp a) { return t - a.t; }
 inline bool operator==(Timestamp a) { return t == a.t; }
 operator char*();
};

using Price = double;
constexpr double kPricePrecision = 0.00001;

using Volume = double;

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

// Source of Level2's and BidAskSpread's
template <typename O>
class ObjectStream {
public:
 virtual explicit operator bool() = 0;
 virtual ObjectStream<O>& operator>>(O&) = 0;
 virtual ~ObjectStream(){};
};

template <template <typename> class Allocator,
          typename T = std::pair<const Price, Volume>>
class OrderBook {
public:
 OrderBook<Allocator, T>& operator<<(const Level2&);
 BidAskSpread GetBidAskSpread(Volume) const;

 template <template <typename> class A, typename B>
 friend std::ostream& operator<<(std::ostream&, const OrderBook<A, B>&);

private:
 std::map<Price, Volume, std::less<Price>, Allocator<T>> bids_;
 std::map<Price, Volume, std::less<Price>, Allocator<T>> asks_;
 Timestamp latest_timestamp_;
 src::severity_logger<SeverityLevel> lg;
};

template <template <typename> class Allocator,
          typename T = std::pair<const Price, Volume>>
class TradingPeriod : ObjectStream<BidAskSpread> {
public:
 TradingPeriod(ObjectStream<Level2>* depth_changes, double volume);
 explicit operator bool();
 TradingPeriod<Allocator, T>& operator>>(BidAskSpread&);

protected:
 bool ProcessNextEpisode();

 OrderBook<Allocator, T> ob_;
 ObjectStream<Level2>* depth_changes_;
 Volume volume_;
 Level2 unprocessed_;
 BidAskSpread current_;
 bool is_failed_;

 src::severity_logger<SeverityLevel> lg;
};

template <template <typename> class Allocator, typename T>
std::ostream&
operator<<(std::ostream& stream, const OrderBook<Allocator, T>& ob) {
 stream << " Bids: " << ob.bids_.size() << " Asks: " << ob.asks_.size();
 return stream;
}

template <template <typename> class Allocator, typename T>
OrderBook<Allocator, T>&
OrderBook<Allocator, T>::operator<<(const Level2& next_depth) {
 latest_timestamp_ = next_depth.t;
 std::map<Price, Volume, std::less<Price>, Allocator<T>>* side;
 switch (next_depth.s) {
  case Side::kBid:
   side = &bids_;
   break;
  case Side::kAsk:
   side = &asks_;
   break;
 }
 if (next_depth.v == 0.0){
  auto search = side->find(next_depth.p);
  if(search != side->end()) {
   side->erase(search);
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug5) << "From OB " << next_depth.p << " " << static_cast<char>(next_depth.s) << " (" << side->size() << ")";
  }
  else 
   BOOST_LOG_SEV(lg, SeverityLevel::kWarning) << "From OB(NOT FOUND!)" << next_depth.p << " " << static_cast<char>(next_depth.s) << " (" << side->size() << ")";

 }
 else{
  (*side)[next_depth.p] = next_depth.v;
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug5) << "In OB " << next_depth.p << " " << static_cast<char>(next_depth.s) << " (" << side->size() << ")";
 }
 return *this;
};

template <template <typename> class Allocator, typename T>
BidAskSpread
OrderBook<Allocator, T>::GetBidAskSpread(Volume volume) const {
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
   if (v >= volume)
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
   if (v >= volume)
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

template <template <typename> class Allocator, typename T>
TradingPeriod<Allocator, T>::TradingPeriod(ObjectStream<Level2>* depth_changes,
                                           double volume)
    : depth_changes_(depth_changes), volume_(volume), is_failed_(false) {
 if (!(*depth_changes_ >> unprocessed_)) is_failed_ = true;
}

template <template <typename> class Allocator, typename T>
TradingPeriod<Allocator, T>::operator bool() {
 return !is_failed_;
}

template <template <typename> class Allocator, typename T>
bool
TradingPeriod<Allocator, T>::ProcessNextEpisode() {
 if (unprocessed_) {
  Timestamp current_timestamp = unprocessed_.t;
  bool is_unprocessed_ = false;
  ob_ << unprocessed_;
  while (*depth_changes_ >> unprocessed_) {
   if (unprocessed_.t == current_timestamp)
    ob_ << unprocessed_;
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

template <template <typename> class Allocator, typename T>
TradingPeriod<Allocator, T>&
TradingPeriod<Allocator, T>::operator>>(BidAskSpread& to_be_returned) {
 if (!is_failed_) {
  to_be_returned = current_;
  BOOST_LOG_SEV(lg, SeverityLevel::kDebug2) << "Previous=" << static_cast<char*>(current_);
  while (ProcessNextEpisode()) {
   current_ = ob_.GetBidAskSpread(volume_);
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
       << "Current=" << static_cast<char*>(current_) << ob_;
   if (current_ != to_be_returned) break;
  }
  if (current_ != to_be_returned) {
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug2) << "Returned=" << static_cast<char*>(current_);
   to_be_returned = current_;
  } else
   is_failed_ = true;
 }
 return *this;
}
}  // namespace obadiah
#endif
