// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 2 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#include "order_book.h"
#include <cmath>
#include <limits>
#include "spi_allocator.h"
namespace obad {

class order_book::order_book_side : public postgres_heap {
public:
 order_book_side(char s) : side(s){};
 void update(level3 &&);
 // returns all level2s changed since the latest clean_touched()
 void clean_touched(obad::deque<level2> *);

private:
 inline amount get_price_level_volume(const price p) const {
  amount volume = 0;
  try {
   const obad::unordered_set<level3 *> &level3s{by_price.at(p)};
   for (const level3 *l3 : level3s) {
    volume += l3->get_volume();
   }
  } catch (const std::out_of_range &oor) {
  };
  return volume;
 };

 obad::map<price, level2> touched;

 char side;
 obad::map<uint64, level3> by_order_id;
 obad::map<price, obad::unordered_set<level3 *>> by_price;
};

order_book::order_book() {
 bids = new (allocation_mode::non_spi) order_book::order_book_side{'b'};
 asks = new (allocation_mode::non_spi) order_book::order_book_side{'s'};
};

order_book::~order_book() {
 delete bids;
 delete asks;
};

void
order_book::order_book_side::clean_touched(obad::deque<level2> *output) {
#if DEBUG_DEPTH
 elog(DEBUG3, "%s starts side %c", __PRETTY_FUNCTION__, side);
#endif
 if (output) {
  for (auto &pl : touched) {
   level2 &l2 = pl.second;
   price p = l2.get_price();
   amount current = get_price_level_volume(p);
#if DEBUG_DEPTH
   elog(DEBUG4, "%s processing price: %.5Lf. volume before: %.8Lf after: %.8Lf",
        __PRETTY_FUNCTION__, p, l2.get_volume(), current);
#endif
   if (std::fabs(current - l2.get_volume()) >
       10*std::numeric_limits<amount>::epsilon()) {
    l2.set_volume(current);
    output->push_back(std::move(l2));
   }
#if DEBUG_DEPTH
   elog(DEBUG3, "%s side %c output size %lu after processing price %.5Lf",
        __PRETTY_FUNCTION__, side, output->size(), p);
#endif
  }
 }
 touched.clear();
#if DEBUG_DEPTH
 elog(DEBUG3, "%s ends side %c", __PRETTY_FUNCTION__, side);
#endif
};

void
order_book::order_book_side::update(level3 &&l3) {
#if DEBUG_DEPTH
 elog(DEBUG3, "%s side %c start processing %s", __PRETTY_FUNCTION__, side,
      to_string<level3>(l3).c_str());
#endif
 // First, save volume for the modified price levels BEFORE update
 level3 *previous_l3{nullptr};

 price changed_prices[2];
 int num_of_changed = 1;
 changed_prices[0] = l3.get_price();

 try {
  previous_l3 = &by_order_id.at(l3.get_order_id());
  changed_prices[1] = previous_l3->get_price();
  if (changed_prices[1] != changed_prices[0]) num_of_changed = 2;
 } catch (const std::out_of_range &oor) {
 };

 for (int i = 0; i < num_of_changed; i++) {
  price p = changed_prices[i];
  try {
   touched.at(p);
#if DEBUG_DEPTH
   elog(DEBUG3, "%s side %c price %.5Lf is already saved", __PRETTY_FUNCTION__,
        side, p);
#endif
  } catch (const std::out_of_range &oor) {
   amount volume = get_price_level_volume(p);
   level2 l2{l3.get_episode(), side, p, volume};
   touched[p] = std::move(l2);
#if DEBUG_DEPTH
   elog(DEBUG3, "%s side %c price %.5Lf is saved with volume %.8Lf",
        __PRETTY_FUNCTION__, side, p, volume);
#endif
  }
 }
 // Second, remove from the order book the  previous level3 event for the given
 // order_id, if any
 if (previous_l3) {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s side %c removed previous %s", __PRETTY_FUNCTION__, side,
       to_string<level3>(*previous_l3).c_str());
#endif
  size_t erased = by_price.at(previous_l3->get_price()).erase(previous_l3);
  if (erased != 1)
   ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                   errmsg("couldn't erase pointer to level3 %lu from the set",
                          previous_l3->get_order_id())));
  erased = by_order_id.erase(previous_l3->get_order_id());
  if (erased != 1)
   ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
                   errmsg("couldn't erase level3 %lu from the map",
                          previous_l3->get_order_id())));
  previous_l3 = nullptr;
 }
 // Third, append new level3 into the order book if it's not an order_deleted
 if (!l3.is_deleted()) {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s side %c added %s", __PRETTY_FUNCTION__, side,
       to_string<level3>(l3).c_str());
#endif
  price p = l3.get_price();
  uint64 oid = l3.get_order_id();
  by_price[p].insert(&(by_order_id[oid] = std::move(l3)));
 } else {
#if DEBUG_DEPTH
  elog(DEBUG3, "%s side %c skipped %s (order_deleted event)",
       __PRETTY_FUNCTION__, side, to_string<level3>(l3).c_str());
#endif
 }
};

void
order_book::update(std::vector<level3> &&v, obad::deque<level2> *result) {
#if DEBUG_DEPTH
 elog(DEBUG2, "%s with %lu level3 records", __PRETTY_FUNCTION__, v.size());
#endif
 for (level3 &l3 : v) by_side(l3.get_side())->update(std::move(l3));

 bids->clean_touched(result);
 asks->clean_touched(result);
};
}  // namespace obad
