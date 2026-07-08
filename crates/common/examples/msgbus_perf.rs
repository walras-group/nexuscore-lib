//! Standalone throughput harness for the typed message bus publish hot path.
//!
//! Run with: `cargo run --release -p nautilus-common --example msgbus_perf`
//!
//! Measures `TopicRouter::publish` (the core typed pub/sub dispatch) across the
//! same scenarios covered by `benches/msgbus.rs`, without requiring criterion.

use std::{
    hint::black_box,
    sync::atomic::{AtomicU64, Ordering},
    time::Instant,
};

use nautilus_common::msgbus::{
    MStr, Pattern, Topic, TypedHandler,
    typed_router::TopicRouter,
};
use nautilus_model::data::QuoteTick;
use ustr::Ustr;

static COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Clone)]
struct CountingHandler {
    id: Ustr,
}

impl nautilus_common::msgbus::Handler<QuoteTick> for CountingHandler {
    fn id(&self) -> Ustr {
        self.id
    }

    fn handle(&self, quote: &QuoteTick) {
        COUNTER.fetch_add(quote.bid_price.raw as u64, Ordering::Relaxed);
    }
}

fn bench(name: &str, iters: u64, dispatches_per_iter: u64, mut f: impl FnMut()) {
    // Warm up
    for _ in 0..1_000 {
        f();
    }
    let start = Instant::now();
    for _ in 0..iters {
        f();
    }
    let elapsed = start.elapsed();
    let total_dispatches = iters * dispatches_per_iter;
    let ns_per_dispatch = elapsed.as_nanos() as f64 / total_dispatches as f64;
    println!(
        "{name:<40} {ns_per_dispatch:>8.3} ns/dispatch  ({total_dispatches} dispatches in {:?})",
        elapsed
    );
}

fn make_router(sub_count: usize, pattern: &str) -> TopicRouter<QuoteTick> {
    let mut router = TopicRouter::<QuoteTick>::new();
    let pattern: MStr<Pattern> = MStr::from(pattern);
    for i in 0..sub_count {
        let handler = TypedHandler::new(CountingHandler {
            id: Ustr::from(&format!("handler_{i}")),
        });
        router.subscribe(pattern, handler, 0);
    }
    router
}

fn main() {
    let quote = QuoteTick::default();

    println!("=== TopicRouter::publish throughput ===");

    // Single subscriber, exact topic (high volume)
    {
        let mut router = make_router(1, "data.quotes.BINANCE.BTCUSDT");
        let topic: MStr<Topic> = MStr::from("data.quotes.BINANCE.BTCUSDT");
        router.publish(topic, &quote); // warm cache
        bench("single_subscriber_exact", 20_000_000, 1, || {
            router.publish(black_box(topic), black_box(&quote));
        });
    }

    // Wildcard subscription, single subscriber
    {
        let mut router = make_router(1, "data.quotes.*.BTCUSDT");
        let topic: MStr<Topic> = MStr::from("data.quotes.BINANCE.BTCUSDT");
        router.publish(topic, &quote);
        bench("single_subscriber_wildcard", 20_000_000, 1, || {
            router.publish(black_box(topic), black_box(&quote));
        });
    }

    // Multiple subscribers
    for &count in &[5usize, 10] {
        let mut router = make_router(count, "data.quotes.BINANCE.BTCUSDT");
        let topic: MStr<Topic> = MStr::from("data.quotes.BINANCE.BTCUSDT");
        router.publish(topic, &quote);
        bench(
            &format!("{count}_subscribers_exact"),
            5_000_000,
            count as u64,
            || {
                router.publish(black_box(topic), black_box(&quote));
            },
        );
    }

    // Mixed topics (4 instruments, one wildcard subscriber)
    {
        let instruments = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT"];
        let topics: Vec<MStr<Topic>> = instruments
            .iter()
            .map(|i| MStr::from(&format!("data.quotes.BINANCE.{i}")))
            .collect();
        let mut router = make_router(1, "data.quotes.BINANCE.*");
        for t in &topics {
            router.publish(*t, &quote);
        }
        bench("mixed_4_topics_wildcard", 5_000_000, 4, || {
            for t in &topics {
                router.publish(black_box(*t), black_box(&quote));
            }
        });
    }

    println!("COUNTER (anti-optimization): {}", COUNTER.load(Ordering::Relaxed));
}
