import logging
import logging.handlers
import sys
import traceback
import signal


def listener_process(logging_queue, log_file_name):
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    root = logging.getLogger()
    h = logging.handlers.RotatingFileHandler(log_file_name,
                                             'a',
                                             2**24,
                                             20)
    f = logging.Formatter('%(asctime)s %(process)-6d %(name)s '
                          '%(levelname)-8s %(message)s')
    h.setFormatter(f)
    root.addHandler(h)
    while True:
        try:
            record = logging_queue.get()
            if record is None:
                break
            logger = logging.getLogger(record.name)
            logger.handle(record)
        except Exception:
            print('Whoops! Problem:', file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
    #  print('Exit - listener_process()', file=sys.stdout)


def logging_configurer(logging_queue, logging_level=logging.DEBUG):
    h = logging.handlers.QueueHandler(logging_queue)
    root = logging.getLogger()
    root.addHandler(h)
    root.setLevel(logging_level)


def log_notices(logger, notices):
    while notices:
        logger.info(notices.pop(0))


class QueueSizeLogger:
    def __init__(self, queue, queue_name, threshold=100):
        self.n = 0
        self.queue = queue
        self.queue_name = queue_name
        self.THRE = threshold

    def __call__(self, logger):

        s = self.queue.qsize()
        if (s > self.THRE*2**(self.n)):
            self.n += 1
            logger.warning("Unprocessed %s size: %i" % (self.queue_name, s))
        elif self.n and (s < self.THRE*2**(self.n - 1)):
            self.n -= 1
