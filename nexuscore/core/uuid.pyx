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

import os
import uuid

from nexuscore.core.correctness cimport Condition


cdef class UUID4:
    """
    Represents a Universally Unique Identifier (UUID)
    version 4 based on a 128-bit label as specified in RFC 4122.

    References
    ----------
    https://en.wikipedia.org/wiki/Universally_unique_identifier
    """

    def __init__(self):
        # Equivalent to `str(uuid.uuid4())` but skips the intermediate `uuid.UUID`
        # object: draw 16 CSPRNG bytes, set the version (4) and RFC 4122 variant
        # bits, then format as the canonical 8-4-4-4-12 lowercase hex string.
        cdef bytearray b = bytearray(os.urandom(16))
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        cdef str h = b.hex()
        self._value = f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"

    def __getstate__(self):
        return self._value

    def __setstate__(self, state):
        self._value = state

    def __eq__(self, UUID4 other) -> bool:
        if other is None:
            return False
        return self._value == other._value

    def __hash__(self) -> int:
        return hash(self._value)

    def __str__(self) -> str:
        return self._value

    def __repr__(self) -> str:
        return f"{type(self).__name__}('{self._value}')"

    cdef str to_str(self):
        return self._value

    @property
    def value(self) -> str:
        return self._value

    @staticmethod
    cdef UUID4 from_str_c(str value):
        Condition.valid_string(value, "value")
        uuid_obj = uuid.UUID(value)
        Condition.is_true(uuid_obj.version == 4, "UUID value is not version 4")
        Condition.is_true(uuid_obj.variant == uuid.RFC_4122, "UUID value is not RFC 4122")

        cdef UUID4 uuid4 = UUID4.__new__(UUID4)
        uuid4._value = str(uuid_obj)
        return uuid4

    @staticmethod
    def from_str(str value) -> UUID4:
        """
        Create a new UUID4 from the given string value.

        Parameters
        ----------
        value : str
            The UUID value.

        Returns
        -------
        UUID4

        Raises
        ------
        ValueError
            If `value` is not a valid UUID version 4 RFC 4122 string.

        """
        return UUID4.from_str_c(value)
