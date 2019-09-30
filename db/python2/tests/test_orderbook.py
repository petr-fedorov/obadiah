import unittest
from obadiah_db.orderbook import OrderBook, read_level3_csv
from decimal import Decimal


class TestOrderBook(unittest.TestCase):
    def setUp(self):

        self.order_book = OrderBook()
        self.order_book.update(read_level3_csv('level3_initial.csv'))
        self.episode = read_level3_csv('level3_episode.csv')

    def test_event_added(self):
        order_id = long(4154961174) # noqa: E0602

        self.assertIsNone(self.order_book.event(order_id))
        self.assertIsNone(self.order_book.event(order_id))
        self.assertIsNone(self.order_book.events(Decimal(7993)))
        self.order_book.update(self.episode)
        self.assertIsNotNone(self.order_book.event(order_id))
        self.assertIsNotNone(self.order_book.events(Decimal(7993)))

    def test_event_replaced(self):
        order_id = long(4154960398) # noqa: E0602
        self.assertEqual(
            self.order_book.by_order_id[order_id]["event_no"], 1)
        self.order_book.update(self.episode)
        self.assertEquals(
            self.order_book.event(order_id)["event_no"], 2)
        self.assertIsNotNone(self.order_book.events(Decimal(7992)))

    def test_event_removed(self):
        order_id = long(4154960397) # noqa: E0602
        self.assertEqual(
            self.order_book.by_order_id[order_id]["event_no"], 1)
        self.order_book.update(self.episode)
        self.assertIsNone(self.order_book.event(order_id))
        self.assertIsNone(self.order_book.events(Decimal(7990.40)))
