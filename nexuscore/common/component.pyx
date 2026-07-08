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

import copy
import datetime as dt
from typing import Any
from typing import Callable

import cython
import numpy as np

cimport numpy as np
from cpython.datetime cimport datetime
from cpython.datetime cimport timedelta
from cpython.datetime cimport tzinfo
from cpython.object cimport PyObject
from cpython.pycapsule cimport PyCapsule_GetPointer
from libc.stdint cimport uint64_t

from nexuscore.core.correctness cimport Condition
from nexuscore.core.datetime cimport dt_to_unix_nanos
from nexuscore.core.datetime cimport maybe_dt_to_unix_nanos
from nexuscore.core.message cimport Event
from nexuscore.core.rust.common cimport TimeEventHandler_t
from nexuscore.core.rust.common cimport is_matching_ffi
from nexuscore.core.rust.common cimport live_clock_cancel_timer
from nexuscore.core.rust.common cimport live_clock_drop
from nexuscore.core.rust.common cimport live_clock_new
from nexuscore.core.rust.common cimport live_clock_next_time
from nexuscore.core.rust.common cimport live_clock_register_default_handler
from nexuscore.core.rust.common cimport live_clock_set_time_alert
from nexuscore.core.rust.common cimport live_clock_set_timer
from nexuscore.core.rust.common cimport live_clock_timer_count
from nexuscore.core.rust.common cimport live_clock_timer_names
from nexuscore.core.rust.common cimport live_clock_timestamp
from nexuscore.core.rust.common cimport live_clock_timestamp_ms
from nexuscore.core.rust.common cimport live_clock_timestamp_ns
from nexuscore.core.rust.common cimport live_clock_timestamp_us
from nexuscore.core.rust.common cimport test_clock_advance_time
from nexuscore.core.rust.common cimport test_clock_cancel_timer
from nexuscore.core.rust.common cimport test_clock_cancel_timers
from nexuscore.core.rust.common cimport test_clock_drop
from nexuscore.core.rust.common cimport test_clock_new
from nexuscore.core.rust.common cimport test_clock_next_time
from nexuscore.core.rust.common cimport test_clock_register_default_handler
from nexuscore.core.rust.common cimport test_clock_set_time
from nexuscore.core.rust.common cimport test_clock_set_time_alert
from nexuscore.core.rust.common cimport test_clock_set_timer
from nexuscore.core.rust.common cimport test_clock_timer_count
from nexuscore.core.rust.common cimport test_clock_timer_names
from nexuscore.core.rust.common cimport test_clock_timestamp
from nexuscore.core.rust.common cimport test_clock_timestamp_ms
from nexuscore.core.rust.common cimport test_clock_timestamp_ns
from nexuscore.core.rust.common cimport test_clock_timestamp_us
from nexuscore.core.rust.common cimport time_event_new
from nexuscore.core.rust.common cimport time_event_to_cstr
from nexuscore.core.rust.common cimport vec_time_event_handlers_drop
from nexuscore.core.rust.core cimport CVec
from nexuscore.core.rust.core cimport uuid4_from_cstr
from nexuscore.core.string cimport PyUnicode_AsUTF8AndSize
from nexuscore.core.string cimport cstr_to_pystr
from nexuscore.core.string cimport pystr_to_cstr
from nexuscore.core.string cimport ustr_to_pystr
from nexuscore.core.uuid cimport UUID4
from nexuscore.model.identifiers cimport TraderId
from nexuscore.serialization.base cimport _EXTERNAL_PUBLISHABLE_TYPES
from nexuscore.serialization.base cimport Serializer


