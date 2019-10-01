import unittest
from obadiah_db.orderbook import OrderBook, read_level3_csv
from decimal import Decimal
import logging

logging.basicConfig(filename='obadiah_db.log', level=logging.DEBUG)


class TestOrderBook(unittest.TestCase):
    def setUp(self):

        logging.debug('Setup starts')
        self.order_book = OrderBook(True)
        self.order_book.update(read_level3_csv('level3_initial.csv'))
        self.episode = read_level3_csv('level3_episode.csv')
        logging.debug('Setup ends')

    # @unittest.skip("")
    def test_event_added(self):
        order_id = long(4154961174) # noqa: E0602

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

    # @unittest.skip("")
    def test_event_removed(self):
        order_id = long(4154960397) # noqa: E0602
        self.assertEqual(
            self.order_book.by_order_id[order_id]["event_no"], 1)
        self.order_book.update(self.episode)
        self.assertIsNone(self.order_book.event(order_id))
        self.assertIsNone(self.order_book.events(Decimal(7990.40)))

    def test_initial_spread(self):
        self.assertEqual(self.order_book.best_bid_level.price, Decimal('7989'))
        self.assertEqual(self.order_book.best_ask_level.price,
                         Decimal('7990.40'))

    def test_spread_after_episode(self):
        logging.debug('spread_after_episode')
        self.order_book.update(self.episode)
        self.assertEqual(self.order_book.best_bid_level.price, Decimal('7990'))
        self.assertEqual(self.order_book.best_ask_level.price,
                         Decimal('7992'))
