import logging
import time
from datetime import datetime
from multiprocessing import Process, Queue
from threading import Thread
from queue import Empty
import pusherclient
from obanalyticsdb.utils import connect_db, Spawned, log_notices
from obanalyticsdb.reorder import OrderedDatabaseInsertion, Reorderer


def get_pair(pair, dbname, user):
    with connect_db(dbname, user, f"'{pair}:BITSTAMP'") as con:
        with con.cursor() as curr:
            curr.execute(" SELECT pair_id "
                         " FROM bitstamp.pairs "
                         " WHERE pair = %s", (pair, ))
            pair_id = curr.fetchone()
            if pair_id is None:
                print('Pair %s has not been set up in the database' % pair)
                raise KeyError(pair)
            return pair_id


class Stockkeeper(Spawned):

    def __init__(self, q_unordered, dbname, user, pair, stop_flag, log_queue,
                 log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q_unordered = q_unordered
        self.dbname = dbname
        self.user = user
        self.pair = pair

    def __call__(self):
        self._call_init()

        logger = logging.getLogger(self.__module__ + "."
                                   + self.__class__.__qualname__)
        q_ordered = Queue()

        # Bitstamp once sent 'order_created' 1.01 seconds after 'order_deleted'
        # for the same order, so delay set to 3 seconds to be on the safe side

        reorderer = Reorderer(self.q_unordered, q_ordered, self.stop_flag,
                              delay=3)

        reorder = Thread(target=reorderer.run)
        reorder.start()

        logger.info('Started')
        with connect_db(self.dbname, self.user,
                        f"'{self.pair}:BITSTAMP'") as con:
            con.set_session(autocommit=True)
            with con.cursor() as curr:
                while True:
                    try:
                        obj = q_ordered.get(timeout=5)
                        s, d = obj.data
                        if not self.stop_flag.is_set():
                            curr.execute(s, d)
                            logger.debug('Saved %r' % d)
                        else:
                            logger.debug('Discarded %r' % d)
                    except Empty:
                        if not self.stop_flag.is_set():
                            continue
                        else:
                            con.rollback()
                            break
                    except Exception:
                        logger.exception('An exception occured while '
                                         'processing %s' % d)
                        self.stop_flag.set()
                    finally:
                        log_notices(logger, con.notices)
        reorder.join()
        logger.info("Exit")


class LiveStream(Spawned):

    def _connect_handler(self):
        raise NotImplementedError

    def _saving_thread(self):
        raise NotImplementedError

    def __call__(self):
        self._call_init()

        self.logger = logging.getLogger(self.__module__ + "."
                                        + self.__class__.__qualname__)
        self.pusher = pusherclient.Pusher(self.pusher_key,
                                          log_level=logging.WARNING)
        self.pusher.connection.bind('pusher:connection_established',
                                    self._connect_handler)
        self.pusher.connect()
        self.q = Queue()
        self.saver = Thread(target=self._saving_thread)
        self.saver.start()
        self.logger.info('Started')

        while not self.stop_flag.is_set():
            time.sleep(1)
        self.saver.join()
        self.logger.info('Exit')


class LiveOrders(LiveStream):

    def __init__(self, pair_id, pair, q_save, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.pusher_key = 'de504dc5763aeef9ff52'
        self.era = None
        self.q_save = q_save

    def _connect_handler(self, data):
        channel_name = 'live_orders'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('order_created', self.order_created)
        channel.bind('order_changed', self.order_changed)
        channel.bind('order_deleted', self.order_deleted)

    def _saving_thread(self):
        while not self.stop_flag.is_set():
            try:
                event, data = self.q.get(timeout=5)
                data = eval(data)
                data["event"] = event
                data["microtimestamp"] = datetime.fromtimestamp(
                    int(data["microtimestamp"])/1000000)
                data["local_timestamp"] = datetime.now()
                if not self.era:
                    self.era = data["microtimestamp"]
                    era = OrderedDatabaseInsertion(data["local_timestamp"],
                                                   data["microtimestamp"],
                                                   0)
                    era.data = ("""
                                    INSERT INTO bitstamp.live_orders_eras
                                    VALUES (%(era)s, %(pair_id)s)
                                """, {"era": self.era,
                                      "pair_id": self.pair_id})
                    self.q_save.put(era)
                data["era"] = self.era
                data["datetime"] = datetime.fromtimestamp(
                    int(data["datetime"]))
                data["pair_id"] = self.pair_id
                if data["order_type"]:
                    data["order_type"] = "sell"
                else:
                    data["order_type"] = "buy"
                event = OrderedDatabaseInsertion(data["local_timestamp"],
                                                 data["microtimestamp"],
                                                 1)
                event.data = ("""
                            INSERT INTO bitstamp.transient_live_orders
                            (order_id, amount, event, order_type,
                            datetime, microtimestamp, local_timestamp,
                            price, pair_id, era )
                            VALUES (%(id)s, %(amount)s, %(event)s,
                            %(order_type)s, %(datetime)s,
                            %(microtimestamp)s, %(local_timestamp)s,
                            %(price)s, %(pair_id)s, %(era)s )
                            """, data)
                self.q_save.put(event)
                self.logger.debug("queue size: %i" % self.q.qsize())
            except Empty:
                if not self.stop_flag.is_set():
                    continue
                else:
                    break
            except Exception as e:
                self.logger.exception('%s', e)
                self.stop_flag.set()

    def order_created(self, data):
        self.logger.debug("order_created %s" % (data, ))
        self.q.put(("order_created", data))

    def order_changed(self, data):
        self.logger.debug("order_changed %s" % (data, ))
        self.q.put(("order_changed", data))

    def order_deleted(self, data):
        self.logger.debug("order_deleted %s" % (data, ))
        self.q.put(("order_deleted", data))


class LiveTrades(LiveStream):

    def __init__(self, pair_id, pair, q_save, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.pusher_key = 'de504dc5763aeef9ff52'
        self.q_save = q_save

    def _connect_handler(self, data):
        channel_name = 'live_trades'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('trade', self.trade)

    def _saving_thread(self):
        while not self.stop_flag.is_set():
            try:
                data = self.q.get(timeout=5)
                data = eval(data)
                data["timestamp"] = datetime.fromtimestamp(
                    int(data["timestamp"]))
                data["local_timestamp"] = datetime.now()
                data["pair_id"] = self.pair_id
                if data["type"]:
                    data["type"] = "sell"
                else:
                    data["type"] = "buy"
                trade = OrderedDatabaseInsertion(data["local_timestamp"],
                                                 data["timestamp"],
                                                 2)
                trade.data = ("""
                            INSERT INTO bitstamp.transient_live_trades
                            (bitstamp_trade_id, amount, price, trade_timestamp,
                            trade_type, buy_order_id, sell_order_id,
                            pair_id, local_timestamp )
                            VALUES (%(id)s, %(amount)s, %(price)s,
                            %(timestamp)s, %(type)s, %(buy_order_id)s,
                            %(sell_order_id)s, %(pair_id)s,
                            %(local_timestamp)s )
                            """, data)
                self.q_save.put(trade)
                self.logger.debug("queue size: %i" % self.q.qsize())
            except Empty:
                if not self.stop_flag.is_set():
                    continue
                else:
                    break
            except Exception as e:
                self.logger.exception('%s', e)
                self.stop_flag.set()

    def trade(self, data):
        self.logger.debug("trade %s" % (data, ))
        self.q.put(data)


class LiveDiffOrderBook(LiveStream):

    def __init__(self, pair_id, pair, dbname, user, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.dbname = dbname
        self.user = user
        self.pusher_key = 'de504dc5763aeef9ff52'

    def _connect_handler(self, data):
        channel_name = 'diff_order_book'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('data', self.data)

    def _saving_thread(self):
        with connect_db(self.dbname, self.user,
                        f"'{self.pair}:BITSTAMP'") as con:
            con.set_session(autocommit=True)
            with con.cursor() as curr:
                while not self.stop_flag.is_set():
                    try:
                        data = self.q.get(timeout=5)
                        data = eval(data)
                        data["timestamp"] = datetime.fromtimestamp(
                            int(data["timestamp"]))
                        data["local_timestamp"] = datetime.now()
                        data["pair_id"] = self.pair_id
                        for side in ('bids', 'asks'):
                            for d in data[side]:
                                curr.execute("""
                                          INSERT INTO bitstamp.diff_order_book
                                          (local_timestamp, pair_id, timestamp,
                                          price, amount, side)
                                          VALUES (%s, %s, %s, %s, %s, %s)
                                          """,
                                             (data["local_timestamp"],
                                              data["pair_id"],
                                              data["timestamp"], d[0], d[1],
                                              side[:-1]))
                        self.logger.debug("queue size: %i" % self.q.qsize())
                    except Empty:
                        if not self.stop_flag.is_set():
                            continue
                        else:
                            break
                    except Exception as e:
                        self.logger.exception('%s', e)
                        self.stop_flag.set()

    def data(self, data):
        self.logger.debug("data %s" % (data, ))
        self.q.put(data)


class LiveOrderBook(LiveStream):

    def __init__(self, pair_id, pair, dbname, user, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.dbname = dbname
        self.user = user
        self.pusher_key = 'de504dc5763aeef9ff52'

    def _connect_handler(self, data):
        channel_name = 'order_book'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('data', self.data)

    def data(self, data):
        self.logger.debug("data %s" % (data, ))


def capture(pair, dbname, user,  stop_flag, log_queue):

    logger = logging.getLogger("bitstamp.capture")
    q_save = Queue()
    exitcode = 0

    try:
        pair_id = get_pair(pair, dbname, user)
        ts = [Process(target=LiveOrders(pair_id, pair, q_save, stop_flag,
                                        log_queue, log_level=logging.INFO)),
              Process(target=LiveTrades(pair_id, pair, q_save, stop_flag,
                                        log_queue, log_level=logging.INFO)),
              Process(target=Stockkeeper(q_save, dbname, user, pair, stop_flag,
                                         log_queue, log_level=logging.DEBUG)),
              # Process(target=LiveOrderBook(pair_id, pair, dbname, user,
              #                               stop_flag, log_queue,
              #                               log_level=logging.INFO)),
              # Process(target=LiveDiffOrderBook(pair_id, pair, dbname, user,
              #                                 stop_flag, log_queue,
              #                                 log_level=logging.INFO)),
              ]
        for t in ts:
            t.start()

        while not stop_flag.is_set():
            time.sleep(1)

        logger.info('Ctrl-C has been pressed, '
                    'exiting from the application ...')

        for t in ts:
            pid = t.pid
            t.join()
            if t.exitcode:
                logger.error('Process %i terminated, exitcode %i' %
                             (pid, t.exitcode))
                exitcode = t.exitcode
            else:
                logger.debug('Process %i terminated, exitcode %i' %
                             (pid, t.exitcode))
    except Exception as e:
        logger.exception('%s', e)
        exitcode = 1

    logger.info("Exit")
    return exitcode
