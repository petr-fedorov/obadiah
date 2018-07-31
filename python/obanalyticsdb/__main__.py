import logging
import logging.handlers
from multiprocessing import set_start_method, Event, Process, Queue
import signal
import argparse
import obanalyticsdb.bitfinex as bf
from obanalyticsdb.utils import listener_process, logging_configurer


def main():
    parser = argparse.ArgumentParser(description="Gather high-frequency trade "
                                     "data for a pair from a cryptocurrency "
                                     "exchange and store it.")
    parser.add_argument("--stream", help="where STREAM  must be in the format "
                        "PAIR:EXCHANGE (default: BTCUSD:BITFINEX)",
                        default="BTCUSD:BITFINEX")

    args = parser.parse_args()
    stream = args.stream.split(':')
    # We have to use the default context since BtfxWss uses it to create Queues
    set_start_method('spawn')

    stop_flag = Event()

    signal.signal(signal.SIGINT, lambda n, f: stop_flag.set())

    log_queue = Queue(-1)
    listener = Process(target=listener_process,
                       args=(log_queue, "oba%s_%s.log" % tuple(stream)))
    listener.start()

    logging_configurer(log_queue)
    logger = logging.getLogger("obanalyticsdb.main")
    logger.info('Started')

    exchanges = {'BITFINEX': bf.capture}

    try:
        capture = exchanges[stream[1]]
        print("Press Ctrl-C to stop ...")
        capture(stream[0], stop_flag, log_queue)
    except KeyError as e:
        logging.getLogger("bitfinex.main").exception(e)
        print('Exchange %s is not supported (yet)' % stream[1])

    logger.info('Exit')
    log_queue.put_nowait(None)
    listener.join()


if __name__ == '__main__':
    main()
