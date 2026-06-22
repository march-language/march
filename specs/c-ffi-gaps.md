# C FFI — Known gaps & limitations

**Status:** living document. Tracks what the FFI does *not* yet do, as of the
end of Phase 4. Companion to the design spec (`specs/2026-06-19-c-ffi-abi-design.md`).

Phases 1–4 are done and on `main`: ABI core + primitives, strings/bytes +
Option/Result + the RC-leak gauge + borrow-default ownership, resources +
`consume`, and primitive interpreter FFI. What remains:

## Marshalling

- **Records / variants — codecs DONE for C (Phase 9 accessors + type-directed
  generators).** `march_variant_tag`/`variant_field`/`record_field` +
  `march_make_variant`/`make_record` move ADTs/records across the boundary
  (`test/native/ffi_variant`), and `forge ffi gen-c` now *generates* repr-C
  mirror structs + `march_decode_T`/`march_encode_T` so the author works with
  plain C structs, never touching slots (`test/native/ffi_codec`, spec §6.4).
  Remaining sub-gaps:
  - **Field kinds beyond the typed set are passed through as raw `march_value`.**
    The generated mirror fully types `Int`/`Bool` (raw `int64_t`), `Float`
    (`double`), `String`/`Bytes` (`march_slice`), and nested records/variants;
    `Option`/`Result`/`resource`/`List` fields are exposed as the raw
    `march_value` (author uses `march_some`/`ok`/`err`/`march_resource_get` +
    accessors). Fully-typed `Option`/`Result` field decoding is future.
  - **Recursive types** (reachable from themselves) and **generic** record/
    variant types get no generated codec — a by-value mirror can't represent
    them; they fall back to the `march_value` passthrough.
  - **No List-copy** (§6.6): `List(T)` ⇄ C array+length is unbuilt.
  - **Rust `#[derive(Encoder/Decoder)]`** — the Rust analog of these codecs — is
    the next follow-on; it reuses this exact ABI.
- **`Option(Float)` / `Option(Unit)` returns — DONE** via `march_some_boxed` /
  `march_none_boxed`. The bare `march_some`/`march_none` are the niche form
  (`Some(x)=x`, `None=0`), correct only for niche-eligible payloads. A 0-bit
  payload (`0.0` / unit) aliases `None=0`, so those use the boxed path — and the
  compiler is asymmetric here, matched empirically: **`Option(Float)`** is fully
  boxed (`Some`=`march_some_boxed(march_make_float(f))`, `None`=`march_none_boxed()`,
  matched by cell tag); **`Option(Unit)`** uses boxed `Some` + niche `None`
  (`march_some_boxed(0)` / `march_none()`, matched by null-check). `gen-c` emits
  the right variant per payload type. Verified: `test/native/ffi_float`.
- **No `raw` zero-copy escape hatch** (spec §7). All structured values go through
  the copy/borrow paths; there's no opt-in to hand a binding the raw
  `march_value` with author-managed RC. (Phase 8.)

## Errors