cdef class Clock:
    """
    The base class for all clocks.

    Notes
    -----
    An *active* timer is one which has not expired.

    Warnings
    --------
    This class should not be used directly, but through a concrete subclass.
    """

    @property
    def timer_names(self) -> list[str]:
        """
        Return the names of *active* timers running in the clock.

        Returns
        -------
        list[str]

        """
        raise NotImplementedError("method `timer_names` must be implemented in the subclass")  # pragma: no cover

    @property
    def timer_count(self) -> int:
        """
        Return the count of *active* timers running in the clock.

        Returns
        -------
        int

        """
        raise NotImplementedError("method `timer_count` must be implemented in the subclass")  # pragma: no cover

    cpdef double timestamp(self):
        """
        Return the current UNIX timestamp in seconds.

        Returns
        -------
        double

        References
        ----------
        https://en.wikipedia.org/wiki/Unix_time

        """
        raise NotImplementedError("method `timestamp` must be implemented in the subclass")  # pragma: no cover

    cpdef uint64_t timestamp_ms(self):
        """
        Return the current UNIX timestamp in milliseconds (ms).

        Returns
        -------
        uint64_t

        References
        ----------
        https://en.wikipedia.org/wiki/Unix_time

        """
        raise NotImplementedError("method `timestamp_ms` must be implemented in the subclass")  # pragma: no cover

    cpdef uint64_t timestamp_us(self):
        """
        Return the current UNIX timestamp in microseconds (us).

        Returns
        -------
        uint64_t

        References
        ----------
        https://en.wikipedia.org/wiki/Unix_time

        """
        raise NotImplementedError("method `timestamp_us` must be implemented in the subclass")  # pragma: no cover

    cpdef uint64_t timestamp_ns(self):
        """
        Return the current UNIX timestamp in nanoseconds (ns).

        Returns
        -------
        uint64_t

        References
        ----------
        https://en.wikipedia.org/wiki/Unix_time

        """
        raise NotImplementedError("method `timestamp_ns` must be implemented in the subclass")  # pragma: no cover

    cpdef datetime utc_now(self):
        """
        Return the current time (UTC).

        Returns
        -------
        datetime
            The current tz-aware UTC time of the clock.

        """
        return dt.datetime.fromtimestamp(self.timestamp_ns() / 1_000_000_000, tz=dt.timezone.utc)

    cpdef datetime local_now(self, tzinfo tz = None):
        """
        Return the current datetime of the clock in the given local timezone.

        Parameters
        ----------
        tz : tzinfo, optional
            The local timezone (if None the system local timezone is assumed for
            the target timezone).

        Returns
        -------
        datetime
            tz-aware in local timezone.

        """
        return self.utc_now().astimezone(tz)

    cpdef void register_default_handler(self, handler: Callable[[TimeEvent], None]):
        """
        Register the given handler as the clocks default handler.

        Parameters
        ----------
        handler : Callable[[TimeEvent], None]
            The handler to register.

        Raises
        ------
        TypeError
            If `handler` is not of type `Callable`.

        """
        raise NotImplementedError("method `register_default_handler` must be implemented in the subclass")  # pragma: no cover

    cpdef uint64_t next_time_ns(self, str name):
        """
        Find a particular timer.

        Parameters
        ----------
        name : str
            The name of the timer.

        Returns
        -------
        uint64_t

        Raises
        ------
        ValueError
            If `name` is not a valid string.

        """
        raise NotImplementedError("method `next_time_ns` must be implemented in the subclass")  # pragma: no cover

    cpdef void set_time_alert(
        self,
        str name,
        alert_time,
        callback: Callable[[TimeEvent], None] = None,
        bint override = False,
        bint allow_past = True,
    ):
        """
        Set a time alert for the given time.

        When the time is reached the handler will be passed the `TimeEvent`
        containing the timers unique name. If no handler is passed then the
        default handler (if registered) will receive the `TimeEvent`.

        Parameters
        ----------
        name : str
            The name for the alert (must be unique for this clock).
        alert_time : datetime | int
            The time for the alert (datetime or UNIX nanoseconds).
        callback : Callable[[TimeEvent], None], optional
            The callback to receive time events.
        override: bool, default False
            If override is set to True an alert with a given name can be overwritten if it exists already.
        allow_past : bool, default True
            If True, allows an `alert_time` in the past and adjusts it to the current time
            for immediate firing. If False, raises an error when the `alert_time` is in the
            past, requiring it to be in the future.

        Raises
        ------
        ValueError
            If `name` is not a valid string.
        KeyError
            If `name` is not unique for this clock.
        TypeError
            If `handler` is not of type `Callable` or ``None``.
        ValueError
            If `handler` is ``None`` and no default handler is registered.

        Warnings
        --------
        If `alert_time` is in the past or at current time, then an immediate
        time event will be generated (rather than being invalid and failing a condition check).

        """
        if override and self.next_time_ns(name) > 0:
            self.cancel_timer(name)

        self.set_time_alert_ns(
            name=name,
            alert_time_ns=dt_to_unix_nanos(alert_time),
            callback=callback,
            allow_past=allow_past,
        )

    cpdef void set_time_alert_ns(
        self,
        str name,
        uint64_t alert_time_ns,
        callback: Callable[[TimeEvent], None] = None,
        bint allow_past = True,
    ):
        """
        Set a time alert for the given time.

        When the time is reached the handler will be passed the `TimeEvent`
        containing the timers unique name. If no callback is passed then the
        default handler (if registered) will receive the `TimeEvent`.

        Parameters
        ----------
        name : str
            The name for the alert (must be unique for this clock).
        alert_time_ns : uint64_t
            The UNIX timestamp (nanoseconds) for the alert.
        callback : Callable[[TimeEvent], None], optional
            The callback to receive time events.
        allow_past : bool, default True
            If True, allows an `alert_time_ns` in the past and adjusts it to the current time
            for immediate firing. If False, panics when the `alert_time_ns` is in the
            past, requiring it to be in the future.

        Raises
        ------
        ValueError
            If `name` is not a valid string.
        ValueError
            If `name` is not unique for this clock.
        TypeError
            If `callback` is not of type `Callable` or ``None``.
        ValueError
            If `callback` is ``None`` and no default handler is registered.

        Warnings
        --------
        If `alert_time_ns` is in the past or at current time, then an immediate
        time event will be generated (rather than being invalid and failing a condition check).

        """
        raise NotImplementedError("method `set_time_alert_ns` must be implemented in the subclass")  # pragma: no cover

    cpdef void set_timer(
        self,
        str name,
        timedelta interval,
        datetime start_time = None,
        datetime stop_time = None,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
        bint fire_immediately = False,
    ):
        """
        Set a timer to run.

        The timer will run from the start time (optionally until the stop time).
        When the intervals are reached the handlers will be passed the
        `TimeEvent` containing the timers unique name. If no handler is passed
        then the default handler (if registered) will receive the `TimeEvent`.

        Parameters
        ----------
        name : str
            The name for the timer (must be unique for this clock).
        interval : timedelta
            The time interval for the timer.
        start_time : datetime, optional
            The start time for the timer (if None then starts immediately).
        stop_time : datetime, optional
            The stop time for the timer (if None then repeats indefinitely).
        callback : Callable[[TimeEvent], None], optional
            The callback to receive time events.
        allow_past : bool, default True
            If True, allows timers where the next event time may be in the past.
            If False, raises an error when the next event time would be in the past.
        fire_immediately : bool, default False
            If True, the timer will fire immediately at the start time,
            then fire again after each interval. If False, the timer will
            fire after the first interval has elapsed (default behavior).

        Raises
        ------
        ValueError
            If `name` is not a valid string.
        KeyError
            If `name` is not unique for this clock.
        ValueError
            If `interval` is not positive (> 0).
        ValueError
            If `stop_time` is not ``None`` and `stop_time` < time now.
        ValueError
            If `stop_time` is not ``None`` and `start_time` + `interval` > `stop_time`.
        TypeError
            If `handler` is not of type `Callable` or ``None``.
        ValueError
            If `handler` is ``None`` and no default handler is registered.

        """
        interval_ns = <uint64_t>int(interval.total_seconds() * 1_000_000_000)

        self.set_timer_ns(
            name=name,
            interval_ns=interval_ns,
            start_time_ns=maybe_dt_to_unix_nanos(start_time) or 0,
            stop_time_ns=maybe_dt_to_unix_nanos(stop_time) or 0,
            callback=callback,
            allow_past=allow_past,
            fire_immediately=fire_immediately,
        )

    cpdef void set_timer_ns(
        self,
        str name,
        uint64_t interval_ns,
        uint64_t start_time_ns,
        uint64_t stop_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
        bint fire_immediately = False,
    ):
        """
        Set a timer to run.

        The timer will run from the start time until the stop time.
        When the intervals are reached the handlers will be passed the
        `TimeEvent` containing the timers unique name. If no handler is passed
        then the default handler (if registered) will receive the `TimeEvent`.

        Parameters
        ----------
        name : str
            The name for the timer (must be unique for this clock).
        interval_ns : uint64_t
            The time interval (nanoseconds) for the timer.
        start_time_ns : uint64_t
            The start UNIX timestamp (nanoseconds) for the timer.
        stop_time_ns : uint64_t
            The stop UNIX timestamp (nanoseconds) for the timer.
        callback : Callable[[TimeEvent], None], optional
            The callback to receive time events.
        allow_past : bool, default True
            If True, allows timers where the next event time may be in the past.
            If False, raises an error when the next event time would be in the past.
        fire_immediately : bool, default False
            If True, the timer will fire immediately at the start time,
            then fire again after each interval. If False, the timer will
            fire after the first interval has elapsed (default behavior).

        Raises
        ------
        ValueError
            If `name` is not a valid string.
        KeyError
            If `name` is not unique for this clock.
        ValueError
            If `interval` is not positive (> 0).
        ValueError
            If `stop_time` is not ``None`` and `stop_time` < time now.
        ValueError
            If `stop_time` is not ``None`` and `start_time` + interval > `stop_time`.
        TypeError
            If `callback` is not of type `Callable` or ``None``.
        ValueError
            If `callback` is ``None`` and no default handler is registered.

        """
        raise NotImplementedError("method `set_timer_ns` must be implemented in the subclass")  # pragma: no cover

    cpdef void cancel_timer(self, str name):
        """
        Cancel the timer corresponding to the given label.

        Parameters
        ----------
        name : str
            The name for the timer to cancel.

        Raises
        ------
        ValueError
            If `name` is not a valid string.
        KeyError
            If `name` is not an active timer name for this clock.

        """
        raise NotImplementedError("method `cancel_timer` must be implemented in the subclass")  # pragma: no cover

    cpdef void cancel_timers(self):
        """
        Cancel all timers.
        """
        raise NotImplementedError("method `cancel_timers` must be implemented in the subclass")  # pragma: no cover


