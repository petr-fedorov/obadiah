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


class LiveOrders(Spawned):

    def __init__(self, pair_id, pair, dbname, user, stop_flag, log_queue,
                 log_level):

        super().__init__(log_queue, stop_flag, log_level)

        self.pair_id = pair_id
        self.pair = pair
        self.stop_flag = stop_flag
        self.dbname = dbname
        self.user = user

    def connect_handler(self, data):
        channel = self.pusher.subscribe('live_orders')
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
                self.curr.execute("""
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

    def __call__(self):
        self._call_init()

        self.logger = logging.getLogger("bitstamp.LiveOrders")
        self.con = connect_db(self.dbname, self.user)
        self.con.set_session(autocommit=True)
        self.curr = self.con.cursor()
        self.pusher = pusherclient.Pusher('de504dc5763aeef9ff52',
                                          log_level=logging.WARNING)
        self.pusher.connection.bind('pusher:connection_established',
                                    self.connect_handler)
        self.pusher.connect()
        self.logger.info('Started')

        while not self.stop_flag.is_set():
            time.sleep(1)
        self.logger.info('Exit')

    def stop(self):
        pass


def capture(pair, dbname, user,  stop_flag, log_queue):

    logger = logging.getLogger("bitstamp.capture")

    try:
        pair_id = get_pair(pair, dbname, user)
        ts = [Process(target=LiveOrders(pair_id, pair, dbname, user,
                                        stop_flag, log_queue,
                                        log_level=logging.DEBUG)), ]
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
