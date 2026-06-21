# C FFI — Known gaps & limitations

**Status:** living document. Tracks what the FFI does *not* yet do, as of the
end of Phase 4. Companion to the design spec (`specs/2026-06-19-c-ffi-abi-design.md`).

Phases 1–4 are done and on `main`: ABI core + primitives, strings/bytes +
Option/Result + the RC-leak gauge + borrow-default ownership, resources +
`consume`, and primitive interpreter FFI. What remains:

## Marshalling

- **Records / variants — primitive codecs DONE (Phase 9); type-directed
  generated codecs still open.** `march_variant_tag`/`variant_field`/
  `record_field` (read) and `march_make_variant`/`make_record` (construct) move
  ADTs and records across the boundary; a binding builds/reads them by hand
  (`test/native/ffi_variant`). The accessors move a field *slot* verbatim, so the
  binding must marshal each field in March's **native per-field representation**:
  `Int`/`Bool` raw (NOT a tagged value word), `Float` raw bits, `String`/heap as
  the value word. What's still missing (spec §6.4 "generated codecs", v1.1): the
  *type-directed* layer that hides this per-field marshalling — i.e.
  auto-generated encode/decode from a March type so the author never touches
  slots. That's the prerequisite for Rust `#[derive(Encoder/Decoder)]`. Records
  built this way are constructed in canonical (name-sorted) field order; nested
  aggregates and `Float`/heap fields work but are the author's responsibility to
  marshal correctly.
- **`Option(Float)` / `Option(Unit)` returns are unsupported by the bare
  constructors.** `march_some`/`march_none` emit the P6 *niche* form (`Some(x)=x`,
  `None=0`), correct only for niche-eligible payloads (Int/Bool/String/heap).
  Float/Unit Options stay boxed in the compiler and would need a kind-aware
  boxed constructor. `Result` is unaffected (always boxed).
- **No `raw` zero-copy escape hatch** (spec §7). All structured values go through
  the copy/borrow paths; there's no opt-in to hand a binding the raw
  `march_value` with author-managed RC. (Phase 8.)

## Errors

- **No env-routed `march_raise`.** Fallible bindings return `Result` by building
  `march_ok`/`march_err` directly (works, tested). The spec's `march_env` +
  `march_raise(env, e)` convenience — `return` normally and raise out-of-band —
  is not implemented. It needs the `march_env` parameter threaded through the
  generated wrapper.
- **Panic/longjmp safety is by convention only.** A C binding that `longjmp`s or
  segfaults across the boundary corrupts/aborts the process — inherent to
  in-process C FFI. The Rust `#[march]` layer (future) will `catch_unwind`.

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
- **Binding generators — `gen-c` DONE (Phase 7), `import` deferred.**
  `forge ffi gen-c <file.march>` generates a compilable C shim skeleton from the
  `extern` blocks (correct signatures, String/Bytes borrow slices, resource-get
  + `consume`-drop hints, typed Option/Result/String return stubs, TODO for the
  call). `forge ffi import <header.h>` (C header → draft `extern` + `.ffi.toml`)
  is still unbuilt — it needs a C-header parser (libclang), a heavier dependency.
- **ABI version handshake not enforced.** `march_ffi_abi_version()` exists but
  nothing checks it at link/dlopen time. Only meaningful once separately-built
  binding objects exist (Phase 5).

## Other languages / direction

- **Rust: the manual C-ABI path works today; the ergonomic `#[march]` layer is
  future.** A Rust `staticlib` crate with `extern "C"` functions that call the
  `march_*` ABI binds cleanly through `forge.toml`'s `[ffi] link` — proven and
  documented in `specs/c-ffi-rust-manual.md` (a real cargo crate: `add`/`shout`/
  `parse` round-trip via March, both Result arms). Still missing: the `march`
  crate (`#[march]`, `#[derive(Encoder/Decoder)]`, `ResourceArc`, panic→Err) and
  `forge add-rust` / `[[ffi.rust]]` cargo integration. The OCaml layer is also
  future. (Record/variant *primitives* now cross the boundary — Phase 9; the
  `#[derive]` codecs still need the type-directed generated-codec layer.)
- **No native→March callbacks (upcalls).** Bindings cannot call back into March
  closures. Would need `march_call(env, fn, args…)` and passing closures across
  the boundary as resources (spec §19). Future.

## Unrelated pre-existing (not FFI)

- `--no-opt` builds fail to link (`_http_fetch` undefined; DCE removes the dead
  caller at `--opt`). Tracked separately.
