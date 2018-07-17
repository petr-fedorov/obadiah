from multiprocessing import Process
import logging
import time
from btfxwss import BtfxWss
import psycopg2
from datetime import datetime

MAX_EPISODE_NO = 2147483647


def connect_db():
    return psycopg2.connect("dbname=ob-analytics user=ob-analytics")


def process_trade(q, stop_flag, pair, snapshot_id):
    logger = logging.getLogger("bitfinex.trade")
    with connect_db() as con:
        con.set_session(autocommit=True)
        with con.cursor() as curr:
            try:
                while not stop_flag.is_set():
                    data, lts = q.get()
                    logger.debug("%i %s" % (snapshot_id, data))
                    *data, rts = data
                    lts = datetime.fromtimestamp(lts)
                    if data[0] == 'tu':
                        data = [data[1]]
                    elif data[0] == 'te':
                        data = []
                    else:  # it's an initial snapshot of trades
                        # skip initial snapshot of trades
                        # since they usually can't be matched to any events
                        continue
                        # data = data[0]
                    for d in data:
                        try:
                            curr.execute("INSERT INTO bitfinex.bf_trades"
                                         "(id, pair, trade_timestamp, qty,"
                                         "price,local_timestamp, snapshot_id,"
                                         "exchange_timestamp)"
                                         "VALUES (%s, %s, %s, %s, %s, %s,"
                                         "%s, %s)",
                                         (d[0], pair,
                                          datetime.fromtimestamp(d[1]/1000),
                                          d[2], d[3], lts, snapshot_id,
                                          datetime.fromtimestamp(rts/1000)))
                        except psycopg2.IntegrityError as e:
                            logger.warn('Skipping %s', e)
            except Exception as e:
                logger.exception('An exception caught while '
                                 'processing a trade: %s', e)
                stop_flag.set()


def insert_event(curr, lts, pair, order_id, event_price, order_qty,
                 snapshot_id, exchange_timestamp, episode_no, event_no):
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
                 (lts, pair, order_id, event_price, order_qty, snapshot_id,
                  exchange_timestamp, episode_no, event_no, MAX_EPISODE_NO))


def insert_episode(curr, snapshot_id, episode_no, episode_starts, rts):

    curr.execute("INSERT INTO bitfinex.bf_order_book_episodes "
                 "(snapshot_id, episode_no,"
                 "starts_exchange_timestamp,ends_exchange_timestamp) "
                 "VALUES (%s, %s, %s, %s)",
                 (snapshot_id, episode_no, episode_starts, rts))


def process_raw_order_book(q, stop_flag, pair, snapshot_id):
    logger = logging.getLogger("bitfinex.order.book.event")
    try:
        with connect_db() as con:
            con.set_session(autocommit=False, deferrable=True)
            with con.cursor() as curr:
                episode_no = 0
                event_no = 1
                episode_starts = None

                increase_episode_no = False  # The first 'addition' event

                while not stop_flag.is_set():
                    data, lts = q.get()
                    logger.debug("%i %s" % (snapshot_id, data))
                    *data, rts = data
                    rts = datetime.fromtimestamp(rts/1000)
                    lts = datetime.fromtimestamp(lts)
                    if isinstance(data[0][0], list):
                        data = data[0]
                    for d in data:
                        if not float(d[1]):  # it is a 'removal' event
                            if increase_episode_no:
                                # it is the first one for an episode
                                con.commit()
                                increase_episode_no = False
                                episode_no += 10
                                if episode_no == MAX_EPISODE_NO:
                                    stop_flag.set()
                                    break
                                event_no = 1
                                insert_episode(curr, snapshot_id, episode_no,
                                               episode_starts, rts)
                                # the end time of this episode will be
                                # the start time for the next one
                                episode_starts = rts
                                logger.debug("Unprocessed queue size: %i" %
                                             (q.qsize(),))
                        elif not increase_episode_no:
                            # it is the first 'addition' event of an episode
                            increase_episode_no = True

                            if episode_no == 0:
                                # Need to insert the anomalous '0' episode
                                # for it is the only episode starting from
                                # an 'addition' event. The others start from
                                # a 'removal' event and are inserted by the
                                # code above
                                episode_starts = rts
                                insert_episode(curr, snapshot_id, episode_no,
                                               episode_starts, rts)

                        insert_event(curr, lts, pair, d[0], d[1], d[2],
                                     snapshot_id, rts, episode_no, event_no)
                        event_no += 1

            # the latest uncommitted episode will be rolled back
            con.rollback()
    except Exception as e:
        logger.exception('An exception caught while processing '
                         'an order book event: %s', e)
        stop_flag.set()


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
        snapshot_id = start_new_snapshot(ob_len, pair)
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

    ts = [Process(target=process_trade,
                  args=(wss.trades(pair), stop_flag, pair, snapshot_id)),
          Process(target=process_raw_order_book,
                  args=(wss.raw_books(pair), stop_flag, pair, snapshot_id)),
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
