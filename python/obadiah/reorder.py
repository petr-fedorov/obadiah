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


from queue import Empty
import logging
from heapq import heappush, heappop
from datetime import datetime, timedelta
from functools import total_ordering
from obadiah.utils import QueueSizeLogger


@total_ordering
class OrderedDatabaseInsertion:
    def __init__(self, local_timestamp, exchange_timestamp, priority=0):
        self.local_timestamp = local_timestamp
        self.exchange_timestamp = exchange_timestamp
        self.priority = priority

    def __eq__(self, other):
        return ((self.exchange_timestamp == other.exchange_timestamp) and
                (self.priority == other.priority) and
                (self.local_timestamp == other.local_timestamp))

    def __lt__(self, other):
        if self.exchange_timestamp < other.exchange_timestamp:
            return True
        elif (self.exchange_timestamp == other.exchange_timestamp and
              self.priority < other.priority):
            return True
        elif (self.exchange_timestamp == other.exchange_timestamp and
              self.priority == other.priority and
              self.local_timestamp < other.local_timestamp):
            return True
        else:
            return False


class Reorderer(object):

    def __init__(self, q_unordered, q_ordered, stop_flag, delay=1):

        self.logger = logging.getLogger(self.__module__ + "."
                                        + self.__class__.__qualname__)

        self.q_unordered = q_unordered
        self.q_ordered = q_ordered
        self.delay = timedelta(seconds=delay)
        self.stop_flag = stop_flag
        self.buffer = []
        self.latest_arrived = datetime.now()
        self.latest_departed = datetime.now()
        self.log_output_queue_size = QueueSizeLogger(q_ordered, "q_ordered")

    def __repr__(self):
        return "Reorderer a:%s d: %s b:%s" % (self.latest_arrived.strftime(
            "%H-%M-%S.%f")[:-3],
            self.latest_departed.strftime("%H-%M-%S.%f")[:-3], self.buffer)

    def _current_delay(self):
        return (self.latest_arrived - self.latest_departed)

    def receive_unordered(self):

        while self._current_delay() < self.delay:
            try:
                obj = self.q_unordered.get(True,
                                           (self.delay -
                                            self._current_delay()
                                            ).total_seconds())
                if obj.local_timestamp > self.latest_arrived:
                    self.latest_arrived = obj.local_timestamp
                heappush(self.buffer, obj)

            except Empty:
                self.latest_arrived = datetime.now()

    def send_reordered(self):
        while True:
            try:
                if self.buffer[0].local_timestamp > self.latest_departed:
                    self.latest_departed = self.buffer[0].local_timestamp

                if self._current_delay() >= self.delay:
                    obj = heappop(self.buffer)
                    self.q_ordered.put(obj)
                else:
                    break
            except IndexError:
                self.latest_departed = datetime.now()
                break

    def run(self):
        while not (self.stop_flag.is_set()
                   and self.q_unordered.qsize() == 0
                   and len(self.buffer) == 0
                   and self.q_ordered.qsize() == 0):
            self.receive_unordered()
            self.send_reordered()
            self.log_output_queue_size(self.logger)
