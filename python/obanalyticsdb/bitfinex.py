from queue import Empty
from multiprocessing import Process, Queue
import logging
import time
import signal
from heapq import heappush, heappop
from btfxwss import BtfxWss
import psycopg2
from datetime import datetime, timedelta
from functools import total_ordering
from obanalyticsdb.utils import logging_configurer


@total_ordering
class DatabaseInsertion:
    def __init__(self, local_timestamp, exchange_timestamp):
        self.local_timestamp = local_timestamp
        self.exchange_timestamp = exchange_timestamp
        self.priority = 0
        self.seq_no = 0

    def __eq__(self, other):
        return ((self.exchange_timestamp == other.exchange_timestamp) and
                (self.priority == other.priority) and
                (self.seq_no == other.seq_no))

    def __lt__(self, other):
        if self.exchange_timestamp < other.exchange_timestamp:
            return True
        elif (self.exchange_timestamp == other.exchange_timestamp and
              self.priority < other.priority):
            return True
        elif (self.exchange_timestamp == other.exchange_timestamp and
              self.priority == other.priority and self.seq_no < other.seq_no):
            return True
        else:
            return False


class Episode(DatabaseInsertion):

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 snapshot_id,
                 episode_no,
                 next_episode_starts):
        super().__init__(local_timestamp, exchange_timestamp)
        self.priority = 2  # Lower priority than OrderBookEvent below
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.next_episode_starts = next_episode_starts

    def __repr__(self):
        return "Ep-de no: %i e:%s p:%i s:%i l:%s" % (
            self.episode_no,
            self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.priority,
            self.seq_no,
            self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
        )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex.bf_order_book_episodes "
                     "(snapshot_id, episode_no,"
                     "exchange_timestamp) "
                     "VALUES (%s, %s, %s)",
                     (self.snapshot_id, self.episode_no,
                      self.exchange_timestamp))


class OrderBookEvent(DatabaseInsertion):
    MAX_EPISODE_NO = 2147483647

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 pair,
                 order_id,
                 event_price,
                 order_qty,
                 snapshot_id,
                 episode_no,
                 event_no):
        super().__init__(local_timestamp, exchange_timestamp)
        self.priority = 1  # Lower priority than Trade below
        self.pair = pair
        self.order_id = order_id
        self.event_price = event_price
        self.order_qty = order_qty
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.event_no = event_no

    def __repr__(self):
        return ("Event id: %s ep: %i ev: %i pr: %s qty:%s e:%s p:%i s:%i l:%s"
                % (self.order_id,
                   self.episode_no,
                   self.event_no,
                   self.event_price,
                   self.order_qty,
                   self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   self.priority,
                   self.seq_no,
                   self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   )
                )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex."
                     "bf_order_book_events "
                     "(local_timestamp,pair,"
                     "order_id,"
                     "event_price, order_qty, "
                     "snapshot_id,"
                     "exchange_timestamp, "
                     "episode_no, event_no, order_next_episode_no)"
                     "VALUES (%s, %s, %s, %s, %s,"
                     "%s, %s, %s, %s, %s) ",
                     (self.local_timestamp, self.pair, self.order_id,
                      self.event_price, self.order_qty, self.snapshot_id,
                      self.exchange_timestamp, self.episode_no, self.event_no,
                      OrderBookEvent.MAX_EPISODE_NO))


class Trade(DatabaseInsertion):
    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 id,
                 pair,
                 trade_timestamp,
                 qty,
                 price,
                 snapshot_id):
        super().__init__(local_timestamp, exchange_timestamp)
        self.id = id
        self.pair = pair
        self.trade_timestamp = trade_timestamp
        self.qty = qty
        self.price = price
        self.snapshot_id = snapshot_id

    def __repr__(self):
        return "Trade id: %s p: %s qty: %s e:%s p:%i s:%i l:%s" % (
            self.id,
            self.price,
            self.qty,
            self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.priority,
            self.seq_no,
            self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
        )

    def save(self, curr):

        curr.execute("INSERT INTO bitfinex.bf_trades"
                     "(id, pair, trade_timestamp, qty,"
                     "price,local_timestamp, snapshot_id,"
                     "exchange_timestamp)"
                     "VALUES (%s, %s, %s, %s, %s, %s,"
                     "%s, %s)",
                     (self.id, self.pair, self.trade_timestamp, self.qty,
                      self.price, self.local_timestamp, self.snapshot_id,
                      self.exchange_timestamp))


