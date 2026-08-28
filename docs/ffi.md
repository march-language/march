---
layout: docs
title: Foreign Function Interface
nav_order: 19
permalink: /docs/ffi/
---

# Foreign Function Interface (FFI)

March binds to native libraries through a stable C ABI, the same idea as BEAM's
`erl_nif.h`. You declare an `extern` block in March, write (or generate) a thin C
shim against `runtime/march_ffi.h`, and link it through `forge.toml`. Rust crates
bind through the ergonomic `march` crate, which goes through the same C ABI.

The payoff over a hand-written FFI is that ownership crosses the boundary
*checked*: each heap argument is either `borrow`ed (March keeps it and frees it
after the call) or `consume`d (ownership transfers into the binding), and the
compiler threads the reference counts for you, so the common case needs no
manual `march_dup`/`march_drop` and can't leak or double-free. The marshalling
mechanics below are what make that ownership contract concrete for each type.

---

## Declaring externs

An `extern` block names a C library, brings an FFI capability, and lists the
foreign functions with their March types and C symbol names:

```march
mod Demo do
  needs IO.Console
  needs IO.Foreign                       -- using an extern implies this capability
  needs Ffi                              -- the extern block's own Cap(Ffi) requirement

  extern "demo" : Cap(Ffi) do
    fn add(a: Int, b: Int): Int = "demo_add"
    fn shout(s: String): String = "demo_shout"
  end

  fn main() : Unit do
    println(int_to_string(add(2, 3)))    -- 5
    println(shout("hi"))                  -- HI
  end
end
```

The `= "symbol"` gives the exact C symbol; omit it and the default is
`<lib>_<fn>`. Any module with an `extern` block needs the `IO.Foreign`
[capability](capabilities.md) (and `IO.Foreign.Blocking` if any function is
`blocking`).

---

## Marshalling tiers

Values cross the boundary by their static type; there is no universal runtime
tag, so each side accesses a value by the type the signature declares.

| March type | C side (`march_ffi.h`) |
|---|---|
| `Int` / `Bool` | passed by value (`int64_t`) |
| `Float` | passed by value (`double`) |
| `String` / `Bytes` | `march_str_borrow(v)` → `march_slice {ptr, len}`; build with `march_str_new(p, len)` |
| `Option(T)` | `march_none()` / `march_some(v)` (niche); `march_some_boxed`/`march_none_boxed` for `Float`/`Unit` payloads |
| `Result(T, E)` | `march_ok(v)` / `march_err(e)`, or the `raises` protocol below |
| record / variant | the generated codecs (`march_decode_T` / `march_encode_T`, see below) |
| `resource R` | an opaque native handle (`march_resource_new` / `march_resource_get`) |

Strings and bytes are **borrowed** for the duration of the call; copy them with
`march_str_new` if you need to keep them.

---

## Ownership: `borrow` vs `consume`

Heap arguments are **borrowed** by default: March still owns them and frees them
after the call, so a binding may read but must not retain them. Prefix a
parameter with `consume` to transfer ownership to the binding (March will not
free it; the binding must drop or store it):

```march
extern "store" : Cap(Ffi) do
  fn put(consume key: String, consume value: Bytes): Unit = "store_put"
end
```

This maps directly onto March's linear/ownership model, so the refcounting stays
correct with no manual `march_dup`/`march_drop` in the common case.

---

## Errors

A `Result`-returning binding can build the result itself with `march_ok` /
`march_err`. Or mark it `raises` to use the **env-routed** protocol: the binding
takes a hidden `march_env *`, returns the bare `Ok` payload on success, and calls
`march_raise(env, e)` to fail; the compiler materializes `Ok`/`Err`:

```march
extern "rt" : Cap(Ffi) do
  raises fn parse(s: String): Result(Int, String) = "rt_parse"
end
```
```c
int64_t rt_parse(march_env *env, march_value s) {
    march_slice v = march_str_borrow(s);
    if (/* not a number */) { march_raise(env, march_str_new((const uint8_t*)"bad", 3)); return 0; }
    return parsed;                 /* bare Ok payload; the wrapper builds Ok(...) */
}
```

This is also how the Rust layer turns a panic into an `Err`.

---

## `blocking`

A `blocking` binding runs on a dedicated OS thread while the calling green thread
cooperatively yields, so a long C call doesn't stall the scheduler:

```march
extern "io" : Cap(Ffi) do
  blocking fn read_file(consume path: String): Bytes = "io_read_file"
end
```

---

## Generating the C glue

`forge ffi gen-c <file.march>` reads your `extern` blocks and emits a compilable
C shim skeleton: correct signatures, `march_str_borrow` slices for `String`/
`Bytes`, resource-get + `consume`-drop hints, typed `Result`/`Option` return
stubs, and a `TODO` for the actual library call. For every record/variant type
reachable from a signature it also generates **codecs** (a repr-C mirror struct
plus `march_decode_T` / `march_encode_T`), so you work with plain C structs
instead of poking value slots:

