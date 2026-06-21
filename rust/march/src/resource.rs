//! `ResourceArc<T>` — an `Arc`-like handle to a native Rust value living behind
//! a March opaque `resource` (§4.8). March manages the reference count; when it
//! drops the last reference the registered destructor runs `Drop` on the `T`.
//!
//! Ownership notes:
//!   * `ResourceArc::new(t)` mints an owned handle (rc = 1).
//!   * Returning it (`to_march`) transfers that reference to March.
//!   * Receiving one as a by-value parameter borrows it for the call: the shim
//!     `march_dup`s on entry and `march_drop`s on `Drop`, a net-zero that never
//!     corrupts March's count regardless of borrow/consume. (A consume mode that
//!     frees from Rust is a documented follow-up.)

use crate::sys::*;
use crate::value::{FromMarch, ToMarch};
use core::ffi::c_void;
use core::marker::PhantomData;

extern "C" fn drop_box<T>(p: *mut c_void) {
    if !p.is_null() {
        unsafe { drop(Box::from_raw(p as *mut T)) };
    }
}

/// Register (idempotently, by Rust type name) the March resource type for `T`,
/// returning its stable type id.
fn type_id_for<T: 'static>() -> i32 {
    let name = std::any::type_name::<T>();
    // type_name has no interior NUL; fall back to a fixed name if it ever does.
    let cname = std::ffi::CString::new(name)
        .unwrap_or_else(|_| std::ffi::CString::new("march_resource").unwrap());
    unsafe { march_resource_type(cname.as_ptr(), drop_box::<T> as march_destructor) }
}

/// A reference-counted handle to a native `T` behind a March resource value.
pub struct ResourceArc<T: 'static> {
    v: march_value,
    _pd: PhantomData<T>,
}

impl<T: 'static> ResourceArc<T> {
    /// Move `value` onto the heap and wrap it as an owned March resource (rc = 1).
    pub fn new(value: T) -> Self {
        let tid = type_id_for::<T>();
        let ptr = Box::into_raw(Box::new(value)) as *mut c_void;
        let v = unsafe { march_resource_new(tid, ptr) };
        ResourceArc { v, _pd: PhantomData }
    }

    /// Borrow the native `T`.
    pub fn get(&self) -> &T {
        let tid = type_id_for::<T>();
        unsafe { &*(march_resource_get(self.v, tid) as *const T) }
    }

    /// The underlying March value word (advanced use).
    pub fn as_value(&self) -> march_value {
        self.v
    }
}

impl<T: 'static> ToMarch for ResourceArc<T> {
    fn to_march(self) -> march_value {
        let v = self.v;
        core::mem::forget(self); // transfer our reference to March
        v
    }
}

impl<T: 'static> FromMarch for ResourceArc<T> {
    fn from_march(v: march_value) -> Self {
        unsafe { march_dup(v) }; // own a reference for the call
        ResourceArc { v, _pd: PhantomData }
    }
}

impl<T: 'static> Drop for ResourceArc<T> {
    fn drop(&mut self) {
        unsafe { march_drop(self.v) };
    }
}
