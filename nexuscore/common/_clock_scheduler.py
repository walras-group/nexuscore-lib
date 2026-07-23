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
"""
Background wall-clock timer scheduler for `LiveClock`.

A single daemon thread fires due timers via the `fire` callback, which receives
``(callback, name, ts_event_ns, ts_init_ns)``. Recurring timers reschedule by
their interval; one-shot alerts fire once. This preserves the previous Rust
`LiveClock` semantics — timer callbacks run on this background thread (GIL-held),
independent of any asyncio event loop.

Lifecycle notes:

* `fire` is a module-level function (not a bound method of `LiveClock`), so the
  scheduler and its thread never reference the owning clock — no cycle keeps the
  clock (or its daemon thread) alive after it is dropped.
* The worker thread exits whenever there are no active timers (and is restarted
  on the next :meth:`add`), so idle clocks never leak a running daemon thread.
* A raising timer callback is logged and swallowed — it never terminates the
  worker thread or wedges the other timers.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Callable


logger = logging.getLogger(__name__)

# Tolerance (ns) absorbing the sub-microsecond float error of datetime->ns
# conversions when comparing an event time against a timer's stop time. Small
# enough to reject a genuine overshoot (which is at least one interval), large
# enough to accept the `stop == start + interval` boundary.
_STOP_TOL_NS = 1_000


class TimerScheduler:
    def __init__(self, fire: Callable[[Callable, str, int, int], None]) -> None:
        self._fire = fire
        self._timers: dict[str, dict] = {}
        self._cond = threading.Condition()
        self._thread: threading.Thread | None = None
        self._active = False

    def add(
        self,
        name: str,
        first_ns: int,
        interval_ns: int,
        stop_ns: int,
        one_shot: bool,
        callback: Callable,
    ) -> None:
        with self._cond:
            self._timers[name] = {
                "interval_ns": interval_ns,
                "next_ns": first_ns,
                "stop_ns": stop_ns,
                "one_shot": one_shot,
                "callback": callback,
            }
            if self._thread is None or not self._thread.is_alive():
                self._active = True
                self._thread = threading.Thread(
                    target=self._run,
                    name="LiveClock-timer",
                    daemon=True,
                )
                self._thread.start()
            else:
                self._cond.notify()

    def cancel(self, name: str) -> None:
        with self._cond:
            self._timers.pop(name, None)
            self._cond.notify()

    def cancel_all(self) -> None:
        with self._cond:
            self._timers.clear()
            self._cond.notify()

    def names(self) -> list[str]:
        with self._cond:
            return sorted(self._timers.keys())

    def count(self) -> int:
        with self._cond:
            return len(self._timers)

    def has(self, name: str) -> bool:
        with self._cond:
            return name in self._timers

    def next_time(self, name: str) -> int:
        with self._cond:
            t = self._timers.get(name)
            return t["next_ns"] if t is not None else 0

    def stop(self) -> None:
        with self._cond:
            self._active = False
            self._cond.notify()

    def _run(self) -> None:
        while True:
            fires = []
            with self._cond:
                if not self._active or not self._timers:
                    # Stopped, or no work left: exit and let `add` restart us.
                    self._thread = None
                    return
                now = time.time_ns()
                earliest = min(t["next_ns"] for t in self._timers.values())
                if earliest > now:
                    self._cond.wait(timeout=(earliest - now) / 1e9)
                    continue
                now = time.time_ns()
                for name in list(self._timers.keys()):
                    t = self._timers.get(name)
                    if t is None or t["next_ns"] > now:
                        continue
                    ts_event = t["next_ns"]
                    stop_ns = t["stop_ns"]
                    callback = t["callback"]
                    if stop_ns > 0 and ts_event > stop_ns + _STOP_TOL_NS:
                        # Scheduled time is past the stop time: expire, don't fire.
                        del self._timers[name]
                        continue
                    if t["one_shot"]:
                        del self._timers[name]
                    else:
                        t["next_ns"] += t["interval_ns"]
                        if stop_ns > 0 and t["next_ns"] > stop_ns + _STOP_TOL_NS:
                            del self._timers[name]
                    fires.append((callback, name, ts_event))

            # Fire outside the lock so callbacks may safely add/cancel timers.
            # A failing callback must not kill the worker thread or wedge the
            # remaining timers, so each dispatch is isolated.
            ts_init = time.time_ns()
            for callback, name, ts_event in fires:
                try:
                    self._fire(callback, name, ts_event, ts_init)
                except Exception:
                    logger.exception("Timer callback for %r raised; event dropped", name)
