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

from typing import Any
from typing import Callable

import cython

from nexuscore.common.component cimport Clock
from nexuscore.core.correctness cimport Condition
from nexuscore.core.message cimport Request
from nexuscore.core.message cimport Response
from nexuscore.core.string cimport PyUnicode_AsUTF8AndSize
from nexuscore.core.uuid cimport UUID4
from nexuscore.model.identifiers cimport TraderId
from nexuscore.serialization.base cimport _EXTERNAL_PUBLISHABLE_TYPES
from nexuscore.serialization.base cimport Serializer


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
