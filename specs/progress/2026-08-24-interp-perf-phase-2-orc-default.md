# Interpreter/REPL JIT performance, Phase 2: ORC becomes the default REPL backend

Closes Phase 2 of `.superpowers/sdd/2026-08-23-interpreter-and-repl-jit-performance/`.

## Summary

The REPL JIT gained an in-process LLVM ORC backend (`MARCH_JIT_BACKEND=orc`)
that compiles each fragment directly into a shared `LLJIT` instead of
shelling out to `clang` + `dlopen`-ing a fresh `.so` per line. Phase 2 made
ORC the *default* backend (auto-detected via a libLLVM availability probe,
with `clang` as the fallback and an explicit env-var escape hatch), fixed a
SIGSEGV that blocked flipping the default, added a parity test group over
optimisation-sensitive shapes, and closes with this task: hide ORC's
one-time libLLVM-load cost behind REPL startup, and evaluate (and reject) an
IR-level optimisation pass pipeline.

## 1. Availability probe + default flip

`Repl_jit.resolve_backend` (`lib/jit/repl_jit.ml`) resolves the backend
lazily, on first use, in this order:

1. `MARCH_JIT_BACKEND=orc` / `=clang` — explicit override wins.
2. Any other value — falls back to `clang` (66dec977), not a hard error, so a
   typo doesn't crash the REPL.
3. Unset — `Jit_orc.available ()` probes for libLLVM (dlopen with
   `RTLD_GLOBAL`, no side effects on failure) and picks `orc` if found, else
   `clang`.

Resolution is intentionally lazy: `march --compile` and other non-JIT entry
points never call `Jit_orc.available ()` and never dlopen libLLVM, so the
compile-only path pays zero cost for this feature existing.

## 2. SIGSEGV root cause (ad4c168c)

Flipping the default to ORC was blocked by a crash: defining a second REPL
`fn` after any prior `fn` binding crashed the whole REPL with SIGSEGV (exit
139). Full root-cause writeup:
`specs/progress/2026-08-24-orc-repl-segfault-fn-def-after-let-lambda.md`.

Two stacked defects, both required to explain "crash, not an error":

1. **Duplicate external symbol across fragments** — `lib/tir/llvm_repl.ml`'s
   prev-slot loader functions were emitted at *module* (i.e. process-wide,
   under ORC) linkage, named after the bare binding. A second `fn` fragment's
   loader for a REPL-bound function collided with that function's own
   top-level definition from an earlier fragment. Invisible under `clang`
   (each fragment is its own `.so`, so a local symbol wins inside it);
   ORC's single shared `JITDylib` makes it a hard `addIRModule` error.
2. **Double-free on the ORC add-module error path** — `jit_orc_stubs.c`
   called `LLVMOrcDisposeThreadSafeModule(TSM)` on the error branch of
   `LLVMOrcLLJITAddLLVMIRModule`, but that C API function *unconditionally*
   consumes and destroys `TSM` on return (success or failure). The explicit
   dispose re-ran `~ThreadSafeModule` on already-freed memory, which
   SIGSEGV'd inside a destroyed mutex — turning defect (1)'s recoverable
   "duplicate symbol" error into a process-killing crash with no diagnostic.

Fix: give prev-slot loaders `internal` linkage (never enters the JITDylib
symbol table, so neither fn-vs-loader nor loader-vs-loader collisions can
arise), and drop the erroneous double-dispose so recoverable ORC errors are
now reported instead of fatal.

## 3. Default + fallback contract

- Default (unset `MARCH_JIT_BACKEND`): ORC if libLLVM is found, else clang —
  existing REPL behaviour is preserved bit-for-bit when libLLVM isn't
  installed.
- `MARCH_JIT_BACKEND=clang`: force the pre-Phase-2 subprocess-clang backend.
- `MARCH_JIT_BACKEND=orc`: force ORC (fails loudly if libLLVM truly isn't
  found — this is an explicit request, unlike the auto-detect path).
- Documented in `specs/features/repl.md`'s environment-variable table
  (alongside the pre-existing `MARCH_REPL_INTERP`), together with the new
  `MARCH_LLVM_LIB` override for a non-standard libLLVM install path.
- `test/test_stdlib_suite.ml`'s `both_backends` parity harness (Task 2.2)
  now includes `test_parity_opt_shapes`, exercising a tail-recursive fold, a
  float expression, and a two-variable-capturing closure across both
  backends — the shapes most likely to diverge if an IR-level optimisation
  pass were ever added. Run via
  `./_build/default/test/run_stdlib.exe test repl_compiler_parity -e`.

## 4. This task: pre-warm + pipeline evaluation

### Caller audit for the pre-warm change

`Repl_jit.create` is called from exactly three sites in `bin/main.ml`, all
REPL/JIT paths, plus test helpers:

- `argv.(1) = "warm-cache"` — the cache-priming subcommand.
- `argv.(1) = "repl"` — explicit REPL invocation.
- `!files = []` (no positional file) — the default interactive REPL.

`| [f] -> compile f` (the `march --compile` / single-file path) never
constructs a `Repl_jit.t`. `test/test_helpers.ml` and `test/test_codegen.ml`
call `create` only inside JIT-specific test setup. So moving a
`backend_is_orc ()` (and therefore a lazy libLLVM dlopen) call to the end of
`create` cannot affect any AOT-compile invocation.

### Pre-warm (kept)

`Repl_jit.create` now ends with:

```ocaml
if backend_is_orc () then ignore (get_orc ())
```

