import asyncio
import asyncpg
import aiohttp
import websockets
import logging
import json
from datetime import datetime
from decimal import Decimal


class BitfinexBookDataHandler:
    # Will send to Postgres using COPY only this number of events or more
    MIN_SAVE_COUNT = 1000

    def __init__(self, con, pair_id, message):
        self.chanId = int(message['chanId'])
        self.logger = logging.getLogger(__name__ + ".bookdatahandler")
        #  self.logger.setLevel(logging.DEBUG)
        self.pair_id = pair_id
        self.con = con

        self.is_episode_started = False
        self.accumulated_data = []
        self.episode_rts = None
        self.table = 'transient_raw_book_events'
        self.columns = ['exchange_timestamp', 'order_id', 'price', 'amount',
                        'pair_id', 'local_timestamp', 'channel_id',
                        'episode_timestamp', 'bl']
        self.records = []

    async def data(self, lts, data, bl):
        data = data[1:]
        is_episode_completed = False
        rts = data[1]
        rts = datetime.fromtimestamp(rts/1000)

        if isinstance(data[0][0], list):
            episode_data = [(d, rts, lts, bl) for d in data[0]]
            is_episode_completed = True
            self.episode_rts = rts
            self.logger.info('%s %s', rts, data[0])
            await self.con.execute('''
                insert into bitfinex.transient_raw_book_channels
                (episode_timestamp, pair_id, channel_id)
                values($1, $2, $3)''', rts, self.pair_id, self.chanId)
        else:
            if data[0] == 'hb':
                return
            data = data[0]
            if not float(data[1]):
                if self.is_episode_started:
                    episode_data = self.accumulated_data
                    is_episode_completed = True
                    self.is_episode_started = False
                    self.accumulated_data = []
            else:
                self.is_episode_started = True

            self.accumulated_data.append((data, rts, lts, bl))

        if is_episode_completed:
            self.records = self.records + [(rts, int(d[0]), Decimal(d[1]),
                                            Decimal(d[2]),
                                            self.pair_id, lts, self.chanId,
                                            self.episode_rts, bl)
                                           for d, rts, lts, bl in episode_data]
            reccount = len(self.records)
            if reccount > BitfinexBookDataHandler.MIN_SAVE_COUNT:
                await self.con.copy_records_to_table(self.table,
                                                     records=self.records,
                                                     schema_name='bitfinex',
                                                     columns=self.columns)
                self.logger.debug('Saved %i raw book events: %s - %s',
                                  reccount, self.records[0][0],
                                  self.records[-1][0])
                self.records = []
            else:
                self.logger.debug('Accumulated an episode to be saved with %i '
                                  'raw book events ...', reccount)
            is_episode_completed = False

        if rts > self.episode_rts:
            self.episode_rts = rts

    async def close(self):
        reccount = len(self.records)
        if reccount:

            await self.con.copy_records_to_table(self.table,
                                                 records=self.records,
                                                 schema_name='bitfinex',
                                                 columns=self.columns)
            self.logger.info('Finally saved %i raw book events, pair_id %i '
                             'episode_timestamp: %s - %s',
                             reccount, self.pair_id, self.records[0][0],
                             self.records[-1][0])
            self.records = []
        if len(self.accumulated_data):
            self.logger.info('An incomplete episode, not saved: %s',
                             self.accumulated_data)
        self.logger.info('Closed handler for channel %i', self.chanId)


class BitfinexTradeDataHandler:
    def __init__(self, con, pair_id, message):
        self.chanId = int(message['chanId'])
        self.logger = logging.getLogger(__name__ + ".tradedatahandler")
        self.pair_id = pair_id
        self.con = con

    async def data(self, lts, data, bl):
        data = data[1:]
        if data[0] == 'tu':
            data = [data[1]]
        elif data[0] == 'te' or data[0] == 'hb':
            data = []
        else:
            # initial snapshot of trades
            self.logger.info(data)
            data = data[0]
        for d in data:
            await self.con.execute('''
                                   insert into bitfinex.transient_trades
                                   (id, qty, price, local_timestamp,
                                   exchange_timestamp, pair_id, channel_id)
                                   values ($1, $2, $3, $4, $5, $6, $7) ''',
                                   int(d[0]), Decimal(d[2]), Decimal(d[3]),
                                   lts, datetime.fromtimestamp(d[1]/1000),
                                   self.pair_id, self.chanId)

            self.logger.debug(d)

    async def close(self):
        self.logger.info('Closed handler for channel %i', self.chanId)


