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



import asyncio
import asyncpg
import websockets
import logging
import json
import re
from datetime import datetime


class QueueSizeLogger:

    def __init__(self, exchange, pair, queue_name, logger, min_max_queue):
        self.queue_name = queue_name
        self.logger = logger
        self.exchange = exchange
        self.pair = pair
        self.min_max_queue = min_max_queue
        self.max_queue = min_max_queue
        self.logger.info(f'Started {self.exchange} {self.pair} '
                         f'{self.queue_name} queue size logging')

    def log(self, bl):

        if bl > self.max_queue:
            self.logger.warning(
                f'{self.exchange} {self.pair} {self.queue_name} queue size: %i',
                bl)
            self.max_queue = bl*1.25
        elif (bl >= self.min_max_queue and
                bl < self.max_queue*0.75/1.25):
            self.logger.warning(
                f'{self.exchange} {self.pair} '
                f'{self.queue_name} queue size: {bl} (decreasing)')
            self.max_queue = bl

class MessageHandler:

    def __init__(self, ws, exchange, exchange_id, pair, pair_id, pool, q):
        self.ws = ws
        self.exchange = exchange
        self.exchange_id = exchange_id
        self.pair = pair
        self.pair_id = pair_id
        self.pool = pool
        self.q = q

        # Wait for the book subscription up to 5 sec (then less -- see below)
        self.timeout = 30


    async def subscribe_channels(self):
        return


    async def data(self, lts, message):
        return


    async def process_messages(self):
        clean = lambda varStr: re.sub('\W|^(?=\d)','_', varStr)

        async with self.pool.acquire() as con:
            await con.execute(
                f"set application_name to '{self.exchange}:{self.pair}'")
            self.con = con
            qsl = QueueSizeLogger(self.exchange, self.pair, "internal",
                                  self.logger, 1000)
            lts, message = await self.q.get()
            while message is not None:
                message = json.loads(message)
                self.logger.debug(message)
                if isinstance(message, dict):
                    await getattr(self, clean(message['event']))(lts, message)
                else:
                    await self.data(lts, message)
                lts, message = await self.q.get()
                qsl.log(self.q.qsize())
            await asyncio.shield(self.close())



async def capture(exchange, pair, user, database, url, message_handler):
    logger = logging.getLogger(__name__ + ".capture")
    logger.info(f'Started {exchange}, {pair}, {user}, {database}')

    async with await asyncpg.create_pool(user=user, database=database,
                                         min_size=1, max_size=1) as pool:

        async with pool.acquire() as con:

            pair_id = await con.fetchval('''
                                         select pair_id from obanalytics.pairs
                                         where pair = $1 ''', pair)
            exchange_id = await con.fetchval('''
                                         select exchange_id
                                         from obanalytics.exchanges
                                         where exchange = $1 ''', exchange)
        is_closing = False
        wait_list = list()

        while True:
            try:
                if is_closing:
                    break
                logger.info(f'Connecting to {exchange} ...')
                async with websockets.connect(url,
                                              max_queue=2**20) as ws:
                    q = asyncio.Queue()
                    wqsl = QueueSizeLogger(exchange, pair,
                                       "websocket", logger, 100)
                    mh = message_handler(ws, exchange, exchange_id, pair,
                                         pair_id, pool, q)
                    mh.task = asyncio.ensure_future(mh.process_messages())
                    await mh.subscribe_channels()
                    while True:
                        try:
                            message = await asyncio.wait_for(
                                ws.recv(), timeout=mh.timeout)
                            lts = datetime.now()
                            if mh.task.done():
                                mh.task.result()
                                raise asyncio.CancelledError
                            else:
                                q.put_nowait((lts, message))
                            wqsl.log(len(ws.messages))

                        except asyncio.TimeoutError:
                            logger.info(f'{exchange}, {pair} websocket '
                                        'exhausted, re-connecting ...')
                            await ws.close()
                        except asyncio.CancelledError:
                            logger.info(f'{exchange} {pair} closing '
                                        'websocket ...')
                            is_closing = True
                            await ws.close()

            except (websockets.exceptions.InvalidHandshake,
                    websockets.exceptions.InvalidState,
                    websockets.exceptions.PayloadTooBig,
                    websockets.exceptions.ConnectionClosed,
                    websockets.exceptions.WebSocketProtocolError) as e:
                logger.info(e)
                q.put_nowait((datetime.now(), None))
                wait_list.append(mh.task)
                # don't exit, re-connect

            except (websockets.exceptions.WebSocketException, Exception) as e:
                logger.exception(e)
                raise

        await asyncio.gather(*wait_list)
        logger.info('Exiting ...')