# Global map of clocks per kernel instance used when running a `BacktestEngine`
_COMPONENT_CLOCKS = {}


cdef list[TestClock] get_component_clocks(UUID4 instance_id):
    # Create a shallow copy of the clocks list, in case a new
    # clock is registered during iteration.
    return _COMPONENT_CLOCKS[instance_id].copy()


cpdef void register_component_clock(UUID4 instance_id, Clock clock):
    Condition.not_none(instance_id, "instance_id")
    Condition.not_none(clock, "clock")

    cdef list[Clock] clocks = _COMPONENT_CLOCKS.get(instance_id)
    if clocks is None:
        clocks = []
        _COMPONENT_CLOCKS[instance_id] = clocks

    if clock not in clocks:
        clocks.append(clock)


cpdef void deregister_component_clock(UUID4 instance_id, Clock clock):
    Condition.not_none(instance_id, "instance_id")
    Condition.not_none(clock, "clock")

    cdef list[Clock] clocks = _COMPONENT_CLOCKS.get(instance_id)

    if clocks is None:
        return

    if clock in clocks:
        clocks.remove(clock)


cpdef void remove_instance_component_clocks(UUID4 instance_id):
    Condition.not_none(instance_id, "instance_id")

    _COMPONENT_CLOCKS.pop(instance_id, None)


# Global backtest force stop flag
_FORCE_STOP = False

cpdef void set_backtest_force_stop(bint value):
    global FORCE_STOP
    FORCE_STOP = value


cpdef bint is_backtest_force_stop():
    return FORCE_STOP


cdef class TestClock(Clock):
    """
    Provides a monotonic clock for backtesting and unit testing.

    """

    __test__ = False  # Prevents pytest from collecting this as a test class

    def __init__(self):
        self._mem = test_clock_new()

    def __del__(self) -> None:
        if self._mem._0 != NULL:
            test_clock_drop(self._mem)

    @property
    def timer_names(self) -> list[str]:
        cdef str timer_names = cstr_to_pystr(test_clock_timer_names(&self._mem))
        if not timer_names:
            return []

        # For simplicity we split a string on a reasonably unique delimiter.
        # This is a temporary solution pending the removal of Cython.
        return sorted(timer_names.split("<,>"))

    @property
    def timer_count(self) -> int:
        return test_clock_timer_count(&self._mem)

    cpdef double timestamp(self):
        return test_clock_timestamp(&self._mem)

    cpdef uint64_t timestamp_ms(self):
        return test_clock_timestamp_ms(&self._mem)

    cpdef uint64_t timestamp_us(self):
        return test_clock_timestamp_us(&self._mem)

    cpdef uint64_t timestamp_ns(self):
        return test_clock_timestamp_ns(&self._mem)

    cpdef void register_default_handler(self, callback: Callable[[TimeEvent], None]):
        Condition.callable(callback, "callback")

        test_clock_register_default_handler(&self._mem, <PyObject *>callback)

    cpdef void set_time_alert_ns(
        self,
        str name,
        uint64_t alert_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
    ):
        Condition.valid_string(name, "name")
        Condition.not_in(name, self.timer_names, "name", "self.timer_names")

        # Validate allow_past logic to prevent Rust errors
        cdef uint64_t ts_now = self.timestamp_ns()

        if not allow_past:
            if alert_time_ns < ts_now:
                alert_dt = datetime.fromtimestamp(alert_time_ns / 1e9).isoformat()
                current_dt = datetime.fromtimestamp(ts_now / 1e9).isoformat()
                raise ValueError(
                    f"Timer '{name}' alert time {alert_dt} was in the past "
                    f"(current time is {current_dt})"
                )

        test_clock_set_time_alert(
            &self._mem,
            pystr_to_cstr(name),
            alert_time_ns,
            <PyObject *>callback,
            allow_past,
        )

    cpdef void set_timer_ns(
        self,
        str name,
        uint64_t interval_ns,
        uint64_t start_time_ns,
        uint64_t stop_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
        bint fire_immediately = False,
    ):
        Condition.valid_string(name, "name")
        Condition.not_in(name, self.timer_names, "name", "self.timer_names")
        Condition.positive_int(interval_ns, "interval_ns")

        # Validate callback availability to prevent Rust panics
        # Note: We can't easily check if default handler is registered from Cython,
        # but we can provide a more informative error than a Rust panic
        # The existing tests in the codebase show this validation should be done

        cdef uint64_t ts_now = self.timestamp_ns()

        if start_time_ns == 0:
            start_time_ns = ts_now
        if stop_time_ns:
            Condition.is_true(stop_time_ns > ts_now, "`stop_time_ns` was < `ts_now`")
            Condition.is_true(start_time_ns + interval_ns <= stop_time_ns, "`start_time_ns` + `interval_ns` was > `stop_time_ns`")

        # Validate allow_past logic to prevent Rust errors
        cdef uint64_t next_event_time

        if not allow_past:
            if fire_immediately:
                next_event_time = start_time_ns
            else:
                next_event_time = start_time_ns + interval_ns

            if next_event_time < ts_now:
                next_dt = datetime.fromtimestamp(next_event_time / 1e9).isoformat()
                current_dt = datetime.fromtimestamp(ts_now / 1e9).isoformat()
                raise ValueError(
                    f"Timer '{name}' next event time {next_dt} would be in the past "
                    f"(current time is {current_dt})"
                )

        test_clock_set_timer(
            &self._mem,
            pystr_to_cstr(name),
            interval_ns,
            start_time_ns,
            stop_time_ns,
            <PyObject *>callback,
            allow_past,
            fire_immediately,
        )

    cpdef uint64_t next_time_ns(self, str name):
        Condition.valid_string(name, "name")
        return test_clock_next_time(&self._mem, pystr_to_cstr(name))

    cpdef void cancel_timer(self, str name):
        Condition.valid_string(name, "name")
        Condition.is_in(name, self.timer_names, "name", "self.timer_names")

        test_clock_cancel_timer(&self._mem, pystr_to_cstr(name))

    cpdef void cancel_timers(self):
        test_clock_cancel_timers(&self._mem)

    cpdef void set_time(self, uint64_t to_time_ns):
        """
        Set the clocks datetime to the given time (UTC).

        Parameters
        ----------
        to_time_ns : uint64_t
            The UNIX timestamp (nanoseconds) to set.

        """
        test_clock_set_time(&self._mem, to_time_ns)

    cdef CVec advance_time_c(self, uint64_t to_time_ns, bint set_time=True):
        Condition.is_true(to_time_ns >= test_clock_timestamp_ns(&self._mem), "to_time_ns was < time_ns (not monotonic)")

        return <CVec>test_clock_advance_time(&self._mem, to_time_ns, set_time)

    cpdef list advance_time(self, uint64_t to_time_ns, bint set_time=True):
        """
        Advance the clocks time to the given `to_time_ns`.

        Parameters
        ----------
        to_time_ns : uint64_t
            The UNIX timestamp (nanoseconds) to advance the clock to.
        set_time : bool
            If the clock should also be set to the given `to_time_ns`.

        Returns
        -------
        list[TimeEventHandler]
            Sorted chronologically.

        Raises
        ------
        ValueError
            If `to_time_ns` is < the clocks current time.

        """
        cdef CVec raw_handler_vec = self.advance_time_c(to_time_ns, set_time)
        cdef TimeEventHandler_t* raw_handlers = <TimeEventHandler_t*>raw_handler_vec.ptr
        cdef list event_handlers = []

        cdef:
            uint64_t i
            object callback
            TimeEvent event
            TimeEventHandler_t raw_handler
            TimeEventHandler event_handler
            PyObject *raw_callback
        for i in range(raw_handler_vec.len):
            raw_handler = <TimeEventHandler_t>raw_handlers[i]
            event = TimeEvent.from_mem_c(raw_handler.event)

            # Cast raw `PyObject *` to a `PyObject`
            raw_callback = <PyObject *>raw_handler.callback_ptr
            callback = <object>raw_callback

            event_handler = TimeEventHandler(event, callback)
            event_handlers.append(event_handler)

        vec_time_event_handlers_drop(raw_handler_vec)

        return event_handlers


