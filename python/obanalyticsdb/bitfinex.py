import asyncio
import asyncpg
import aiohttp
import websockets
import logging
import json
from datetime import datetime


class BitfinexBookDataHandler:
    def __init__(self, con, pair_id, message):
        self.chanId = message['chanId']
        self.logger = logging.getLogger("BitfinexBookDataHandler")
        self.pair_id = pair_id
        self.con = con

        self.is_episode_started = False
        self.accumulated_data = []
        self.episode_rts = None
        self.table = 'transient_raw_book_events'
        self.columns = ['exchange_timestamp', 'order_id', 'price', 'amount',
                        'pair_id', 'local_timestamp', 'channel_id',
                        'episode_timestamp']

    async def data(self, lts, data):
        data = data[1:]
        is_episode_completed = False
        rts = data[1]
        rts = datetime.fromtimestamp(rts/1000)

        if isinstance(data[0][0], list):
            episode_data = [(d, rts, lts) for d in data[0]]
            is_episode_completed = True
            self.episode_rts = rts
            self.logger.info('%s %s', rts, data[0])
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

            self.accumulated_data.append((data, rts, lts))

        if is_episode_completed:
            records = [(rts, d[0], d[1], d[2], self.pair_id, lts, self.chanId,
                        self.episode_rts) for d, rts, lts in episode_data]
            await self.con.copy_records_to_table(self.table,
                                                 records=records,
                                                 schema_name='bitfinex',
                                                 columns=self.columns)
            is_episode_completed = False

        if rts > self.episode_rts:
            self.episode_rts = rts


class BitfinexTradeDataHandler:
    def __init__(self, con, pair_id, message):
        self.chanId = message['chanId']
        self.logger = logging.getLogger("BitfinexTradeDataHandler")
        self.pair_id = pair_id
        self.con = con

    async def data(self, lts, data):
        data = data[1:]
        if data[0] == 'tu':
            data = [data[1]]
        elif data[0] == 'te' or data[0] == 'hb':
            data = []
        else:
            self.logger.info(data)
            return
        for d in data:
            await self.con.execute('''
                                   insert into bitfinex.transient_trades
                                   (id, qty, price, local_timestamp,
                                   exchange_timestamp, pair_id, channel_id)
                                   values ($1, $2, $3, $4, $5, $6, $7) ''',
                                   d[0], d[2], d[3], lts,
                                   datetime.fromtimestamp(d[1]/1000),
                                   self.pair_id, self.chanId)


class BitfinexMessageHandler:

    def __init__(self, ws, pair, pair_id, con):
        self.ws = ws
        self.pair = pair
        self.pair_id = pair_id
        self.con = con
        self.channels = {}
        self.logger = logging.getLogger("BitfinexMessageHandler")

    async def info(self, lts, message):
        self.logger.info(message)
        if message.get("version", 0):
            await self.ws.send(json.dumps({
                "event": "subscribe",
                "channel": "trades", "symbol": 't'+self.pair}))
            await self.ws.send(json.dumps({"event": "subscribe",
                                           "channel": "book",
                                           "prec": "R0",
                                           "len": 100,
                                           "symbol": 't'+self.pair}))

    async def conf(self, lts, message):
        self.logger.info(message)

    async def subscribed(self, lts, message):
        self.logger.info(message)
        if message['channel'] == 'book':
            handler = BitfinexBookDataHandler(self.con, self.pair_id, message)
        elif message['channel'] == 'trades':
            handler = BitfinexTradeDataHandler(self.con, self.pair_id, message)
        self.channels[message['chanId']] = handler

    async def data(self, lts, message):
        await (self.channels[message[0]].data(lts, message))


async def capture(pair, user, database):
    logger = logging.getLogger("capture")
    logger.info(f'Started {pair}, {user}, {database}')

    con = await asyncpg.connect(user=user, database=database)
    pair_id = await con.fetchval(''' select pair_id from obanalytics.pairs
                                where pair = $1 ''', pair)
    await con.execute(f"set application_name to '{pair}:BITFINEX'")

    while True:
        try:
            logger.info('Connecting to Bitfinex ...')
            async with websockets.connect("wss://api.bitfinex.com/ws/2") as ws:
                await ws.send(json.dumps({'event': 'conf', 'flags': 32768}))
                handler = BitfinexMessageHandler(ws, pair, pair_id, con)
                async for message in ws:
                    lts = datetime.now()
                    message = json.loads(message)
                    #  logger.debug(message)
                    if isinstance(message, dict):
                        await getattr(handler, message['event'])(lts, message)
                    else:
                        await handler.data(lts, message)

        except websockets.ConnectionClosed as e:
            logger.error(e)
            # don't exit, re-connect
        except asyncio.CancelledError:
            logger.info('Cancelled, exiting ...')
            raise
        except Exception as e:
            logger.error(e)
            raise


async def monitor(user, database):

    logger = logging.getLogger("monitor")
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
