import logging
import logging.handlers
from multiprocessing import set_start_method, Event, Process, Queue
import signal
import argparse
import sys
import obanalyticsdb.bitfinex as bf
import obanalyticsdb.bitstamp as bs
from obanalyticsdb.utils import listener_process, logging_configurer
import asyncio
import functools


def main():
    parser = argparse.ArgumentParser(description="Gather high-frequency trade "
                                     "data for a pair from a cryptocurrency "
                                     "exchange and store it.")
    parser.add_argument("-s", "--stream",
                        help="where STREAM  must be in the format "
                        "PAIR:EXCHANGE (default: BTCUSD:BITFINEX)",
                        default="BTCUSD:BITFINEX")

    parser.add_argument("-d", "--dbname", help="where DBNAME is the name of "
                        "PostgreSQL database where the data is to be saved "
                        "(default: ob-analytics),",
                        default="ob-analytics")

    parser.add_argument("-U", "--user", help="where USER is the name of "
                        "PostgreSQL database role to be used to save the data"
                        "(default: ob-analytics),",
                        default="ob-analytics")
    args = parser.parse_args()
    stream = args.stream.split(':')
    if stream[1] == 'BITSTAMP':
        set_start_method('spawn')

        stop_flag = Event()

        signal.signal(signal.SIGINT, lambda n, f: stop_flag.set())

        log_queue = Queue(-1)
        listener = Process(target=listener_process,
                           args=(log_queue, "./oba%s_%s_%s.log" %
                                 (tuple(stream) + (args.dbname.upper(),))))
        listener.start()

        logging_configurer(log_queue, logging.INFO)
        logger = logging.getLogger("obanalyticsdb.main")
        logger.info('Started')

        exchanges = {'BITFINEX': bf.capture, 'BITSTAMP': bs.capture}
        exitcode = 0

        try:
            capture = exchanges[stream[1]]
            print("Press Ctrl-C to stop ...")
            exitcode = capture(stream[0], args.dbname, args.user, stop_flag,
                               log_queue)
        except KeyError as e:
            logger.exception(e)

        logger.info('Exit')
        log_queue.put_nowait(None)
        listener.join()

    elif stream[1] == 'BITFINEX':

        h = logging.handlers.RotatingFileHandler(
            "./oba%s_%s_%s.log" % (tuple(stream) + (args.dbname.upper(),)),
            'a', 2**24, 20)
        logging.basicConfig(format='%(asctime)s %(process)-6d %(name)s '
                            '%(levelname)-8s %(message)s',
                            handlers=[h], level=logging.INFO)

        logger = logging.getLogger("obanalyticsdb.main")

        task = asyncio.ensure_future(bf.capture(stream[0],
                                                args.user,
                                                args.dbname))
        loop = asyncio.get_event_loop()
        #  loop.set_debug(True)
        loop.add_signal_handler(getattr(signal, 'SIGINT'),
                                functools.partial(
                                    lambda task: task.cancel(), task))

        print("Press Ctrl-C to stop ...")
        try:
            asyncio.get_event_loop().run_until_complete(task)
        except asyncio.CancelledError:
            logger.info('Cancelled, exiting ...')
        except Exception as e:
            logger.error(e)
            exitcode = 1
        exitcode = 0
    else:
        print('Exchange %s is not supported (yet)' % stream[1])
        exitcode = 1

    sys.exit(exitcode)


if __name__ == '__main__':
    main()