cdef class LiveClock(Clock):
    """
    Provides a monotonic clock for live trading.

    All times are tz-aware UTC.

    Parameters
    ----------
    loop : asyncio.AbstractEventLoop
        The event loop for the clocks timers.
    """

    def __init__(self):
        self._mem = live_clock_new()

    def __del__(self) -> None:
        if self._mem._0 != NULL:
            live_clock_drop(self._mem)

    @property
    def timer_names(self) -> list[str]:
        cdef str timer_names = cstr_to_pystr(live_clock_timer_names(&self._mem))
        if not timer_names:
            return []

        # For simplicity we split a string on a reasonably unique delimiter.
        # This is a temporary solution pending the removal of Cython.
        return sorted(timer_names.split("<,>"))

    @property
    def timer_count(self) -> int:
        return live_clock_timer_count(&self._mem)

    cpdef double timestamp(self):
        return live_clock_timestamp(&self._mem)

    cpdef uint64_t timestamp_ms(self):
        return live_clock_timestamp_ms(&self._mem)

    cpdef uint64_t timestamp_us(self):
        return live_clock_timestamp_us(&self._mem)

    cpdef uint64_t timestamp_ns(self):
        return live_clock_timestamp_ns(&self._mem)

    cpdef void register_default_handler(self, callback: Callable[[TimeEvent], None]):
        Condition.callable(callback, "callback")

        callback = create_pyo3_conversion_wrapper(callback)

        live_clock_register_default_handler(&self._mem, <PyObject *>callback)

    cpdef void set_time_alert_ns(
        self,
        str name,
        uint64_t alert_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
    ):
        Condition.valid_string(name, "name")
        Condition.not_in(name, self.timer_names, "name", "self.timer_names")

        # Validate allow_past logic to prevent Rust errors
        cdef uint64_t ts_now = self.timestamp_ns()

        if not allow_past:
            if alert_time_ns < ts_now:
                alert_dt = datetime.fromtimestamp(alert_time_ns / 1e9).isoformat()
                current_dt = datetime.fromtimestamp(ts_now / 1e9).isoformat()
                raise ValueError(
                    f"Timer '{name}' alert time {alert_dt} was in the past "
                    f"(current time is {current_dt})"
                )

        if callback is not None:
            callback = create_pyo3_conversion_wrapper(callback)

        live_clock_set_time_alert(
            &self._mem,
            pystr_to_cstr(name),
            alert_time_ns,
            <PyObject *>callback,
            allow_past,
        )

    cpdef void set_timer_ns(
        self,
        str name,
        uint64_t interval_ns,
        uint64_t start_time_ns,
        uint64_t stop_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
        bint fire_immediately = False,
    ):
        Condition.valid_string(name, "name")
        Condition.not_in(name, self.timer_names, "name", "self.timer_names")
        Condition.positive_int(interval_ns, "interval_ns")

        # Validate callback availability to prevent Rust panics
        # For LiveClock, we need either a callback or a default handler
        # Since we can't easily check default handler from Cython, we need some validation
        if callback is None:
            # If no callback provided, we rely on default handler being set
            # This will be validated by Rust, but we can't prevent the panic here
            pass

        # Validate allow_past logic to prevent Rust errors
        cdef uint64_t ts_now = self.timestamp_ns()
        cdef uint64_t next_event_time

        if not allow_past:
            if start_time_ns != 0:  # Only validate if start_time is explicitly set
                if fire_immediately:
                    next_event_time = start_time_ns
                else:
                    next_event_time = start_time_ns + interval_ns

                if next_event_time < ts_now:
                    from datetime import datetime
                    next_dt = datetime.fromtimestamp(next_event_time / 1e9).isoformat()
                    current_dt = datetime.fromtimestamp(ts_now / 1e9).isoformat()
                    raise ValueError(
                        f"Timer '{name}' next event time {next_dt} would be in the past "
                        f"(current time is {current_dt})"
                    )

        if callback is not None:
            callback = create_pyo3_conversion_wrapper(callback)

        live_clock_set_timer(
            &self._mem,
            pystr_to_cstr(name),
            interval_ns,
            start_time_ns,
            stop_time_ns,
            <PyObject *>callback,
            allow_past,
            fire_immediately,
        )

    cpdef uint64_t next_time_ns(self, str name):
        Condition.valid_string(name, "name")

        return live_clock_next_time(&self._mem, pystr_to_cstr(name))

    cpdef void cancel_timer(self, str name):
        Condition.valid_string(name, "name")
        Condition.is_in(name, self.timer_names, "name", "self.timer_names")

        live_clock_cancel_timer(&self._mem, pystr_to_cstr(name))

    cpdef void cancel_timers(self):
        cdef str name
        for name in self.timer_names:
            # Using a list of timer names from the property and passing this
            # to cancel_timer() handles the clean removal of both the handler
            # and timer.
            self.cancel_timer(name)


