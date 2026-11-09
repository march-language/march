---
layout: docs
title: Foreign Function Interface
nav_order: 19
permalink: /docs/ffi/
---

# Foreign Function Interface (FFI)

The FFI lets March call native code. You declare the foreign functions in an `extern`
block with their March types, write or generate a thin C shim against
`runtime/march_ffi.h`, and list the shim in `forge.toml`. Rust crates bind through the
`march` crate, which goes through the same C ABI. The design follows BEAM's
`erl_nif.h`.

Ownership crosses the boundary checked. Each heap argument is either borrowed (March
keeps it and frees it after the call) or consumed (ownership moves into the binding),
and the compiler adjusts the reference counts for you. The common case needs no manual
`march_dup` or `march_drop`, so it cannot leak or double-free.

C code is outside everything the compiler checks, so calling it is a capability: a
module with an `extern` block declares `needs IO.Foreign`, and `main` has to grant it.
This page covers writing a binding first, then generating the glue, building and
linking, and running under the interpreter.

## On this page

**Start here**

- [Which form do I need?](#which-form-do-i-need)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)

**Writing a binding**

- [Declaring externs](#declaring-externs)
- [Marshalling tiers](#marshalling-tiers): how each March type crosses
- [Ownership: `borrow` vs `consume`](#ownership-borrow-vs-consume)
- [Returning errors: `raises`](#returning-errors-raises)
- [`blocking`](#blocking)
- [Native→March callbacks (upcalls)](#nativemarch-callbacks-upcalls)

**Generating and building**

- [Generating the C glue](#generating-the-c-glue)
- [Binding a Rust crate](#binding-a-rust-crate)
- [Building & linking](#building--linking)
- [Interpreter mode](#interpreter-mode)

**Reference**

- [Remaining limitations](#remaining-limitations)
- [Errors you'll see](#errors-youll-see)
- [See also](#see-also)

## Which form do I need?

| You want | Write |
|---|---|
| To call a C function | An `extern "lib" : Cap(Ffi) do ... end` block in a module that `needs IO.Foreign` |
| A March name that differs from the C symbol | `fn name(...) : T = "c_symbol"` |
| The binding to keep a heap argument | `consume` before the parameter |
| A C function that can fail | Return `Result(T, E)`, and mark it `raises` to fail with `march_raise` |
| A long C call that must not stall other green threads | `blocking fn ...`, plus `needs IO.Foreign.Blocking` |
| A native handle March frees for you | A `resource` type; `ResourceArc<T>` from Rust |
| The C shim written for you | `forge ffi gen-c file.march` |
| A Rust crate | `#[march]` functions and `march::init!`; `forge ffi add-rust name` to start one |
| The shim compiled and linked by `forge build` | `[ffi]` (or `[ffi.rust]`) in `forge.toml` |

## How it fits with the rest of March

| Concept | Where the FFI meets it | Chapter |
|---|---|---|
| **Capabilities** | An `extern` block needs `IO.Foreign`, a `blocking` one `IO.Foreign.Blocking`; `cap no_extern` forbids both in a module. | [Capabilities]({{ site.baseurl }}/docs/capabilities/#ioforeign--calling-unverified-c) |
| **Linear types** | `resource` and `consume` make ownership moving across the C boundary explicit, so a handle cannot be freed twice. | [Linear Types]({{ site.baseurl }}/docs/linear-types/#ffi-and-native-resources) |
| **Memory model** | Arguments are borrowed or consumed under Perceus reference counting; naming a small scalar aggregate in an `extern` signature puts it back on the heap. | [Memory Model]({{ site.baseurl }}/docs/memory-model/) |
| **Type system** | Values cross by their static type: `Option`, `Result`, records and variants each have a C form. | [Type System]({{ site.baseurl }}/docs/types/) |
| **Threat model** | C code reached through `extern` is not analysed; the threat model says what that leaves open. | [Capability Threat Model]({{ site.baseurl }}/docs/capability-threat-model/#foreign-code-ioforeign) |
| **Tooling** | `forge ffi gen-c` and `forge ffi add-rust` write the glue; `forge build` compiles and links it. | [Tooling]({{ site.baseurl }}/docs/tooling/) |

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

  fn main(_console : Cap(IO.Console), _foreign : Cap(IO.Foreign)) : Unit do
    println(int_to_string(add(2, 3)))    -- 5
    println(shout("hi"))                  -- HI
  end
end
```

The `= "symbol"` gives the exact C symbol; omit it and the default is
`<lib>_<fn>`. Any module with an `extern` block needs the `IO.Foreign`
[capability]({{ site.baseurl }}/docs/capabilities/#ioforeign--calling-unverified-c)
(and `IO.Foreign.Blocking` if any function is `blocking`), and `main` grants it like
any other capability: here `Cap(IO.Foreign)` beside `Cap(IO.Console)`. Leaving out
`needs IO.Foreign` is an error (`extern_needs_foreign`; it was a warning before
2026-11-06), and so is leaving out the grant on `main`.

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

**Small scalar aggregates keep their heap representation across the FFI.** A
one-constructor variant of two to four `Int`/`Float`/`Bool` fields (`Vec3(Float,
Float, Float)`) is normally represented inline, in registers, with no heap cell
at all — see [Memory Model]({{ site.baseurl }}/docs/memory-model/), "Small
scalar aggregates never reach the heap at all". Naming such a type anywhere in
an `extern` signature turns that off **for the whole program**: the type goes
back to being an ordinary heap value, so the C side sees exactly the cell the
generated `march_decode_T`/`march_encode_T` codecs were written against and
your bindings need no change. Nothing is rejected and nothing is marshalled
differently; the only consequence is that the type loses the inline
representation everywhere it is used, which matters if it is also on a hot path
elsewhere. If that trade is wrong for your program, pass the fields
individually (`fn f(x: Float, y: Float, z: Float)`) and keep the aggregate on
the March side of the boundary.

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

## Returning errors: `raises`

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

## Native→March callbacks (upcalls)

C bindings can call back into March closures via `march_call(closure, nargs,
args)` in `march_ffi.h`. A binding that receives a function-typed argument calls
it as a plain function pointer. Args use the **native slot representation** (raw
`int64_t` for `Int`, not `march_make_int`); the return is the generic tagged word
(`march_get_int` to unpack an `Int`).

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

A project that binds several native libraries declares one table per library
with `[[ffi]]` (and `[[ffi.rust]]` for several crates). forge uses every
table, in the order they appear:

```toml
[[ffi]]
sources = ["native/zip_shim.c"]
link    = ["-lz"]

[[ffi]]
sources = ["native/db_shim.c"]
link    = ["-lsqlite3"]
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

`[ffi.rust]` crates work under the interpreter too, with or without
`[ffi] sources`. Cargo builds a static `.a`, which cannot be loaded directly, so
the compiler links every static archive passed with `--ffi-link` whole into the
interpreter's shim library (`-Wl,-force_load` on macOS, `--whole-archive` on
Linux; an empty stub stands in when there are no C sources). The shim is cached
by the archive's contents, so rebuilding the crate rebuilds the shim. The same
holds for any prebuilt `lib<name>.a` you pass with `--ffi-link`.

The interpreter has one gap: **closures/upcalls as arguments**. If a binding
takes a function-typed parameter (`fn(Int) -> Int`), the interpreter reports a
clear error and asks you to run with `--compile`. Compiled mode has no such
limit.

---

## Remaining limitations

- `blocking` spawns a fresh OS thread per call (no pool; fine for occasional long
  calls, not for high-frequency ones).
- Recursive and generic record/variant types have no generated codec; they fall
  back to raw `march_value` passthrough.
- `forge ffi import <header.h>` (C header → draft `extern` block) is not yet
  implemented; it needs a C-header parser (libclang).

---

## Errors you'll see

The [Error Messages tour]({{ site.baseurl }}/docs/error-messages/) walks through the capability errors an `extern` block can raise, each with a program you can edit and re-check in the browser:

- [`main` with no grant for a capability the program reaches]({{ site.baseurl }}/docs/error-messages/#main-no-grant)
- [A function that uses a capability its module's `needs` lines leave out]({{ site.baseurl }}/docs/error-messages/#missing-needs)

These codes have their own page, the same text `march --explain` prints:

- [`cap_grant`]({{ site.baseurl }}/docs/errors/cap_grant/): `main` reaches `IO.Foreign` but declares no grant
- [`cap_needs`]({{ site.baseurl }}/docs/errors/cap_needs/): a module uses `Cap(Ffi)` without `needs Ffi`

A function-typed argument under the interpreter is a run-time error that asks you to
compile instead; see [Interpreter mode](#interpreter-mode).

---

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/#ioforeign--calling-unverified-c): `IO.Foreign`, `IO.Foreign.Blocking` and `cap no_extern`
- [Linear Types]({{ site.baseurl }}/docs/linear-types/#ffi-and-native-resources): `resource` and `consume` for native handles
- [Memory Model]({{ site.baseurl }}/docs/memory-model/): the reference counting the ownership rules plug into
- [Capability Threat Model]({{ site.baseurl }}/docs/capability-threat-model/#foreign-code-ioforeign): what C code can still do
- `runtime/march_ffi.h`: the full C ABI
- `specs/archive/2026-06-19-c-ffi-abi-design.md` and `specs/c-ffi-rust-layer.md`: the design rationale for the C ABI and the Rust layer
