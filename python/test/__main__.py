import unittest
import multiprocessing
import logging
from obanalyticsdb.__main__ import listener_process


def main():

    queue = multiprocessing.Queue(-1)
    listener = multiprocessing.Process(target=listener_process,
                                       args=(queue, "test.log"))
    listener.start()

    h = logging.handlers.QueueHandler(queue)
    root = logging.getLogger()
    root.addHandler(h)
    root.setLevel(logging.DEBUG)

    unittest.main(module='test.test_bitfinex', exit=False)
    queue.put_nowait(None)
    listener.join()


if __name__ == '__main__':
    main()