This moves the LLJIT's one-time setup (libLLVM dlopen +
`LLVMOrcCreateLLJIT` + native-target init) from the *first REPL fragment*
to *REPL startup*, overlapping it with `precompile_stdlib`'s existing
startup work instead of stalling the user's first keystroke. The backend
selector block (`type backend`, `resolve_backend`, `get_orc`, …) was moved
earlier in `lib/jit/repl_jit.ml` (above `create`) so `create` can reference
it — OCaml top-level `let`s can't forward-reference.

Effect, measured with `MARCH_JIT_PROFILE=1`:

- The `[jit-prof] clang+dlopen` phase around the first fragment's
  `compile_fragment` call (which includes the backend-resolution/dlopen
  cost under the old code, since `backend_is_orc ()` runs inside that
  timed region) dropped from **6.8 ms → 0.5 ms**, consistently reproducible
  across repeated runs.
- `[timing] precompile` grew from ~0.016–0.017 s to ~0.017–0.023 s — well
  under the ≤100 ms budget.
- Whole 2-line-session wall time (`1 + 1` / `:quit`) was unchanged within
  noise: ~0.88–0.92 s before and after, over 5 runs each — confirming the
  cost moved rather than grew.

**Measurement caveat:** the brief's reference numbers (first `orc_add_ir`
~89 ms → ~1 ms) reflect a *cold* OS page cache for `libLLVM.dylib`. This
worktree's dlopen was already warm from repeated `dune build`/test
invocations in the same session (a known apparatus trap — repeated
processes keep large shared libraries resident), so the absolute magnitude
observed here (single-digit ms) is smaller than the brief's cold-cache
numbers, even though the *relative* effect (cost moves out of the first
fragment) is clearly and repeatably present in the `clang+dlopen` phase
timing above.

### Pass pipeline (Step 3, evaluated and DROPPED)

Added `LLVMRunPasses(Mod, "default<O1>", NULL, opts)` to
`march_orc_add_ir` in `lib/jit/jit_orc_stubs.c` (header
`llvm-c/Transforms/PassBuilder.h`, non-fatal on failure — falls through to
the unoptimised module and prints a `[march] orc: pass pipeline failed`
warning, matching the file's existing report-don't-crash policy for
recoverable ORC errors). Verified it builds and links: on macOS the symbol
resolves through the existing `-Wl,-undefined,dynamic_lookup` +
runtime-dlopen mechanism (no link-time dependency added); on Linux
`lib/jit/detect_llvm.sh` links `-lLLVM-N` directly, so `LLVMRunPasses`
(a C API added in LLVM 17) requires **CI's LLVM to be >= 17** — worth
confirming in `ci/*.yml` before ever reviving this pipeline, not confirmed
as part of this task since the pipeline was dropped.

**Decision gate: keep `default<O1>` only if per-fragment `orc_add_ir` stays
< 5 ms *and* a heavy `fib` call in the session is measurably faster; else
try `"mem2reg,instcombine,simplifycfg"`; else drop Step 3 entirely.**

Measurements (this machine, `arm64-apple-macosx`, 3 runs each unless noted):

| Variant | per-fragment `orc_add_ir` (repl_session.txt) | `fib(30)` session wall time |
|---|---|---|
| No pipeline (baseline) | 0.4–0.9 ms | 0.88 s / 0.89 s / 0.92 s |
| `"default<O1>"` | 0.8–3.9 ms | 0.90 s / 0.91 s / 1.35 s* |
| `"mem2reg,instcombine,simplifycfg"` | 0.5–3.2 ms | 0.88 s / 0.89 s / 1.52 s* |

(*first-run outlier from process/page-cache warmup, consistent with the
`clang+dlopen`/precompile behavior noted above — later runs are the
reliable signal.)

Both variants satisfy the < 5 ms per-fragment budget, but **neither shows a
measurable `fib` speedup over the unoptimised baseline** — all three
variants land in the same 0.88–0.92 s band once warmup is excluded. This
makes sense in hindsight: the March compiler's `llvm_emit.ml` already
produces clean SSA-form IR directly (no clang-frontend-style redundant
loads/stores for `mem2reg` to promote away), and `fib`'s runtime cost is
dominated by the March runtime's per-call heap allocation and refcounting
(calls into `runtime.so`), which IR-level `instcombine`/`simplifycfg` at
-O1 don't touch. Per the decision gate, **Step 3 is dropped entirely**:
`lib/jit/jit_orc_stubs.c` is unchanged from before this task (reverted to
HEAD). `bench/results/*.jsonl` rows generated while measuring were deleted,
not committed, per the task instructions.

If a future task wants to revisit fragment-level optimisation, the
takeaway is that IR-level passes are the wrong lever here — any win would
have to come from reducing runtime-call/allocation overhead at the TIR
level (Perceus/FBIP), not from an LLVM pass pipeline bolted onto
already-clean generated IR.

## Gates run

- `./_build/default/test/run_stdlib.exe test repl_compiler_parity -e` — 16
  tests, exit 0 (both before and after the pre-warm change; also verified
  green with each pipeline variant during evaluation, before it was
  reverted).
- `./_build/default/test/test_jit.exe -e` — 4 tests, exit 0.
- Full `dune build --root .` — clean.

## Net change

`lib/jit/repl_jit.ml` only: `Repl_jit.create` pre-warms the shared LLJIT
when the resolved backend is ORC; the backend-selector block was relocated
above `create` to make that call legal. No change to
`lib/jit/jit_orc_stubs.c`, `bin/main.ml`, or any test file beyond what
Task 2.2 already landed (`test_parity_opt_shapes` — confirmed present,
not re-added).
