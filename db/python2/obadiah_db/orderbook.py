from sortedcollections import SortedList, SortedDict
from csv import DictReader
from decimal import Decimal
import logging


def event_log(e):
    return "{0} {1} {2} {3} {4} {5} n:{6} n:{7} p:{8} p:{9}".format(
        e["microtimestamp"], e["order_id"], e["event_no"], e["side"],
        e["price"], e["amount"], e["next_microtimestamp"], e["next_event_no"],
        e["price_microtimestamp"], e["price_event_no"])


def price_level_log(price, price_level):
    return "p:{0} b:{1} s:{2} e:[{3}]".format(
        price, price_level.amount('b'), price_level.amount('s'),
        ", ".join(
            ["{0} {1} {2}".format(
                e["order_id"],
                e["event_no"],
                e["side"]) for e in price_level.events()]))


def read_level3_csv(filename):
    def level3(d):
        '''
            Converts types of dictionary entries as described in
            paragraph 46.3.1. Data Type Mapping PostgreSQL 11.5
            Documentation. The other entries should be str
        '''
        d["order_id"] = long(d["order_id"]) # noqa: E0602
        d["event_no"] = int(d["event_no"])
        d["price"] = Decimal(d["price"])
        d["amount"] = Decimal(d["amount"])
        d["fill"] = Decimal(d["fill"])
        if d["next_event_no"].strip() != 'NULL':
            d["next_event_no"] = int(d["next_event_no"])
        else:
            d["next_event_no"] = None
        d["pair_id"] = int(d["pair_id"])
        d["exchange_id"] = int(d["exchange_id"])
        d["price_event_no"] = int(d["price_event_no"])
        d["is_maker"] = bool(d["is_maker"])
        d["is_crossed"] = bool(d["is_crossed"])
        return d

    with open(filename) as f:
        return [level3(x) for x in DictReader(f, skipinitialspace=True)]


class PriceLevel(object):
    def __init__(self):
        self.amounts = {}
        self.e = SortedList(
            key=lambda e: (e["price_microtimestamp"],
                           e["microtimestamp"],
                           e["order_id"]))

    def add(self, e):
        self.e.add(e)
        self.amounts[e["side"]] = self.amounts.get(e["side"],
                                                   Decimal(0)) + e["amount"]

    def remove(self, e):
        self.e.remove(e)
        self.amounts[e["side"]] -= e["amount"]
        if self.amounts[e["side"]] < 1e-5:
            # check whether the amount is actually zero
            found = False
            for ev in self.e:
                if ev["side"] == e["side"]:
                    found = True
                    break
            if not found:
                self.amounts[e["side"]] = Decimal(0)

    def amount(self, side):
        return self.amounts.get(side)

    def events(self):
        return self.e

    def purge(self):
        '''
        Leaves only non-zeros in self.amounts in order to identify the episode
        when the zero amount will be zeroed out next time.
        '''
        for side in ['b', 's']:
            if self.amounts.get(side) == Decimal(0):
                del self.amounts[side]


class OrderBook(object):

    def __init__(self, log_enabled=False):
        self.by_price = SortedDict()
        self.by_order_id = {}
        self.log_enabled = log_enabled
        self.logger = logging.getLogger(__name__)

    def _add(self, e):
        if e["next_microtimestamp"] != '-infinity':
            if self.log_enabled:
                self.logger.debug('Add %s', event_log(e))

            price_level = self.by_price.get(e["price"])
            if price_level is None:
                price_level = PriceLevel()
                self.by_price[e["price"]] = price_level
            price_level.add(e)
            self.by_order_id[e["order_id"]] = e
            self.changed_price_levels[e["price"]] = price_level
            if self.log_enabled:
                self.logger.debug('PL-add: %s', price_level_log(e["price"],
                                                                price_level))

            return True
        else:
            self.logger.debug('Ign %s', event_log(e))
            return False

    def _remove(self, order_id):
        old_event = self.by_order_id.pop(order_id, None)
        if old_event is not None:
            if self.log_enabled:
                self.logger.debug('Del %s', event_log(old_event))
            old_price_level = self.by_price[old_event["price"]]
            old_price_level.remove(old_event)
            if self.log_enabled:
                self.logger.debug('PL-del: %s',
                                  price_level_log(old_event["price"],
                                                  old_price_level))
            self.changed_price_levels[old_event["price"]] = old_price_level

        return old_event

    def update(self, episode):
        if self.log_enabled:
            self.logger.debug('OB update %s starts',
                              episode[0]["microtimestamp"])
        episode = sorted(episode, key=lambda e: e["event_no"])
        self.changed_price_levels = SortedDict()
        for e in episode:
            if e["event_no"] > 1:
                self._remove(e["order_id"])
            self._add(e)

        result = []
        for price in self.changed_price_levels.keys():
            price_level = self.changed_price_levels[price]
            if self.log_enabled:
                self.logger.debug('Changed PL: %s',
                                  price_level_log(price, price_level))
            for side in ['b', 's']:
                amount = price_level.amount(side)
                if amount >= Decimal(0):
                    # obanalytics.level2_depth_record
                    result.append({"price": price,
                                   "volume": amount,
                                   "side": side,
                                   "bps_level": None})
            price_level.purge()
            if price_level.amount("s") is None and\
                    price_level.amount("b") is None:
                del self.by_price[price]

        if self.log_enabled:
            self.logger.debug('OB update %s ends',
                              episode[0]["microtimestamp"])
        return result

    def event(self, order_id):
        return self.by_order_id.get(order_id)

    def events(self, price):
        price_level = self.by_price.get(price)
        if price_level is not None:
            return price_level.events()
        else:
            return None

    def all_events(self):
        best_bid_price = None
        best_sell_price = None
        for price in self.by_price:
            for e in self.by_price[price].events():
                if e["side"] == 'b':
                    if best_bid_price is None or e["price"] > best_bid_price:
                        best_bid_price = e["price"]
                    if best_sell_price is None:
                        e["is_maker"] = True
                        e["is_crossed"] = False
                    elif e["price"] <= best_sell_price:
                        e["is_maker"] = True
                        if e["price"] > best_sell_price:
                            e["is_crossed"] = True
                        else:
                            e["is_crossed"] = False
                    else:
                        e["is_maker"] = False
                        e["is_crossed"] = True
                else:
                    if best_sell_price is None or e["price"] < best_sell_price:
                        best_sell_price = e["price"]
                    if best_bid_price is None:
                        e["is_maker"] = True
                        e["is_crossed"] = False
                    elif e["price"] >= best_bid_price:
                        e["is_maker"] = True
                        if e["price"] < best_bid_price:
                            e["is_crossed"] = True
                        else:
                            e["is_crossed"] = False
                    else:
                        e["is_maker"] = False
                        e["is_crossed"] = True
                yield e
