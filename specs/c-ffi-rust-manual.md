# Binding Rust to March today (the manual C-ABI path)

**Status:** proven & reproducible (2026-06-20). This is the *manual* path — no
`#[march]` macro, no `forge` cargo integration. It works **today** on the
shipped C FFI (Phases 1–7) because Rust speaks the C ABI natively via
`extern "C"`. The ergonomic `march` crate (derive macros, `ResourceArc`,
panic-catching) is future work; see `specs/c-ffi-gaps.md` and the design spec
§15–16.

This is exactly how Rustler works for the BEAM: the NIF interface is a C ABI
(`erl_nif.h`); Rustler binds it from Rust and generates the `extern "C"` glue.
Here `runtime/march_ffi.h` is the `erl_nif.h` analog, and you write the glue by
hand (until the macro layer exists).

## The principle

- Rust has no stable ABI, so March↔Rust goes through `extern "C"` — i.e. the C
  ABI you already have (`march_ffi.h`).
- A Rust **`staticlib`** crate exports `#[no_mangle] pub extern "C"` functions
  and calls the `march_*` ABI functions (which the March runtime provides; they
  resolve at the final link).
- March binds those symbols with a normal `extern` block (`fn … = "rs_symbol"`),
  and `forge.toml`'s `[ffi] link` points the linker at the crate's `.a`.

## 1. The Rust crate (`Cargo.toml` + `src/lib.rs`)

```toml
# Cargo.toml
[package]
name = "march_rust_demo"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]

[profile.release]
panic = "abort"          # never unwind across the FFI boundary
```

```rust
// src/lib.rs — idiomatic Rust, hand-bound to the march_ffi.h ABI.
#![allow(non_camel_case_types)]
type march_value = i64;

#[repr(C)]
struct MarchSlice { ptr: *const u8, len: usize }   // == march_slice

extern "C" {
    fn march_str_borrow(s: march_value) -> MarchSlice;
    fn march_str_new(utf8: *const u8, len: usize) -> march_value;
    fn march_make_int(n: i64) -> march_value;
    fn march_ok(v: march_value) -> march_value;
    fn march_err(e: march_value) -> march_value;
}

// A borrowed String arg -> &str valid for the call (March's `borrow` default).
unsafe fn borrow_str<'a>(s: march_value) -> &'a str {
    let sl = march_str_borrow(s);
    std::str::from_utf8(std::slice::from_raw_parts(sl.ptr, sl.len)).unwrap_or("")
}
fn new_str(s: &str) -> march_value { unsafe { march_str_new(s.as_ptr(), s.len()) } }

#[no_mangle] pub extern "C" fn rs_add(a: i64, b: i64) -> i64 { a + b }

#[no_mangle] pub extern "C" fn rs_shout(s: march_value) -> march_value {
    new_str(&unsafe { borrow_str(s) }.to_uppercase())
}

#[no_mangle] pub extern "C" fn rs_parse(s: march_value) -> march_value {
    match unsafe { borrow_str(s) }.trim().parse::<i64>() {
        Ok(n)  => unsafe { march_ok(march_make_int(n)) },
        Err(_) => unsafe { march_err(new_str("bad int")) },
    }
}
```

Build it: `cargo build --release` → `target/release/libmarch_rust_demo.a`.

## 2. The March app (`lib/main.march`)

```march
mod RustDemo do
  needs Ffi
  extern "rust" : Cap(Ffi) do
    fn add(a: Int, b: Int): Int = "rs_add"
    fn shout(s: String): String = "rs_shout"
    fn parse(s: String): Result(Int, String) = "rs_parse"
  end
  fn show(r: Result(Int, String)) : String do
    match r do
      Ok(n) -> int_to_string(n)
      Err(e) -> e
    end
  end
  fn main() : Unit do
    println(int_to_string(add(40, 2)))   -- 42
    println(shout("rust"))                -- RUST
    println(show(parse("123")))           -- 123
    println(show(parse("xx")))            -- bad int
  end
end
```

You can also scaffold the `extern` block's matching C-or-Rust signatures with
`forge ffi gen-c lib/main.march` and translate the stubs to Rust.

## 3. `forge.toml` — link the staticlib

```toml
[package]
name = "rustforge"
version = "0.1.0"
type = "app"
entrypoint = "lib/main.march"

# Build the crate separately (cargo build --release); we just link its .a.
[ffi]
link = ["-L/abs/path/march_rust_demo/target/release", "-lmarch_rust_demo"]
```

`forge build` passes those as linker flags; the March runtime (which defines
`march_str_borrow`/`march_str_new`/… ) is already in the link, so the Rust
crate's references resolve.

## Verified output

```
$ cargo build --release            # in the crate
$ forge build                      # in the app
$ ./.march/build/debug/rustforge
42
RUST
123
bad int
```

Both `Ok` and `Err` arms round-trip; the Rust side borrows the March string and
returns a fresh one — all through the C ABI, with the same type scope as C.

## Scope & caveats (manual path)

- **Same type support as C**: primitives, `String`/`Bytes` (borrow/new),
  `Option`/`Result` (`march_some`/`none`/`ok`/`err`), opaque `resource`s
  (`march_resource_type`/`new`/`get`), `borrow`/`consume`, `blocking`.
- **No `#[derive(Encoder/Decoder)]`** — you marshal by hand; passing Rust
  structs ↔ March records needs the record/variant codecs (Phase 9).
- **You write the `extern "C"` + `march_*` bindings and the March `extern`
  block by hand**; cargo is run separately; link flags are manual.
- **`panic = "abort"`** (or `catch_unwind` at each boundary) — never unwind
  across `extern "C"`.

The future `march` crate (proc-macro `#[march]`, `Encoder`/`Decoder`,
`ResourceArc`, auto-generated `extern` blocks, `forge add-rust`) automates all
of the boilerplate above. Until then, this path is fully functional.
