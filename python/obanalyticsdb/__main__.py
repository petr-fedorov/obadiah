import obanalyticsdb.bitfinex as bf
import logging
import logging.handlers
import multiprocessing
import sys
import traceback
import signal


def listener_configurer():
    root = logging.getLogger()
    h = logging.handlers.RotatingFileHandler('obanalyticsdb.log',
                                             'a',
                                             2**20,
                                             10)
    f = logging.Formatter('%(asctime)s %(process)-6d %(name)s '
                          '%(levelname)-8s %(message)s')
    h.setFormatter(f)
    root.addHandler(h)


def listener_process(queue, configurer):
    configurer()
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


def worker_configurer(queue):
    h = logging.handlers.QueueHandler(queue)
    root = logging.getLogger()
    root.addHandler(h)
    root.setLevel(logging.DEBUG)


def main():

    stop_flag = multiprocessing.Event()

    def handler(signum, frame):
        stop_flag.set()

    signal.signal(signal.SIGINT, handler)
    print("Press Ctrl-C to stop ...")

    queue = multiprocessing.Queue(-1)
    listener = multiprocessing.Process(target=listener_process,
                                       args=(queue, listener_configurer))
    listener.start()

    bf.capture(queue, worker_configurer, stop_flag)

    queue.put_nowait(None)
    listener.join()


if __name__ == '__main__':
    main()