class Spawned:

    def __init__(self, log_queue, stop_flag, log_level=logging.INFO):
        self.log_queue = log_queue
        self.stop_flag = stop_flag
        self.log_level = log_level

    def _call_init(self):
        logging_configurer(self.log_queue, self.log_level)

        signal.signal(signal.SIGINT, signal.SIG_IGN)


class Orderer(Spawned):

    def __init__(self, q_unordered, q_ordered, stop_flag, log_queue,
                 log_level=logging.INFO, delay=1):
        super().__init__(log_queue, stop_flag, log_level)
        self.q_unordered = q_unordered
        self.q_ordered = q_ordered
        self.delay = timedelta(seconds=delay)
        self.buffer = []
        self.latest_arrived = datetime.now()
        self.latest_departed = datetime.now()
        self.seq_no = 0
        self.latest_departed_seq_no = -1

    def __repr__(self):
        return "Orderer a:%s d: %s b:%s" % (self.latest_arrived.strftime(
            "%H-%M-%S.%f")[:-3],
            self.latest_departed.strftime("%H-%M-%S.%f")[:-3], self.buffer)

    def _current_delay(self):
        return (self.latest_arrived - self.latest_departed)

    def _arrive_from_exchange(self):
        self.alogger.debug('Start arrive - current delay %f, l_a %s' %
                           (self._current_delay().total_seconds(),
                            self.latest_arrived.strftime("%H-%M-%S.%f")[:-3])
                           )

        while self._current_delay() < self.delay:
            self.alogger.debug('current_delay %f ' %
                               self._current_delay().total_seconds())
            try:
                obj = self.q_unordered.get(True,
                                           (self.delay -
                                            self._current_delay()
                                            ).total_seconds())
                obj.seq_no = self.seq_no
                self.alogger.debug('%r' % obj)
                self.seq_no += 1
                if obj.local_timestamp > self.latest_arrived:
                    self.latest_arrived = obj.local_timestamp
                    self.alogger.debug('l_a %s' % self.latest_arrived.strftime(
                        "%H-%M-%S.%f")[:-3])
                heappush(self.buffer, obj)

            except Empty:
                self.latest_arrived = datetime.now()
                self.alogger.debug('l_a(time-out) %s' %
                                   self.latest_arrived.strftime(
                                       "%H-%M-%S.%f")[:-3])
        self.alogger.debug('Suspend arrive - current_delay %f, l_a %s ' %
                           (self._current_delay().total_seconds(),
                            self.latest_arrived.strftime("%H-%M-%S.%f")[:-3]))
        self.alogger.debug('Unprocessed q_unordered size: %i' %
                           self.q_unordered.qsize())

    def _depart_to_database(self):
        self.dlogger.debug('Start depart - current delay %f, l_d %s' %
                           (self._current_delay().total_seconds(),
                            self.latest_departed.strftime("%H-%M-%S.%f")[:-3])
                           )
        while True:
            self.dlogger.debug('current_delay %f ' %
                               self._current_delay().total_seconds())
            try:
                if self.buffer[0].local_timestamp > self.latest_departed:
                    self.latest_departed = self.buffer[0].local_timestamp
                    self.dlogger.debug(
                        'l_d %s' % self.latest_departed.strftime(
                            "%H-%M-%S.%f")[:-3])

                if self._current_delay() >= self.delay:
                    obj = heappop(self.buffer)
                    if obj.seq_no > self.latest_departed_seq_no:
                        self.dlogger.debug('%r' % obj)
                        self.latest_departed_seq_no = obj.seq_no
                    else:
                        self.dlogger.debug('DELAYED %r' % obj)
                    self.q_ordered.put(obj)
                else:
                    break
            except IndexError:
                self.latest_departed = datetime.now()
                self.dlogger.debug('l_d(empty) %s' %
                                   self.latest_departed.strftime(
                                       "%H-%M-%S.%f")[:-3])
                break
        self.dlogger.debug('Suspend depart - current_delay %f, l_d %s ' %
                           (self._current_delay().total_seconds(),
                            self.latest_departed.strftime("%H-%M-%S.%f")[:-3]))
        self.dlogger.debug('Unprocessed q_ordered size: %i' %
                           self.q_ordered.qsize())

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.Orderer.__call")
        self.alogger = logging.getLogger("bitfinex.Orderer.arrive")
        self.dlogger = logging.getLogger("bitfinex.Orderer.depart")
        logger.info('Started %r ' % (self,))
        while not (self.stop_flag.is_set()
                   and self.q_unordered.qsize() == 0
                   and len(self.buffer) == 0
                   and self.q_ordered.qsize() == 0):
            self._arrive_from_exchange()
            self._depart_to_database()
            logger.debug("Unprocessed heap size: %i" % len(self.buffer))
        logger.info('Exit %r ' % (self,))