class BitfinexMessageHandler:

    def __init__(self, ws, pair, pair_id, pool, q):
        self.ws = ws
        self.pair = pair
        self.pair_id = pair_id
        self.pool = pool
        self.channels = {}
        self.q = q
        self.logger = logging.getLogger(__name__ + ".messagehandler")

    async def process_messages(self):
        async with self.pool.acquire() as con:
            self.con = con
            await con.execute(
                f"set application_name to 'BITFINEX:{self.pair}'")
            lts, bl, message = await self.q.get()
            MIN_MAX_QUEUE = 1024
            max_queue = MIN_MAX_QUEUE
            while message is not None:
                message = json.loads(message)
                self.logger.debug(message)
                if isinstance(message, dict):
                    await getattr(self, message['event'])(lts, message)
                else:
                    await self.data(lts, message, bl)
                lts, bl, message = await self.q.get()
                if self.q.qsize() > max_queue:
                    self.logger.warning(
                        'queue size: %i', self.q.qsize())
                    max_queue = self.q.qsize()*1.25
                elif (self.q.qsize() >= MIN_MAX_QUEUE and
                      self.q.qsize() < max_queue*0.75/1.25):
                    self.logger.warning(
                        'queue size: %i (decreasing)', self.q.qsize())
                    max_queue = self.q.qsize()
            await asyncio.shield(self.close())

    async def info(self, lts, message):
        self.logger.info(message)
        if message.get("version", 0):
            await self.ws.send(json.dumps({"event": "subscribe",
                                           "channel": "book",
                                           "prec": "R0",
                                           "len": 100,
                                           "symbol": 't'+self.pair}))
            await self.ws.send(json.dumps({
                "event": "subscribe",
                "channel": "trades", "symbol": 't'+self.pair}))
        elif message.get("code", 0) == 20051:
            self.logger.info('Trying to reconnect as requested ...')
            await self.ws.close()

    async def conf(self, lts, message):
        self.logger.info(message)

    async def subscribed(self, lts, message):
        self.logger.info(message)
        if message['channel'] == 'book':
            self.logger.info('Channel %i, pair_id %i',
                             message['chanId'], self.pair_id)
            handler = BitfinexBookDataHandler(self.con, self.pair_id, message)
        elif message['channel'] == 'trades':
            handler = BitfinexTradeDataHandler(self.con, self.pair_id, message)
        self.channels[message['chanId']] = handler

    async def data(self, lts, message, bl):
        await (self.channels[message[0]].data(lts, message, bl))

    async def close(self):
        for handler in self.channels.values():
            await handler.close()


async def capture(pair, user, database):
    logger = logging.getLogger(__name__ + ".capture")
    logger.info(f'Started {pair}, {user}, {database}')

    async with await asyncpg.create_pool(user=user, database=database,
                                         min_size=1, max_size=1) as pool:

        async with pool.acquire() as con:
            pair_id = await con.fetchval('''
                                         select pair_id from obanalytics.pairs
                                         where pair = $1 ''', pair)
        is_closing = False
        MIN_MAX_QUEUE = 100
        wait_list = list()

        while True:
            try:
                if is_closing:
                    break
                logger.info('Connecting to Bitfinex ...')
                max_queue = MIN_MAX_QUEUE
                async with websockets.connect("wss://api.bitfinex.com/ws/2",
                                              max_queue=2**20) as ws:
                    q = asyncio.Queue()
                    handler = asyncio.ensure_future(
                        BitfinexMessageHandler(ws, pair, pair_id, pool,
                                               q).process_messages())
                    await ws.send(json.dumps({'event': 'conf',
                                              'flags': 32768 + 8}))
                    while True:
                        try:
                            message = await asyncio.wait_for(ws.recv(),
                                                             timeout=2.0)
                            lts = datetime.now()
                            bl = len(ws.messages)
                            if handler.done():
                                handler.result()
                                raise asyncio.CancelledError
                            else:
                                q.put_nowait((lts, bl, message))

                            if bl > max_queue or is_closing:
                                logger.warning(
                                    'websockets internal queue size: %i', bl)
                                if is_closing:
                                    logger.info(message)
                                max_queue = bl*1.25
                            elif (bl >= MIN_MAX_QUEUE and
                                  bl < max_queue*0.75/1.25):
                                logger.warning(
                                    'websockets internal queue size: %i '
                                    '(decreasing)', bl)
                                max_queue = bl
                        except asyncio.TimeoutError:
                            logger.info('Websocket exhausted, re-connect ...')
                            await ws.close()
                        except asyncio.CancelledError:
                            logger.info('Closing websocket ...')
                            is_closing = True
                            await ws.close()
            except (websockets.InvalidHandshake, websockets.InvalidState,
                    websockets.PayloadTooBig, websockets.ConnectionClosed,
                    websockets.WebSocketProtocolError) as e:
                logger.info(e)
                q.put_nowait((datetime.now(), 0, None))
                wait_list.append(handler)
                # don't exit, re-connect

            except Exception as e:
                logger.exception(e)
                raise

        await asyncio.gather(*wait_list)
        logger.info('Exiting ...')


async def monitor(user, database):

    logger = logging.getLogger(__name__ + ".monitor")
    logger.info(f'Started {user}, {database}')

    con = await asyncpg.connect(user=user, database=database)
    await con.execute(f"set application_name to 'BITFINEX'")

    logger.info('Connecting to Bitfinex ...')
    async with aiohttp.ClientSession() as session:
        while True:
            try:
                async with session.get('https://api.bitfinex.com/v1/'
                                       'symbols_details') as resp:
                    details = json.loads(await resp.text())
                    for d in details:
                        if await con.fetchval('select * from bitfinex.'
                                              'update_symbol_details($1, $2, '
                                              '$3, $4, $5, $6, $7, $8)',
                                              d['pair'],
                                              d['price_precision'],
                                              d['initial_margin'],
                                              d['minimum_margin'],
                                              d['maximum_order_size'],
                                              d['minimum_order_size'],
                                              d['expiration'],
                                              d['margin']):
                            logger.info('Updated %s', d)
                await asyncio.sleep(60)
            except asyncio.CancelledError:
                logger.info('Cancelled, exiting ...')
                raise
            except Exception as e:
                logger.error(e)
