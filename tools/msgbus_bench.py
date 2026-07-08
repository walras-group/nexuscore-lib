"""Benchmark harness for the Cython Python MessageBus (no lambda overhead).

Run: PYTHONPATH=. .venv/bin/python tools/msgbus_bench.py
"""
import gc
import time

from nexuscore import MessageBus, TestClock, TraderId


def make_bus():
    return MessageBus(trader_id=TraderId("TRADER-001"), clock=TestClock())


def report(name, elapsed, total):
    print(f"{name:<40} {elapsed/total*1e9:>9.1f} ns/dispatch  "
          f"({total:,} dispatches in {elapsed*1e3:.1f} ms)")


REPEATS = 5


def bench_single(name, iters, bus, topic, msg, dispatches=1):
    gc.disable()
    for _ in range(5000):
        bus.publish(topic, msg)
    best = float("inf")
    for _ in range(REPEATS):
        start = time.perf_counter()
        for _ in range(iters):
            bus.publish(topic, msg)
        best = min(best, time.perf_counter() - start)
    gc.enable()
    report(name, best, iters * dispatches)


def scenario_no_subs(iters=3_000_000):
    bus = make_bus()
    bench_single("no_subscribers (bus overhead)", iters, bus,
                 "data.quotes.BINANCE.BTCUSDT", object())


def scenario_single_exact(iters=3_000_000):
    bus = make_bus()
    c = [0]
    bus.subscribe("data.quotes.BINANCE.BTCUSDT", lambda m: c.__setitem__(0, c[0] + 1))
    bench_single("single_subscriber_exact", iters, bus,
                 "data.quotes.BINANCE.BTCUSDT", object())


def scenario_single_wildcard(iters=3_000_000):
    bus = make_bus()
    c = [0]
    bus.subscribe("data.quotes.*.BTCUSDT", lambda m: c.__setitem__(0, c[0] + 1))
    bench_single("single_subscriber_wildcard", iters, bus,
                 "data.quotes.BINANCE.BTCUSDT", object())


def scenario_multi(count_subs, iters=1_500_000):
    bus = make_bus()
    c = [0]
    for _ in range(count_subs):
        bus.subscribe("data.quotes.BINANCE.BTCUSDT", lambda m: c.__setitem__(0, c[0] + 1))
    bench_single(f"{count_subs}_subscribers_exact", iters, bus,
                 "data.quotes.BINANCE.BTCUSDT", object(), dispatches=count_subs)


def scenario_mixed(iters=1_500_000):
    bus = make_bus()
    c = [0]
    bus.subscribe("data.quotes.BINANCE.*", lambda m: c.__setitem__(0, c[0] + 1))
    topics = [f"data.quotes.BINANCE.{i}" for i in ("BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT")]
    msg = object()
    for t in topics:
        bus.publish(t, msg)
    gc.disable()
    for _ in range(5000):
        for t in topics:
            bus.publish(t, msg)
    best = float("inf")
    for _ in range(REPEATS):
        start = time.perf_counter()
        for _ in range(iters):
            for t in topics:
                bus.publish(t, msg)
        best = min(best, time.perf_counter() - start)
    gc.enable()
    report("mixed_4_topics_wildcard", best, iters * 4)


def _noop(m):
    pass


def scenario_loop_vs_batch(n_msgs=1000, iters=20_000):
    """Compare N sequential publish() calls vs one publish_batch() call.

    Uses a trivial handler so the comparison reflects bus/dispatch throughput.
    """
    bus = make_bus()
    bus.subscribe("data.quotes.BINANCE.BTCUSDT", _noop)
    topic = "data.quotes.BINANCE.BTCUSDT"
    msgs = [object() for _ in range(n_msgs)]
    for m in msgs:  # warm
        bus.publish(topic, m)

    gc.disable()
    best = float("inf")
    for _ in range(REPEATS):
        s = time.perf_counter()
        for _ in range(iters):
            for m in msgs:
                bus.publish(topic, m)
        best = min(best, time.perf_counter() - s)
    report("publish() loop (1 sub, noop)", best, iters * n_msgs)

    has_batch = hasattr(bus, "publish_batch")
    if has_batch:
        best_b = float("inf")
        for _ in range(REPEATS):
            s = time.perf_counter()
            for _ in range(iters):
                bus.publish_batch(topic, msgs)
            best_b = min(best_b, time.perf_counter() - s)
        report("publish_batch() (1 sub, noop)", best_b, iters * n_msgs)
    gc.enable()


def run_all():
    print("=== Python MessageBus.publish throughput ===")
    scenario_loop_vs_batch()
    scenario_no_subs()
    scenario_single_exact()
    scenario_single_wildcard()
    scenario_multi(5)
    scenario_multi(10)
    scenario_mixed()


if __name__ == "__main__":
    run_all()
