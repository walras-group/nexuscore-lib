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

import sys

from nexuscore.core.correctness cimport Condition


cdef class Identifier:
    """
    The abstract base class for all identifiers.
    """

    def __getstate__(self):
        raise NotImplementedError("method `__getstate__` must be implemented in the subclass")  # pragma: no cover

    def __setstate__(self, state):
        raise NotImplementedError("method `__setstate__` must be implemented in the subclass")  # pragma: no cover

    def __lt__(self, Identifier other) -> bool:
        if other is None:
            return NotImplemented
        return self.to_str() < other.to_str()

    def __le__(self, Identifier other) -> bool:
        if other is None:
            return NotImplemented
        return self.to_str() <= other.to_str()

    def __gt__(self, Identifier other) -> bool:
        if other is None:
            return NotImplemented
        return self.to_str() > other.to_str()

    def __ge__(self, Identifier other) -> bool:
        if other is None:
            return NotImplemented
        return self.to_str() >= other.to_str()

    def __str__(self) -> str:
        return self.to_str()

    def __repr__(self) -> str:
        return f"{type(self).__name__}('{self.to_str()}')"

    cdef str to_str(self):
        raise NotImplementedError("method `to_str` must be implemented in the subclass")  # pragma: no cover

    @property
    def value(self) -> str:
        """
        Return the identifier (ID) value.

        Returns
        -------
        str

        """
        return self.to_str()


cdef class TraderId(Identifier):
    """
    Represents a valid trader ID.

    Must be correctly formatted with two valid strings either side of a hyphen.
    It is expected a trader ID is the abbreviated name of the trader
    with an order ID tag number separated by a hyphen.

    Example: "TESTER-001".

    The reason for the numerical component of the ID is so that order and position IDs
    do not collide with those from another node instance.

    Parameters
    ----------
    value : str
        The trader ID value.

    Raises
    ------
    ValueError
        If `value` is not a valid string containing a hyphen.

    Warnings
    --------
    The name and tag combination ID value must be unique at the firm level.
    """

    def __init__(self, str value not None) -> None:
        Condition.valid_string(value, "value")
        Condition.is_true("-" in value, f"invalid string for 'value' did not contain '-', was '{value}'")
        self._value = sys.intern(value)

    def __getstate__(self):
        return self._value

    def __setstate__(self, state):
        self._value = sys.intern(state)

    def __eq__(self, TraderId other) -> bool:
        if other is None:
            return False
        return self._value == other._value

    def __hash__(self) -> int:
        # A rare zero hash will cause frequent recomputations
        if self._hash == 0:
            self._hash = hash(self._value)
        return self._hash

    cdef str to_str(self):
        return self._value

    cpdef str get_tag(self):
        """
        Return the order ID tag value for this ID.

        Returns
        -------
        str

        """
        return self._value.split("-")[-1]


cdef class ComponentId(Identifier):
    """
    Represents a valid component ID.

    Parameters
    ----------
    value : str
        The component ID value.

    Raises
    ------
    ValueError
        If `value` is not a valid string.

    Warnings
    --------
    The ID value must be unique at the trader level.
    """

    def __init__(self, str value not None) -> None:
        Condition.valid_string(value, "value")
        self._value = sys.intern(value)

    def __getstate__(self):
        return self._value

    def __setstate__(self, state):
        self._value = sys.intern(state)

    def __eq__(self, ComponentId other) -> bool:
        if other is None:
            return False
        return self._value == other._value

    def __hash__(self) -> int:
        # A rare zero hash will cause frequent recomputations
        if self._hash == 0:
            self._hash = hash(self._value)
        return self._hash

    cdef str to_str(self):
        return self._value
