//! Raw `extern "C"` declarations of the March FFI ABI (`runtime/march_ffi.h`).
//! These are resolved when the binding `staticlib` is linked into a March
//! binary (the runtime provides the symbols). A `cargo build` of the crate
//! itself does not link, so the undefined references are fine until link time.
#![allow(non_camel_case_types)]

use core::ffi::{c_char, c_int, c_void};

/// An opaque March value word (tagged; see the ABI header).
pub type march_value = i64;

/// Per-call context for `raises` bindings (opaque).
#[repr(C)]
pub struct march_env {
    _private: [u8; 0],
}

/// A borrowed view into a March String/Bytes value — valid for the call only.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct march_slice {
    pub ptr: *const u8,
    pub len: usize,
}

pub type march_destructor = extern "C" fn(*mut c_void);

extern "C" {
    pub fn march_make_int(n: i64) -> march_value;
    pub fn march_get_int(v: march_value) -> i64;
    pub fn march_make_bool(b: c_int) -> march_value;
    pub fn march_get_bool(v: march_value) -> c_int;
    pub fn march_make_float(f: f64) -> march_value;
    pub fn march_get_float(v: march_value) -> f64;

    pub fn march_is_heap(v: march_value) -> c_int;
    pub fn march_as_ptr(v: march_value) -> *mut c_void;
    pub fn march_from_ptr(p: *mut c_void) -> march_value;

    pub fn march_str_borrow(s: march_value) -> march_slice;
    pub fn march_bytes_borrow(b: march_value) -> march_slice;
    pub fn march_utf8_valid(p: *const u8, len: usize) -> c_int;
    pub fn march_str_new(utf8: *const u8, len: usize) -> march_value;
    pub fn march_bytes_new(data: *const u8, len: usize) -> march_value;

    pub fn march_variant_tag(v: march_value) -> i32;
    pub fn march_variant_field(v: march_value, i: i32) -> march_value;
    pub fn march_record_field(v: march_value, i: i32) -> march_value;
    pub fn march_make_variant(tag: i32, nfields: i32, fields: *const march_value) -> march_value;
    pub fn march_make_record(desc: *const c_char, nfields: i32, fields: *const march_value)
        -> march_value;

    pub fn march_none() -> march_value;
    pub fn march_some(v: march_value) -> march_value;
    /// Boxed `Some` for `Option(Float)` / `Option(Unit)` — the payload would
    /// alias `None=0` under the niche form, so a heap cell is used instead.
    /// Pass `march_make_float(f)` for a Float payload.
    pub fn march_some_boxed(payload: march_value) -> march_value;
    /// Boxed `None` paired with `march_some_boxed`: matched by cell tag (0),
    /// so `None` must also be a heap cell (not the niche `0`).
    pub fn march_none_boxed() -> march_value;
    pub fn march_ok(v: march_value) -> march_value;
    pub fn march_err(e: march_value) -> march_value;

    pub fn march_resource_type(name: *const c_char, dtor: march_destructor) -> i32;
    pub fn march_resource_new(type_id: i32, native_ptr: *mut c_void) -> march_value;
    pub fn march_resource_get(v: march_value, type_id: i32) -> *mut c_void;

    pub fn march_raise(env: *mut march_env, e: march_value);
    pub fn march_dup(v: march_value) -> march_value;
    pub fn march_drop(v: march_value);
    pub fn march_fatal(msg: *const c_char);
}
