import asyncio
import asyncpg
import websockets
import logging
import json
from datetime import datetime


async def dispatch_raw_order_book(q, pair, pool, stop_flag, chanId, sub_lts):
    logger = logging.getLogger(f"dispatch_raw_order_book({pair})")
    table = 'transient_raw_book_events'
    columns = ['exchange_timestamp', 'order_id', 'price', 'amount', 'pair_id',
               'local_timestamp', 'channel_id',
               'subscribed_at_local_timestamp', 'episode_timestamp']
    is_episode_completed = False
    is_episode_started = False
    episode_data = []
    accumulated_data = []
    episode_rts = None
    try:
        async with pool.acquire() as con:
            pair_id = await con.fetchval('''
                                        select pair_id
                                        from bitfinex.pairs
                                        where pair = $1
                                         ''', pair)
        while True:
            lts, data = await q.get()
            rts = data[1]
            rts = datetime.fromtimestamp(rts/1000)

            if isinstance(data[0][0], list):
                episode_data = [(d, rts) for d in data[0]]
                is_episode_completed = True
                episode_rts = rts
            else:
                if data[0] == 'hb':
                    continue
                data = data[0]
                if not float(data[1]):
                    if is_episode_started:
                        episode_data = accumulated_data
                        is_episode_completed = True
                        is_episode_started = False
                        accumulated_data = []
                else:
                    is_episode_started = True

                accumulated_data.append((data, rts))

            logger.debug(data)
            if is_episode_completed:
                records = [(rts, d[0], d[1], d[2], pair_id, lts, chanId,
                            sub_lts, episode_rts) for d, rts in episode_data]
                async with pool.acquire() as con:
                    await con.copy_records_to_table(table, records=records,
                                                    schema_name='bitfinex',
                                                    columns=columns)
                is_episode_completed = False

            if rts > episode_rts:
                episode_rts = rts

    except asyncio.CancelledError:
        logger.info(f'dispatch_raw_order_book({pair}) cancelled, exiting ...')
        raise
    except Exception as e:
        logger.error(e)
        stop_flag.set()
        raise e


async def dispatch_trades(q, pair, pool, stop_flag, chanId, sub_lts):
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
                async with pool.acquire() as con:
                    await con.execute('''
                                    insert into bitfinex.transient_trades
                                    (id, qty, price, local_timestamp,
                                    exchange_timestamp, pair_id, channel_id,
                                    subscribed_at_local_timestamp)
                                    values ($1, $2, $3, $4, $5, $6, $7, $8)
                                    ''', d[0], d[2], d[3], lts,
                                      datetime.fromtimestamp(d[1]/1000),
                                      pair_id, chanId, sub_lts)
                logger.debug('Inserted %s %s', lts, d)
    except asyncio.CancelledError:
        logger.info(f'dispatch_trades({pair}) cancelled, exiting ...')
        raise
    except Exception as e:
        logger.error(e)
        stop_flag.set()
        raise e


async def suck_bitfinex_socket(stop_flag, pair, user, database):
    logger = logging.getLogger("suck_bitfinex_socket")
    logger.info(f'Started {pair}, {user}, {database}')

    async def set_name(con):
        await con.execute(f"set application_name to '{pair}:BITFINEX'")

    detected_errors = []

    async with asyncpg.create_pool(user=user, database=database, min_size=1,
                                   max_size=2, init=set_name) as pool:
        async with websockets.connect("wss://api.bitfinex.com/ws/2") as ws:

            await ws.send(json.dumps({'event': 'conf', 'flags': 32768}))

            await ws.send(json.dumps({
                "event": "subscribe",
                "channel": "trades", "symbol": 't'+pair}))

            await ws.send(json.dumps({
                "event": "subscribe", "channel": "book", "prec": "R0",
                "len": 100, "symbol": 't'+pair}))

            channels = {}
            tasks = {}
            queues = {}

            while not stop_flag.is_set():
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
                            if message['channel'] == 'trades':
                                tasks[chanId] = asyncio.ensure_future(
                                    dispatch_trades(queues[chanId],
                                                    message['pair'],
                                                    pool,
                                                    stop_flag, chanId, lts))
                            elif message['channel'] == 'book':
                                tasks[chanId] = asyncio.ensure_future(
                                    dispatch_raw_order_book(queues[chanId],
                                                            message['pair'],
                                                            pool,
                                                            stop_flag, chanId,
                                                            lts))
                        elif message['event'] == 'unsubscribed':
                            # we don't expect any 'unsubscribed' messages ...
                            detected_errors.append(message)
                            stop_flag.set()
                        else:
                            logger.debug(message)
                    else:  # data
                        chanId = message[0]
                        await queues[chanId].put((lts, message[1:]))
                except Exception as e:
                    detected_errors.append(e)
                    logger.error(e)
                    stop_flag.set()

    for task in tasks.values():
        try:
            if not task.done():
                task.cancel()
                await task
            else:
                task.result()
        except asyncio.CancelledError:
            pass
        except Exception as e:
            detected_errors.append(e)

    if detected_errors != []:
        logger.error(detected_errors)

    logger.info('Exit')

    return detected_errors


def capture(pair, dbname, user,  stop_flag, log_queue):

    detected_errors = asyncio.get_event_loop().run_until_complete(
        suck_bitfinex_socket(stop_flag, pair, user, dbname))
    return len(detected_errors)
