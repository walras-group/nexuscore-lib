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

import datetime as dt
import time
from typing import Callable

from cpython.datetime cimport datetime
from cpython.datetime cimport timedelta
from cpython.datetime cimport tzinfo
from libc.stdint cimport uint64_t

from nexuscore.common._clock_scheduler import TimerScheduler

from nexuscore.core.correctness cimport Condition
from nexuscore.core.datetime cimport dt_to_unix_nanos
from nexuscore.core.datetime cimport maybe_dt_to_unix_nanos
from nexuscore.core.message cimport Event
from nexuscore.core.uuid cimport UUID4


cdef extern from "time.h" nogil:
    ctypedef long time_t
    cdef struct timespec:
        time_t tv_sec
        long tv_nsec
    int clock_gettime(int clk_id, timespec *tp)
    int CLOCK_REALTIME


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
        Condition.valid_string(name, "name")
        self._name = name
        self._id = event_id
        self._ts_event = ts_event
        self._ts_init = ts_init

    def __getstate__(self):
        return (
            self._name,
            self._id.value,
            self._ts_event,
            self._ts_init,
        )

    def __setstate__(self, state):
        self._name = state[0]
        self._id = UUID4.from_str_c(state[1])
        self._ts_event = state[2]
        self._ts_init = state[3]

    cdef str to_str(self):
        return self._name

    def __eq__(self, TimeEvent other) -> bool:
        if other is None:
            return False
        return self._id == other._id

    def __hash__(self) -> int:
        return hash(self._id)

    def __str__(self) -> str:
        return self._name

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}("
            f"name={self._name}, "
            f"event_id={self._id}, "
            f"ts_event={self._ts_event}, "
            f"ts_init={self._ts_init})"
        )

    @property
    def name(self) -> str:
        """
        Return the name of the time event.

        Returns
        -------
        str

        """
        return self._name

    @property
    def id(self) -> UUID4:
        """
        The event message identifier.

        Returns
        -------
        UUID4

        """
        return self._id

    @property
    def ts_event(self) -> int:
        """
        UNIX timestamp (nanoseconds) when the event occurred.

        Returns
        -------
        int

        """
        return self._ts_event

    @property
    def ts_init(self) -> int:
        """
        UNIX timestamp (nanoseconds) when the object was initialized.

        Returns
        -------
        int

        """
        return self._ts_init


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
        return dt.datetime.fromtimestamp(self.timestamp_ns() / 1e9, tz=dt.timezone.utc)

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
            for immediate firing. If False, raises an error when the `alert_time_ns` is in the
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


cdef list[Clock] get_component_clocks(UUID4 instance_id):
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
FORCE_STOP = False


cpdef void set_backtest_force_stop(bint value):
    global FORCE_STOP
    FORCE_STOP = value


cpdef bint is_backtest_force_stop():
    return FORCE_STOP


def _fire_time_event(callback, name, ts_event, ts_init):
    # Module-level (not a bound method) so the timer scheduler never holds a
    # reference to the owning `LiveClock` — avoids a reference cycle that would
    # keep the clock (and its daemon thread) alive after it is dropped.
    callback(TimeEvent(name, UUID4(), ts_event, ts_init))


