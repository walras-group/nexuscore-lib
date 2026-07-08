"""Benchmark every public method of the Cython MessageBus (min-of-N).

Run: PYTHONPATH=. .venv/bin/python tools/msgbus_methods_bench.py
"""
import gc
import time

from nexuscore import MessageBus, TestClock, TraderId, UUID4
from nexuscore.core.message import Request, Response

REPEATS = 7


def make_bus():
    return MessageBus(trader_id=TraderId("TRADER-001"), clock=TestClock())


def best(fn, iters):
    gc.disable()
    for _ in range(2000):
        fn()
    b = float("inf")
    for _ in range(REPEATS):
        s = time.perf_counter()
        for _ in range(iters):
            fn()
        b = min(b, time.perf_counter() - s)
    gc.enable()
    return b / iters * 1e9


def bench(name, fn, iters=1_000_000):
    print(f"{name:<28} {best(fn, iters):9.1f} ns/call")


def setup_bus():
    bus = make_bus()
    h = lambda m: None
    for i in range(10):
        bus.subscribe(f"data.quotes.V{i}.*", h)
    bus.subscribe("data.quotes.BINANCE.BTCUSDT", h)
    bus.register("MyEndpoint", h)
    bus.add_streaming_type(int)
    bus.publish("data.quotes.BINANCE.BTCUSDT", object())  # warm resolve cache
    return bus, h


def main():
    print("=== MessageBus per-method throughput ===")
    bus, h = setup_bus()
    noop = lambda m: None
    msg = object()

    # --- read-only / query methods ---
    bench("endpoints", lambda: bus.endpoints())
    bench("topics", lambda: bus.topics())
    bench("subscriptions(None)", lambda: bus.subscriptions())
    bench("subscriptions('data.*')", lambda: bus.subscriptions("data.quotes.BINANCE.BTCUSDT"))
    bench("streaming_types", lambda: bus.streaming_types())
    bench("has_subscribers", lambda: bus.has_subscribers("data.quotes.BINANCE.BTCUSDT"))
    bench("is_subscribed", lambda: bus.is_subscribed("data.quotes.BINANCE.BTCUSDT", h))
    bench("is_streaming_type", lambda: bus.is_streaming_type(int))

    rid = UUID4()
    req_pending = Request(None, rid, 0)
    bus.request("MyEndpoint", Request(noop, UUID4(), 0))  # leaves one pending
    bench("is_pending_request", lambda: bus.is_pending_request(rid))

    # --- point-to-point ---
    bench("send", lambda: bus.send("MyEndpoint", msg))
    req = Request(None, UUID4(), 0)  # callback None -> not stored, reusable
    bench("request", lambda: bus.request("MyEndpoint", req))
    resp = Response(UUID4(), UUID4(), 0)  # no matching correlation -> pop None
    bench("response", lambda: bus.response(resp))

    # --- pub/sub dispatch ---
    bench("publish (1 sub)", lambda: bus.publish("data.quotes.BINANCE.BTCUSDT", msg))
    batch = [object() for _ in range(100)]
    if hasattr(bus, "publish_batch"):
        bench("publish_batch/msg (100)",
              lambda: bus.publish_batch("data.quotes.BINANCE.BTCUSDT", batch),
              iters=200_000)

    bench("add_streaming_type", lambda: bus.add_streaming_type(int))  # idempotent
    bench("dispose", lambda: bus.dispose())

    # --- mutating methods measured as register/deregister & subscribe/unsubscribe cycles ---
    def reg_cycle():
        bus.register("Tmp", noop)
        bus.deregister("Tmp", noop)
    bench("register+deregister", reg_cycle, iters=500_000)

    def sub_cycle():
        bus.subscribe("bench.sub.topic", noop)
        bus.unsubscribe("bench.sub.topic", noop)
    bench("subscribe+unsubscribe", sub_cycle, iters=200_000)


if __name__ == "__main__":
    main()