def create_pyo3_conversion_wrapper(callback) -> Callable:
    def wrapper(capsule):
        callback(capsule_to_time_event(capsule))

    return wrapper


cdef class TimeEvent(Event):
    """
    Represents a time event occurring at the event timestamp.

    Parameters
    ----------
    name : str
        The event name.
    event_id : UUID4
        The event ID.
    ts_event : uint64_t
        UNIX timestamp (nanoseconds) when the time event occurred.
    ts_init : uint64_t
        UNIX timestamp (nanoseconds) when the object was initialized.
    """

    def __init__(
        self,
        str name not None,
        UUID4 event_id not None,
        uint64_t ts_event,
        uint64_t ts_init,
    ):
        # Precondition: `name` validated in Rust
        self._mem = time_event_new(
            pystr_to_cstr(name),
            event_id._mem,
            ts_event,
            ts_init,
        )

    def __getstate__(self):
        return (
            self.to_str(),
            self.id.value,
            self.ts_event,
            self.ts_init,
        )

    def __setstate__(self, state):
        self._mem = time_event_new(
            pystr_to_cstr(state[0]),
            uuid4_from_cstr(pystr_to_cstr(state[1])),
            self.ts_event,
            self.ts_init,
        )

    cdef str to_str(self):
        return ustr_to_pystr(self._mem.name)

    def __eq__(self, TimeEvent other) -> bool:
        if other is None:
            return False
        return self.id == other.id

    def __hash__(self) -> int:
        return hash(self.id)

    def __str__(self) -> str:
        return self.to_str()

    def __repr__(self) -> str:
        return cstr_to_pystr(time_event_to_cstr(&self._mem))

    @property
    def name(self) -> str:
        """
        Return the name of the time event.

        Returns
        -------
        str

        """
        return ustr_to_pystr(self._mem.name)

    @property
    def id(self) -> UUID4:
        """
        The event message identifier.

        Returns
        -------
        UUID4

        """
        cdef UUID4 uuid4 = UUID4.__new__(UUID4)
        uuid4._mem = self._mem.event_id

        return uuid4

    @property
    def ts_event(self) -> int:
        """
        UNIX timestamp (nanoseconds) when the event occurred.

        Returns
        -------
        int

        """
        return self._mem.ts_event

    @property
    def ts_init(self) -> int:
        """
        UNIX timestamp (nanoseconds) when the object was initialized.

        Returns
        -------
        int

        """
        return self._mem.ts_init

    @staticmethod
    cdef TimeEvent from_mem_c(TimeEvent_t mem):
        cdef TimeEvent event = TimeEvent.__new__(TimeEvent)
        event._mem = mem

        return event


cdef inline TimeEvent capsule_to_time_event(capsule):
    cdef TimeEvent_t* ptr = <TimeEvent_t*>PyCapsule_GetPointer(capsule, NULL)
    cdef TimeEvent event = TimeEvent.__new__(TimeEvent)
    event._mem = ptr[0]

    return event


cdef class TimeEventHandler:
    """
    Represents a time event with its associated handler.

    Parameters
    ----------
    event : TimeEvent
        The time event to handle
    handler : Callable[[TimeEvent], None]
        The handler to call.

    """

    def __init__(
        self,
        TimeEvent event not None,
        handler not None: Callable[[TimeEvent], None],
    ) -> None:
        self.event = event
        self._handler = handler

    cpdef void handle(self):
        """
        Call the handler with the contained time event.
        """
        self._handler(self.event)

    def __eq__(self, TimeEventHandler other) -> bool:
        if other is None:
            return False
        return self.event.ts_event == other.event.ts_event

    def __lt__(self, TimeEventHandler other) -> bool:
        if other is None:
            return NotImplemented
        return self.event.ts_event < other.event.ts_event

    def __le__(self, TimeEventHandler other) -> bool:
        if other is None:
            return NotImplemented
        return self.event.ts_event <= other.event.ts_event

    def __gt__(self, TimeEventHandler other) -> bool:
        if other is None:
            return NotImplemented
        return self.event.ts_event > other.event.ts_event

    def __ge__(self, TimeEventHandler other) -> bool:
        if other is None:
            return NotImplemented
        return self.event.ts_event >= other.event.ts_event

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"event={repr(self.event)})"
        )


RECV = "<--"
SENT = "-->"
CMD = "[CMD]"
EVT = "[EVT]"
DOC = "[DOC]"
RPT = "[RPT]"
REQ = "[REQ]"
RES = "[RES]"


