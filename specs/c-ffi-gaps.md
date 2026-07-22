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
  - **Field kinds — DONE for all leaf types, Options, Results, Lists, and nested
    codecs.** The generated mirror fully types `Int`/`Bool` (raw `int64_t`),
    `Float` (`double`), `String`/`Bytes` (`march_slice`), nested records/variants,
    `Option(T)`/`Result(T,E)` fields with any supported payload (including
    `Float`/`Unit` via boxed codecs — `Option_Float_c` fully boxed,
    `Option_Unit_c` mixed niche — and nested record/variant types via niche-safe
    heap-ptr path), and `List(T)` fields as malloc-owned C arrays (`List_T_c`
    with decode via `march_list_length` + spine traversal, encode via reverse-loop
    `march_list_cons`). Topo ordering recurses into type args so `Option(Point)`
    emits `Point_c` before `Option_Point_c`. `march_list_nil`/`cons`/`length`/`nth`
    added to the ABI. Verified: `test/native/ffi_optres`, `test/native/ffi_codec2`.
    Still passed through as raw `march_value`: `resource` fields.
  - **Recursive types** (reachable from themselves) and **generic** record/
    variant types get no generated codec — a by-value mirror can't represent
    them; they fall back to the `march_value` passthrough.
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

## Interpreter

- **Interpreter FFI marshal layer — DONE (2026-06-22).** Under `march file.march`
  (tree-walking, no `--compile`), the full type-directed marshal layer is now in
  place. Supported: Int/Bool (raw GP), Float args (FP register bank via mixed
  `dyncall_fi`/`dyncall_fd` trampolines), String/Bytes (heap-allocated via
  `march_str_new`/`march_bytes_new`, dropped after call), `Option(T)` /
  `Result(T,E)` (niche + boxed representations), `raises` externs (malloc'd
  `march_env` sentinel prepended as GP arg), variant args/returns (tag + field
  slots), record args/returns (shape-descriptor-keyed). `ffi_type_decl_tbl` maps
  type name → type_def for marshal-layer lookup. `lib/eval/ffi_marshal.c` +
  `ffi_marshal.ml` provide OCaml C stubs (lazy-init from `RTLD_DEFAULT` after the
  runtime `.so` is `RTLD_GLOBAL`-loaded). `test/native/ffi_interp2` verifies
  end-to-end. GP arg arity cap raised to 8 (was 6). Remaining interpreter gap:
  - **User [ffi] shims — DONE (2026-06-22, Gap 1).** The interpreter now compiles
    `[ffi] sources = [...]` from forge.toml (passed as `--ffi-c` flags) into a
    content-addressed temp `.so` at `~/.cache/march/march_ffi_shim_<hash>.so` and
    dlopens it via `march_eval_dlopen_extra` (with `RTLD_GLOBAL` so runtime symbols
    are visible to the shim).  Symbol lookup falls back to `RTLD_DEFAULT` after the
    runtime handle, so both runtime and shim symbols are found.  A `--ffi-so <path>`
    CLI flag lets callers pass a pre-compiled `.so` directly.  On macOS, `-undefined
    dynamic_lookup` is passed to the shim compile so runtime symbols are resolved
    lazily at dlopen time.  Verified by `test/native/ffi_interp_shim`.
  - **Closures/upcalls as arguments** (`TyArrow` param types) emit a clean
    actionable error: "interpreter FFI cannot marshal … closures/upcalls not yet
    supported. Run with --compile." rather than crashing or producing wrong results.
    The fundamental limitation: the compiled path's `march_call` reads a C function
    pointer at a fixed offset in the closure heap object; the interpreter's
    `VClosure` values have no such pointer.  Full upcall support would require
    JIT-allocated trampolines (libffi closures or mmap'd machine code) to create
    real C function pointers for OCaml closures — out of scope for this phase.
    Verified: `test/native/ffi_interp_upcall.march` demonstrates the clean error
    (`test/native/ffi_interp_upcall.expected`).
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
  doc: `specs/c-ffi-rust-layer.md`. Remaining gaps closed:
  - **`f64` inside `Option`/fields — DONE.** `Option<f64>` uses the fully-boxed
    path (`march_some_boxed`/`march_none_boxed`, matched by cell tag) not the niche
    form. `sys.rs` declares the two boxed constructors. `value.rs` adds
    `encode_option_f64`/`decode_option_f64` helpers. `#[march]` and
    `#[derive(Encoder/Decoder)]` detect `Option<f64>` and call these helpers
    instead of the generic `ToMarch`/`FromMarch` blanket impls. Verified in
    `test/native/rust_ffi/` (`maybe_float`, `unwrap_float_or`).
  - **`ConsumeResourceArc<T>` — DONE.** A consume-mode resource handle that does
    NOT `march_dup` on `FromMarch` (March transfers ownership); `Drop` calls
    `march_drop`. The `#[march]` macro detects `ConsumeResourceArc` params and
    emits `consume h` in the generated extern block. Verified in
    `test/native/rust_ffi/` (`counter_finish`).
  - **Auto `cargo build --release` in `forge build` — DONE.** `forge.toml`
    `[ffi.rust] crate = "<path>" lib = "<name>"` causes `forge build` to
    auto-run `cargo build --release` in the crate directory and pass the
    resulting `target/release/lib<name>.a` as `--ffi-link`. `forge ffi add-rust`
    prints the `[ffi.rust]` snippet in its next-steps guidance.
  Still open: publishing the `march` crate (path-only), `[[ffi.rust]]`
  (multiple Rust crates — the TOML parser doesn't support array-of-tables),
  and the OCaml layer (still future).
- **Native→March upcalls — DONE.** `march_call(closure, nargs, args)` in the
  ABI — bindings receive March closures as function-typed extern params and call
  back into them. Args use NATIVE SLOT REP (raw machine int for Int, NOT
  `march_make_int`); return is the generic tagged word (`march_get_int` to
  unpack). Verified: `ffi_apply1`/`ffi_count_matching` → `test/native/ffi_upcall`
  → 42/5.

## Unrelated pre-existing (not FFI)

- **FIXED.** `_http_fetch`/`_http_fetch_available` undefined at link time —
  reproduced at every `--opt` level (not just `--no-opt`; `http_fetch_available()`
  is a real runtime call, not a compile-time constant, so DCE can never prove
  the guarded `http_fetch` call in `HttpTransport.request` dead). Root cause:
  neither name had a typecheck builtin binding, so the call sites fell through
  `llvm_emit`'s generic "unresolved global -> declare + call extern C symbol of
  the same name" path with no matching C symbol. Fixed by registering both in
  `typecheck.ml`'s `builtin_bindings` (`http_fetch_available : Bool`,
  `http_fetch : String -> String -> String -> String -> Result(String, String)`)
  and adding native stub implementations in `runtime/march_http.c`
  (`http_fetch_available` always returns raw-Bool `false`; `http_fetch` returns
  an `Err(...)` that's unreachable in practice since the native call site never
  takes the `http_fetch_available()` branch — native requests go through the
  `tcp_*` socket path instead).
