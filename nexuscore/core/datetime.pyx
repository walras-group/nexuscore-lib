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
This module provides efficient functions for performing standard datetime related operations.

Functions include awareness/tz checks and conversions, as well as ISO 8601 (RFC 3339) conversion.
"""

import datetime as dt

try:
    import pandas as pd
    from pandas.api.types import is_datetime64_ns_dtype
except Exception:  # pragma: no cover
    pd = None
    is_datetime64_ns_dtype = None

cimport cpython.datetime
from cpython.datetime cimport datetime
from cpython.datetime cimport datetime_tzinfo
from libc.stdint cimport uint64_t

from nexuscore.core.correctness cimport Condition


# UNIX epoch is the UTC time at 00:00:00 on 1/1/1970
# https://en.wikipedia.org/wiki/Unix_time
cdef datetime UNIX_EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)


cpdef uint64_t secs_to_nanos(double secs):
    if secs < 0:
        return 0
    return <uint64_t>(secs * 1_000_000_000.0)


cpdef uint64_t secs_to_millis(double secs):
    if secs < 0:
        return 0
    return <uint64_t>(secs * 1_000.0)


cpdef uint64_t millis_to_nanos(double millis):
    if millis < 0:
        return 0
    return <uint64_t>(millis * 1_000_000.0)


cpdef uint64_t micros_to_nanos(double micros):
    if micros < 0:
        return 0
    return <uint64_t>(micros * 1_000.0)


cpdef double nanos_to_secs(uint64_t nanos):
    return nanos / 1_000_000_000.0


cpdef uint64_t nanos_to_millis(uint64_t nanos):
    return nanos // 1_000_000


cpdef uint64_t nanos_to_micros(uint64_t nanos):
    return nanos // 1_000


cdef inline datetime _as_utc_datetime(datetime dt_obj):
    if datetime_tzinfo(dt_obj) is None:
        return dt_obj.replace(tzinfo=dt.timezone.utc)
    if datetime_tzinfo(dt_obj) is not dt.timezone.utc:
        return dt_obj.astimezone(dt.timezone.utc)
    return dt_obj


cdef inline uint64_t _py_dt_to_unix_nanos(datetime dt_obj):
    cdef datetime utc_dt = _as_utc_datetime(dt_obj)
    return <uint64_t>int(utc_dt.timestamp() * 1_000_000_000)


cpdef unix_nanos_to_dt(uint64_t nanos):
    """
    Return the datetime (UTC) from the given UNIX timestamp (nanoseconds).

    Parameters
    ----------
    nanos : uint64_t
        The UNIX timestamp (nanoseconds) to convert.

    Returns
    -------
    datetime

    """
    return dt.datetime.fromtimestamp(nanos / 1e9, tz=dt.timezone.utc)


cpdef dt_to_unix_nanos(dt_value):
    """
    Return the UNIX timestamp (nanoseconds) from the given datetime (UTC).

    Parameters
    ----------
    dt_value : datetime | str | int
        The datetime to convert.

    Returns
    -------
    uint64_t

    Warnings
    --------
    This function supports Python ``datetime`` objects; nanosecond precision
    is preserved when a ``pandas.Timestamp`` is provided and pandas is available.

    """
    Condition.not_none(dt_value, "dt")

    if pd is not None:
        if isinstance(dt_value, pd.Timestamp):
            return <uint64_t>dt_value.value
        try:
            ts = pd.Timestamp(dt_value)
        except Exception:
            ts = None
        if ts is not None:
            return <uint64_t>ts.value

    if isinstance(dt_value, datetime):
        return _py_dt_to_unix_nanos(dt_value)

    if isinstance(dt_value, (int, float)):
        if abs(dt_value) > 1_000_000_000_000:
            return <uint64_t>int(dt_value)
        return <uint64_t>int(dt_value * 1_000_000_000)

    if isinstance(dt_value, str):
        try:
            parsed = dt.datetime.fromisoformat(dt_value)
        except ValueError as exc:
            raise ValueError(f"Invalid datetime string: {dt_value!r}") from exc
        return _py_dt_to_unix_nanos(parsed)

    raise TypeError(f"Unsupported datetime type: {type(dt_value)}")


cpdef str unix_nanos_to_iso8601(uint64_t unix_nanos, bint nanos_precision = True):
    """
    Convert the given `unix_nanos` to an ISO 8601 (RFC 3339) format string.

    Parameters
    ----------
    unix_nanos : int
        The UNIX timestamp (nanoseconds) to be converted.
    nanos_precision : bool, default True
        If True, use nanosecond precision. If False, use millisecond precision.

    Returns
    -------
    str

    """
    cdef uint64_t secs = unix_nanos // 1_000_000_000
    cdef uint64_t frac = unix_nanos % 1_000_000_000
    cdef str base = dt.datetime.fromtimestamp(secs, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    if nanos_precision:
        return f"{base}.{frac:09d}Z"
    return f"{base}.{frac // 1_000_000:03d}Z"


cpdef str format_iso8601(datetime dt_value, bint nanos_precision = True):
    """
    Format the given datetime as an ISO 8601 (RFC 3339) specification string.

    Parameters
    ----------
    dt_value : datetime
        The datetime to format.
    nanos_precision : bool, default True
        If True, use nanosecond precision. If False, use millisecond precision.

    Returns
    -------
    str

    """
    Condition.not_none(dt_value, "dt")

    cdef uint64_t nanos = dt_to_unix_nanos(dt_value)
    return unix_nanos_to_iso8601(nanos, nanos_precision)


cpdef str format_optional_iso8601(datetime dt_value, bint nanos_precision = True):
    """
    Format the given optional datetime as an ISO 8601 (RFC 3339) specification string.

    If value is `None` then will return the string "None".

    Parameters
    ----------
    dt_value : datetime, optional
        The datetime to format.
    nanos_precision : bool, default True
        If True, use nanosecond precision. If False, use millisecond precision.

    Returns
    -------
    str

    """
    if dt_value is None:
        return str(None)

    return format_iso8601(dt_value, nanos_precision)


cpdef maybe_unix_nanos_to_dt(nanos):
    """
    Return the datetime (UTC) from the given UNIX timestamp (nanoseconds), or ``None``.

    If nanos is ``None``, then will return ``None``.

    Parameters
    ----------
    nanos : int, optional
        The UNIX timestamp (nanoseconds) to convert.

    Returns
    -------
    datetime or ``None``

    """
    if nanos is None:
        return None
    else:
        return dt.datetime.fromtimestamp(nanos / 1e9, tz=dt.timezone.utc)


cpdef maybe_dt_to_unix_nanos(dt_value):
    """
    Return the UNIX timestamp (nanoseconds) from the given datetime, or ``None``.

    If dt is ``None``, then will return ``None``.

    Parameters
    ----------
    dt_value : datetime, optional
        The datetime to convert.

    Returns
    -------
    int64 or ``None``

    Warnings
    --------
    If the input is not ``None`` then this function supports ``datetime`` inputs.

    """
    if dt_value is None:
        return None

    return <uint64_t>dt_to_unix_nanos(dt_value)


cpdef bint is_datetime_utc(datetime dt_value):
    """
    Return a value indicating whether the given timestamp is timezone aware UTC.

    Parameters
    ----------
    dt_value : datetime
        The datetime to check.

    Returns
    -------
    bool
        True if timezone aware UTC, else False.

    """
    Condition.not_none(dt_value, "dt")

    return datetime_tzinfo(dt_value) == dt.timezone.utc


cpdef bint is_tz_aware(time_object):
    """
    Return a value indicating whether the given object is timezone aware.

    Parameters
    ----------
    time_object : datetime, pd.Timestamp, pd.Series, pd.DataFrame
        The time object to check.

    Returns
    -------
    bool
        True if timezone aware, else False.

    """
    Condition.not_none(time_object, "time_object")

    if isinstance(time_object, datetime):
        return datetime_tzinfo(time_object) is not None
    if pd is not None:
        if isinstance(time_object, pd.Timestamp):
            return time_object.tzinfo is not None
        if isinstance(time_object, pd.DataFrame):
            return hasattr(time_object.index, "tz") or time_object.index.tz is not None
    raise ValueError(f"Cannot check timezone awareness of a {type(time_object)} object")


cpdef bint is_tz_naive(time_object):
    """
    Return a value indicating whether the given object is timezone naive.

    Parameters
    ----------
    time_object : datetime, pd.Timestamp, pd.DataFrame
        The time object to check.

    Returns
    -------
    bool
        True if object timezone naive, else False.

    """
    return not is_tz_aware(time_object)


cpdef datetime as_utc_timestamp(datetime dt_value):
    """
    Ensure the given timestamp is tz-aware UTC.

    Parameters
    ----------
    dt_value : datetime
        The timestamp to check.

    Returns
    -------
    datetime

    """
    Condition.not_none(dt_value, "dt")

    if dt_value.tzinfo is None:  # tz-naive
        return dt_value.replace(tzinfo=dt.timezone.utc)
    if dt_value.tzinfo != dt.timezone.utc:
        return dt_value.astimezone(dt.timezone.utc)
    return dt_value  # Already UTC


cpdef object as_utc_index(data):
    """
    Ensure the given data has a DateTimeIndex which is tz-aware UTC.

    Parameters
    ----------
    data : pandas.Series or pandas.DataFrame.
        The object to ensure is UTC.

    Returns
    -------
    pd.Series, pd.DataFrame or ``None``

    """
    Condition.not_none(data, "data")

    if pd is None:
        raise ImportError("pandas is required for as_utc_index")

    if data.empty:
        return data

    # Ensure the index is localized to UTC
    if data.index.tzinfo is None:  # tz-naive
        data = data.tz_localize(dt.timezone.utc)
    elif data.index.tzinfo != dt.timezone.utc:
        data = data.tz_convert(None).tz_localize(dt.timezone.utc)

    # Check if the index is in nanosecond resolution, convert if not
    if not is_datetime64_ns_dtype(data.index.dtype):
        data.index = data.index.astype("datetime64[ns, UTC]")

    return data


cpdef datetime time_object_to_dt(time_object):
    """
    Return the datetime (UTC) from the given UNIX timestamp as integer (nanoseconds), string or pd.Timestamp.

    Parameters
    ----------
    time_object : datetime | str | int | None
        The time object to convert.

    Returns
    -------
    datetime or ``None``
        Returns None if the input is None.

    """
    if time_object is None:
        return None

    if pd is not None and isinstance(time_object, pd.Timestamp):
        return as_utc_timestamp(time_object)

    if isinstance(time_object, datetime):
        return as_utc_timestamp(time_object)

    if isinstance(time_object, (int, float)):
        return dt.datetime.fromtimestamp(time_object, tz=dt.timezone.utc)

    if isinstance(time_object, str):
        return as_utc_timestamp(dt.datetime.fromisoformat(time_object))

    if pd is not None:
        return as_utc_timestamp(pd.Timestamp(time_object))

    raise TypeError(f"Unsupported time object type: {type(time_object)}")



def max_date(date1: dt.datetime | str | int | None = None, date2: str | int | None = None) -> dt.datetime | None:
    """
    Return the maximum date as a datetime (UTC).

    Parameters
    ----------
    date1 : datetime | str | int | None, optional
        The first date to compare. Can be a string, integer (timestamp), or None. Default is None.
    date2 : datetime | str | int | None, optional
        The second date to compare. Can be a string, integer (timestamp), or None. Default is None.

    Returns
    -------
    datetime | None
        The maximum date, or None if both input dates are None.

    """
    if date1 is None and date2 is None:
        return None

    if date1 is None:
        return time_object_to_dt(date2)

    if date2 is None:
        return time_object_to_dt(date1)

    return max(time_object_to_dt(date1), time_object_to_dt(date2))


def min_date(date1: dt.datetime | str | int | None = None, date2: str | int | None = None) -> dt.datetime | None:
    """
    Return the minimum date as a datetime (UTC).

    Parameters
    ----------
    date1 : datetime | str | int | None, optional
        The first date to compare. Can be a string, integer (timestamp), or None. Default is None.
    date2 : datetime | str | int | None, optional
        The second date to compare. Can be a string, integer (timestamp), or None. Default is None.

    Returns
    -------
    datetime | None
        The minimum date, or None if both input dates are None.

    """
    if date1 is None and date2 is None:
        return None

    if date1 is None:
        return time_object_to_dt(date2)

    if date2 is None:
        return time_object_to_dt(date1)

    return min(time_object_to_dt(date1), time_object_to_dt(date2))


def ensure_pydatetime_utc(timestamp) -> dt.datetime | None:
    """
    Convert an optional ``pandas.Timestamp`` to a timezone-aware ``datetime`` in UTC.

    The underlying Python ``datetime`` type only supports microsecond precision. When
    the provided ``timestamp`` contains non-zero nanoseconds these **cannot** be
    represented and are therefore truncated to microseconds before the conversion
    takes place.  This avoids the "Discarding nonzero nanoseconds in conversion"
    ``UserWarning`` raised by pandas when calling :py:meth:`Timestamp.to_pydatetime`.

    Parameters
    ----------
    timestamp : pandas.Timestamp or datetime, optional
        The timestamp to convert. If ``None`` the function immediately returns
        ``None``.

    Returns
    -------
    datetime.datetime | None
        The converted timestamp with tz-info set to ``UTC`` or ``None`` if the
        input was ``None``.

    """
    if timestamp is None:
        return None

    if pd is not None and isinstance(timestamp, pd.Timestamp):
        # ``to_pydatetime`` emits a warning when nanoseconds are present because the
        # Python ``datetime`` type cannot store them.  We truncate to the closest
        # microsecond to silence the warning while keeping deterministic behaviour.
        if timestamp.nanosecond:
            timestamp = timestamp.floor("us")
        return timestamp.tz_convert("UTC").to_pydatetime()

    if isinstance(timestamp, datetime):
        return as_utc_timestamp(timestamp)

    raise TypeError(f"Unsupported timestamp type: {type(timestamp)}")
