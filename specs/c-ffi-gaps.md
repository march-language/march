# C FFI — Known gaps & limitations

**Status:** living document. Tracks what the FFI does *not* yet do, as of the
end of Phase 4. Companion to the design spec (`specs/2026-06-19-c-ffi-abi-design.md`).

Phases 1–4 are done and on `main`: ABI core + primitives, strings/bytes +
Option/Result + the RC-leak gauge + borrow-default ownership, resources +
`consume`, and primitive interpreter FFI. What remains:

## Marshalling

- **Records / variants have no canonical codecs.** Only primitives (Int/Float/
  Bool/Char), `String`/`Bytes`, `Option`/`Result`, and opaque `resource`s cross
  the boundary. Passing/returning a user record or arbitrary ADT is unsupported
  (spec §6.4 "generated codecs", v1.1). Workaround: decompose into primitives or
  wrap behind a `resource`.
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

- **No `fast`/`blocking` classification.** Every extern call runs inline on the
  current scheduler thread. A long/blocking C call stalls all green threads
  multiplexed onto that scheduler thread. The `blocking` modifier + OS-thread
  pool dispatch (spec §9) is Phase 6.

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
- **No binding generators.** `forge ffi gen-c` (March `extern` → C shim skeleton)
  and `forge ffi import` (C header → draft `extern` block + `.ffi.toml` sidecar)
  are unbuilt (spec §17, Phase 7).
- **ABI version handshake not enforced.** `march_ffi_abi_version()` exists but
  nothing checks it at link/dlopen time. Only meaningful once separately-built
  binding objects exist (Phase 5).

## Other languages / direction

- **No Rust `#[march]` or OCaml binding layers** (spec §15–16). Designed for; the
  C ABI is the substrate. Future.
- **No native→March callbacks (upcalls).** Bindings cannot call back into March
  closures. Would need `march_call(env, fn, args…)` and passing closures across
  the boundary as resources (spec §19). Future.

## Unrelated pre-existing (not FFI)

- `--no-opt` builds fail to link (`_http_fetch` undefined; DCE removes the dead
  caller at `--opt`). Tracked separately.
