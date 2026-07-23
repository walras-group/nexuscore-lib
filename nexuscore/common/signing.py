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
HMAC-SHA256 message signing, backed by the Python standard library.

Output is a lowercase hex digest, byte-identical to the previous Rust (aws-lc)
implementation. HMAC is used only on the authentication path (per REST request /
per WebSocket login), so the stdlib backend is more than fast enough while keeping
the package free of any native crypto dependency.
"""

from __future__ import annotations

import hashlib
import hmac


def hmac_signature(secret: str, data: str) -> str:
    """
    Return the HMAC-SHA256 of `data` keyed by `secret`, as a lowercase hex digest.

    Drop-in replacement for the previous Rust implementation.

    Parameters
    ----------
    secret : str
        The secret key.
    data : str
        The message to sign.

    Returns
    -------
    str
        The signature as a lowercase hex digest.

    """
    return hmac.new(secret.encode(), data.encode(), hashlib.sha256).hexdigest()


class HmacSigner:
    """
    Reusable HMAC-SHA256 signer that caches the key schedule.

    Build once per connection with a fixed `secret`, then call :meth:`sign` per
    request. Absorbing the key only once (via ``hmac.HMAC.copy``) is ~1.4x faster
    than :func:`hmac_signature` when signing many messages with the same key.

    Parameters
    ----------
    secret : str
        The secret key (absorbed once at construction).

    """

    def __init__(self, secret: str) -> None:
        self._base = hmac.new(secret.encode(), None, hashlib.sha256)

    def sign(self, data: str) -> str:
        """
        Return the HMAC-SHA256 of `data` as a lowercase hex digest.

        Parameters
        ----------
        data : str
            The message to sign.

        Returns
        -------
        str

        """
        h = self._base.copy()
        h.update(data.encode())
        return h.hexdigest()
