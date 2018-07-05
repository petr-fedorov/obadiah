from multiprocessing import Process
import logging
import time
from btfxwss import BtfxWss
import psycopg2
import datetime


def connect_db():
    return psycopg2.connect("dbname=ob-analytics user=ob-analytics")


def process_trade(q, stop_flag, pair, snapshot_id):
    logger = logging.getLogger("process_trade")
    with connect_db() as con:
        con.set_session(autocommit=True)
        with con.cursor() as curr:
            while not stop_flag.is_set():
                data, lts = q.get()
                logger.debug("%i %s" % (snapshot_id, data))
                *data, rts = data
                lts = datetime.datetime.fromtimestamp(lts)
                if data[0] == 'tu':
                    data = [data[1]]
                elif data[0] == 'te':
                    data = []
                else:
                    data = data[0]  # it's an initial snapshot of trades
                for d in data:
                    try:
                        curr.execute("INSERT INTO bitfinex.bf_trades"
                                     "(id, pair, trade_timestamp, qty, price,"
                                     "local_timestamp, snapshot_id,"
                                     "exchange_timestamp)"
                                     "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                                     (d[0], pair,
                                      datetime.datetime.fromtimestamp(
                                          d[1]/1000), d[2], d[3], lts,
                                      snapshot_id,
                                      datetime.datetime.fromtimestamp(
                                          rts/1000)))
                    except Exception as e:
                        logger.exception('An exception caught while trying to'
                                         ' insert trade: %s', e)


def start_new_snapshot(ob_len, pair):
    logger = logging.getLogger()
    with connect_db() as con:
        # con.set_session(autocommit=True)
        with con.cursor() as curr:
            try:
                curr.execute("insert into bitfinex.bf_snapshots (len)"
                             "values (%s) returning snapshot_id", (ob_len,))
                snapshot_id = curr.fetchone()[0]
                con.commit()
                logger.info("New snapshot started: %i" % snapshot_id)
            except Exception as e:
                logger.exception('An exception caught while trying to start'
                                 'a new snapshot: %s',
                                 e)
                raise e

    return snapshot_id


def capture(logging_queue, configurer, stop_flag):
    configurer(logging_queue)

    ob_len = 100
    pair = 'BTCUSD'

    try:
        snapshot_id = start_new_snapshot(ob_len, pair)
    except Exception:
        return

    wss = BtfxWss(log_level=logging.INFO)
    wss.start()

    while not wss.conn.connected.is_set():
        time.sleep(1)

    wss.config(ts=True)
    # wss.subscribe_to_raw_order_book(pair, len=100)
    wss.subscribe_to_trades(pair)
    time.sleep(10)

    ts = [Process(target=process_trade,
                  args=(wss.trades(pair), stop_flag, pair, snapshot_id)),
          ]

    for t in ts:
        t.start()

    for t in ts:
        t.join()

    wss.stop()
