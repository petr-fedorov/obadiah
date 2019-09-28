import unittest
from csv import DictReader
from obadiah_db.orderbook import OrderBook
from decimal import Decimal


class TestOrderBook(unittest.TestCase):
    def setUp(self):
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

        with open('level3_initial.csv') as f:
            self.order_book = OrderBook([
               level3(x) for x in DictReader(f, skipinitialspace=True)])

        with open('level3_episode.csv') as f:
            self.episode = [
               level3(x) for x in DictReader(f, skipinitialspace=True)]

    def test_event_added(self):
        order_id = long(4154961174) # noqa: E0602

        self.assertIsNone(self.order_book.by_order_id.get(order_id))
        self.assertIsNone(self.order_book.by_order_id.get(order_id))
        self.assertIsNone(self.order_book.by_price.get(Decimal(7993)))
        self.order_book.update(self.episode)
        self.assertIsNotNone(self.order_book.by_order_id.get(order_id))
        self.assertIsNotNone(self.order_book.by_price.get(Decimal(7993)))

    def test_event_replaced(self):
        order_id = long(4154960398) # noqa: E0602
        self.assertEqual(
            self.order_book.by_order_id[order_id]["event_no"], 1)
        self.order_book.update(self.episode)
        self.assertEquals(
            self.order_book.by_order_id.get(order_id)["event_no"], 2)
        self.assertIsNotNone(self.order_book.by_price.get(Decimal(7992)))

    def test_event_removed(self):
        order_id = long(4154960397) # noqa: E0602
        self.assertEqual(
            self.order_book.by_order_id[order_id]["event_no"], 1)
        self.order_book.update(self.episode)
        self.assertIsNone(self.order_book.by_order_id.get(order_id))
        self.assertIsNone(self.order_book.by_price.get(Decimal(7990.40)))