def connect_db():
    return psycopg2.connect("dbname=ob-analytics user=ob-analytics")


class Stockkeeper(Spawned):

    def __init__(self, q_ordered, stop_flag, log_queue,
                 log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q_ordered = q_ordered

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.Stockkeeper")
        logger.info('Started')
        with connect_db() as con:
            con.set_session(autocommit=False)
            with con.cursor() as curr:
                curr.execute("SET CONSTRAINTS ALL DEFERRED")
                try:
                    while True:
                        try:
                            obj = self.q_ordered.get(timeout=5)
                            logger.debug('%r' % obj)
                        except Empty:
                            if not self.stop_flag.is_set():
                                continue
                            else:
                                break
                        obj.save(curr)
                        if isinstance(obj, Episode):
                            con.commit()
                            curr.execute("SET CONSTRAINTS ALL DEFERRED")
                except Exception as e:
                    logger.exception('%s', e)
                    self.stop_flag.set()
        logger.info("Exit")


class TradeConverter(Spawned):

    def __init__(self, q, stop_flag, pair, q_snapshots, q_unordered,
                 log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q = q
        self.pair = pair
        self.q_unordered = q_unordered
        self.q_snapshots = q_snapshots

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.TradeConverter")
        logger.info('Started')
        try:
            snapshot_id = 0
            while True:
                try:
                    data, lts = self.q.get(timeout=5)
                except Empty:
                    if not self.stop_flag.is_set():
                        continue
                    else:
                        break
                logger.debug("%i %s" % (snapshot_id, data))
                *data, rts = data
                lts = datetime.fromtimestamp(lts)
                rts = datetime.fromtimestamp(rts/1000)

                if data[0] == 'tu':
                    data = [data[1]]
                elif data[0] == 'te':
                    data = []
                else:
                    # A new snapshot has started after (re)connect
                    # get new snapshot_id from process_raw_order_book()
                    while not self.stop_flag.is_set():
                        try:
                            snapshot_id = self.q_snapshots.get(timeout=1)
                            logger.debug("New snapshot_id: %i" % snapshot_id)
                            break
                        except Empty:
                            continue
                    # skip initial snapshot of trades
                    # since they usually can't be matched to any events
                    continue
                    # data = data[0]
                for d in data:
                    self.q_unordered.put(Trade(lts, rts,  d[0],
                                               self.pair,
                                               datetime.fromtimestamp(
                                                   d[1]/1000),
                                               d[2], d[3], snapshot_id))

        except Exception as e:
            logger.exception('%s', e)
            self.stop_flag.set()
        logger.info('Exit')


class EventConverter(Spawned):

    def __init__(self, q, stop_flag, pair, q_snapshots, ob_len, q_unordered,
                 log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q = q
        self.pair = pair
        self.ob_len = ob_len
        self.q_unordered = q_unordered
        self.q_snapshots = q_snapshots

    def __call__(self):
        self._call_init()
        logger = logging.getLogger("bitfinex.EventConverter")
        logger.info('Started')
        try:
            episode_no = 0
            event_no = 1
            episode_starts = None
            increase_episode_no = False  # The first 'addition' event
            snapshot_id = 0

            while True:
                try:
                    data, lts = self.q.get(timeout=2)
                except Empty:
                    if not self.stop_flag.is_set():
                        continue
                    else:
                        break
                logger.debug("%i %s" % (snapshot_id, data))
                *data, rts = data
                rts = datetime.fromtimestamp(rts/1000)
                lts = datetime.fromtimestamp(lts)
                if isinstance(data[0][0], list):  # A new snapshot started
                    snapshot_id = start_new_snapshot(self.ob_len, self.pair)
                    logger.debug("Started new snapshot: %i" % snapshot_id)
                    self.q_snapshots.put(snapshot_id)
                    episode_no = 0
                    event_no = 1
                    episode_starts = None
                    increase_episode_no = False
                    data = data[0]
                for d in data:
                    if not float(d[1]):  # it is a 'removal' event
                        if increase_episode_no:
                            # it is the first event for an episode
                            # so insert PREVIOUS episode
                            self.q_unordered.put(Episode(datetime.now(),
                                                         episode_starts,
                                                         snapshot_id,
                                                         episode_no, rts))
                            increase_episode_no = False
                            episode_no += 10
                            if episode_no == OrderBookEvent.MAX_EPISODE_NO:
                                self.stop_flag.set()
                                break
                            event_no = 1
                            # the end time of this episode will be
                            # the start time for the next one
                            episode_starts = rts
                            logger.debug("Unprocessed queue size: %i" %
                                         (self.q.qsize(),))
                    elif not increase_episode_no:
                        # it is the first 'addition' event of an episode
                        increase_episode_no = True

                        if episode_no == 0:
                            # episode 0 starts and ends at the same time
                            episode_starts = rts

                    self.q_unordered.put(OrderBookEvent(lts, rts, self.pair,
                                                        d[0], d[1], d[2],
                                                        snapshot_id,
                                                        episode_no, event_no))
                    event_no += 1

        except Exception as e:
            logger.exception('%s', e)
            self.stop_flag.set()
        logger.info('Exit')


def check_pair(pair):
    with connect_db() as con:
        with con.cursor() as curr:
            curr.execute(" SELECT * "
                         " FROM bitfinex.bf_pairs "
                         " WHERE pair = %s", (pair, ))
            if curr.fetchone() is None:
                print('Pair %s has not been set up in the database' % pair)
                raise KeyError(pair)


def start_new_snapshot(ob_len, pair):
    logger = logging.getLogger("bitfinex.new.snapshot")
    with connect_db() as con:
        with con.cursor() as curr:
            try:
                curr.execute("insert into bitfinex.bf_snapshots (len)"
                             "values (%s) returning snapshot_id", (ob_len,))
                snapshot_id = curr.fetchone()[0]
                con.commit()
                logger.info("A new snapshot started: %i, pair: %s, len: %i" %
                            (snapshot_id, pair, ob_len))
            except Exception as e:
                logger.exception('%s', e)
                raise e

    return snapshot_id


def capture(pair, stop_flag, log_queue):

    logger = logging.getLogger("bitfinex.capture")
    ob_len = 100

    try:
        check_pair(pair)
    except Exception as e:
        logger.exception('%s', e)
        return

    wss = BtfxWss(log_level=logging.INFO)
    wss.start()

    while not wss.conn.connected.is_set():
        time.sleep(1)

    wss.config(ts=True)
    wss.subscribe_to_raw_order_book(pair, len=ob_len)
    wss.subscribe_to_trades(pair)

    time.sleep(5)

    q_snapshots = Queue()
    q_unordered = Queue()
    q_ordered = Queue()

    ts = [Process(target=TradeConverter(wss.trades(pair), stop_flag, pair,
                                        q_snapshots, q_unordered,
                                        log_queue, logging.DEBUG)),
          Process(target=EventConverter(wss.raw_books(pair), stop_flag, pair,
                                        q_snapshots, ob_len, q_unordered,
                                        log_queue, logging.DEBUG)),
          Process(target=Orderer(q_unordered, q_ordered, stop_flag,
                                 log_queue, logging.DEBUG, delay=2)),
          Process(target=Stockkeeper(q_ordered, stop_flag, log_queue,
                                     logging.DEBUG)),
          ]

    for t in ts:
        t.start()

    while not stop_flag.is_set():
        time.sleep(1)

    logger.info('Ctrl-C has been pressed, exiting from the application ...')

    wss.unsubscribe_from_trades(pair)
    wss.unsubscribe_from_raw_order_book(pair)
    time.sleep(2)
    wss.stop()
####
    for t in ts:
        pid = t.pid
        t.join()
        logger.debug('Process %i terminated, exitcode %i' % (pid, t.exitcode))

    logger.info("Exit")
