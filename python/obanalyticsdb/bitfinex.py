import multiprocessing
import logging
import time


def process_trade(queue, configurer, stop_flag):
    configurer(queue)
    logger = logging.getLogger()
    while not stop_flag.is_set():
        logger.debug("Test message")
        time.sleep(5)


def capture(queue, configurer, stop_flag):
    configurer(queue)
    logger = logging.getLogger()
    logger.debug("Test message")
    process = multiprocessing.Process(target=process_trade,
                                      args=(queue, configurer, stop_flag))
    process.start()
    process.join()
