# WebAssembly Target

## Status: Not Started (Assessment Only)

## Overview

March's LLVM IR codegen (`lib/tir/llvm_emit.ml`) produces textual LLVM IR and shells out to `clang` for native compilation. This architecture makes WASM a natural second target — LLVM already knows how to emit WASM, so the codegen layer needs minimal changes. The real effort is in porting the C runtime.

## What changes in the compiler

### llvm_emit.ml

- Parameterize target triple (currently hardcoded `arm64-apple-macosx15.0.0`) to emit `wasm32-wasi` or `wasm64-wasi`.
- Pointer size: current object layout assumes 8-byte pointers. WASM32 uses 4-byte pointers, so either parameterize `ptr_size` throughout emission or target wasm64 (less ecosystem support but fewer changes).
- Add `--target wasm32-wasi --sysroot=<wasi-sdk>` to the clang invocation path.

### CLI

- New flag: `--target wasm` (or `--target wasm32-wasi` / `--target wasm64-wasi`).
- Output `.wasm` instead of native binary.

## Runtime porting

The C runtime (`runtime/march_runtime.c` ~2,000 lines, `runtime/march_http.c` ~1,500 lines) is heavily POSIX. Each subsystem has different WASM readiness:

| Subsystem | Files | WASM impact | Effort |
|-----------|-------|-------------|--------|
| Allocation (calloc/free) | march_runtime.c | Works via wasi-libc linear memory | Low |
| Atomic RC (`_Atomic int64_t`) | march_runtime.c | Degrades to plain ops in single-threaded WASM; correct | Low |
| Math (sin, cos, sqrt, …) | march_runtime.c | Works via wasi-libc | Low |
| Strings | march_runtime.c | Pure memory ops; works | Low |
| Ord/Hash (splitmix64, FNV-1a) | march_runtime.c | Pure compute; works | Low |
| File I/O (open, read, write, stat) | march_runtime.c | Partially supported via WASI `fd_*` calls | Medium |
| pthreads (actors, scheduler) | march_runtime.c | No threads in core WASM; WASI-threads experimental | High |
| Networking (TCP, HTTP, WebSocket) | march_http.c | No sockets in WASM; WASI networking is phase-2 proposal | High |
| Capabilities & supervision | march_runtime.c | Depends on actor system | High |
| dlopen/dlsym (JIT/REPL) | jit_stubs.c | Not applicable; JIT doesn't make sense in WASM | N/A |

## Implementation tiers

### Tier 1 — Pure compute (~1 week)

Get pure functional March programs compiling to WASM. No actors, no networking, no file I/O.

- Parameterize target triple in `llvm_emit.ml`.
- Compile runtime with wasi-sdk (`clang --target=wasm32-wasi --sysroot=…`).
- `#ifdef` out pthreads, networking, file ops (or provide stubs that panic).
- Fix pointer-size assumptions or use wasm64.
- Test with `wasmtime` / `wasmer`.

What works: arithmetic, strings, closures, pattern matching, variants, records, Perceus RC, TCO, all pure stdlib.

### Tier 2 — WASI CLI programs (~2–3 weeks)

Add file I/O, stdin/stdout, command-line args via WASI preview 2.

- Implement WASI-compatible file operations in runtime.
- Map `march_print` / `march_println` to WASI fd_write on stdout.
- CSV module works (file-based).
- March programs can be useful CLI tools running in Wasmtime.

### Tier 3 — Actors in WASM (~4–6 weeks)

Actor concurrency is the hard problem. Options:

1. **Cooperative single-threaded scheduler** — rewrite actor `march_spawn` to use coroutine-style cooperative multitasking on one thread. No real parallelism but preserves the programming model. Closest to what Erlang's BEAM does (M:N scheduling) but with M=1.
2. **WASI-threads** — experimental extension; not widely supported yet. Would allow closer parity with native but ties March to bleeding-edge runtimes.
3. **Web Workers (browser only)** — each actor maps to a Worker with `postMessage` for send/receive. Browser-specific; doesn't help server-side WASM.

Recommendation: option 1 (cooperative scheduler) is the most portable and aligns with March's actor semantics. Real parallelism can come later when WASI-threads stabilizes.

### Tier 4 — Browser target (additional ~2–3 weeks on top of Tier 1–3)

- Emit JS glue code for imports/exports.
- DOM interop via extern declarations.
- Asset pipeline (`.wasm` + `.js` loader).
- This is a separate effort from WASI and would likely need a `--target wasm32-unknown-unknown` path.

## Dependencies

- **wasi-sdk** — provides clang cross-compilation toolchain and wasi-libc.
- **wasmtime** or **wasmer** — for running/testing WASI binaries.
- No changes needed to the March language, parser, typechecker, TIR, or optimization passes.

## Key risk: pointer size

The object layout in `llvm_emit.ml` uses a 16-byte heap header (8B RC + 4B tag + 4B pad) and 8B-per-field slots. On wasm32, pointers are 4 bytes. Two options:

1. **Target wasm64** — keeps all sizes identical, but wasm64 has limited runtime support (Wasmtime supports it; browsers do not yet).
2. **Parameterize layout** — add a `target_ptr_size` to the codegen context and compute offsets dynamically. More work upfront, but future-proofs for any target.

## Recommendation

Start with **Tier 1** targeting **wasm64-wasi** to minimize codegen changes. This gets pure March programs running in Wasmtime with ~1 week of effort and validates the pipeline end-to-end. Port to wasm32 later when browser support matters.
