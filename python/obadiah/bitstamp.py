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
import json
from datetime import datetime
from obadiah.capture import MessageHandler
from decimal import Decimal




class BitstampMessageHandler(MessageHandler):
    TRADES_SAVE_LEN=2
    EVENTS_SAVE_LEN=10

    def __init__(self, ws, exchange, exchange_id, pair, pair_id, pool, q):
        super().__init__(ws, exchange, exchange_id, pair, pair_id, pool, q)
        self.logger = logging.getLogger(__name__ + ".messagehandler")
        self.trades = []
        self.events = []
        self.era = None


    async def subscribe_channels(self):
        await self.ws.send(json.dumps({
            "event": "bts:subscribe",
            "data": { "channel": f"live_trades_{self.pair.lower()}"}}
        ))
        await self.ws.send(json.dumps({
            "event": "bts:subscribe",
            "data": { "channel": f"live_orders_{self.pair.lower()}"}}
        ))
        return

    async def trade(self, lts, message):
        self.logger.debug(message)
        message = message["data"]
        ts = datetime.fromtimestamp(
            float(message["microtimestamp"])/1000000)
        self.trades.append((
            ts,
            Decimal(message["amount_str"]),
            message["buy_order_id"],
            message["sell_order_id"],
            Decimal(message["price_str"]),
            message["id"],
            'sell' if message["type"] else 'buy',
            self.pair_id,
            lts
        ))

        if len(self.trades) > BitstampMessageHandler.TRADES_SAVE_LEN:
            await self.con.copy_records_to_table(
                "transient_live_trades",
                records=self.trades,
                columns=["trade_timestamp", "amount", "buy_order_id",
                         "sell_order_id", "price", "bitstamp_trade_id",
                         "trade_type", "pair_id", "local_timestamp"],
                schema_name="bitstamp"
            )
            self.trades = []

    async def live_order_event(self, lts, message):
        self.logger.debug(message)
        data = message["data"]
        ts = datetime.fromtimestamp(
            float(data["microtimestamp"])/1000000)

        if self.era is None:
            self.era = ts
            await self.con.execute('''
                                   insert into bitstamp.live_orders_eras
                                   (era, pair_id)
                                   values($1, $2)''', self.era, self.pair_id)
            self.logger.info(f'{self.exchange} {self.pair} new era {self.era}')

        self.events.append((
            ts,
            datetime.fromtimestamp(float(data["datetime"])),
            Decimal(data["amount_str"]),
            Decimal(data["price_str"]),
            int(data["id"]),
            'sell' if data["order_type"] else 'buy',
            message["event"],
            self.era,
            self.pair_id,
            lts
        ))

        if len(self.events) > BitstampMessageHandler.EVENTS_SAVE_LEN:
            await self.con.copy_records_to_table(
                "transient_live_orders",
                records=self.events,
                columns=["microtimestamp", "datetime", "amount", "price",
                         "order_id", "order_type", "event", "era",
                         "pair_id", "local_timestamp"],
                schema_name="bitstamp"
            )
            self.events = []

    async def order_created(self, lts, message):
        await self.live_order_event(lts,message)

    async def order_changed(self, lts, message):
        await self.live_order_event(lts,message)

    async def order_deleted(self, lts, message):
        await self.live_order_event(lts,message)

    async def bts_subscription_succeeded(self, lts,message):
        self.logger.info(message)
        self.timestamp = 2

    async def close(self):
        if len(self.trades) > 0:
            await self.con.copy_records_to_table(
                "transient_live_trades",
                records=self.trades,
                columns=["trade_timestamp", "amount", "buy_order_id",
                         "sell_order_id", "price", "bitstamp_trade_id",
                         "trade_type", "pair_id", "local_timestamp"],
                schema_name="bitstamp"
            )
        if len(self.events) > 0:
            await self.con.copy_records_to_table(
                "transient_live_orders",
                records=self.events,
                columns=["microtimestamp", "datetime", "amount", "price",
                         "order_id", "order_type", "event", "era",
                         "pair_id", "local_timestamp"],
                schema_name="bitstamp"
            )
            self.events = []
        return
