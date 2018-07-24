from multiprocessing import Process, Queue
from queue import Empty
import logging
import time
from heapq import heappush, heappop, heapify
from btfxwss import BtfxWss
import psycopg2
from datetime import datetime, timedelta
from functools import total_ordering


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
                     "starts_exchange_timestamp,ends_exchange_timestamp) "
                     "VALUES (%s, %s, %s, %s)",
                     (self.snapshot_id, self.episode_no,
                      self.exchange_timestamp, self.next_episode_starts))


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


class Orderer:

    def __init__(self, q_in, q_out, stop_flag, delay=1):
        self.q_in = q_in
        self.q_out = q_out
        self.stop_flag = stop_flag
        self.delay = timedelta(seconds=delay)
        self.buffer = []
        heapify(self.buffer)
        self.latest_arrived = datetime.now()
        self.latest_departed = datetime.now()
        self.seq_no = 0
        self.alogger = logging.getLogger("bitfinex.Orderer.arrive")
        self.dlogger = logging.getLogger("bitfinex.Orderer.depart")

    def __repr__(self):
        return "Orderer a:%s d: %s b:%s" % (self.latest_arrived.strftime(
            "%H-%M-%S.%f")[:-3],
            self.latest_departed.strftime("%H-%M-%S.%f")[:-3], self.buffer)

    def _current_delay(self):
        return (self.latest_arrived - self.latest_departed)

    def _arrive_from_exchange(self):
        self.alogger.debug('i l_a %s' % self.latest_arrived.strftime(
            "%H-%M-%S.%f")[:-3])
        while self._current_delay() < self.delay:
            self.alogger.debug('current_delay %f ' %
                               self._current_delay().total_seconds())
            try:
                obj = self.q_in.get(True,
                                    (self.delay -
                                     self._current_delay()).total_seconds())
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
        self.alogger.debug('current_delay %f ' %
                           self._current_delay().total_seconds())
        self.alogger.debug('Unprocessed q_in size: %i' % self.q_in.qsize())

    def _depart_to_database(self):
        self.dlogger.debug('i l_d %s' % self.latest_departed.strftime(
            "%H-%M-%S.%f")[:-3])
        while True:
            try:
                if self.buffer[0].local_timestamp > self.latest_departed:
                    self.latest_departed = self.buffer[0].local_timestamp
                    self.dlogger.debug(
                        'l_d %s' % self.latest_departed.strftime(
                            "%H-%M-%S.%f")[:-3])

                if self._current_delay() >= self.delay:
                    obj = heappop(self.buffer)
                    self.dlogger.debug('%r' % obj)
                    self.q_out.put(obj)
                else:
                    break
            except IndexError:
                self.latest_departed = datetime.now()
                self.dlogger.debug('l_d(empty) %s' %
                                   self.latest_departed.strftime(
                                       "%H-%M-%S.%f")[:-3])
                break
        self.dlogger.debug('current_delay %f ' %
                           self._current_delay().total_seconds())
        self.dlogger.debug('Unprocessed q_out size: %i' % self.q_out.qsize())

    def __call__(self):

        logger = logging.getLogger("bitfinex.Orderer.__call")
        logger.debug('S %r ' % (self,))
        while not self.stop_flag.is_set():
            self._arrive_from_exchange()
            self._depart_to_database()
            logger.debug("Unprocessed heap size: %i" % len(self.buffer))
        logger.debug('F %r ' % (self,))


def connect_db():
    return psycopg2.connect("dbname=ob-analytics user=ob-analytics")


def save_all(q_out, stop_flag):
    logger = logging.getLogger("bitfinex.save_all")
    with connect_db() as con:
        con.set_session(autocommit=False)
        with con.cursor() as curr:
            curr.execute("SET CONSTRAINTS ALL DEFERRED")
            try:
                while not stop_flag.is_set():
                    try:
                        obj = q_out.get(timeout=1)
                        logger.debug('%r' % obj)
                    except Empty:
                        continue

                    obj.save(curr)
                    if isinstance(obj, Episode):
                        con.commit()
                        curr.execute("SET CONSTRAINTS ALL DEFERRED")
            except Exception as e:
                logger.exception('An exception caught while '
                                 'saving to a database: %s', e)
                stop_flag.set()
    logger.info("Exit")


