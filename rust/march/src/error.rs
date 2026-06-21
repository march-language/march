//! The error type carried by `Result`-returning bindings. Encodes to a March
//! `String` (the `Err` payload); a panic in a `#[march]` body is caught and
//! turned into one of these (never UB across the `extern "C"` boundary).

use crate::value::ToMarch;
use crate::sys::march_value;
use std::any::Any;

/// A binding error. The message becomes the March `Err(String)` payload.
#[derive(Debug, Clone)]
pub struct Error {
    msg: String,
}

impl Error {
    pub fn msg(m: impl Into<String>) -> Self {
        Error { msg: m.into() }
    }

    pub fn message(&self) -> &str {
        &self.msg
    }

    /// Build an `Error` from a caught panic payload (best-effort message).
    pub fn from_panic(payload: Box<dyn Any + Send>) -> Self {
        let msg = if let Some(s) = payload.downcast_ref::<&str>() {
            (*s).to_string()
        } else if let Some(s) = payload.downcast_ref::<String>() {
            s.clone()
        } else {
            "panic in Rust binding".to_string()
        };
        Error { msg }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.msg)
    }
}

impl std::error::Error for Error {}

impl ToMarch for Error {
    fn to_march(self) -> march_value {
        self.msg.to_march()
    }
}
