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

#include "depth.h"

namespace obad {

level1
depth::spread() {
 price best_bid_price{-1}, best_ask_price{-1};
 amount best_bid_qty{-1}, best_ask_qty{-1};

 if (!bid.empty()) {
  level2 &best_level = bid.rbegin()->second;
  best_bid_price = best_level.get_price();
  best_bid_qty = best_level.get_volume();
 }

 if (!ask.empty()) {
  level2 &best_level = ask.begin()->second;
  best_ask_price = best_level.get_price();
  best_ask_qty = best_level.get_volume();
 }

 return level1{best_bid_price, best_bid_qty, best_ask_price, best_ask_qty,
               episode};
}

level1
depth::update(obad::deque<obad::level2> *v) {
 if (!v->empty()) episode = v->front().get_microtimestamp();
 while(!v->empty()) {
  level2 &l {v->front()};
  if (l.get_volume() > 0)
   if (l.get_side() == 'b')
    bid[l.get_price()] = std::move(l);
   else
    ask[l.get_price()] = std::move(l);
  else if (l.get_side() == 'b')
   bid.erase(l.get_price());
  else
   ask.erase(l.get_price());
  v->pop_front();
 }
 return spread();
};

level1
depth::update(std::vector<level2> v) {
 if (!v.empty()) episode = v[0].get_microtimestamp();
 for (level2 &l : v) {
  if (l.get_volume() > 0)
   if (l.get_side() == 'b')
    bid[l.get_price()] = std::move(l);
   else
    ask[l.get_price()] = std::move(l);
  else if (l.get_side() == 'b')
   bid.erase(l.get_price());
  else
   ask.erase(l.get_price());
 }
 return spread();
};

depth::~depth() {
#if DEBUG_SPREAD
 elog(DEBUG1, "~depth");
#endif
}
}  // namespace obad
