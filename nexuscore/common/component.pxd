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
from nexuscore.core.uuid cimport UUID4


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

cdef list[Clock] get_component_clocks(UUID4 instance_id)
cpdef void register_component_clock(UUID4 instance_id, Clock clock)
cpdef void deregister_component_clock(UUID4 instance_id, Clock clock)


cdef bint FORCE_STOP

cpdef void set_backtest_force_stop(bint value)
cpdef bint is_backtest_force_stop()


cdef class LiveClock(Clock):
    cdef object _sched
    cdef object _default_handler


cdef class TimeEvent(Event):
    cdef str _name
    cdef UUID4 _id
    cdef uint64_t _ts_event
    cdef uint64_t _ts_init

    cdef str to_str(self)