cdef class LiveClock(Clock):
    """
    Provides a real-time clock for live trading.

    All times are tz-aware UTC. Timer callbacks fire on a background scheduler
    thread (the GIL is held for each callback).
    """

    def __init__(self):
        self._sched = TimerScheduler(_fire_time_event)
        self._default_handler = None

    def __del__(self) -> None:
        if self._sched is not None:
            self._sched.stop()

    @property
    def timer_names(self) -> list[str]:
        return self._sched.names()

    @property
    def timer_count(self) -> int:
        return self._sched.count()

    cpdef double timestamp(self):
        cdef timespec ts
        clock_gettime(CLOCK_REALTIME, &ts)
        return <double>ts.tv_sec + <double>ts.tv_nsec / 1e9

    cpdef uint64_t timestamp_ms(self):
        cdef timespec ts
        clock_gettime(CLOCK_REALTIME, &ts)
        return <uint64_t>ts.tv_sec * 1_000 + <uint64_t>ts.tv_nsec // 1_000_000

    cpdef uint64_t timestamp_us(self):
        cdef timespec ts
        clock_gettime(CLOCK_REALTIME, &ts)
        return <uint64_t>ts.tv_sec * 1_000_000 + <uint64_t>ts.tv_nsec // 1_000

    cpdef uint64_t timestamp_ns(self):
        cdef timespec ts
        clock_gettime(CLOCK_REALTIME, &ts)
        return <uint64_t>ts.tv_sec * 1_000_000_000 + <uint64_t>ts.tv_nsec

    cpdef void register_default_handler(self, callback: Callable[[TimeEvent], None]):
        Condition.callable(callback, "callback")
        self._default_handler = callback

    cpdef void set_time_alert_ns(
        self,
        str name,
        uint64_t alert_time_ns,
        callback: Callable[[TimeEvent], None] | None = None,
        bint allow_past = True,
    ):
        Condition.valid_string(name, "name")
        Condition.not_in(name, self._sched.names(), "name", "self.timer_names")

        if callback is None:
            callback = self._default_handler
        if callback is None:
            raise ValueError(f"No callback provided for alert '{name}' and no default handler registered")
        Condition.callable(callback, "callback")

        cdef uint64_t ts_now = self.timestamp_ns()
        if alert_time_ns < ts_now:
            if not allow_past:
                alert_dt = dt.datetime.fromtimestamp(alert_time_ns / 1e9).isoformat()
                current_dt = dt.datetime.fromtimestamp(ts_now / 1e9).isoformat()
                raise ValueError(
                    f"Timer '{name}' alert time {alert_dt} was in the past "
                    f"(current time is {current_dt})"
                )
            alert_time_ns = ts_now

        self._sched.add(name, alert_time_ns, 0, 0, True, callback)

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
        Condition.not_in(name, self._sched.names(), "name", "self.timer_names")
        Condition.positive_int(interval_ns, "interval_ns")

        if callback is None:
            callback = self._default_handler
        if callback is None:
            raise ValueError(f"No callback provided for timer '{name}' and no default handler registered")
        Condition.callable(callback, "callback")

        cdef uint64_t ts_now = self.timestamp_ns()
        cdef uint64_t start = start_time_ns if start_time_ns != 0 else ts_now
        cdef uint64_t first
        if fire_immediately:
            first = start
        else:
            first = start + interval_ns

        if not allow_past and start_time_ns != 0 and first < ts_now:
            next_dt = dt.datetime.fromtimestamp(first / 1e9).isoformat()
            current_dt = dt.datetime.fromtimestamp(ts_now / 1e9).isoformat()
            raise ValueError(
                f"Timer '{name}' next event time {next_dt} would be in the past "
                f"(current time is {current_dt})"
            )

        if stop_time_ns != 0 and stop_time_ns < ts_now:
            stop_dt = dt.datetime.fromtimestamp(stop_time_ns / 1e9).isoformat()
            current_dt = dt.datetime.fromtimestamp(ts_now / 1e9).isoformat()
            raise ValueError(
                f"Timer '{name}' stop time {stop_dt} was in the past "
                f"(current time is {current_dt})"
            )

        # A `stop_time` earlier than the first event time is enforced by the
        # scheduler (the timer expires without firing past its stop time).
        self._sched.add(name, first, interval_ns, stop_time_ns, False, callback)

    cpdef uint64_t next_time_ns(self, str name):
        Condition.valid_string(name, "name")
        return <uint64_t>self._sched.next_time(name)

    cpdef void cancel_timer(self, str name):
        Condition.valid_string(name, "name")
        Condition.is_in(name, self._sched.names(), "name", "self.timer_names")
        self._sched.cancel(name)

    cpdef void cancel_timers(self):
        cdef str name
        for name in self._sched.names():
            self._sched.cancel(name)
