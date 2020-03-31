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
from obadiah.capture import MessageHandler


class CoinbaseMessageHandler(MessageHandler):
    TRADES_SAVE_LEN = 2
    EVENTS_SAVE_LEN = 10

    def __init__(self, ws, exchange, exchange_id, pair, pair_id, pool, q):
        super().__init__(ws, exchange, exchange_id, pair, pair_id, pool, q,
                         'type')
        self.pair = (self.pair[:3]+'-'+self.pair[3:]).upper()
        self.logger = logging.getLogger(__name__ + ".messagehandler")
        self.trades = []
        self.events = []
        self.era = None

    async def subscribe_channels(self):
        await self.ws.send(json.dumps({
            "type": "subscribe",
            "product_ids": [self.pair],
            "channels": ["full"]
        }))
        return

    async def received(self, lts, message):
        self.logger.info(message)

    async def open(self, lts, message):
        self.logger.info(message)

    async def done(self, lts, message):
        self.logger.info(message)

    async def match(self, lts, message):
        self.logger.info(message)

    async def change(self, lts, message):
        self.logger.info(message)

    async def activate(self, lts, message):
        self.logger.info(message)

    async def subscriptions(self, lts, message):
        self.logger.info(message)

    async def close(self):
        return
