from queue import Empty, Full
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
class OrderedDatabaseInsertion:
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


class Episode(OrderedDatabaseInsertion):

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 snapshot_id,
                 episode_no,
                 is_complete=True):
        super().__init__(local_timestamp, exchange_timestamp)
        self.priority = 2  # Lower priority than OrderBookEvent below
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.is_complete = is_complete

    def __repr__(self):
        return "Ep-de no: %i e:%s p:%i s:%i l:%s sn:%s" % (
            self.episode_no,
            self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.priority,
            self.seq_no,
            self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.snapshot_id
        )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex.bf_order_book_episodes "
                     "(snapshot_id, episode_no,"
                     "exchange_timestamp) "
                     "VALUES (%s, %s, %s)",
                     (self.snapshot_id, self.episode_no,
                      self.exchange_timestamp))

    def finalize(self, con):
        if self.is_complete:
            con.commit()
            return True
        else:
            con.rollback()
            return False


class ConsBookEpisode:

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 snapshot_id,
                 episode_no,
                 is_complete=True):
        self.local_timestamp = local_timestamp
        self.exchange_timestamp = exchange_timestamp
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.is_complete = is_complete

    def __repr__(self):
        return "CB Ep-de no: %i e:%s l:%s sn:%s" % (
            self.episode_no,
            self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.snapshot_id
        )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex.bf_cons_book_episodes "
                     "(snapshot_id, episode_no,"
                     "exchange_timestamp) "
                     "VALUES (%s, %s, %s)",
                     (self.snapshot_id, self.episode_no,
                      self.exchange_timestamp))

    def finalize(self, con):
        if self.is_complete:
            con.commit()
            return True
        else:
            con.rollback()
            return False


class OrderBookEvent(OrderedDatabaseInsertion):
    MAX_EPISODE_NO = 2147483647

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 order_id,
                 event_price,
                 order_qty,
                 snapshot_id,
                 episode_no,
                 event_no):
        super().__init__(local_timestamp, exchange_timestamp)
        self.priority = 1  # Lower priority than Trade below
        self.order_id = order_id
        self.event_price = event_price
        self.order_qty = order_qty
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.event_no = event_no

    def __repr__(self):
        return ("Event id: %s ep: %i ev: %i pr: %s qty:%s e:%s p:%i s:%i l:%s "
                "sn:%s"
                % (self.order_id,
                   self.episode_no,
                   self.event_no,
                   self.event_price,
                   self.order_qty,
                   self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   self.priority,
                   self.seq_no,
                   self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   self.snapshot_id
                   )
                )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex."
                     "bf_order_book_events "
                     "(local_timestamp,"
                     "order_id,"
                     "event_price, order_qty, "
                     "snapshot_id,"
                     "exchange_timestamp, "
                     "episode_no, event_no)"
                     "VALUES (%s, %s, %s, %s,"
                     "%s, %s, %s, %s) ",
                     (self.local_timestamp, self.order_id,
                      self.event_price, self.order_qty, self.snapshot_id,
                      self.exchange_timestamp, self.episode_no, self.event_no))


class ConsBookEvent:
    MAX_EPISODE_NO = 2147483647

    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 price,
                 cnt,
                 qty,
                 snapshot_id,
                 episode_no,
                 event_no):
        self.local_timestamp = local_timestamp
        self.exchange_timestamp = exchange_timestamp
        self.price = price
        self.cnt = cnt
        self.qty = qty
        self.snapshot_id = snapshot_id
        self.episode_no = episode_no
        self.event_no = event_no

    def __repr__(self):
        return ("CB Event pr: %s ep: %i ev: %i cnt: %i qty:%s e:%s l:%s sn:%s"
                % (self.price,
                   self.episode_no,
                   self.event_no,
                   self.cnt,
                   self.qty,
                   self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
                   self.snapshot_id
                   )
                )

    def save(self, curr):
        curr.execute("INSERT INTO bitfinex."
                     "bf_cons_book_events "
                     "(local_timestamp,"
                     "price, cnt, qty, "
                     "snapshot_id,"
                     "exchange_timestamp, "
                     "episode_no, event_no)"
                     "VALUES (%s, %s, %s, %s,"
                     "%s, %s, %s, %s) ",
                     (self.local_timestamp, self.price, self.cnt, self.qty,
                      self.snapshot_id, self.exchange_timestamp,
                      self.episode_no, self.event_no))


