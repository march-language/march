//! Marshalling traits between Rust values and March value words.
//!
//! Two representations, mirroring the C ABI:
//!   * **tagged / generic** (`to_march` / `from_march`) — the value as a
//!     standalone March value and as a `Result`/`Option` payload (a generic
//!     slot): `Int`/`Bool` are tag-encoded `(n<<1)|1`.
//!   * **native slot** (`to_march_slot` / `from_march_slot`) — a top-level
//!     extern argument/return and a record/variant field: `Int`/`Bool` are raw.
//! Heap types (`String`, records, variants, resources) use the same word for
//! both, so the slot methods default to the tagged ones.

use crate::sys::*;

/// Encode a Rust value into a March value word.
pub trait ToMarch {
    /// Tagged/generic form (Result/Option payload, standalone heap value).
    fn to_march(self) -> march_value;
    /// Native-slot form (top-level return, record/variant field). Heap types
    /// reuse `to_march`; scalars override to the raw form.
    fn to_march_slot(self) -> march_value
    where
        Self: Sized,
    {
        self.to_march()
    }
}

/// Decode a March value word into a Rust value.
pub trait FromMarch {
    fn from_march(v: march_value) -> Self;
    fn from_march_slot(v: march_value) -> Self
    where
        Self: Sized,
    {
        Self::from_march(v)
    }
}

// ── Primitives ──────────────────────────────────────────────────────────────

impl ToMarch for i64 {
    fn to_march(self) -> march_value {
        unsafe { march_make_int(self) }
    }
    fn to_march_slot(self) -> march_value {
        self // raw
    }
}
impl FromMarch for i64 {
    fn from_march(v: march_value) -> Self {
        unsafe { march_get_int(v) }
    }
    fn from_march_slot(v: march_value) -> Self {
        v // raw
    }
}

impl ToMarch for bool {
    fn to_march(self) -> march_value {
        unsafe { march_make_bool(self as core::ffi::c_int) }
    }
    fn to_march_slot(self) -> march_value {
        self as march_value // raw 0/1
    }
}
impl FromMarch for bool {
    fn from_march(v: march_value) -> Self {
        unsafe { march_get_bool(v) != 0 }
    }
    fn from_march_slot(v: march_value) -> Self {
        v != 0
    }
}

// Float: the slot holds raw IEEE-754 bits (march_make_float is a bitcast), so
// `to_march`/`to_march_slot` coincide. Top-level f64 args/returns are passed as
// C `double` directly by the macro (it special-cases them); these impls cover
// f64 record/variant fields.
impl ToMarch for f64 {
    fn to_march(self) -> march_value {
        unsafe { march_make_float(self) }
    }
}
impl FromMarch for f64 {
    fn from_march(v: march_value) -> Self {
        unsafe { march_get_float(v) }
    }
}

// ── Strings & bytes ─────────────────────────────────────────────────────────

impl ToMarch for String {
    fn to_march(self) -> march_value {
        let b = self.as_bytes();
        unsafe { march_str_new(b.as_ptr(), b.len()) }
    }
}
impl FromMarch for String {
    fn from_march(v: march_value) -> Self {
        let s = unsafe { march_str_borrow(v) };
        let bytes = unsafe { core::slice::from_raw_parts(s.ptr, s.len) };
        String::from_utf8_lossy(bytes).into_owned()
    }
}

impl<'a> ToMarch for &'a str {
    fn to_march(self) -> march_value {
        unsafe { march_str_new(self.as_ptr(), self.len()) }
    }
}

impl ToMarch for Vec<u8> {
    fn to_march(self) -> march_value {
        unsafe { march_bytes_new(self.as_ptr(), self.len()) }
    }
}
impl FromMarch for Vec<u8> {
    fn from_march(v: march_value) -> Self {
        let s = unsafe { march_bytes_borrow(v) };
        unsafe { core::slice::from_raw_parts(s.ptr, s.len) }.to_vec()
    }
}

// ── Option (niche: Some(x)=x, None=0) ───────────────────────────────────────

impl<T: ToMarch> ToMarch for Option<T> {
    fn to_march(self) -> march_value {
        match self {
            Some(x) => unsafe { march_some(x.to_march()) },
            None => unsafe { march_none() },
        }
    }
}
impl<T: FromMarch> FromMarch for Option<T> {
    fn from_march(v: march_value) -> Self {
        if v == 0 {
            None
        } else {
            Some(T::from_march(v))
        }
    }
}

// ── Result (boxed: Ok=tag 0, Err=tag 1) ─────────────────────────────────────

impl<T: ToMarch, E: ToMarch> ToMarch for Result<T, E> {
    fn to_march(self) -> march_value {
        match self {
            Ok(x) => unsafe { march_ok(x.to_march()) },
            Err(e) => unsafe { march_err(e.to_march()) },
        }
    }
}
impl<T: FromMarch, E: FromMarch> FromMarch for Result<T, E> {
    fn from_march(v: march_value) -> Self {
        unsafe {
            if march_variant_tag(v) == 0 {
                Ok(T::from_march(march_variant_field(v, 0)))
            } else {
                Err(E::from_march(march_variant_field(v, 0)))
            }
        }
    }
}

/// Borrow a March `String` argument as a `&str` for the duration of the call.
/// Used by `#[march]` for `&str` parameters (a borrow — March still owns it).
///
/// # Safety
/// The returned reference is valid only while the underlying March value lives
/// (the call). The generated shim never lets it escape the body.
pub unsafe fn borrow_str<'a>(v: march_value) -> &'a str {
    let s = march_str_borrow(v);
    let bytes = core::slice::from_raw_parts(s.ptr, s.len);
    core::str::from_utf8_unchecked(bytes)
}

/// Borrow a March `Bytes` argument as a `&[u8]` for the duration of the call.
///
/// # Safety
/// As `borrow_str`.
pub unsafe fn borrow_bytes<'a>(v: march_value) -> &'a [u8] {
    let s = march_bytes_borrow(v);
    core::slice::from_raw_parts(s.ptr, s.len)
}
