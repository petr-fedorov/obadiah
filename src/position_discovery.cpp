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
#include <cassert>
#include <chrono>
#include <ctime>
#include <iomanip>
#include "log.h"

namespace obadiah {
TradingStrategy::TradingStrategy(TradingPeriod* period, double phi, double rho)
    : rho_(rho),
      phi_(phi),
      trading_period_(period),
      sl_(0, 0),
      el_(0, 0),
      ss_(0, 0),
      es_(0, 0) {
 if (trading_period_->IsNextAvailable()) {
  Spread c = trading_period_->next();

  sl_.p = c.a;
  sl_.t = c.t;

  ss_.p = c.b;
  ss_.t = c.t;
 }
};

std::ostream&
operator<<(std::ostream& stream, Spread& p) {
 using namespace std::chrono;
 duration<double> d(p.t);
 std::time_t t = d.count();
 stream << "t: " << std::put_time(std::localtime(&t), "%T") << "."
        << duration_cast<microseconds>(d).count() % 1000000 << " b: " << p.b
        << " a: " << p.a;
 return stream;
}

std::ostream&
operator<<(std::ostream& stream, InstantPrice& price) {
 using namespace std::chrono;
 duration<double> d(price.t);
 std::time_t t = d.count();
 stream << "t: " << std::put_time(std::localtime(&t), "%T") << "."
        << duration_cast<microseconds>(d).count() % 1000000
        << " p: " << price.p;
 return stream;
};

std::ostream&
operator<<(std::ostream& stream, Position& position) {
 stream << "Position O: " << position.s << " C: " << position.e;
 return stream;
};

Position
TradingStrategy::DiscoverNextPosition() {
 while (trading_period_->IsNextAvailable()) {
  Spread c = trading_period_->next();
  InstantPrice bid(c.b, c.t);
  InstantPrice ask(c.a, c.t);

  if (!el_.p && !es_.p) {  // No position discovered yet
   if (bid - sl_ > Interest(bid, sl_) + Commission()) {
    el_ = bid;
    ss_ = bid;
#ifndef NDEBUG
    L_(ldebug3) << "L sl_: " << sl_ << " el_(ss_):" << el_;
#endif
    continue;
   }
   if (ss_ - ask > Interest(ss_, ask) + Commission()) {
    es_ = ask;
    sl_ = ask;
#ifndef NDEBUG
    L_(ldebug3) << "S ss_: " << ss_ << " es_(sl_):" << es_;
#endif
    continue;
   }
   if (ask - sl_ < Interest(bid, sl_)) {
    sl_ = ask;
#ifndef NDEBUG
    L_(ldebug3) << "N Upd sl_: " << sl_;
#endif
   }
   if (ss_ - bid < Interest(ss_, bid)) {
    ss_ = bid;
#ifndef NDEBUG
    L_(ldebug3) << "N Upd ss_: " << ss_;
#endif
   }
  } else if (el_.p) {  // Long position has been already discovered
   if (ss_ - bid < Interest(ss_, bid)) {
    ss_ = bid;
#ifndef NDEBUG
    L_(ldebug3) << "L Upd ss_: " << ss_ << " el_: " << el_;
#endif
   }

   if (bid - el_ > Interest(bid, el_)) {
    el_ = bid;  // extending the long position
    ss_ = bid;  // short position may start only from long's end
#ifndef NDEBUG
    L_(ldebug3) << "L Ext el_(ss_): " << bid;
#endif
   } else {
    if (ss_ - ask > Interest(ss_, ask) + Commission()) {
#ifndef NDEBUG
     L_(ldebug3) << "L* sl_: " << sl_ << " el_:" << el_;
#endif
     Position p(sl_, el_);
     es_ = ask;
     sl_ = ask;

     el_.p = 0;
#ifndef NDEBUG
     L_(ldebug3) << "S(L) ss_:" << ss_ << " es_(sl_):" << es_;
#endif
     return p;
    } else {  // Could we close the previous long and start a new one?
     if (el_ - ask > Commission() - Interest(ask, el_)) {
      assert(es_.p == 0);
#ifndef NDEBUG
      L_(ldebug3) << "L* sl_: " << sl_ << " el_:" << el_ << " ask: " << ask
                  << " el_ - ask: " << el_ - ask
                  << " Comm() - Int(): " << Commission() - Interest(ask, el_);
#endif
      Position p(sl_, el_);
      sl_ = ask;
      el_.p = 0;
      return p;
     }
    }
   }
  } else {  // Short position has been already discovered
   if (ask - sl_ < Interest(ask, sl_)) {
    sl_ = ask;
#ifndef NDEBUG
    L_(ldebug3) << "S Upd sl_: " << sl_ << " es_: " << es_;
#endif
   }

   if (es_ - ask > Interest(es_, ask)) {
    es_ = ask;  // going down ... extending short position
    sl_ = ask;
#ifndef NDEBUG
    L_(ldebug3) << "S Ext es_(sl_): " << ask;
#endif
   } else {
    if (bid - sl_ > Interest(sl_, bid) + Commission()) {
#ifndef NDEBUG
     L_(ldebug3) << "S* ss_: " << ss_ << " es_:" << es_;
#endif
     Position p(ss_, es_);
     el_ = bid;
     ss_ = bid;

     es_.p = 0;
#ifndef NDEBUG
     L_(ldebug3) << "L(S) " << sl_ << " " << el_;
#endif
     return p;
    } else {  // Could we close the previous short and start a new one?
#ifndef NDEBUG
//      L_(ldebug3) << "S es_: " << es_ << " bid: " << bid
//                  << " Cms() - Int(): " << Commission() - Interest(bid, es_);
#endif
     if (es_ - bid > Commission() - Interest(bid, es_)) {
      assert(el_.p == 0);
#ifndef NDEBUG
      L_(ldebug3) << "S* ss_: " << ss_ << " es_:" << es_
                  << " es_ - bid: " << bid - es_
                  << " Comm() - Int(): " << Commission() - Interest(bid, es_);
#endif
      Position p(ss_, es_);
      ss_ = bid;
      es_.p = 0;
      return p;
     }
    }
   }
  }
 }
 if (!el_.p && !es_.p)  // No position discovered yet
  throw NoPositionDiscovered();
 else {
  if (el_.p) {
#ifndef NDEBUG
   L_(ldebug3) << "L* sl_: " << sl_ << " el_:" << el_;
#endif
   Position p(sl_, el_);
   el_.p = 0;
   return p;
  } else {
#ifndef NDEBUG
   L_(ldebug3) << "S* ss_: " << ss_ << " es_:" << es_;
#endif
   Position p(ss_, es_);
   es_.p = 0;
   return p;
  }
 }
}
}  // namespace obadiah
