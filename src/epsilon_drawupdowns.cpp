// Copyright (C) 2020 Petr Fedorov <petr.fedorov@phystech.edu>

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
#include "epsilon_drawupdowns.h"

#ifndef NDEBUG
#include <boost/log/sources/record_ostream.hpp>
#endif

namespace obadiah {

std::ostream&
operator<<(std::ostream& stream, EpsilonDrawUpDowns& p) {
 stream << "st_:" << p.st_ << " tp_:" << p.tp_ << " en_:" << p.en_
        << " delta:" << std::abs(p.en_ - p.tp_) << " epsilon_:" << p.epsilon_
        << " is_all_processed_:" << p.is_all_processed_;
 return stream;
}

EpsilonDrawUpDowns::EpsilonDrawUpDowns(ObjectStream<InstantPrice>* period,
                                       double epsilon)
    : trading_period_(period), epsilon_(epsilon) {
 if (*trading_period_ >> st_) {
  tp_ = st_;
  en_ = st_;
  is_all_processed_ = false;
 }
#ifndef NDEBUG
 BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << "Created " << *this;
#endif
}

ObjectStream<Position>&
EpsilonDrawUpDowns::operator>>(Position& pos) {
 if (!is_all_processed_) {
  while (*trading_period_ >> en_) {
#ifndef NDEBUG
   BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << "End point " << en_;
#endif
   if (en_.p == tp_.p) {
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << *this;
#endif
    continue;
   }
   if ((tp_.p >= st_.p && en_.p > tp_.p) || (tp_.p <= st_.p && en_.p < tp_.p)) {
    tp_ = en_;  // Extend the draw, set the new turning point
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << "E " << *this;
#endif
    continue;
   } else {
    double delta = std::abs(en_ - tp_);
    if (delta > epsilon_) {
     pos.s = st_;
     pos.e = tp_;
     st_ = tp_;
#ifndef NDEBUG
     BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << "N " << *this;
#endif
     return *this;
    }
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, SeverityLevel::kDebug4) << "TP " << *this;
#endif
    continue;
   }
  }
  if (en_.t.t > st_.t.t) {
   pos.s = st_;
   pos.e = en_;
   st_ = en_;
  } else
   is_all_processed_ = true;
 }
 return *this;
}

}  // namespace obadiah
