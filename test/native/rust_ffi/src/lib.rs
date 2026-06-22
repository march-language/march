//! End-to-end demo binding for the `march` Rust FFI layer — exercises all four
//! slices: #[march] (primitives/String/Result + panic→Err), #[derive(Encoder,
//! Decoder)] (struct↔record, enum↔variant), ResourceArc, and init!.

use march::{march, Decoder, Encoder, Error, ResourceArc};

// ── Slice 1: primitives / String / Result / panic→Err ───────────────────────

#[march]
fn add(a: i64, b: i64) -> i64 {
    a + b
}

#[march]
fn shout(s: &str) -> String {
    s.to_uppercase()
}

#[march]
fn parse(s: &str) -> Result<i64, Error> {
    s.trim()
        .parse::<i64>()
        .map_err(|e| Error::msg(e.to_string()))
}

#[march]
fn boom(n: i64) -> Result<i64, Error> {
    if n == 0 {
        panic!("divide by zero"); // becomes Err("...divide by zero") via catch_unwind
    }
    Ok(100 / n)
}

// ── Slice 2: derive(Encoder, Decoder) ───────────────────────────────────────

#[derive(Encoder, Decoder)]
struct Point {
    x: i64,
    y: i64,
}

#[march]
fn translate(p: Point, dx: i64, dy: i64) -> Point {
    Point { x: p.x + dx, y: p.y + dy }
}

#[derive(Encoder, Decoder)]
enum Shape {
    Circle(i64),
    Rect(i64, i64),
}

#[march]
fn area(s: Shape) -> i64 {
    match s {
        Shape::Circle(r) => 3 * r * r,
        Shape::Rect(w, h) => w * h,
    }
}

// ── Slice 3: ResourceArc ────────────────────────────────────────────────────

struct Counter {
    n: i64,
}

#[march]
fn counter_new(start: i64) -> ResourceArc<Counter> {
    ResourceArc::new(Counter { n: start })
}

#[march]
fn counter_value(c: ResourceArc<Counter>) -> i64 {
    c.get().n
}

// ── Slice 5: Option(Float) — fully-boxed ABI ────────────────────────────────

/// Return Some(f) if f > 0.0, else None — exercises the boxed Option<f64> path.
#[march]
fn maybe_float(f: f64) -> Option<f64> {
    if f > 0.0 { Some(f) } else { None }
}

/// Accept an Option<f64> — exercises boxed Option<f64> decode.
#[march]
fn unwrap_float_or(v: Option<f64>, default: f64) -> f64 {
    v.unwrap_or(default)
}

// ── Slice 6: ConsumeResourceArc — take ownership of a resource ──────────────

/// Consume a Counter resource and return its value. Declared `consume c` in
/// the March extern block — March transfers the reference, Rust drops it.
#[march]
fn counter_finish(c: march::ConsumeResourceArc<Counter>) -> i64 {
    // Read the stored value; Drop will call march_drop when this fn returns.
    c.get().n
}

// ── Slice 7: the binding manifest ───────────────────────────────────────────

march::init!("demo", [add, shout, parse, boom, translate, area,
    counter_new, counter_value, counter_finish,
    maybe_float, unwrap_float_or]);
