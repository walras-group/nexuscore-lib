# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2026 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------

from typing import Callable

from cpython.datetime cimport datetime
from cpython.datetime cimport timedelta
from cpython.datetime cimport tzinfo
from libc.stdint cimport uint64_t

from nexuscore.core.message cimport Event
from nexuscore.core.message cimport Request
from nexuscore.core.message cimport Response
from nexuscore.core.rust.common cimport LiveClock_API
from nexuscore.core.rust.common cimport TestClock_API
from nexuscore.core.rust.common cimport TimeEvent_t
from nexuscore.core.rust.core cimport CVec
from nexuscore.core.uuid cimport UUID4
from nexuscore.model.identifiers cimport TraderId
from nexuscore.serialization.base cimport Serializer


cdef class Clock:
    cpdef double timestamp(self)
    cpdef uint64_t timestamp_ms(self)
    cpdef uint64_t timestamp_us(self)
    cpdef uint64_t timestamp_ns(self)
    cpdef datetime utc_now(self)
    cpdef datetime local_now(self, tzinfo tz=*)
    cpdef uint64_t next_time_ns(self, str name)
    cpdef void register_default_handler(self, handler: Callable[[TimeEvent], None])
    cpdef void set_time_alert(
        self,
        str name,
        object alert_time,
        callback: Callable[[TimeEvent], None]=*,
        bint override=*,
        bint allow_past=*,
    )
    cpdef void set_time_alert_ns(
        self,
        str name,
        uint64_t alert_time_ns,
        callback: Callable[[TimeEvent], None]=*,
        bint allow_past=*,
    )
    cpdef void set_timer(
        self,
        str name,
        timedelta interval,
        datetime start_time=*,
        datetime stop_time=*,
        callback: Callable[[TimeEvent], None]=*,
        bint allow_past=*,
        bint fire_immediately=*,
    )
    cpdef void set_timer_ns(
        self,
        str name,
        uint64_t interval_ns,
        uint64_t start_time_ns,
        uint64_t stop_time_ns,
        callback: Callable[[TimeEvent], None]=*,
        bint allow_past=*,
        bint fire_immediately=*,
    )
    cpdef void cancel_timer(self, str name)
    cpdef void cancel_timers(self)


cdef dict[UUID4, Clock] _COMPONENT_CLOCKS

cdef list[TestClock] get_component_clocks(UUID4 instance_id)
cpdef void register_component_clock(UUID4 instance_id, Clock clock)
cpdef void deregister_component_clock(UUID4 instance_id, Clock clock)


cdef bint FORCE_STOP

cpdef void set_backtest_force_stop(bint value)
cpdef bint is_backtest_force_stop()


cdef class TestClock(Clock):
    cdef TestClock_API _mem

    cpdef void set_time(self, uint64_t to_time_ns)
    cdef CVec advance_time_c(self, uint64_t to_time_ns, bint set_time=*)
    cpdef list advance_time(self, uint64_t to_time_ns, bint set_time=*)


cdef class LiveClock(Clock):
    cdef LiveClock_API _mem


cdef class TimeEvent(Event):
    cdef TimeEvent_t _mem

    cdef str to_str(self)

    @staticmethod
    cdef TimeEvent from_mem_c(TimeEvent_t raw)


cdef class TimeEventHandler:
    cdef object _handler
    cdef readonly TimeEvent event
    """The handlers event.\n\n:returns: `TimeEvent`"""

    cpdef void handle(self)


cdef str RECV
cdef str SENT
cdef str CMD
cdef str EVT
cdef str DOC
cdef str RPT
cdef str REQ
cdef str RES


cdef class MessageBus:
    cdef Clock _clock
    cdef dict[Subscription, list[str]] _subscriptions
    cdef dict[str, list] _patterns
    cdef list _topics_cache
    cdef dict _query_cache
    cdef dict[str, object] _endpoints
    cdef dict[UUID4, object] _correlation_index
    cdef tuple[type] _publishable_types
    cdef set[type] _streaming_types
    cdef bint _resolved

    cdef readonly TraderId trader_id
    """The trader ID associated with the bus.\n\n:returns: `TraderId`"""
    cdef readonly Serializer serializer
    """The serializer for the bus.\n\n:returns: `Serializer`"""
    cdef readonly bint has_backing
    """If the message bus has a database backing.\n\n:returns: `bool`"""
    cdef readonly uint64_t sent_count
    """The count of messages sent through the bus.\n\n:returns: `uint64_t`"""
    cdef readonly uint64_t req_count
    """The count of requests processed by the bus.\n\n:returns: `uint64_t`"""
    cdef readonly uint64_t res_count
    """The count of responses processed by the bus.\n\n:returns: `uint64_t`"""
    cdef readonly uint64_t pub_count
    """The count of messages published by the bus.\n\n:returns: `uint64_t`"""

    cpdef list endpoints(self)
    cpdef list topics(self)
    cpdef list subscriptions(self, str pattern=*)
    cpdef set streaming_types(self)
    cpdef bint has_subscribers(self, str pattern=*)
    cpdef bint is_subscribed(self, str topic, handler)
    cpdef bint is_pending_request(self, UUID4 request_id)
    cpdef bint is_streaming_type(self, type cls)

    cpdef void dispose(self)
    cpdef void register(self, str endpoint, handler)
    cpdef void deregister(self, str endpoint, handler)
    cpdef void add_streaming_type(self, type cls)
    cpdef void send(self, str endpoint, msg)
    cpdef void request(self, str endpoint, Request request)
    cpdef void response(self, Response response)
    cpdef void subscribe(self, str topic, handler, int priority=*)
    cpdef void unsubscribe(self, str topic, handler)
    cpdef void publish(self, str topic, msg, bint external_pub=*)
    cdef void publish_c(self, str topic, msg, bint external_pub=*)
    cpdef void publish_batch(self, str topic, list msgs, bint external_pub=*)
    cdef void publish_batch_c(self, str topic, list msgs, bint external_pub=*)
    cdef list _resolve_subscriptions(self, str topic)


cdef class Subscription:
    cdef Py_hash_t _hash
    cdef readonly str topic
    """The topic for the subscription.\n\n:returns: `str`"""
    cdef readonly object handler
    """The handler for the subscription.\n\n:returns: `Callable`"""
    cdef readonly int priority
    """The priority for the subscription.\n\n:returns: `int`"""

    @staticmethod
    cdef Subscription _create(str topic, object handler, int priority)
