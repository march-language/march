# Parallel list operations + parallelization lint — Design

Date: 2026-06-21
Status: Approved (brainstorming complete; ready for implementation plan)

## Goal

Add parallel map-family functions to the March stdlib and let the compiler
recognize when a sequential `List.map`/`List.filter` over a pure function could
safely become its parallel equivalent.

Two halves, deliberately separated by what is *provable*:

- **Explicit stdlib functions** — the user opts in by calling them; correctness
  contracts (associativity for reduce) are the user's responsibility.
- **Compiler assistance** — only ever does what it can *prove* safe (purity).
  Ships as an advisory LSP hint now; an opt-in auto-rewrite flag is designed
  here but deferred.

## Context (what already exists — do not rebuild)

- **Real parallelism substrate.** `runtime/march_scheduler.c` is an M:N
  multithreaded work-stealing scheduler (default 4 OS threads). RC is
  thread-safe via C11 atomics; per-actor arena heaps mean no stop-the-world GC.
  Real CPU parallelism happens in **compiled (LLVM) code**; the Phase-1
  interpreter runs spawned tasks eagerly on one thread (correct results, no
  speedup).
- **An order-preserving parallel map already exists**:
  `Task.async_stream(list, f)` in `stdlib/task.march:113` spawns all tasks and
  awaits them in input order, returning `[Ok(v1), Ok(v2), ...]`. Our `pmap`
  builds on this machinery rather than adding new runtime concurrency code.
- **A purity oracle already exists** at the TIR level in `lib/tir/purity.ml`:
  `is_pure`, `is_pure_ext(impure_fns, e)`, and `impure_fns_of_module(m)`
  (a transitive fixed point). It is conservative — defaults to *impure* when
  uncertain, which is the safe bias for parallelization. Already used to gate
  fusion, DCE, and inlining.
- **`List` is plain March source** (`stdlib/list.march`): `map` (line ~222),
  `filter` (~279), `fold_left` (~322). All structure/tail recursive.

## Non-goals

- No dependent typing / length-indexed vectors. List length is overwhelmingly a
  runtime property, and profitability also depends on per-element cost, which the
  type system cannot see. Profitability is decided at **runtime** via a threshold.
- No parallel `fold`. Parallel reduction requires an **associative** combiner;
  associativity is undecidable in general and March has no algebraic-law system
  to look it up. `preduce` exists as an explicit function with a user-asserted
  contract; the lint never touches folds/reduces.
- No automatic rewriting in this milestone (designed, gated behind a flag, built
  later).

## Part 1 — Stdlib functions (`stdlib/list.march`)

All map/filter results are **identical** to their sequential equivalents,
including element order. The only observable difference is wall-clock time (in
compiled code) and the requirement that the supplied function is safe to run
concurrently (pure / no cross-element ordering dependency).

### `List.pmap(xs: List(a), f: a -> b): List(b)`
- If `List.length(xs) < pmap_threshold()` → delegate to `List.map(xs, f)`
  (zero spawn overhead, the common case).
- Else: split `xs` into `N` contiguous chunks where `N` tracks the scheduler
  count, spawn one task per chunk (each task runs sequential `map` over its
  chunk), await in order, concatenate. Chunking (not spawn-per-element) keeps
  overhead proportional to core count, not list length.

### `List.pmap_n(xs: List(a), f: a -> b, max_concurrency: Int): List(b)`
- Same chunked, order-preserving semantics, but the number of concurrent tasks
  is capped at `max_concurrency`. No threshold check — this is the explicit
  override for "few elements, heavy per-element work."

### `List.pfilter(xs: List(a), pred: a -> Bool): List(a)`
- Below threshold → `List.filter`. Above → parallel per-chunk filter, results
  concatenated in input order.

### `List.preduce(xs: List(a), identity: a, combine: a -> a -> a): a`
- **Contract (documented loudly): `combine` must be associative and `identity`
  must be its unit.** sum/product/max/min/concat/union qualify; subtraction and
  average do not.
- Below threshold → sequential `fold_left(xs, identity, combine)`.
- Above → reduce each chunk sequentially in parallel tasks, then combine the
  partial results (also via `combine`) in order.

### Implementation note
These are thin compositions over `Task.async`/`Task.await_many` /
`Task.async_stream`. Where `Task.async_stream` already gives order-preserving
per-element parallelism, the chunked versions wrap chunk-level tasks to control
granularity. Reuse existing `List` helpers (`take`/`drop`/`length`/`concat`).

## Part 2 — Threshold config (compiler flag)

- New builtin `pmap_threshold() -> Int`, registered in:
  - `lib/typecheck/typecheck.ml` (type `Fn(Unit) -> Int`),
  - `lib/eval/eval.ml` (returns the configured value / default),
  - `lib/tir/*` + `runtime/` (LLVM backend emits it as a compile-time constant).
- Compiler flag `--pmap-threshold=N`, parsed in `bin/main.ml`, plumbed to both
  the interpreter and the LLVM backend. `forge` passes it through.
- Default **1024** — a documented *starting point*, validated against
  `bench/list_ops.march`. Honest caveat: any count-based cutoff ignores
  per-element cost, so it is a safe-ish floor; `pmap_n` is the precise override.

## Part 3 — Suggestion lint (LSP only)

- New analysis flags `List.map(xs, f)` / `List.filter(xs, p)` calls whose
  function argument is **provably pure** via `Purity.is_pure_ext` +
  `impure_fns_of_module`.
- Surfaced as a `Hint`-severity diagnostic with a **"Convert to `List.pmap`"
  (resp. `List.pfilter`) code action** in `lsp/`. Never printed on CLI builds.
- Folds/reduces are never flagged.
- **Span-mapping challenge (resolve in plan):** purity is computed on TIR
  (post-monomorphization) but diagnostics need a *source* span. Resolution
  approach: surface the candidate `EApp` call sites with their source spans —
  either by carrying the call-site span on the TIR node and mapping back, or by
  running a lighter purity check keyed by the typed-AST call node. The plan must
  pick one and justify it.

## Part 4 — Staged auto-rewrite (designed, deferred)

- A TIR pass rewriting `map`→`pmap` (and `filter`→`pfilter`) when the function
  is pure, gated behind `--auto-parallel` (off by default), reusing the same
  purity oracle and runtime threshold. Spec'd here; implementation deferred to a
  later milestone. No code in this milestone beyond leaving clean extension
  points.

## Testing strategy (TDD)

- **stdlib (`run_stdlib`)**: for each of `pmap`/`pmap_n`/`pfilter`/`preduce`,
  assert result equality with the sequential equivalent across sizes: empty,
  size 1, just-below-threshold, just-above-threshold, large. Order preservation
  explicitly checked (e.g. `pmap` with index-sensitive function).
- **Interpreter↔compiled parity** (marked `Slow`): same program run both ways
  yields identical output.
- **Threshold flag**: a program whose behavior is observable (e.g. exposes which
  branch ran via a count) confirms `--pmap-threshold` flips the fallback.
- **Lint**: LSP test asserting the Hint appears on a pure `List.map`, is absent
  on an impure one (e.g. one that calls `println`), and that the code action
  rewrites to `List.pmap`. A fold is never flagged.
- **Benchmark**: re-run `bench/list_ops.march` to validate/tune the default
  threshold and catch regressions.

## Spec/docs maintenance

- Move the item to Done in `specs/todos.md`; update counts + feature list in
  `specs/progress.md`; add doctests; document the `preduce` associativity
  contract; note `--pmap-threshold` in the relevant flag docs.
