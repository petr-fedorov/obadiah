import logging
import time
from datetime import datetime
from multiprocessing import Process
import pusherclient
from obanalyticsdb.utils import connect_db, Spawned


def get_pair(pair, dbname, user):
    with connect_db(dbname, user) as con:
        with con.cursor() as curr:
            curr.execute(" SELECT pair_id "
                         " FROM bitstamp.pairs "
                         " WHERE pair = %s", (pair, ))
            pair_id = curr.fetchone()
            if pair_id is None:
                print('Pair %s has not been set up in the database' % pair)
                raise KeyError(pair)
            return pair_id


class LiveStream(Spawned):

    def connect_handler(self):
        raise NotImplementedError

    def __call__(self):
        self._call_init()

        self.logger = logging.getLogger(self.__module__ + "."
                                        + self.__class__.__qualname__)
        # psycopg2's connections are thread safe, so will share it ...
        self.con = connect_db(self.dbname, self.user)
        self.con.set_session(autocommit=True)
        self.pusher = pusherclient.Pusher(self.pusher_key,
                                          log_level=logging.WARNING)
        self.pusher.connection.bind('pusher:connection_established',
                                    self.connect_handler)
        self.pusher.connect()
        self.logger.info('Started')

        while not self.stop_flag.is_set():
            time.sleep(1)
        self.con.close()
        self.logger.info('Exit')


class LiveOrders(LiveStream):

    def __init__(self, pair_id, pair, dbname, user, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.dbname = dbname
        self.user = user
        self.pusher_key = 'de504dc5763aeef9ff52'

    def connect_handler(self, data):
        channel_name = 'live_orders'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('order_created', self.order_created)
        channel.bind('order_changed', self.order_changed)
        channel.bind('order_deleted', self.order_deleted)

    def _save_event(self, event, data):
        if not self.stop_flag.is_set():
            try:
                data = eval(data)
                data["event"] = event
                data["microtimestamp"] = datetime.fromtimestamp(
                    int(data["microtimestamp"])/1000000)
                data["datetime"] = datetime.fromtimestamp(
                    int(data["datetime"]))
                data["local_timestamp"] = datetime.now()
                data["pair_id"] = self.pair_id
                if data["order_type"]:
                    data["order_type"] = "sell"
                else:
                    data["order_type"] = "buy"
                # psycopg2's connections are not thread safe
                # so we have to create one here
                with self.con.cursor() as curr:
                    curr.execute("""
                                 INSERT INTO bitstamp.live_orders
                                 (order_id, amount, event, order_type,
                                 datetime, microtimestamp, local_timestamp,
                                 price, pair_id )
                                 VALUES (%(id)s, %(amount)s, %(event)s,
                                 %(order_type)s, %(datetime)s,
                                 %(microtimestamp)s, %(local_timestamp)s,
                                 %(price)s, %(pair_id)s )
                                 """, data)
            except Exception as e:
                self.logger.exception('%s', e)
                self.stop_flag.set()

    def order_created(self, data):
        self.logger.debug("order_created %s" % (data, ))
        self._save_event("order_created", data)

    def order_changed(self, data):
        self.logger.debug("order_changed %s" % (data, ))
        self._save_event("order_changed", data)

    def order_deleted(self, data):
        self.logger.debug("order_deleted %s" % (data, ))
        self._save_event("order_deleted", data)


class LiveTicker(LiveStream):

    def __init__(self, pair_id, pair, dbname, user, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.dbname = dbname
        self.user = user
        self.pusher_key = 'de504dc5763aeef9ff52'

    def connect_handler(self, data):
        channel_name = 'live_trades'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('trade', self.trade)

    def trade(self, data):
        self.logger.debug("trade %s" % (data, ))
        if not self.stop_flag.is_set():
            try:
                data = eval(data)
                data["timestamp"] = datetime.fromtimestamp(
                    int(data["timestamp"]))
                data["local_timestamp"] = datetime.now()
                data["pair_id"] = self.pair_id
                if data["type"]:
                    data["type"] = "sell"
                else:
                    data["type"] = "buy"
                # psycopg2's connections are not thread safe
                # so we have to create one here
                with self.con.cursor() as curr:
                    curr.execute("""
                                 INSERT INTO bitstamp.live_trades
                                 (trade_id, amount, price, trade_timestamp,
                                  trade_type, buy_order_id, sell_order_id,
                                  pair_id, local_timestamp )
                                 VALUES (%(id)s, %(amount)s, %(price)s,
                                 %(timestamp)s, %(type)s, %(buy_order_id)s,
                                 %(sell_order_id)s, %(pair_id)s,
                                 %(local_timestamp)s )
                                 """, data)
            except Exception as e:
                self.logger.exception('%s', e)
                self.stop_flag.set()


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

    def connect_handler(self, data):
        channel_name = 'diff_order_book'
        if self.pair != 'BTCUSD':
            channel_name += '_' + self.pair.lower()
        self.logger.info(channel_name)
        channel = self.pusher.subscribe(channel_name)
        channel.bind('data', self.data)

    def _insert_differences(self, curr, side, data):
        for d in data[side]:
            curr.execute("""
                        INSERT INTO bitstamp.diff_order_book
                        (local_timestamp, pair_id, timestamp,
                         price, amount, side)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """, (data["local_timestamp"], data["pair_id"],
                              data["timestamp"], d[0], d[1], side[:-1]))

    def data(self, data):
        self.logger.debug("data %s" % (data, ))
        if not self.stop_flag.is_set():
            try:
                data = eval(data)
                data["timestamp"] = datetime.fromtimestamp(
                    int(data["timestamp"]))
                data["local_timestamp"] = datetime.now()
                data["pair_id"] = self.pair_id
                # psycopg2's connections are not thread safe
                # so we have to create one here
                with self.con.cursor() as curr:
                    self._insert_differences(curr, "bids", data)
                    self._insert_differences(curr, "asks", data)

            except Exception as e:
                self.logger.exception('%s', e)
                self.stop_flag.set()


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

    def connect_handler(self, data):
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

    try:
        pair_id = get_pair(pair, dbname, user)
        ts = [Process(target=LiveOrders(pair_id, pair, dbname, user,
                                        stop_flag, log_queue,
                                        log_level=logging.INFO)),
              Process(target=LiveTicker(pair_id, pair, dbname, user,
                                        stop_flag, log_queue,
                                        log_level=logging.INFO)),
              # Process(target=LiveOrderBook(pair_id, pair, dbname, user,
              #                              stop_flag, log_queue,
              #                              log_level=logging.DEBUG)),
              Process(target=LiveDiffOrderBook(pair_id, pair, dbname, user,
                                               stop_flag, log_queue,
                                               log_level=logging.INFO)), ]
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
            else:
                logger.debug('Process %i terminated, exitcode %i' %
                             (pid, t.exitcode))
    except Exception as e:
        logger.exception('%s', e)
        return

    logger.info("Exit")