- **Env-routed `march_raise` — DONE.** An extern declared `raises fn … :
  Result(T, E)` gets a hidden `march_env *` first param; the binding returns the
  bare Ok payload (T's natural C type) and calls `march_raise(env, e)` to fail,
  and the compiler-emitted call-site wrapper materializes `Ok(payload)` /
  `Err(e)` (`test/native/ffi_raise`, `gen-c` emits the `march_env*` signature).
  The self-build path (`march_ok`/`march_err` directly, no `raises`) still works.
  `Result(Float, _)` Ok payloads now work too (the wrapper boxes the bare
  `double` via `march_make_float`; `test/native/ffi_float`). Remaining sub-gap:
  `march_env` is threaded only for `raises` bindings (the spec's
  env-for-all-allocating-bindings + `march_str_new(env, …)` is not retrofitted —
  the env-less constructors stay).
- **Panic/longjmp safety is by convention only.** A C binding that `longjmp`s or
  segfaults across the boundary corrupts/aborts the process — inherent to
  in-process C FFI. The Rust `#[march]` layer (future) will `catch_unwind` →
  `march_raise` (the `raises` ABI is the exact hook).

## Interpreter (Phase 4 scope)

- **Interpreter FFI is primitives-only.** Under `march file.march` (tree-walking,
  no `--compile`): **Int/Bool arguments and Int/Bool/Float returns** only, via a
  fixed-arity GP-register trampoline (no libffi). Unsupported interpreter-side,
  with a clear *"run with `--compile`"* error:
  - **Float as an *argument*** — the trampoline passes args in GP registers; FP
    args need FP registers (would need libffi or per-signature stubs).
  - **String/Bytes, Option/Result, records, resources** — the interpreter's
    value representation (`VInt`/`VString`/…) differs from the compiled heap
    layout, so there's no marshalling for them yet.
  - Arity is capped at 6 arguments (trampoline cases).
  Compiled mode and the JIT have none of these limits.

## Scheduler

- **`blocking` dispatch — DONE (Phase 6), with caveats.** `blocking fn` runs the
  C call on a dedicated OS thread while the green thread cooperatively yields, so
  other green threads keep running. Remaining sub-gaps:
  - **No thread pool.** A fresh `pthread` is spawned + joined per blocking call
    (fine for occasional long calls; not for high-frequency ones).
  - **Poll, not park.** The waiting green thread loops on `march_sched_yield`;
    outside a scheduler context that yield is a no-op, so the loop busy-spins
    until the call finishes (a true park/wake would be better).
  - **Arg/return scope** matches the trampoline: Int/Bool/pointer args + Int/
    Bool/Float returns; float-as-argument is a compile error for `blocking`.
  - `fast` is the implicit default (no keyword); there's no explicit `fast`.

## Tooling / build

- **`forge [ffi]` build integration — DONE (Phase 5).** `forge.toml`:
  `[ffi] sources = ["native/x.c"]` + `link = ["-lz"]` → compiled+linked via the
  compiler's `--ffi-c`/`--ffi-link`; shim edits invalidate the CAS binary cache.
  Remaining sub-gaps:
  - **Single `[ffi]` section only.** No named `[[ffi]]` array-of-tables for
    multiple independent binding libs yet (the TOML parser doesn't support
    array-of-tables cleanly). One project-wide list of sources/link flags.
  - **User shims are compiled-mode only.** The interpreter (Phase 4) dlopens
    only the runtime `.so`, so a symbol from a `[ffi]` shim isn't resolvable
    under `march file.march` — only via `--compile`. (Interpreter FFI still
    works for symbols that live in the runtime itself.)
- **Binding generators — `gen-c` DONE (Phase 7) incl. type-directed codecs,
  `import` deferred.** `forge ffi gen-c <file.march>` generates a compilable C
  shim skeleton from the `extern` blocks (correct signatures, String/Bytes borrow
  slices, resource-get + `consume`-drop hints, typed Option/Result/String return
  stubs, TODO for the call) AND repr-C mirror structs + `march_decode_T`/
  `march_encode_T` for every record/variant type reachable from a signature
  (§6.4), wiring shim bodies to decode params / encode returns. `forge ffi import
  <header.h>` (C header → draft `extern` + `.ffi.toml`) is still unbuilt — it
  needs a C-header parser (libclang), a heavier dependency.
- **ABI version handshake — enforced at interpreter dlopen** (spec §4.1). When
  the interpreter dlopens the runtime `.so`, it dlsyms + calls
  `march_ffi_abi_version()` and rejects a mismatch with a clear error (a
  stale/foreign `.so` fails loudly instead of corrupting at a later call;
  `lib/eval/eval.ml` `_ffi_get_handle`). The **compiled path** is
  version-consistent by construction (the runtime is compiled fresh from the
  same `march_ffi.h` into every binary). Remaining: a *pre-built external*
  binding (e.g. a Rust staticlib built against a different `march_ffi.h`) doesn't
  export its own version symbol, so a compiled-path cross-version skew isn't
  caught — would need the binding to export `__march_binding_abi_version` + a
  startup check (low priority; no such artifacts ship yet).

## Other languages / direction

- **Rust: the ergonomic `march` crate — DONE.** `rust/march` (+ `rust/march-macro`)
  is the Rustler analog: `#[march]` generates the `extern "C"` shim
  (decode → `catch_unwind` → encode; `Result` routes `Err`/panic via `march_err`),
  `#[derive(Encoder, Decoder)]` marshals structs↔records / enums↔variants,
  `ResourceArc<T>` wraps native state behind a March resource, and `march::init!`
  generates the March extern block. `forge ffi add-rust <name>` scaffolds a
  binding crate. Proven end-to-end (`scripts/verify-rust-ffi.sh`,
  `test/native/rust_ffi/`). The manual `extern "C"` path
  (`specs/c-ffi-rust-manual.md`) still works for zero-extra-crate bindings. Full
  doc: `specs/c-ffi-rust-layer.md`. Remaining: `f64` inside `Result`/`Option`/
  fields (top-level f64 works), a `consume`-and-free `ResourceArc` mode (the
  borrow/net-zero mode ships; consume would leak a ref), auto cargo build +
  extern-block generation inside `forge build` (manual today), publishing the
  `march` crate (path-only), and `[[ffi.rust]]`. The OCaml layer is still future.
- **No native→March callbacks (upcalls).** Bindings cannot call back into March
  closures. Would need `march_call(env, fn, args…)` and passing closures across
  the boundary as resources (spec §19). Future.

## Unrelated pre-existing (not FFI)

- `--no-opt` builds fail to link (`_http_fetch` undefined; DCE removes the dead
  caller at `--opt`). Tracked separately.
