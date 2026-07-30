# The `march` Rust FFI layer (the Rustler analog)

**Status:** built 2026-06-21, extended 2026-06-22 — all five pieces working
end-to-end. Implements `specs/archive/2026-06-19-c-ffi-abi-design.md` §16. Supersedes
the manual `extern "C"` path documented in `specs/c-ffi-rust-manual.md` (which
still works and needs no `march` crate).

## What it is

A Rust crate that lets you bind a Rust library to March by writing **idiomatic
Rust** — no hand-written `extern "C"`, no `march_*` calls, no manual refcounting.
It rides the C ABI (`runtime/march_ffi.h`); a binding is a cargo `staticlib`
(compiled) linked through `forge.toml`'s `[ffi] link`.

```rust
use march::{march, Encoder, Decoder, Error, ResourceArc};

#[march]
fn parse(s: &str) -> Result<i64, Error> {        // decode &str (borrow), catch_unwind,
    s.trim().parse().map_err(|e| Error::msg(e.to_string()))  // encode Ok/Err
}

#[derive(Encoder, Decoder)]
struct Point { x: i64, y: i64 }                  // <-> March record (name-sorted)

#[derive(Encoder, Decoder)]
enum Shape { Circle(i64), Rect(i64, i64) }       // <-> March variant (decl-order tags)

march::init!("demo", [parse]);                   // generates the March extern block
```

## Layout

`rust/` is a cargo workspace:
- **`march`** — runtime: the `march_*` ABI (`sys`), `ToMarch`/`FromMarch`
  marshalling traits, `Error`, `ResourceArc`, and the panic/abort helpers.
- **`march-macro`** — proc-macros: `#[march]`, `#[derive(Encoder)]`,
  `#[derive(Decoder)]`, `init!`.

## The five pieces

1. **`#[march]`** generates the `#[no_mangle] pub extern "C"` shim: decode each
   argument, `catch_unwind` the body, encode the result. A `Result<T, Error>`
   return routes `Err` and panics through `march_err` (panic never crosses
   `extern "C"`); a non-`Result` panic reports via `march_fatal` and aborts.
2. **`#[derive(Encoder, Decoder)]`** implements `ToMarch`/`FromMarch` for
   structs (↔ records, via `march_make_record`/`march_record_field`) and enums
   (↔ variants, via `march_make_variant`/`march_variant_tag`/`march_variant_field`).
   Nested derives compose. `Option<f64>` uses the fully-boxed representation
   (`march_some_boxed`/`march_none_boxed`) automatically so `0.0` doesn't alias `None`.
3. **`ResourceArc<T>`** wraps a native `T` behind a March opaque `resource`; the
   registered destructor runs `Drop` on the `T` when March releases the last ref.
   The standard form dups on entry (borrow semantics). Use `ConsumeResourceArc<T>`
   when the binding should take ownership: `FromMarch` skips `march_dup` (March
   transfers its reference), and `Drop` calls `march_drop`. The generated March
   extern block emits `consume h` for these parameters.
4. **`march::init!("lib", [..])`** emits `march_print_extern_block()`, which
   prints the March `extern` block assembled from each `#[march]` signature.
5. **`forge ffi add-rust <name>`** scaffolds a binding crate and **`forge build`
   auto-runs `cargo build --release`** when `[ffi.rust] crate = "..."` is set in
   `forge.toml`, passing the resulting `.a` as `--ffi-link`. No manual build step.

## Representation (mirrors the C ABI)

`ToMarch`/`FromMarch` carry two forms: **tagged/generic** (`to_march`) for
`Result`/`Option` payloads, and **native slot** (`to_march_slot`) for top-level
args/returns and record/variant fields — `Int`/`Bool` raw in a slot, tag-encoded
as a payload. Heap types use one word for both. `f64` top-level args/returns are
passed as C `double` (the macro special-cases them).

Type mapping: `i64`→`Int`, `bool`→`Bool`, `f64`→`Float`, `String`/`&str`→
`String` (owned ⇒ `consume`), `Vec<u8>`/`&[u8]`→`Bytes`, `Error`→`String`,
`Result`/`Option`/derived structs/enums/`ResourceArc<T>` as expected.

## `forge ffi add-rust <name>` and `[ffi.rust]`

`forge ffi add-rust <name>` scaffolds a binding crate (`Cargo.toml` with
`crate-type = ["staticlib","lib"]` + `panic = "unwind"` + the `march` path dep,
a `src/lib.rs` stub, and a `gen_extern` bin) and prints the `[ffi.rust]` snippet
to add to `forge.toml`.

Once added, `forge build` runs `cargo build --release` automatically:

```toml
[ffi.rust]
crate = "native/my_binding"   # relative or absolute path to Cargo project
lib   = "my_binding"          # [lib] name; default = basename of crate path
```

Workflow: write `#[march]` fns → `cargo run --bin gen_extern` (prints the March
`extern` block) → `forge build` (cargo runs automatically, links the `.a`).

## Verification

`scripts/verify-rust-ffi.sh` cargo-builds the demo binding
(`test/native/rust_ffi/`), links it via `--ffi-link`, runs, and diffs
`app.expected` — covering `#[march]` primitives/String/`Result`, panic→`Err`,
`#[derive]` struct + enum, `ResourceArc`, `ConsumeResourceArc`, and
`Option<f64>` (`42 / HELLO / 7 / 25 / divide by zero / 33 / 75 / 24 / 41 /
Some(3.14) / None / 2.72`). It is **not** a `dune runtest` rule: it needs the
Rust toolchain, which isn't assumed in CI. Forge unit tests cover the `add-rust`
scaffolder and `init!`/codec output statically.

## Known limitations / follow-ups

- **`march` crate is path-only** — not yet published to crates.io; external
  projects reference it via a `path` dep.
- **`[[ffi.rust]]` array-of-tables** not yet supported — only one `[ffi.rust]`
  section per `forge.toml` (TOML parser limitation). Multiple Rust binding crates
  must be merged into one Cargo workspace staticlib.
- **async/tokio, generics/trait objects** can't cross — expose concrete,
  blocking wrappers (§16.4).
- **OCaml layer** — designed for in the ABI spec but not started.