class Trade(OrderedDatabaseInsertion):
    def __init__(self,
                 local_timestamp,
                 exchange_timestamp,
                 id,
                 qty,
                 price,
                 snapshot_id):
        super().__init__(local_timestamp, exchange_timestamp)
        self.id = id
        self.qty = qty
        self.price = price
        self.snapshot_id = snapshot_id

    def __repr__(self):
        return "Trade id: %s p: %s qty: %s e:%s p:%i s:%i l:%s sn: %s" % (
            self.id,
            self.price,
            self.qty,
            self.exchange_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.priority,
            self.seq_no,
            self.local_timestamp.strftime("%H-%M-%S.%f")[:-3],
            self.snapshot_id
        )

    def save(self, curr):

        curr.execute("INSERT INTO bitfinex.bf_trades"
                     "(id,  qty, price,local_timestamp, snapshot_id,"
                     "exchange_timestamp)"
                     "VALUES (%s, %s, %s, %s, %s, %s)",
                     (self.id, self.qty, self.price, self.local_timestamp,
                      self.snapshot_id, self.exchange_timestamp))


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
        self.alogger.info('Unprocessed q_unordered size: %i' %
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
        self.dlogger.info('Unprocessed q_ordered size: %i' %
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
            logger.info("Unprocessed heap size: %i" % len(self.buffer))
        logger.info('Exit %r ' % (self,))


def connect_db(dbname, user):
    return psycopg2.connect("dbname=%s user=%s password=%s" %
                            (dbname, user, user))


class Stockkeeper(Spawned):

    def __init__(self, q_ordered, q_spreader, stop_flag, pair, dbname, user,
                 log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q_ordered = q_ordered
        self.q_spreader = q_spreader
        self.prec = "R0"
        self.pair = pair
        self.dbname = dbname
        self.user = user

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.Stockkeeper_%s_%s" % (self.pair,
                                                                   self.prec))
        logger.info('Started')
        with connect_db(self.dbname, self.user) as con:
            con.set_session(autocommit=False)
            with con.cursor() as curr:
                curr.execute("SET CONSTRAINTS ALL DEFERRED")
                # We'll send ranges of episodes (fi, la) to Spreader
                fi = None
                la = None
                while True:
                    try:
                        obj = self.q_ordered.get(timeout=5)
                        if not self.stop_flag.is_set():
                            obj.save(curr)
                            if isinstance(obj, Episode):
                                if obj.finalize(con):
                                    logger.debug('Commited %r' % obj)
                                    if not fi:
                                        fi = obj
                                    la = obj
                                    try:
                                        self.q_spreader.put_nowait((fi, la))
                                        fi = None
                                    except Full:
                                        pass
                                else:
                                    logger.debug('Rolled back %r' % obj)
                                curr.execute("SET CONSTRAINTS ALL DEFERRED")
                            else:
                                logger.debug('Saved %r' % obj)
                        else:
                            logger.debug('Discarded %r' % obj)
                    except Empty:
                        if not self.stop_flag.is_set():
                            continue
                        else:
                            con.rollback()
                            break
                    except Exception:
                        logger.exception('An exception occured while '
                                         'processing %s' % obj)
                        self.stop_flag.set()
        logger.info("Exit")


class Spreader(Spawned):

    def __init__(self, n, q_spreader, dbname, user, stop_flag, log_queue,
                 log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q_spreader = q_spreader
        self.n = n
        self.dbname = dbname
        self.user = user

    def _insert_spread(self, curr, fi, la, logger):
        if fi.snapshot_id == la.snapshot_id:
            curr.execute("INSERT INTO bitfinex.bf_spreads "
                         "SELECT * FROM bitfinex.bf_spread_between_episodes_v"
                         "(%(s_id)s, %(from)s, %(to)s)"
                         " UNION ALL "
                         "SELECT * "
                         "FROM bitfinex.bf_spread_after_episode_v"
                         "(%(s_id)s, %(from)s, %(to)s)",
                         {'s_id': fi.snapshot_id, 'from': fi.episode_no,
                          'to': la.episode_no})
            logger.debug("New spread: snapshot %i from %i to %i" % (
                                fi.snapshot_id,
                                fi.episode_no,
                                la.episode_no))
        else:
            curr.execute("INSERT INTO bitfinex.bf_spreads "
                         "SELECT * "
                         "FROM bitfinex.bf_spread_between_episodes_v"
                         "(%(s_id)s, %(from)s)"
                         " UNION ALL "
                         "SELECT * "
                         "FROM bitfinex.bf_spread_after_episode_v"
                         "(%(s_id)s, %(from)s)",
                         {'s_id': fi.snapshot_id, 'from': fi.episode_no})
            logger.debug("New spread: snapshot %i from %i to ..." % (
                                fi.snapshot_id, fi.episode_no))
            curr.execute("INSERT INTO bitfinex.bf_spreads "
                         "SELECT * "
                         "FROM bitfinex.bf_spread_between_episodes_v"
                         "(%(s_id)s, %(from)s, %(to)s)"
                         " UNION ALL "
                         "SELECT * "
                         "FROM bitfinex.bf_spread_after_episode_v"
                         "(%(s_id)s, %(from)s, %(to)s)",
                         {'s_id': la.snapshot_id, 'from': 0,
                          'to': la.episode_no})
            logger.debug("New spread: snapshot %i from %i to %i" % (
                                la.snapshot_id,
                                0,
                                la.episode_no))

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.Spreader_%i" % self.n)
        logger.info('Started')
        with connect_db(self.dbname, self.user) as con:
            con.set_session(autocommit=True)
            with con.cursor() as curr:
                try:
                    while True:
                        try:
                            fi, la = self.q_spreader.get(timeout=5)
                            self._insert_spread(curr, fi, la, logger)
                        except Empty:
                            if not self.stop_flag.is_set():
                                continue
                            else:
                                break
                except Exception as e:
                    logger.exception('%s', e)
                    self.stop_flag.set()
        logger.info("Exit")


class TradeConverter(Spawned):

    def __init__(self, q, stop_flag, q_snapshots, q_unordered,
                 log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q = q
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
                *data, _ = data
                lts = datetime.fromtimestamp(lts)

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
                    self.q_unordered.put(Trade(lts,
                                               datetime.fromtimestamp(
                                                   d[1]/1000), d[0],
                                               d[2], d[3], snapshot_id))

        except Exception as e:
            logger.exception('%s', e)
            self.stop_flag.set()
        logger.info('Exit')


class EventConverter(Spawned):

    def __init__(self, q, stop_flag, pair, dbname, user,  q_snapshots, ob_len,
                 q_unordered, log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q = q
        self.pair = pair
        self.ob_len = ob_len
        self.q_unordered = q_unordered
        self.q_snapshots = q_snapshots
        self.dbname = dbname
        self.user = user

    def __call__(self):
        self._call_init()
        logger = logging.getLogger("bitfinex.EventConverter")
        logger.info('Started')
        try:
            episode_no = 0
            event_no = 1
            episode_rts = datetime(1970, 8, 1, 20, 15)
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
                    if episode_no > 0:
                            # it is a switch to a new snapshot
                            # so insert the last INCOMPLETE episode of the
                            # PREVIOUS snapshot
                        self.q_unordered.put(Episode(datetime.now(),
                                                     episode_rts,
                                                     snapshot_id,
                                                     episode_no,
                                                     False))
                    snapshot_id = start_new_snapshot(self.ob_len, self.pair,
                                                     self.dbname, self.user)
                    logger.debug("Started new snapshot: %i" % snapshot_id)
                    self.q_snapshots.put(snapshot_id)
                    episode_no = 0
                    event_no = 1
                    increase_episode_no = False
                    data = data[0]
                for d in data:
                    if not float(d[1]):  # it is a 'removal' event
                        if increase_episode_no:
                            # it is the first event for an episode
                            # so insert PREVIOUS episode
                            self.q_unordered.put(Episode(datetime.now(),
                                                         episode_rts,
                                                         snapshot_id,
                                                         episode_no))
                            increase_episode_no = False
                            episode_no += 10
                            if episode_no == OrderBookEvent.MAX_EPISODE_NO:
                                self.stop_flag.set()
                                break
                            event_no = 1
                            episode_rts = rts
                            logger.info("Unprocessed queue size: %i" %
                                        (self.q.qsize(),))
                    elif not increase_episode_no:
                        # it is the first 'addition' event of an episode
                        increase_episode_no = True

                    self.q_unordered.put(OrderBookEvent(lts, rts, d[0], d[1],
                                                        d[2], snapshot_id,
                                                        episode_no, event_no))
                    event_no += 1

                    # An episode's exchange_timestamp must be equal to
                    # MAX(exchange_timestamp) among events that belongs to the
                    # episode
                    if rts > episode_rts:
                        episode_rts = rts

        except Exception as e:
            logger.exception('%s', e)
            self.stop_flag.set()
        logger.info('Exit')


class ConsEventConverter(Spawned):

    def __init__(self, q, stop_flag, pair, dbname, user, prec, ob_len,
                 log_queue, log_level=logging.INFO):
        super().__init__(log_queue, stop_flag, log_level)
        self.q = q
        self.ob_len = ob_len
        self.pair = pair
        self.prec = prec
        self.dbname = dbname
        self.user = user

    def __call__(self):
        self._call_init()

        logger = logging.getLogger("bitfinex.ConsEventConverter_%s_%s" %
                                   (self.pair, self.prec))
        logger.info('Started')
        try:
            episode_no = 0
            event_no = 1
            episode_rts = datetime(1970, 8, 1, 20, 15)
            last_rts = None
            increase_episode_no = True  # The first 'addition' event
            snapshot_id = 0

            with connect_db(self.dbname, self.user) as con:
                con.set_session(autocommit=False)
                with con.cursor() as curr:
                    curr.execute("SET CONSTRAINTS ALL DEFERRED")

                    while True:
                        try:
                            data, lts = self.q.get(timeout=5)
                        except Empty:
                            if not self.stop_flag.is_set():
                                continue
                            else:
                                # Rollback saved events from INCOMPLETE episode
                                con.rollback()
                                break
                        logger.debug("%i %s" % (snapshot_id, data,))
                        *data, rts = data
                        rts = datetime.fromtimestamp(rts/1000)
                        lts = datetime.fromtimestamp(lts)

                        # we need to track last_rts in order to catch
                        # starts of new episodes since for P-precision
                        # they do not always start from removal events
                        if not last_rts:
                            last_rts = rts

                        if isinstance(data[0][0], list):
                            # A new snapshot started
                            if episode_no > 0:
                                    # it is a switch to a new snapshot
                                    # so rollback the INCOMPLETE episode of the
                                    # PREVIOUS snapshot
                                con.rollback()
                                curr.execute("SET CONSTRAINTS ALL DEFERRED")
                            snapshot_id = start_new_snapshot(self.ob_len,
                                                             self.pair,
                                                             self.dbname,
                                                             self.user,
                                                             self.prec)
                            episode_no = 0
                            event_no = 1
                            increase_episode_no = True
                            data = data[0]
                        for d in data:
                            if not float(d[1]) or\
                                    (rts-last_rts) > timedelta(
                                        milliseconds=200):
                                if increase_episode_no:
                                    # it is the first event for an episode
                                    # so insert PREVIOUS episode
                                    obj = ConsBookEpisode(datetime.now(),
                                                          episode_rts,
                                                          snapshot_id,
                                                          episode_no)
                                    obj.save(curr)
                                    if obj.finalize(con):
                                        logger.debug('Commited %r' % obj)
                                    else:
                                        logger.debug('Rolled back %r' % obj)
                                    curr.execute(
                                        "SET CONSTRAINTS ALL DEFERRED")

                                    if not float(d[1]):
                                        # if this was a 'removal' event
                                        # we change flag so next 'removal'
                                        # event if any will not trigger new
                                        # episode again
                                        increase_episode_no = False

                                    episode_no += 10
                                    if episode_no == ConsBookEvent.\
                                            MAX_EPISODE_NO:
                                        self.stop_flag.set()
                                        break
                                    event_no = 1
                                    episode_rts = rts
                                    logger.info("Unprocessed queue size: %i" %
                                                (self.q.qsize(),))
                            elif not increase_episode_no:
                                # it is the first addition event of an episode
                                increase_episode_no = True

                            obj = ConsBookEvent(lts, rts, d[0], d[1], d[2],
                                                snapshot_id, episode_no,
                                                event_no)
                            obj.save(curr)
                            logger.debug('Saved %r' % obj)
                            event_no += 1
                            last_rts = rts

                            # An episode's exchange_timestamp must be equal to
                            # MAX(exchange_timestamp) among events that belongs
                            # to the episode
                            if rts > episode_rts:
                                episode_rts = rts

        except Exception as e:
            logger.exception('%s', e)
            self.stop_flag.set()
        logger.info('Exit')


def check_pair(pair, dbname, user):
    with connect_db(dbname, user) as con:
        with con.cursor() as curr:
            curr.execute(" SELECT * "
                         " FROM bitfinex.bf_pairs "
                         " WHERE pair = %s", (pair, ))
            if curr.fetchone() is None:
                print('Pair %s has not been set up in the database' % pair)
                raise KeyError(pair)


def start_new_snapshot(ob_len, pair, dbname, user, prec="R0"):
    logger = logging.getLogger("bitfinex.new.snapshot")
    with connect_db(dbname, user) as con:
        with con.cursor() as curr:
            try:
                curr.execute("insert into bitfinex.bf_snapshots "
                             "(len, pair, prec)"
                             "values (%s, %s, %s) returning snapshot_id",
                             (ob_len, pair, prec))
                snapshot_id = curr.fetchone()[0]
                con.commit()
                logger.info("A new snapshot started: "
                            "%i, pair: %s, len: %i, prec: %s" %
                            (snapshot_id, pair, ob_len, prec))
            except Exception as e:
                logger.exception('%s', e)
                raise e

    return snapshot_id


def capture(pair, dbname, user,  stop_flag, log_queue):

    logger = logging.getLogger("bitfinex.capture")
    ob_len = 100

    try:
        check_pair(pair, dbname, user)
    except Exception as e:
        logger.exception('%s', e)
        return

    ob_R0 = BtfxWss(log_level=logging.INFO)

    precs = ['P0', 'P1', 'P2', 'P3']
    obs = [BtfxWss(log_level=logging.INFO) for p in precs]

    for ob in [ob_R0] + obs:
        ob.start()

    while not all([ob.conn.connected.is_set() for ob in [ob_R0] + obs]):
        time.sleep(1)

    for ob in [ob_R0] + obs:
        ob.config(ts=True)

    ob_R0.subscribe_to_raw_order_book(pair, len=ob_len)
    ob_R0.subscribe_to_trades(pair)

    for prec, ob in zip(precs, obs):
        ob.subscribe_to_order_book(pair, prec=prec, len=ob_len)

    time.sleep(5)

    q_snapshots = Queue()
    q_unordered = Queue()
    q_ordered = Queue()

    num_of_spreaders = 3
    q_spreader = Queue(num_of_spreaders)

    ts = [Process(target=TradeConverter(ob_R0.trades(pair), stop_flag,
                                        q_snapshots, q_unordered,
                                        log_queue)),
          Process(target=EventConverter(ob_R0.raw_books(pair), stop_flag, pair,
                                        dbname, user, q_snapshots, ob_len,
                                        q_unordered, log_queue)),
          Process(target=Orderer(q_unordered, q_ordered, stop_flag,
                                 log_queue, delay=2)),
          Process(target=Stockkeeper(q_ordered, q_spreader, stop_flag, pair,
                                     dbname, user, log_queue,
                                     log_level=logging.INFO)),
          ] + [Process(target=Spreader(n, q_spreader, dbname, user, stop_flag,
                                       log_queue, log_level=logging.DEBUG))
               for n in range(num_of_spreaders)] + [
                   Process(target=ConsEventConverter(ob.books(pair),
                                                     stop_flag, pair, dbname,
                                                     user, prec, ob_len,
                                                     log_queue,
                                                     log_level=logging.DEBUG))
                   for (prec, ob) in zip(precs, obs)]

    for t in ts:
        t.start()

    while not stop_flag.is_set():
        time.sleep(1)

    logger.info('Ctrl-C has been pressed, exiting from the application ...')

    ob_R0.unsubscribe_from_trades(pair)
    ob_R0.unsubscribe_from_raw_order_book(pair)

    for ob in obs:
        ob.unsubscribe_from_order_book(pair)

    time.sleep(2)

    ob_R0.stop()
    for ob in obs:
        ob.stop()
####
    for t in ts:
        pid = t.pid
        t.join()
        logger.debug('Process %i terminated, exitcode %i' % (pid, t.exitcode))

    logger.info("Exit")
