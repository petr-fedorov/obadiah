import unittest
from obanalyticsdb.bitfinex import OrderBookEvent, Trade, Orderer
from multiprocessing import Process, Queue, Event
from queue import Empty
from datetime import datetime, timedelta
from time import sleep


class TestPutInOrder(unittest.TestCase):
    def setUp(self):
        self.q_in = Queue()
        self.q_out = Queue()
        self.log_queue = Queue()
        self.stop_flag = Event()
        self.p = Process(target=Orderer(self.q_in, self.q_out, self.stop_flag,
                                        self.log_queue))
        self.p.start()

    def tearDown(self):
        self.stop_flag.set()
        self.p.join()

    @unittest.skip('Optional')
    def test_nothing_happens(self):

        sleep(5)

    def test_order_by_exchange_time(self):
        exchange_timestamp = datetime.now()
        local_timestamp = datetime.now()
        delay = timedelta(seconds=0.5)

        tr = Trade(local_timestamp, exchange_timestamp+delay, 1, 0.1, 1, 1)
        obe = OrderBookEvent(local_timestamp+delay, exchange_timestamp,
                             1, 1, 1, 1, 1, 1)

        self.q_in.put(tr)
        sleep(delay.total_seconds())
        self.q_in.put(obe)

        sleep(0.5)
        obe.seq_no = 1

        self.assertEqual(self.q_out.get(), obe)
        self.assertEqual(self.q_out.get(), tr)

    def test_trade_overtakes_event(self):
        exchange_timestamp = datetime.now()
        local_timestamp = datetime.now()
        obe = OrderBookEvent(local_timestamp, exchange_timestamp,
                             1, 1, 1, 1, 1, 1)
        tr = Trade(local_timestamp, exchange_timestamp, 1, 0.1, 1, 1)

        self.q_in.put(obe)
        sleep(0.5)
        self.q_in.put(tr)

        with self.assertRaises(Empty):
            self.q_out.get_nowait()

        sleep(0.5)
        tr.seq_no = 1

        self.assertEqual(self.q_out.get(), tr)
        self.assertEqual(self.q_out.get(), obe)

    def test_beyond_delay(self):
        exchange_timestamp = datetime.now()
        local_timestamp = datetime.now()
        delay = timedelta(seconds=0.5)

        tr = Trade(local_timestamp, exchange_timestamp+delay, 1, 0.1, 1, 1)
        obe = OrderBookEvent(local_timestamp+delay, exchange_timestamp,
                             1, 1, 1, 1, 1, 1)

        self.q_in.put(tr)
        sleep(3*delay.total_seconds())
        self.q_in.put(obe)

        obe.seq_no = 1

        self.assertEqual(self.q_out.get(), tr)
        self.assertEqual(self.q_out.get(), obe)
