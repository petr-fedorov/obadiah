import asyncio
import asyncpg
import websockets
import logging
import json
from datetime import datetime


async def dispatch_trades(q, pair, pool, stop_flag):
    logger = logging.getLogger(f"dispatch_trades({pair})")
    try:
        async with pool.acquire() as con:
            pair_id = await con.fetchval('''
                                        select pair_id
                                        from bitfinex.pairs
                                        where pair = $1
                                         ''', pair)
            while True:
                lts, data = await q.get()
                if data[0] == 'tu':
                    data = [data[1]]
                elif data[0] == 'te' or data[0] == 'hb':
                    data = []
                else:
                    continue
                for d in data:
                    await con.execute('''
                                    insert into bitfinex.transient_trades
                                    (id, qty, price, local_timestamp,
                                    exchange_timestamp, pair_id)
                                    values ($1, $2, $3, $4, $5, $6 )
                                    ''', d[0], d[2], d[3], lts,
                                      datetime.fromtimestamp(d[1]/1000),
                                      pair_id)
                    # logger.debug(status)
                    logger.debug('Inserted %s %s', lts, d)
    except asyncio.CancelledError:
        logger.debug(f'save_trade({pair}) cancelled, exiting ...')
    except Exception as e:
        logger.error(e)
        stop_flag.set()


async def suck_bitfinex_socket(stop_flag, pair, subscriptions,
                               bitfinex_socket_flags, user, database):
    logger = logging.getLogger("suck_bitfinex_socket")
    logger.info(f'Started {pair} , {subscriptions}, {user}, {database}')

    async def set_name(con):
        await con.execute(f"set application_name to '{pair}:BITFINEX'")

    pool = await asyncpg.create_pool(user=user,
                                     database=database,
                                     min_size=1,
                                     max_size=2,
                                     init=set_name)
    async with websockets.connect("wss://api.bitfinex.com/ws/2") as ws:

        await ws.send(json.dumps({'event': 'conf',
                                  'flags': bitfinex_socket_flags}))

        for channel in subscriptions:
            await ws.send(json.dumps({"event": "subscribe",
                                      "channel": channel,
                                      "symbol": pair}))
        channels = {}
        tasks = {}
        queues = {}

        while not stop_flag.is_set() or channels != {}:
            try:
                # If there is no activity, Bitfinex will send a heartbeat
                # message every 5 sec, so timeout is not needed for recv()
                message = await ws.recv()
                lts = datetime.now()
                message = json.loads(message)

                if isinstance(message, dict):
                    logger.info(message)
                    if message['event'] == 'subscribed':
                        chanId = message['chanId']
                        channels[chanId] = lts  # subscription time
                        queues[chanId] = asyncio.Queue()
                        tasks[chanId] = asyncio.ensure_future(
                            dispatch_trades(queues[chanId],
                                            message['pair'],
                                            pool,
                                            stop_flag))
                    elif message['event'] == 'unsubscribed':
                        chanId = message['chanId']
                        tasks[chanId].cancel()
                        del channels[chanId]
                        del tasks[chanId]
                        del queues[chanId]
                    else:
                        logger.debug(message)
                else:  # data
                    chanId = message[0]
                    await queues[chanId].put((lts, message[1:]))
            except websockets.ConnectionClosed:
                logger.info('Websocket connection closed!')
                channels = {}
                for t in tasks.values():
                    t.cancel()
                tasks = {}
                queues = {}
                stop_flag.set()
            except Exception as e:
                logger.error(e)
                stop_flag.set()
                raise e

            if stop_flag.is_set():
                for key, value in zip(channels.keys(),
                                      channels.values()):
                    if value:
                        await ws.send(json.dumps(
                            {'event': 'unsubscribe', 'chanId': key}))
                        channels[key] = None
    await pool.close()
    logger.info('Exit')


def capture(pair, dbname, user,  stop_flag, log_queue):

    asyncio.get_event_loop().run_until_complete(
        suck_bitfinex_socket(stop_flag, pair, ["trades"], 32768, user, dbname))
