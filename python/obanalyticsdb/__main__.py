import logging
import logging.handlers
import multiprocessing
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

    multiprocessing.set_start_method('spawn')
    stop_flag = multiprocessing.Event()

    signal.signal(signal.SIGINT, lambda n, f: stop_flag.set())

    logging_queue = multiprocessing.Queue(-1)
    listener = multiprocessing.Process(target=listener_process,
                                       args=(logging_queue,
                                             "oba%s_%s.log" % tuple(stream)))
    listener.start()

    logging_configurer(logging_queue)

    exchanges = {'BITFINEX': bf.capture}

    try:
        capture = exchanges[stream[1]]
        print("Press Ctrl-C to stop ...")
        capture(stream[0], stop_flag, logging_queue)
    except KeyError as e:
        logging.getLogger("bitfinex.main").exception(e)
        print('Exchange %s is not supported (yet)' % stream[1])

    logging_queue.put_nowait(None)
    listener.join()


if __name__ == '__main__':
    main()
