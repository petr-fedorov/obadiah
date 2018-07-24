import obanalyticsdb.bitfinex as bf
import logging
import logging.handlers
import multiprocessing
import sys
import traceback
import signal
import argparse


def listener_process(queue, log_file_name):
    root = logging.getLogger()
    h = logging.handlers.RotatingFileHandler(log_file_name,
                                             'a',
                                             2**22,
                                             10)
    f = logging.Formatter('%(asctime)s %(process)-6d %(name)s '
                          '%(levelname)-8s %(message)s')
    h.setFormatter(f)
    root.addHandler(h)
    while True:
        try:
            record = queue.get()
            if record is None:
                break
            logger = logging.getLogger(record.name)
            logger.handle(record)
        except Exception:
            print('Whoops! Problem:', file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
    print('listener_process() is done.', file=sys.stdout)


def main():
    parser = argparse.ArgumentParser(description="Gather high-frequency trade "
                                     "data for a pair from a cryptocurrency "
                                     "exchange and store it.")
    parser.add_argument("--stream", help="where STREAM  must be in the format "
                        "PAIR:EXCHANGE (default: BTCUSD:BITFINEX)",
                        default="BTCUSD:BITFINEX")

    args = parser.parse_args()
    stream = args.stream.split(':')

    stop_flag = multiprocessing.Event()

    def handler(signum, frame):
        stop_flag.set()

    signal.signal(signal.SIGINT, handler)

    queue = multiprocessing.Queue(-1)
    listener = multiprocessing.Process(target=listener_process,
                                       args=(queue,
                                             "oba%s_%s.log" % tuple(stream)))
    listener.start()

    h = logging.handlers.QueueHandler(queue)
    root = logging.getLogger()
    root.addHandler(h)
    root.setLevel(logging.INFO)

    exchanges = {'BITFINEX': bf.capture}

    try:
        capture = exchanges[stream[1]]
        print("Press Ctrl-C to stop ...")
        capture(stream[0], stop_flag)
    except KeyError as e:
        root.exception(e)
        print('Exchange %s is not supported (yet)' % stream[1])

    queue.put_nowait(None)
    listener.join()


if __name__ == '__main__':
    main()
