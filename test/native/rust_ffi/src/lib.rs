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

// ── Slice 4: the binding manifest ───────────────────────────────────────────

march::init!("demo", [add, shout, parse, boom, translate, area, counter_new, counter_value]);