```march
type Point = { x : Int, y : Int }
type Shape = Circle(Int) | Rect(Int, Int)
```
```c
typedef struct { int64_t x, y; } Point_c;          /* generated */
Point_c march_decode_Point(march_value v);
march_value march_encode_Point(Point_c p);
```

Record/variant **fields** of `Option(T)`/`Result(T,E)` (with `Int`/`Bool`/
`String`/`Bytes`/`Float`/`Unit` payloads, and nested record/variant types) get
their own typed mirrors too (`Option_Int_c`, `Result_Int_String_c`, …) so nested
optionals decode into `o.maybe.is_some` rather than a raw `march_value`.
`List(T)` fields are emitted as malloc-owned C arrays (`List_T_c` with
`data`/`len`), with generated decode/encode that traverse the March spine.

---

## Binding a Rust crate

The `march` Rust crate (`rust/march`) is the Rustler analog: write idiomatic
Rust, and `#[march]` generates the `extern "C"` shim (decode args, `catch_unwind`
the body, encode the result; a `Result<T, Error>` routes errors and panics
through the error protocol).

```rust
use march::{march, Encoder, Decoder, Error, ResourceArc};

#[march]
fn parse(s: &str) -> Result<i64, Error> {
    s.trim().parse().map_err(|e: std::num::ParseIntError| Error::msg(e.to_string()))
}

#[derive(Encoder, Decoder)]
struct Point { x: i64, y: i64 }            // <-> March record (name-sorted)

#[derive(Encoder, Decoder)]
enum Shape { Circle(i64), Rect(i64, i64) } // <-> March variant (declaration-order tags)

march::init!("demo", [parse]);             // generates the March extern block
```

- **`#[derive(Encoder, Decoder)]`** marshals structs↔records and enums↔variants.
- **`ResourceArc<T>`** wraps native state behind a March `resource`, with `Drop`
  wired to the registered destructor.
- **`march::init!`** prints the matching March `extern` block (`cargo run --bin
  gen_extern`).

`forge ffi add-rust <name>` scaffolds a binding crate (a cargo `staticlib`
depending on `march`, plus the `gen_extern` helper).

- **`ConsumeResourceArc<T>`** is the ownership-transfer variant of `ResourceArc`:
  `FromMarch` skips `march_dup` (March transfers its reference), and `Drop` calls
  `march_drop`. Use it for `consume h` parameters where the binding takes ownership.
- **`Option<f64>`** uses the fully-boxed representation (`march_some_boxed`/
  `march_none_boxed`) so that `0.0` doesn't alias `None`; the macro handles this
  automatically.

---

## Building & linking

List C shim sources and link flags under `[ffi]` in `forge.toml`; `forge build`
compiles and links them:

```toml
[ffi]
sources = ["native/demo.c"]    # C shims compiled by forge
link    = ["-lz"]              # extra linker flags
```

For a Rust binding, `[ffi.rust]` triggers `cargo build --release` automatically
and passes the resulting `.a` to the linker; no manual build step needed:

```toml
[ffi.rust]
crate = "native/demo_binding"  # path to the Cargo project
lib   = "demo_binding"         # [lib] name (default: basename of crate)
```

Editing a shim or any Rust source invalidates the content-addressed binary cache,
so a rebuild relinks automatically. (Under the bare compiler the flags are
`--ffi-c` / `--ffi-link`.)

---

## Interpreter mode

Running `march file.march` (no `--compile`) now supports the **full marshal
layer**: `Int`/`Bool`/`Float` args, `String`/`Bytes` args (heap-allocated for the
call duration), `Option(T)`/`Result(T,E)` returns, `raises` externs, and
variant/record args and returns. Project-specific C shims (from `[ffi] sources`
in `forge.toml`) are compiled to a shared library on first use and loaded
automatically; no `--compile` required.

The one interpreter gap is **closures/upcalls as arguments**: if a binding takes
a function-typed parameter (`fn(Int) -> Int`), the interpreter reports a clear
error and asks you to run with `--compile`. Compiled mode has no such limit.

## Native→March callbacks (upcalls)

C bindings can call back into March closures via `march_call(closure, nargs,
args)` in `march_ffi.h`. A binding that receives a function-typed argument calls
it as a plain function pointer. Args use the **native slot representation** (raw
`int64_t` for `Int`, not `march_make_int`); the return is the generic tagged word
(`march_get_int` to unpack an `Int`). Verified in `test/native/ffi_upcall`.

## Remaining limitations

- `blocking` spawns a fresh OS thread per call (no pool; fine for occasional long
  calls, not for high-frequency ones).
- Recursive and generic record/variant types have no generated codec; they fall
  back to raw `march_value` passthrough.
- `forge ffi import <header.h>` (C header → draft `extern` block) is not yet
  implemented; it needs a C-header parser (libclang).

The full ABI is documented in `runtime/march_ffi.h`; the design rationale lives
in `specs/archive/2026-06-19-c-ffi-abi-design.md` and the Rust layer in
`specs/c-ffi-rust-layer.md`.
