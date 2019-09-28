from sortedcollections import SortedList, SortedDict
import logging


def event_log(e):
    return "{0} {1} {2} {3} n:{4} n:{5} p:{6} p:{7}".format(
        e["microtimestamp"], e["order_id"], e["event_no"], e["price"],
        e["next_microtimestamp"], e["next_event_no"],
        e["price_microtimestamp"], e["price_event_no"])


class OrderBook(object):

    def __init__(self, events, log_enabled=False):
        self.by_price = SortedDict()
        self.by_order_id = {}
        self.log_enabled = log_enabled
        self.logger = logging.getLogger(__name__)
        for e in events:
            self.add(e)

    def add(self, e):
        if e["next_microtimestamp"] != '-infinity':
            if self.log_enabled:
                self.logger.debug('Add %s', event_log(e))

            if self.by_price.get(e["price"]) is None:
                self.by_price[e["price"]] = SortedList(
                    key=lambda e: (e["price_microtimestamp"],
                                   e["microtimestamp"],
                                   e["order_id"]))
            self.by_price[e["price"]].add(e)
            self.by_order_id[e["order_id"]] = e
        else:
            self.logger.debug('Ign %s', event_log(e))

    def remove(self, order_id):
        old_event = self.by_order_id.pop(order_id, None)
        if old_event is not None:
            if self.log_enabled:
                self.logger.debug('Del %s', event_log(old_event))
            old_price_level = self.by_price[old_event["price"]]
            old_price_level.remove(old_event)

    def update(self, episode):
        for e in episode:
            self.remove(e["order_id"])
            self.add(e)

    def output(self):
        for price in self.by_price:
            for e in self.by_price[price]:
                yield e