def process_trade(q, stop_flag, pair, sq, q_in):
    logger = logging.getLogger("bitfinex.trade")
    try:
        snapshot_id = 0
        while not stop_flag.is_set():
            try:
                logger.debug("Waiting for trades ...")
                data, lts = q.get(timeout=1)
            except Empty:
                logger.debug("Timeout waiting for trades, restarting ..")
                continue
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
                while not stop_flag.is_set():
                    try:
                        snapshot_id = sq.get(timeout=1)
                        logger.debug("New snapshot_id: %i" % snapshot_id)
                        break
                    except Empty:
                        continue
                # skip initial snapshot of trades
                # since they usually can't be matched to any events
                continue
                # data = data[0]
            for d in data:
                q_in.put(Trade(lts, rts,  d[0], pair, datetime.fromtimestamp(
                    d[1]/1000), d[2], d[3], snapshot_id))

    except Exception as e:
        logger.exception('An exception caught while '
                         'processing a trade: %s', e)
        stop_flag.set()
    logger.info('Exit')


def process_raw_order_book(q, stop_flag, pair, sq, ob_len, q_in):
    logger = logging.getLogger("bitfinex.order.book.event")
    try:
        episode_no = 0
        event_no = 1
        episode_starts = None
        increase_episode_no = False  # The first 'addition' event
        snapshot_id = 0

        while not stop_flag.is_set():
            try:
                data, lts = q.get(timeout=1)
            except Empty:
                continue
            logger.debug("%i %s" % (snapshot_id, data))
            *data, rts = data
            rts = datetime.fromtimestamp(rts/1000)
            lts = datetime.fromtimestamp(lts)
            if isinstance(data[0][0], list):  # A new snapshot started
                snapshot_id = start_new_snapshot(ob_len, pair)
                logger.debug("Started new snapshot: %i" % snapshot_id)
                sq.put(snapshot_id)  # process_trade() will wait for it
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
                        q_in.put(Episode(datetime.now(), episode_starts,
                                         snapshot_id, episode_no, rts))
                        increase_episode_no = False
                        episode_no += 10
                        if episode_no == OrderBookEvent.MAX_EPISODE_NO:
                            stop_flag.set()
                            break
                        event_no = 1
                        # the end time of this episode will be
                        # the start time for the next one
                        episode_starts = rts
                        logger.debug("Unprocessed queue size: %i" %
                                     (q.qsize(),))
                elif not increase_episode_no:
                    # it is the first 'addition' event of an episode
                    increase_episode_no = True

                    if episode_no == 0:
                        # episode 0 starts and ends at the same time
                        episode_starts = rts

                q_in.put(OrderBookEvent(lts, rts, pair, d[0], d[1], d[2],
                                        snapshot_id, episode_no, event_no))
                event_no += 1

    except Exception as e:
        logger.exception('An exception caught while processing '
                         'an order book event: %s', e)
        stop_flag.set()
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
                logger.exception('An exception caught while trying to start'
                                 'a new snapshot: %s', e)
                raise e

    return snapshot_id


def capture(pair, stop_flag):

    logger = logging.getLogger("bitfinex.capture")
    ob_len = 100

    try:
        check_pair(pair)
    except Exception as e:
        logger.exception(e)
        return

    wss = BtfxWss(log_level=logging.INFO)
    wss.start()

    while not wss.conn.connected.is_set():
        time.sleep(1)

    wss.config(ts=True)
    wss.subscribe_to_raw_order_book(pair, len=ob_len)
    wss.subscribe_to_trades(pair)

    time.sleep(5)

    sq = Queue()
    q_in = Queue()
    q_out = Queue()

    ts = [Process(target=process_trade,
                  args=(wss.trades(pair), stop_flag, pair, sq, q_in)),
          Process(target=process_raw_order_book,
                  args=(wss.raw_books(pair), stop_flag, pair, sq,
                        ob_len, q_in)),
          Process(target=Orderer(q_in, q_out, stop_flag)),
          Process(target=save_all, args=(q_out, stop_flag)),
          ]

    for t in ts:
        t.start()

    for t in ts:
        t.join()

    wss.unsubscribe_from_trades(pair)
    wss.unsubscribe_from_raw_order_book(pair)

    time.sleep(2)

    wss.stop()
    logger.info("Finished!")
