# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.




import logging
import logging.handlers
import signal
import argparse
import sys
from obadiah.bitstamp import BitstampMessageHandler
from obadiah.bitfinex import BitfinexMessageHandler, monitor
from obadiah.capture import capture
import asyncio
import functools
import sslkeylog

def main():
    parser = argparse.ArgumentParser(description="Gather high-frequency trade "
                                     "data for a selected pair at a "
                                     "cryptocurrency exchange "
                                     "or gather an exchange-wide "
                                     "low-frequency data and store them into "
                                     "a database.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-s", "--stream",
                       help="where STREAM  must be in the format "
                       "PAIR:EXCHANGE ")

    group.add_argument("-m", "--monitor",
                       help="where MONITOR is the exchange name to gather "
                       "its low-frequency data (i.e. list of traded pairs, "
                       " their parameters, etc )")

    parser.add_argument("-d", "--dbname", help="where DBNAME is the name of "
                        "PostgreSQL database where the data is to be saved "
                        "(default: ob-analytics),",
                        default="ob-analytics")

    parser.add_argument("-U", "--user", help="where USER is the name of "
                        "PostgreSQL database role to be used to save the data"
                        "(default: ob-analytics),",
                        default="ob-analytics")
    args = parser.parse_args()
    sslkeylog.set_keylog("sslkeylog.txt")

    if args.stream:
        stream = args.stream.split(':')
        if stream[1] == 'BITSTAMP':
            ws_url = "wss://ws.bitstamp.net"
            mh = BitstampMessageHandler
        elif stream[1] == 'BITFINEX':
            ws_url = "wss://api-pub.bitfinex.com/ws/2"
            mh = BitfinexMessageHandler
        else:
            print('Exchange %s is not supported (yet)' % stream[1])
            exitcode = 1
            sys.exit(exitcode)

        h = logging.handlers.RotatingFileHandler(
            "./oba%s_%s.log" % ('_'.join(stream), args.dbname.upper(),),
            'a', 2**24, 20)
        logging.basicConfig(format='%(asctime)s %(process)-6d %(name)s '
                            '%(levelname)-8s %(message)s', handlers=[h])

        logging.getLogger("obadiah").setLevel(logging.INFO)
        logging.getLogger("websockets").setLevel(logging.INFO)
        logger = logging.getLogger(__name__ + ".main")

        task = asyncio.ensure_future(capture(stream[1],
                                                stream[0],
                                                args.user,
                                                args.dbname,
                                                ws_url,
                                                mh))
        loop = asyncio.get_event_loop()
        #  loop.set_debug(True)
        loop.add_signal_handler(getattr(signal, 'SIGINT'),
                                functools.partial(
                                    lambda task: task.cancel(), task))

        print("Press Ctrl-C to stop ...")
        try:
            exitcode = 0
            asyncio.get_event_loop().run_until_complete(task)
        except asyncio.CancelledError:
            logger.info('Cancelled, exiting ...')
        except Exception as e:
            logger.exception(e)
            exitcode = 1
        sys.exit(exitcode)
    elif args.monitor:
        if args.monitor == 'BITFINEX':
            h = logging.handlers.RotatingFileHandler(
                "oba%s_%s.log" % (args.monitor.upper(), args.dbname.upper(),),
                'a', 2**24, 20)
            logging.basicConfig(format='%(asctime)s %(process)-6d %(name)s '
                                '%(levelname)-8s %(message)s',
                                handlers=[h])
            logging.getLogger(__name__.split('.')[0]).setLevel(logging.INFO)
            logger = logging.getLogger(__name__ + ".main")

            task = asyncio.ensure_future(monitor(args.user, args.dbname))
            loop = asyncio.get_event_loop()
            #  loop.set_debug(True)
            loop.add_signal_handler(getattr(signal, 'SIGINT'),
                                    functools.partial(
                                        lambda task: task.cancel(), task))

            print("Press Ctrl-C to stop ...")
            try:
                exitcode = 0
                asyncio.get_event_loop().run_until_complete(task)
            except asyncio.CancelledError:
                logger.info('Cancelled, exiting ...')
            except Exception as e:
                logger.exception(e)
                exitcode = 1
        else:
            print('Exchange %s is not supported (yet)' % args.monitor)
            exitcode = 1

        sys.exit(exitcode)

    else:
        parser.print_usage()


if __name__ == '__main__':
    main()