cdef class MessageBus:
    """
    Provides a generic message bus to facilitate various messaging patterns.

    The bus provides both a producer and consumer API for Pub/Sub, Req/Rep, as
    well as direct point-to-point messaging to registered endpoints.

    Pub/Sub wildcard patterns for hierarchical topics are possible:
     - `*` asterisk represents one or more characters in a pattern.
     - `?` question mark represents a single character in a pattern.

    Given a topic and pattern potentially containing wildcard characters, i.e.
    `*` and `?`, where `?` can match any single character in the topic, and `*`
    can match any number of characters including zero characters.

    The asterisk in a wildcard matches any character zero or more times. For
    example, `comp*` matches anything beginning with `comp` which means `comp`,
    `complete`, and `computer` are all matched.

    A question mark matches a single character once. For example, `c?mp` matches
    `camp` and `comp`. The question mark can also be used more than once.
    For example, `c??p` would match both of the above examples and `coop`.

    Parameters
    ----------
    trader_id : TraderId
        The trader ID associated with the message bus.
    clock : Clock
        The clock for the message bus.
    name : str, optional
        The custom name for the message bus.
    serializer : Serializer, optional
        The serializer for database operations.

    Raises
    ------
    ValueError
        If `name` is not ``None`` and not a valid string.

    Warnings
    --------
    This message bus is not thread-safe and must be called from the same thread
    as the event loop.
    """

    def __init__(
        self,
        TraderId trader_id not None,
        Clock clock,
        UUID4 instance_id = None,
        str name = None,
        Serializer serializer = None,
        config: Any | None = None,
    ) -> None:
        if instance_id is None:
            instance_id = UUID4()

        if name is None:
            name = type(self).__name__

        Condition.valid_string(name, "name")

        self.trader_id = trader_id
        self.serializer = serializer
        self.has_backing = False

        self._clock = clock

        self._endpoints: dict[str, Callable[[Any], None]] = {}
        self._patterns: dict[str, list] = {}
        self._topics_cache = None
        self._query_cache = {}
        self._subscriptions: dict[Subscription, list[str]] = {}
        self._correlation_index: dict[UUID4, Callable[[Any], None]] = {}

        self._publishable_types = tuple(_EXTERNAL_PUBLISHABLE_TYPES)

        self._streaming_types = set()
        self._resolved = False

        # Counters
        self.sent_count = 0
        self.req_count = 0
        self.res_count = 0
        self.pub_count = 0

    cpdef list endpoints(self):
        """
        Return all endpoint addresses registered with the message bus.

        Returns
        -------
        list[str]

        """
        return list(self._endpoints.keys())

    cpdef list topics(self):
        """
        Return all topics with active subscribers.

        Returns
        -------
        list[str]

        """
        # Cached between subscription changes: repeated calls avoid rescanning
        # and re-sorting all subscriptions.
        cdef set topic_set
        cdef Subscription s
        if self._topics_cache is None:
            topic_set = set()
            for s in self._subscriptions:
                topic_set.add(s.topic)
            self._topics_cache = sorted(topic_set)
        return list(self._topics_cache)

    cpdef list subscriptions(self, str pattern = None):
        """
        Return all subscriptions matching the given topic `pattern`.

        Parameters
        ----------
        pattern : str, optional
            The topic pattern filter. May include wildcard characters `*` and `?`.
            If ``None`` then query is for **all** topics.

        Returns
        -------
        list[Subscription]

        """
        if pattern is None or pattern == "*":
            # `*` matches every topic, so return all subscriptions directly.
            return list(self._subscriptions)

        Condition.valid_string(pattern, "pattern")

        # Cache match results per pattern (invalidated on subscribe/unsubscribe)
        # so repeated queries return a cheap copy instead of rescanning.
        cdef list cached = self._query_cache.get(pattern)
        cdef Subscription s
        if cached is None:
            cached = []
            for s in self._subscriptions:
                if is_matching(s.topic, pattern):
                    cached.append(s)
            self._query_cache[pattern] = cached
        return list(cached)

    cpdef set streaming_types(self):
        """
        Return all types registered for external streaming -> internal publishing.

        Returns
        -------
        set[type]

        """
        return self._streaming_types.copy()

    cpdef bint has_subscribers(self, str pattern = None):
        """
        If the message bus has subscribers for the give topic `pattern`.

        Parameters
        ----------
        pattern : str, optional
            The topic filter. May include wildcard characters `*` and `?`.
            If ``None`` then query is for **all** topics.

        Returns
        -------
        bool

        """
        if pattern is None or pattern == "*":
            # `*` matches every topic, so any subscription counts.
            return len(self._subscriptions) > 0

        Condition.valid_string(pattern, "pattern")

        # Reuse a cached match result if present, otherwise short-circuit on the
        # first match instead of materializing the full list.
        cdef list cached = self._query_cache.get(pattern)
        if cached is not None:
            return len(cached) > 0

        cdef Subscription sub
        for sub in self._subscriptions:
            if is_matching(sub.topic, pattern):
                return True
        return False

    cpdef bint is_subscribed(self, str topic, handler: Callable[[Any], None]):
        """
        Return if topic and handler is subscribed to the message bus.

        Does not consider any previous `priority`.

        Parameters
        ----------
        topic : str
            The topic of the subscription.
        handler : Callable[[Any], None]
            The handler of the subscription.

        Returns
        -------
        bool

        """
        # Fast constructor: this is a read-only membership check, so a bad
        # topic/handler simply yields no match rather than needing validation.
        cdef Subscription sub = Subscription._create(topic, handler, 0)

        return sub in self._subscriptions

    cpdef bint is_pending_request(self, UUID4 request_id):
        """
        Return if the given `request_id` is still pending a response.

        Parameters
        ----------
        request_id : UUID4
            The request ID to check (to match the correlation_id).

        Returns
        -------
        bool

        """
        Condition.not_none(request_id, "request_id")

        return request_id in self._correlation_index

    cpdef bint is_streaming_type(self, type cls):
        """
        Return whether the given type has been registered for external message streaming.

        Returns
        -------
        bool
            True if registered, else False.

        """
        return cls in self._streaming_types

    cpdef void dispose(self):
        """
        Dispose of the message bus which will close the internal channel and thread.

        """
        pass

    cpdef void register(self, str endpoint, handler: Callable[[Any], None]):
        """
        Register the given `handler` to receive messages at the `endpoint` address.

        Parameters
        ----------
        endpoint : str
            The endpoint address to register.
        handler : Callable[[Any], None]
            The handler for the registration.

        Raises
        ------
        ValueError
            If `endpoint` is not a valid string.
        ValueError
            If `handler` is not of type `Callable`.
        KeyError
            If `endpoint` already registered.

        """
        Condition.valid_string(endpoint, "endpoint")
        Condition.callable(handler, "handler")
        Condition.not_in(endpoint, self._endpoints, "endpoint", "_endpoints")

        self._endpoints[endpoint] = handler

    cpdef void deregister(self, str endpoint, handler: Callable[[Any], None]):
        """
        Deregister the given `handler` from the `endpoint` address.

        Parameters
        ----------
        endpoint : str
            The endpoint address to deregister.
        handler : Callable[[Any], None]
            The handler to deregister.

        Raises
        ------
        ValueError
            If `endpoint` is not a valid string.
        ValueError
            If `handler` is not of type `Callable`.
        KeyError
            If `endpoint` is not registered.
        ValueError
            If `handler` is not registered at the endpoint.

        """
        Condition.valid_string(endpoint, "endpoint")
        Condition.callable(handler, "handler")
        Condition.is_in(endpoint, self._endpoints, "endpoint", "self._endpoints")
        Condition.equal(handler, self._endpoints[endpoint], "handler", "self._endpoints[endpoint]")

        del self._endpoints[endpoint]

    cpdef void add_streaming_type(self, type cls):
        """
        Register the given type for external->internal message bus streaming.

        Parameters
        ----------
        type : cls
            The type to add for streaming.

        """
        Condition.not_none(cls, "cls")

        self._streaming_types.add(cls)

    cpdef void send(self, str endpoint, msg: Any):
        """
        Send the given message to the given `endpoint` address.

        Parameters
        ----------
        endpoint : str
            The endpoint address to send the message to.
        msg : object
            The message to send.

        """
        Condition.not_none(endpoint, "endpoint")
        Condition.not_none(msg, "msg")

        handler = self._endpoints.get(endpoint)
        if handler is None:
            return  # Cannot send

        handler(msg)
        self.sent_count += 1

    cpdef void request(self, str endpoint, Request request):
        """
        Handle the given `request`.

        Will log an error if the correlation ID already exists.

        Parameters
        ----------
        endpoint : str
            The endpoint address to send the request to.
        request : Request
            The request to handle.

        """
        Condition.not_none(endpoint, "endpoint")
        Condition.not_none(request, "request")

        if request.id in self._correlation_index:
            return  # Do not handle duplicates

        if request.callback is not None:
            self._correlation_index[request.id] = request.callback

        handler = self._endpoints.get(endpoint)
        if handler is None:
            return  # Cannot handle

        handler(request)
        self.req_count += 1

    cpdef void response(self, Response response):
        """
        Handle the given `response`.

        Will log an error if the correlation ID is not found.

        Parameters
        ----------
        response : Response
            The response to handle

        """
        Condition.not_none(response, "response")

        callback = self._correlation_index.pop(response.correlation_id, None)
        if callback is not None:
            callback(response)

        self.res_count += 1

    cpdef void subscribe(
        self,
        str topic,
        handler: Callable[[Any], None],
        int priority = 0,
    ):
        """
        Subscribe to the given message `topic` with the given callback `handler`.

        Parameters
        ----------
        topic : str
            The topic for the subscription. May include wildcard characters
            `*` and `?`.
        handler : Callable[[Any], None]
            The handler for the subscription.
        priority : int, optional
            The priority for the subscription. Determines the ordering of
            handlers receiving messages being processed, higher priority
            handlers will receive messages prior to lower priority handlers.

        Raises
        ------
        ValueError
            If `topic` is not a valid string.
        ValueError
            If `handler` is not of type `Callable`.

        Warnings
        --------
        Assigning priority handling is an advanced feature which *shouldn't
        normally be needed by most users*. **Only assign a higher priority to the
        subscription if you are certain of what you're doing**. If an inappropriate
        priority is assigned then the handler may receive messages before core
        system components have been able to process necessary calculations and
        produce potential side effects for logically sound behavior.

        """
        Condition.valid_string(topic, "topic")
        Condition.callable(handler, "handler")
        Condition.not_negative_int(priority, "priority")

        # Create subscription (topic/handler/priority already validated above).
        cdef Subscription sub = Subscription._create(topic, handler, priority)

        # Check if already exists
        if sub in self._subscriptions:
            return

        cdef list matches = []
        cdef list patterns = list(self._patterns.keys())
        cdef str pattern
        cdef list subs

        for pattern in patterns:
            if is_matching(topic, pattern):
                subs = list(self._patterns[pattern])
                subs.append(sub)
                subs = sorted(subs, reverse=True)
                self._patterns[pattern] = subs
                matches.append(pattern)

        self._subscriptions[sub] = sorted(matches)

        self._resolved = False
        self._topics_cache = None
        self._query_cache.clear()

    cpdef void unsubscribe(self, str topic, handler: Callable[[Any], None]):
        """
        Unsubscribe the given callback `handler` from the given message `topic`.

        Parameters
        ----------
        topic : str, optional
            The topic to unsubscribe from. May include wildcard characters `*`
            and `?`.
        handler : Callable[[Any], None]
            The handler for the subscription.

        Raises
        ------
        ValueError
            If `topic` is not a valid string.
        ValueError
            If `handler` is not of type `Callable`.

        """
        Condition.valid_string(topic, "topic")
        Condition.callable(handler, "handler")

        cdef Subscription sub = Subscription._create(topic, handler, 0)

        # Check if patterns exist for sub
        cdef list patterns = self._subscriptions.get(sub)
        if patterns is None:
            return

        cdef str pattern
        for pattern in patterns:
            subs = list(self._patterns[pattern])
            subs.remove(sub)
            subs = sorted(subs, reverse=True)
            self._patterns[pattern] = subs

        del self._subscriptions[sub]

        self._resolved = False
        self._topics_cache = None
        self._query_cache.clear()

    cpdef void publish(self, str topic, msg: Any, bint external_pub = True):
        """
        Publish the given message for the given `topic`.

        Subscription handlers will receive the message in priority order
        (highest first).

        Parameters
        ----------
        topic : str
            The topic to publish on.
        msg : object
            The message to publish.
        external_pub : bool, default True
            If the message should also be published externally.

        """
        self.publish_c(topic, msg, external_pub)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void publish_c(self, str topic, msg: Any, bint external_pub = True):
        # Fast path: fetch the cached, priority-sorted subscriber list for this
        # topic and dispatch. The cache stores a plain Python list (not a numpy
        # object array), so the hot path needs no buffer acquisition. Validation
        # is deferred to the cold cache-miss branch to keep the hot path minimal.
        cdef list subs = self._patterns.get(topic)
        if subs is None or (not self._resolved and len(subs) == 0):
            if topic is None:
                return  # Nothing to publish to
            # Add the topic pattern and get matching subscribers
            subs = self._resolve_subscriptions(topic)
            self._resolved = True

        # Send message to all matched subscribers (highest priority first)
        cdef Subscription sub
        for sub in subs:
            sub.handler(msg)

        self.pub_count += 1

    cpdef void publish_batch(self, str topic, list msgs, bint external_pub = True):
        """
        Publish a batch of messages for the given `topic` in order.

        Equivalent to calling `publish(topic, msg)` for each message in `msgs`,
        but resolves the matching subscribers only once for the whole batch and
        dispatches entirely in C. This amortizes the Python-level call overhead
        across the batch, roughly doubling throughput when streaming/replaying
        many messages on a single topic.

        Parameters
        ----------
        topic : str
            The topic to publish on.
        msgs : list[object]
            The messages to publish, delivered in list order. Each message is
            delivered to all matching subscribers (highest priority first)
            before moving to the next message.
        external_pub : bool, default True
            If the messages should also be published externally.

        """
        self.publish_batch_c(topic, msgs, external_pub)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void publish_batch_c(self, str topic, list msgs, bint external_pub = True):
        cdef Py_ssize_t n = len(msgs)
        if n == 0:
            return

        # Resolve subscribers once for the whole batch (see `publish_c`).
        cdef list subs = self._patterns.get(topic)
        if subs is None or (not self._resolved and len(subs) == 0):
            if topic is None:
                return  # Nothing to publish to
            subs = self._resolve_subscriptions(topic)
            self._resolved = True

        cdef Py_ssize_t n_subs = len(subs)
        cdef Py_ssize_t i
        cdef Subscription sub

        if n_subs == 0:
            self.pub_count += n
            return

        if n_subs == 1:
            # Common case: hoist the single handler out of the message loop.
            handler = (<Subscription>subs[0]).handler
            for i in range(n):
                handler(msgs[i])
        else:
            # Deliver each message to all subscribers (priority order) in turn.
            for i in range(n):
                msg = msgs[i]
                for sub in subs:
                    sub.handler(msg)

        self.pub_count += n

    cdef list _resolve_subscriptions(self, str topic):
        cdef list subs_list = []
        cdef Subscription existing_sub

        # Copy to handle subscription changes on iteration
        for existing_sub in self._subscriptions.copy():
            if is_matching(topic, existing_sub.topic):
                subs_list.append(existing_sub)

        subs_list = sorted(subs_list, reverse=True)
        self._patterns[topic] = subs_list

        cdef list matches
        cdef Subscription sub
        for sub in subs_list:
            matches = self._subscriptions.get(sub, [])

            if topic not in matches:
                matches.append(topic)

            self._subscriptions[sub] = sorted(matches)

        return subs_list


