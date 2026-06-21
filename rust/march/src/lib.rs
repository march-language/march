//! The `march` Rust FFI runtime — bind Rust crates to March, Rustler-style.
//!
//! ```ignore
//! use march::{march, Encoder, Decoder, ResourceArc, Error};
//!
//! #[march]
//! fn parse(s: &str) -> Result<i64, Error> {
//!     s.trim().parse().map_err(|e: std::num::ParseIntError| Error::msg(e.to_string()))
//! }
//!
//! #[derive(Encoder, Decoder)]
//! struct Point { x: i64, y: i64 }
//!
//! march::init!("demo", [parse]);
//! ```
//!
//! `#[march]` generates the `#[no_mangle] extern "C"` shim (decode args,
//! `catch_unwind` the body, encode the result); `Result` returns route errors
//! and panics through the March error protocol. See
//! `specs/2026-06-19-c-ffi-abi-design.md` §16.

pub mod sys;
mod error;
mod resource;
mod value;

pub use error::Error;
pub use resource::ResourceArc;
pub use sys::{march_env, march_value};
pub use value::{borrow_bytes, borrow_str, FromMarch, ToMarch};

/// Derive `ToMarch` (the `Encoder` half) for a struct/enum ↔ March record/variant.
pub use march_macro::Encoder;
/// Derive `FromMarch` (the `Decoder` half).
pub use march_macro::Decoder;
/// Generate the `#[no_mangle] extern "C"` shim for a binding function.
pub use march_macro::march;
/// Emit the binding manifest (used by `forge add-rust` to generate the March
/// `extern` block).
pub use march_macro::init;

// `#[derive(Encoder)]` and `#[derive(Decoder)]` are the user-facing names for
// the ToMarch / FromMarch derives.

// ── Internal helpers called from generated code (not a stable API) ───────────

/// Turn a caught panic into a March `Err(msg)` value word (a boxed `Result`, not
/// the bare message). Used by `#[march]` for `Result`-returning bindings — a
/// panic never crosses `extern "C"`.
#[doc(hidden)]
pub fn __panic_to_err(payload: Box<dyn std::any::Any + Send>) -> march_value {
    let msg = Error::from_panic(payload).to_march();
    unsafe { sys::march_err(msg) }
}

/// A panic in a non-`Result` binding has no error channel: report and abort
/// (unwinding across `extern "C"` would be UB).
#[doc(hidden)]
pub fn __abort_panic(payload: Box<dyn std::any::Any + Send>) -> ! {
    let e = Error::from_panic(payload);
    let msg = std::ffi::CString::new(format!("panic in Rust binding: {}", e))
        .unwrap_or_else(|_| std::ffi::CString::new("panic in Rust binding").unwrap());
    unsafe { sys::march_fatal(msg.as_ptr()) };
    std::process::abort();
}

/// A `#[derive(Decoder)]` enum saw a tag outside its variant set.
#[doc(hidden)]
pub unsafe fn __bad_variant_tag() -> ! {
    let msg = std::ffi::CString::new("FromMarch: variant tag out of range").unwrap();
    sys::march_fatal(msg.as_ptr());
    std::process::abort();
}
