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
#include "position_discovery.h"
#include <boost/log/sources/record_ostream.hpp>
#include <cassert>
#include <chrono>
#include <ctime>
#include <iomanip>

namespace obadiah {
TradingStrategy::TradingStrategy(ObjectStream<BidAskSpread>* period, double phi,
                                 double rho)
    : rho_(rho),
      phi_(phi),
      is_all_processed_(true),
      trading_period_(period),
      sl_(0, 0),
      el_(0, 0),
      ss_(0, 0),
      es_(0, 0) {
 BidAskSpread c;
 // Let's find the first BidAskSpread where both prices are not NaN
 while (*trading_period_ >> c) {
  if (!(std::isnan(c.p_ask) || std::isnan(c.p_bid))) {
   sl_.p = c.p_ask;
   sl_.t = c.t;

   ss_.p = c.p_bid;
   ss_.t = c.t;
   is_all_processed_ = false;
   break;
  }
 }
};

std::ostream&
operator<<(std::ostream& stream, InstantPrice& price) {
 stream << "t: " << static_cast<char*>(price.t) << " p: " << price.p;
 return stream;
};

std::ostream&
operator<<(std::ostream& stream, Position& position) {
 stream << "Position O: " << position.s << " C: " << position.e;
 return stream;
};

TradingStrategy::operator bool() { return !is_all_processed_; }

ObjectStream<Position>&
TradingStrategy::operator>>(Position& p) {
 BidAskSpread c;
 while (*trading_period_ >> c) {
  // Currently we just skip BidAskSpreads with NaN
  if ((std::isnan(c.p_ask) || std::isnan(c.p_bid)))
   continue;  
  InstantPrice bid(c.p_bid, c.t);
  InstantPrice ask(c.p_ask, c.t);

  if (!el_.p && !es_.p) {  // No position discovered yet
   if (bid - sl_ > Interest(bid, sl_) + Commission()) {
    el_ = bid;
    ss_ = bid;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
        << "L sl_: " << sl_ << " el_(ss_):" << el_;
    continue;
   }
   if (ss_ - ask > Interest(ss_, ask) + Commission()) {
    es_ = ask;
    sl_ = ask;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
        << "S ss_: " << ss_ << " es_(sl_):" << es_;
    continue;
   }
   if (ask - sl_ < Interest(bid, sl_)) {
    sl_ = ask;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3) << "N Upd sl_: " << sl_;
   }
   if (ss_ - bid < Interest(ss_, bid)) {
    ss_ = bid;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3) << "N Upd ss_: " << ss_;
   }
  } else if (el_.p) {  // Long position has been already discovered
   if (ss_ - bid < Interest(ss_, bid)) {
    ss_ = bid;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
        << "L Upd ss_: " << ss_ << " el_: " << el_;
   }

   if (bid - el_ > Interest(bid, el_)) {
    el_ = bid;  // extending the long position
    ss_ = bid;  // short position may start only from long's end
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3) << "L Ext el_(ss_): " << bid;
   } else {
    if (ss_ - ask > Interest(ss_, ask) + Commission()) {
     BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
         << "L* sl_: " << sl_ << " el_:" << el_;
     p.s = sl_;
     p.e = el_;
     es_ = ask;
     sl_ = ask;

     el_.p = 0;
     BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
         << "S(L) ss_:" << ss_ << " es_(sl_):" << es_;
     return *this;
    } else {  // Could we close the previous long and start a new one
              // profitably?
     if (Interest(ask, el_) > Commission() - (el_ - ask)) {
      assert(es_.p == 0);
      BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
          << "L* sl_: " << sl_ << " el_:" << el_ << " ask: " << ask
          << " Interest(): " << Interest(ask, el_)
          << " Commission - (el_ - ask): " << Commission() - (el_ - ask);
      p.s = sl_;
      p.e = el_;
      sl_ = ask;
      el_.p = 0;
      return *this;
     }
    }
   }
  } else {  // Short position has been already discovered
   if (ask - sl_ < Interest(ask, sl_)) {
    sl_ = ask;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
        << "S Upd sl_: " << sl_ << " es_: " << es_;
   }

   if (es_ - ask > Interest(es_, ask)) {
    es_ = ask;  // going down ... extending short position
    sl_ = ask;
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug3) << "S Ext es_(sl_): " << ask;
   } else {
    if (bid - sl_ > Interest(sl_, bid) + Commission()) {
     BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
         << "S* ss_: " << ss_ << " es_:" << es_;
     p.s = ss_;
     p.e = es_;
     el_ = bid;
     ss_ = bid;

     es_.p = 0;
     BOOST_LOG_SEV(lg, SeverityLevel::kDebug3) << "L(S) " << sl_ << " " << el_;
     return *this;
    } else {  // Could we close the previous short and start a new one
              // profitably?

     if (Interest(bid, es_) > Commission() - (bid - es_)) {
      assert(el_.p == 0);
      BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
          << "S* ss_: " << ss_ << " es_:" << es_
          << " Interest(): " << Interest(bid, es_)
          << " Commission - (bid - es_): " << Commission() - (bid - es_);
      p.s = ss_;
      p.e = es_;
      ss_ = bid;
      es_.p = 0;
      return *this;
     }
    }
   }
  }
 }
 if (!el_.p && !es_.p) {  // No position discovered yet
  is_all_processed_ = true;
  return *this;
 } else {
  if (el_.p) {
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
       << "L* sl_: " << sl_ << " el_:" << el_;
   p.s = sl_;
   p.e = el_;
   el_.p = 0;
   return *this;
  } else {
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug3)
       << "S* ss_: " << ss_ << " es_:" << es_;
   p.s = ss_;
   p.e = es_;
   es_.p = 0;
   return *this;
  }
 }
}
}  // namespace obadiah