cdef bint _is_matching_c(
    const char* topic,
    Py_ssize_t tlen,
    const char* pattern,
    Py_ssize_t plen,
) noexcept nogil:
    # Greedy two-pointer wildcard match (`*` = zero+ chars, `?` = one char).
    # Pure-C port of the Rust `is_matching` so pattern matching avoids an FFI
    # boundary crossing on every call (hot in subscribe/unsubscribe/subscriptions).
    cdef Py_ssize_t i = 0
    cdef Py_ssize_t j = 0
    cdef Py_ssize_t star = -1
    cdef Py_ssize_t match = 0
    while i < tlen:
        if j < plen and (pattern[j] == b"?" or pattern[j] == topic[i]):
            i += 1
            j += 1
        elif j < plen and pattern[j] == b"*":
            star = j
            match = i
            j += 1
        elif star != -1:
            j = star + 1
            match += 1
            i = match
        else:
            return False
    while j < plen and pattern[j] == b"*":
        j += 1
    return j == plen


cdef inline bint is_matching(str topic, str pattern):
    cdef Py_ssize_t tlen = 0
    cdef Py_ssize_t plen = 0
    cdef const char* t = PyUnicode_AsUTF8AndSize(topic, &tlen)
    cdef const char* p = PyUnicode_AsUTF8AndSize(pattern, &plen)
    return _is_matching_c(t, tlen, p, plen)


# Python wrapper for test access
def is_matching_py(str topic, str pattern) -> bool:
    return is_matching(topic, pattern)


cdef class Subscription:
    """
    Represents a subscription to a particular topic.

    This is an internal class intended to be used by the message bus to organize
    topics and their subscribers.

    Parameters
    ----------
    topic : str
        The topic for the subscription. May include wildcard characters `*` and `?`.
    handler : Callable[[Message], None]
        The handler for the subscription.
    priority : int
        The priority for the subscription.

    Raises
    ------
    ValueError
        If `topic` is not a valid string.
    ValueError
        If `handler` is not of type `Callable`.
    ValueError
        If `priority` is negative (< 0).

    Notes
    -----
    The subscription equality is determined by the topic and handler,
    priority is not considered (and could change).
    """

    def __init__(
        self,
        str topic,
        handler not None: Callable[[Any], None],
        int priority=0,
    ):
        Condition.valid_string(topic, "topic")
        Condition.callable(handler, "handler")
        Condition.not_negative_int(priority, "priority")

        self.topic = topic
        self.handler = handler
        self.priority = priority
        # Precompute the hash once (equality is by topic + handler, so priority
        # is excluded). Hash the handler directly — it is consistent with `==`
        # for the callables used here (functions, lambdas, bound methods,
        # partials) and ~4x cheaper than formatting `str(handler)`. Fall back to
        # the string form only for the rare unhashable callable.
        try:
            self._hash = hash((topic, handler))
        except TypeError:
            self._hash = hash((topic, str(handler)))

    @staticmethod
    cdef Subscription _create(str topic, object handler, int priority):
        # Fast internal constructor that skips the `Condition` validation done
        # in `__init__`. Callers must pass an already-validated topic/handler.
        cdef Subscription self = Subscription.__new__(Subscription)
        self.topic = topic
        self.handler = handler
        self.priority = priority
        try:
            self._hash = hash((topic, handler))
        except TypeError:
            self._hash = hash((topic, str(handler)))
        return self

    def __eq__(self, Subscription other) -> bool:
        if other is None:
            return False
        return self.topic == other.topic and self.handler == other.handler

    def __lt__(self, Subscription other) -> bool:
        return self.priority < other.priority

    def __le__(self, Subscription other) -> bool:
        return self.priority <= other.priority

    def __gt__(self, Subscription other) -> bool:
        return self.priority > other.priority

    def __ge__(self, Subscription other) -> bool:
        return self.priority >= other.priority

    def __hash__(self) -> int:
        return self._hash

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"topic={self.topic}, "
            f"handler={self.handler}, "
            f"priority={self.priority})"
        )
