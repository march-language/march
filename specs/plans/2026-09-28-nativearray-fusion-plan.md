# Plan: automatic NativeArray fusion (the "just works" path)

**Date:** 2026-09-28 (revised the same day after a code review of the first draft; the
"Corrections to the first draft" section at the end records what changed and why)
**Todo:** `specs/todos/2026-09-28-nativearray-fusion.md`
**Scope:** make chains of `NativeArray` map / map2 / fold / sum compile to one loop with
**no annotation**, on the `--compile` native and wasm path, with no new toolchain.

**Out of scope:** an MLIR backend or sidecar (see "Where MLIR fits"); multi-dimensional
DataFrame kernels; GPU targets; changes to the list patterns in `lib/tir/fusion.ml`;
the interpreter and the REPL JIT (neither runs the optimizer passes today, see
"Which backends get this").

## Why this and not MLIR

The question that started this was "should March target MLIR?". A full retarget rewrites
the ~15k-line `llvm_*` emitter, while nearly all of March's optimization leverage already
lives in TIR (Perceus/FBIP, borrow, TRMC, fusion, inlining, join points). The one class of
code where MLIR would pay is dense numeric loops, and the concrete win there is **fusing
chained array operations into one loop**, which LLVM can't do because each intermediate
array is an opaque heap allocation.

That fusion doesn't need MLIR. It needs a TIR rewrite, which ships no extra binaries,
pins March to no MLIR release, needs no annotation because the eligibility logic already
exists (`lib/tir/native_map_inline.ml`), and leaves the LLVM emitter's contracts (HCR
ABI, actor layouts, builtin sites, CAS key) untouched.

## What the win actually is: memory traffic, not SIMD

`specs/optimizations.md` (P10, 2026-07-25) already measured the thing the first draft
assumed: inlining and vectorizing a single `map` body gave **no measurable wall-clock
win** on a map-then-sum benchmark, because the loop is memory-bandwidth-bound. One read
plus one write of the whole array dominates a few cycles of ALU work.

Fusion attacks exactly that. Every fused link removes one full-array write and one
full-array read, plus one allocation and its later drop. So the expected result is:

- chains of two or more operations: a real win, roughly proportional to links removed;
- a single map: nothing, and the plan must not spend effort there;
- reductions: the existing `native_float_arr_sum` already vectorizes (see the float
  policy below), so `sum(map(a, f))` wins by dropping the intermediate, not by SIMD.

Phase 0 verifies this; it is not expected to surprise.

## Phase 0 results (2026-09-29): GO, with the order changed

Full table and method: `specs/benchmarks.md`, section `bench/native_array_chains.march`.
Apple M3 Max, 4M elements, minimum of 27 interleaved samples per variant.

- **Map and map2 chains: go.** Hand-fusing gives 2.6× to 6.8× (Float map∘map∘map
  5.66 → 0.83 ms). The bandwidth argument holds: most of the unfused cost is the
  intermediate arrays, including first-touch page faults on each fresh 32 MB
  allocation.
- **Fold is the real bottleneck, and fusion alone can't fix it.** `fold_float`
  runs about 188 ms over 4M elements, about 47 ns per element, against about 0.2 ns
  for an inline map. Every element crosses the boxed closure ABI in the runtime's C
  loop. Fusing map → fold therefore gains nothing today (Int 1.1×, Float none).
- **Rewriting `sum(map(a, f))` into a fold would be a regression**: 2.8× slower for
  Int and 65× slower for Float, because it trades the vectorized runtime sum for the
  closure-call fold. The sum rewrite must target the new inline loop, never
  `fold_*`.

**Revised order.** The fold inline loop moves first and ships on its own: it speeds
up every existing `fold_*` caller (Float roughly 100×, going by the map loop's cost)
with no fusion involved, and fold/sum fusion depends on it. Map/map2 fusion comes
second. Fold and sum fusion come third, gated on the fold loop.

| New phase | Was | Content | Depends on |
|---|---|---|---|
| A | Phase 2, first half | Fold inline loop + unboxed Float clone; detailed spec: `specs/plans/2026-09-30-nativearray-fold-inline-loop.md`. **Done 2026-09-30** (`specs/progress/2026-09-30-nativearray-fold-inline-loop.md`): Float fold 67×, Int fold 21× | nothing |
| B | Phase 1 | map / map2 composition. **Done 2026-10-04** (`specs/progress/2026-10-04-nativearray-map-fusion.md`): unfused chains reach the hand-fused times; f32 and dividing callbacks are not fused | nothing |
| C | Phase 2, second half | map → fold and map → sum fusion onto the inline loop | A, B |
| D | Phase 3 | wider patterns, `@[vectorize]` messages | B |
| E | Phase 4 | hardening, landing | all |

A and B are independent and can land as separate PRs in either order. The phase
sections below keep their original numbering; read them through this table.

## Current state (2026-09-28)

| Piece | Where | Status |
|---|---|---|
| List fusion (map/filter/take → fold/sum/length) | `lib/tir/fusion.ml`, run from `lib/tir/contract_pipeline.ml` after Mono, before Defun, only with `opt` | exists, **lists only**; checks only the producer/consumer *names* for purity, never the callback bodies |
| NativeArray map/map2 → inline loop | `native_map_inline.ml` (after Opt) + `llvm_emit_nmap.ml` | exists, 5 widths; Float gets an unboxed `$mapfast$` clone only when the callback signature is concretely all-Float |
| NativeArray fold → inline loop | none | **missing**: `native_*_arr_fold` is a runtime C loop calling an opaque closure per element |
| `native_float_arr_sum` | `runtime/march_runtime.c` | vectorizes via a scoped `#pragma clang fp reassociate(on)` since 2026-07-24 (~3× measured) |
| `@[vectorize]` / `@[vectorize(warn)]` | `vectorize_mark.ml`, `vectorize_check.ml` | exists, asserts map/map2 eligibility only |
| Lambda shape at the fusion point | `lower_expr.ml:894` | an `Ast.ELam` lowers to `ELet(f, ELetRec([fd], EAtom (AVar fv)), …)` with `fn_kind = FnLambda`; the callback atom is `AVar f` |
| Optimizer kill switch precedent | `contract_pipeline.ml:32` | `MARCH_NO_UNBOX=1` |
| TIR snapshot harness | `test/test_snapshots.ml` | deliberately **excludes** Fusion; `Fusion.gensym_ctr` has no reset |
| Stdlib surface | `stdlib/native_array.march` | `map_*`, `map2_*`, `fold_*(arr, acc, f)` wrapping `native_*_arr_fold(acc, arr, f)` (note the arg swap), `sum_*`, width conversions |

## Design: fusion by body substitution

The rewrite generates no new loops. It builds **one composed callback** and leaves a
single call to an existing primitive, so the existing inline-loop path and LLVM do the
rest:

```
map(map(a, f), g)            →  map(a, fn x -> let t = f_body[x] in g_body[t])
map2(map(a, f), b, g)        →  map2(a, b, fn (x, y) -> let t = f_body[x] in g_body[t, y])
map2(a, map(b, f), g)        →  map2(a, b, fn (x, y) -> let t = f_body[y] in g_body[x, t])
map(map2(a, b, f), g)        →  map2(a, b, fn (x, y) -> let t = f_body[x, y] in g_body[t])
fold(map(a, f), acc, g)      →  fold(a, acc, fn (s, x) -> let t = f_body[x] in g_body[s, t])
sum(map(a, f))               →  __sum_map(a, fn x -> f_body[x])      (Phase 2, see float policy)
```

**Substitute bodies, don't call them.** The composed lambda is built by alpha-renaming
each callback's `fn_def` body (`Inline.alpha_rename` / `Inline.subst_args` already do
this) and splicing them into a fresh `ELetRec` lambda. The first draft proposed
`fn x -> g(f(x))` with `f` and `g` as captured closure variables; that depends on Defun,
Known_call and Inline all lining up afterwards, and the `ECallPtr`s it introduces are
opaque to `Purity`. Substitution makes the composed body pure arithmetic at the fusion
point, which is precisely the shape `Native_map_inline` and `Vectorize_check` accept
(a fresh single-use closure with a concrete signature). Free variables of either body
stay free and become the composed closure's captures; the capturing path
(Phase 2c in `native_map_inline.ml`) already handles that.

Applied to a fixed point, so chains of any length collapse to one call.

**Eligibility (all required, otherwise the chain is left alone):**

1. The intermediate array is used exactly once (`Fusion.use_count`).
2. Each callback is a lambda literal reachable through the enclosing `ELet` chain
   (the `ELetRec([fd], EAtom (AVar fv))` shape). A callback that is a parameter, a
   top-level fn, or a closure built elsewhere is **not fused**. This is the common
   shape in practice and the only one whose body can be inspected.
3. Each callback **body** is pure per `Purity.is_pure fd.fn_body`. This is stricter than
   the list fusion, which only checks the producer and consumer names; do not copy
   that. A body containing an `ECallPtr` is conservatively impure, which is what we
   want.
4. Element widths line up (a `map_f32` feeding a `map_float` is already a type error;
   width conversions are Phase 3).
5. Chain depth at most 8 until Phase 0 numbers say otherwise.
6. Runs at the same pipeline point as list fusion (after Mono, before Defun), matching
   on the `NativeArray.*` wrapper names through `Fusion.base_name` (Inline hasn't
   flattened them to `native_*_arr_*` builtins yet at that point).

**Kill switch.** `MARCH_NO_NATIVEARR_FUSION=1`, same pattern as `MARCH_NO_UNBOX`. This is
the same-box A/B baseline for every benchmark below and the support escape hatch.

## Float policy (revised)

`native_float_arr_sum` has reassociated for two months, on purpose, with a ~3×
measurement behind it, so "bit-exact by default" would make a fused `sum(map(a, f))` loop
**slower** than today's unfused code. The policy is therefore:

- **`sum_*`**: the fused `__sum_map` inline loop carries `reassoc` on its reduction,
  matching the existing runtime `sum` semantics exactly. No new precision decision.
- **`fold_*` with a user callback**: strict, in-order, bit-exact. The user wrote the
  combine function; we don't know it is associative.
- **Unboxed Float loops** require a concretely all-Float signature (`is_all_float_signature`).
  Composition must preserve concrete types: if either callback carries a `TVar`, the
  fused loop still runs but stays on the boxed path. Phase 1 checks that Mono has
  already specialized both callbacks in the common case.

## Which backends get this

- **`--compile` native and wasm**: yes, both go through `Contract_pipeline.run`.
- **Cross targets** (`linux/amd64`, `linux/arm64`): yes, same path.
- **JS**: no. `js_emit.ml` has no NativeArray codegen at all; the fusion pass runs there
  (via `js_pipeline.ml`) but has nothing to match.
- **REPL JIT**: no. `repl_jit.ml`'s `lower_module` runs Lower, TRMC, Mono and Defun only;
  it does not run Fusion, Opt or `Native_map_inline` today. Wiring the optimizer into
  the REPL is a separate item, not this one.
- **Interpreter**: never goes through TIR. It stays the correctness oracle for parity
  tests and is not a performance target.

## Phases

### Phase 0: baseline and gate (~2 days) — DONE 2026-09-29, see results above

- Add `bench/native_array_chains.march`: a 3-deep map chain, map→map2, map→fold,
  map→sum, each over ~4M elements, Int and Float, with one compute-light body
  (`x * 2`) and one compute-heavy body. Register it in `specs/benchmarks.md` beside
  `array_numeric` / `simd_map` / `simd_sum`.
- Hand-fuse each case in March (one map with a composed lambda) and measure both,
  compiled at `--opt 2`, same box, several runs. **The hand-fused numbers are the
  ceiling.** Capture `-Rpass=loop-vectorize` / `-Rpass-missed` remarks as a secondary
  signal only.
- Go/no-go: proceed if chains of two or more show a clear win on the compute-light
  body (that is the bandwidth case). If they don't, stop, record the numbers in the
  todo, and move it to `specs/progress/` as "measured, not worth it".

### Phase 1: map / map2 composition (~1 week)

- Add a sectioned `try_fuse_nativearr` group to `fusion.ml`, separate from the list
  patterns. Cover map∘map, map2 with a map on either input, and map∘map2, all five
  widths.
- Callback lookup and body substitution as designed above; reuse `Inline`'s renaming
  helpers rather than writing a second alpha-renamer.
- Add `Fusion.reset_counter` and reset it in the snapshot harness (the rule from the
  TRMC counter work: a pass with a global counter needs the reset, the harness slot,
  and the fixture, or snapshots are nondeterministic).
- Add a third snapshot stage, `test/snapshots/fusion/`, running Lower → TRMC → Mono →
  Fusion. The existing `lower/` and `perceus/` stages deliberately exclude Fusion, so
  the first draft's "snapshot each shape" could not have worked without this.
- Tests: a fusion snapshot per shape; interpreter-vs-compiled parity per shape and
  width, including capturing callbacks; and one negative fixture per eligibility rule
  (multi-use intermediate, impure body, callback that isn't a literal, `TVar`
  signature) proving no rewrite and, for the `TVar` case, that the loop is boxed but
  fused.

### Phase 2: fold and sum (~1.5–2 weeks)

Larger than the first draft estimated, because it is a new inline-loop family, not
just a pattern:

- Eligibility in `native_map_inline.ml` and a loop emitter in `llvm_emit_nmap.ml` for
  a synthetic `__native_*_arr_fold_inline` (2-input: accumulator and array; callback
  arity 2), following the map2 precedent. Remember the wrapper swaps the argument
  order (`fold_int(arr, acc, f)` → `native_int_arr_fold(acc, arr, f)`).
- An unboxed `$foldfast$`-style clone for `(Float, Float) -> Float` callbacks, mirroring
  `$mapfast$`. Without it a Float fold still boxes twice per element.
- `sum_*(map_*(a, f))` → `__sum_map` inline loop with a `reassoc` reduction (float
  policy above). Int needs no flag.
- The fold callback is strict; only the sum loop reassociates.
- This is a new synthetic builtin family: walk the nine-site builtin checklist
  (`project_new_builtin_nine_sites` memory), including `test_codegen` and the REPL
  finalizers, even though the REPL never emits it.

### Phase 3: widen the pattern set (~3–5 days)

- Width conversions (`to_float_arr`, `float_to_f32_arr`, `int_to_i32_arr`, …) as
  fusible maps with a fixed body.
- `length_*(map_*(a, f))` → `length_*(a)` when `f`'s body is pure **and cannot panic**;
  `Purity` treats division and bounds checks as pure, so this needs its own
  "cannot panic" predicate. Skip it if that predicate is hard; the win is tiny.
- Extend `@[vectorize]` so its assertion recognizes a fused chain and names the link
  that blocked fusion ("the second map's callback isn't a lambda literal").

### Phase 4: hardening and landing (~3–5 days)

- ASAN corpus sweep over the new fixtures. Fusion removes an intermediate array and
  the Perceus drop that went with it; a mistake here is a UAF, and ASAN is the only
  thing that has reliably caught those.
- `scripts/ir-oracle.sh`: every corpus program **without** a NativeArray chain must be
  byte-identical. Diffs are allowed only for programs that actually have chains, and
  each one gets read.
- Perturbation check: disable one eligibility rule on purpose and confirm a negative
  fixture goes red before trusting green.
- Re-run `bench/list_ops.march` (closure/HOF path), `bench/array_numeric.march`, and
  the Phase 0 bench, same box, fused vs `MARCH_NO_NATIVEARR_FUSION=1`, same binary
  build.
- LSP: `contract_pipeline.ml` is shared with `lsp/lib/analysis.ml`; confirm no new
  diagnostics and no measurable slowdown in the `lsp` suite.
- CHANGELOG `### Changed` bullet; document panic-ordering in `specs/lang/`; move the
  todo to `specs/progress/`.

**Total:** roughly 4–5 weeks, with Phase 0 able to cancel everything after 2 days.

## Risks

- **Panic ordering.** `Purity` treats panicking builtins as pure, so composition can
  change *which* panic fires first when both bodies can panic, and `map2(map(a, f), b, g)`
  runs the length-mismatch check before any of `f` instead of after all of it. Both are
  "panics either way, different message". Recommendation: accept and document. Excluding
  panicking bodies would exclude every division and every array read.
- **Code size.** Substitution duplicates nothing at runtime, but a deep composed body
  inlined into a loop can bloat hot functions; the depth cap bounds it.
- **Silent non-fusion.** Users never see when a chain didn't fuse. Phase 3's `@[vectorize]`
  extension is the escape hatch; `MARCH_NO_NATIVEARR_FUSION` is the A/B tool.
- **Type erasure at the fusion point.** If Mono has not specialized a callback (a `TVar`
  in its signature), the fused loop stays boxed. Phase 1 measures how often this
  happens on real code; if it is common, the fix belongs in Mono, not here.

## Open questions for the user

1. **Panic reordering:** accept (recommended) or exclude panicking callbacks?
2. **Fold reassociation:** should a `fold_float` whose combine body is provably plain
   `+` or `*` get the `sum` treatment (reassoc), or stay strict? Default in this plan:
   strict; only `sum_*` reassociates, as it already does.

## Where MLIR fits

Reopen an MLIR sidecar only if, after Phase 2, at least one of these holds:

- fused, inline loops that LLVM still fails to vectorize, in cases that matter;
- DataFrame or matrix work needing tiling, loop interchange, or multi-dimensional fusion;
- a GPU or accelerator target becomes a goal.

**Sidecar spike (2026-09-30).** The fused Float kernel from Phase 0,
`(x * 2 + 3) * 0.5` over 4M doubles, was written as a `linalg.generic`, lowered
with Homebrew MLIR 22 (`mlir-opt` then `mlir-translate`), and called from C
through the expanded rank-1 memref ABI with a NativeArray-shaped buffer. All
three variants below produce identical output. Apple M3 Max, best of 15 rounds
with rotated order, three processes:

| variant | ms |
|---|---:|
| MLIR `affine-super-vectorize`, width 4 | 1.45–1.65 |
| MLIR `affine-super-vectorize`, width 2 | 1.99–2.02 |
| MLIR scalar loops, clang `-O2` vectorizes | 0.55–0.93 |
| plain C loop, clang `-O2` | 0.54–0.92 |

March's own fused inline loop measured 0.83 ms in Phase 0. So for rank-1 kernels
MLIR's vectorizer loses to LLVM's by 2 to 3.5 times, and with LLVM left to
vectorize it merely ties the existing inline loop. The pipeline also needed
`--convert-ub-to-llvm`, which older pass lists don't have: the release-churn cost
is real even at spike size.

The automatic selection built here is exactly what a sidecar would reuse; it would only
replace the backend for the selected loops.

## Corrections to the first draft

1. **The win is bandwidth, not SIMD.** `specs/optimizations.md` P10 measured no
   wall-clock gain from vectorizing a single map. Fusion removes array traffic, which is
   the actual bottleneck. Phase 0 and the go/no-go rule were rewritten around that.
2. **Composition by closure call was wrong.** `fn x -> g(f(x))` leaves `ECallPtr`s that
   `Purity` cannot see through and depends on three later passes to become inlinable.
   Substitute bodies at the fusion point instead.
3. **List fusion never checks callback purity**, only producer/consumer names. The new
   patterns check the lambda bodies and require lambda literals.
4. **"Bit-exact float reductions by default" contradicted the runtime**, where `sum_float`
   has reassociated since 2026-07-24. Sum keeps reassoc; user folds stay strict.
5. **"Works on every backend" was false.** JS has no NativeArray codegen and the REPL
   JIT runs no optimizer passes. Only `--compile` native, wasm and cross targets get this.
6. **The snapshot harness excludes Fusion** and `Fusion.gensym_ctr` has no reset, so the
   planned per-shape snapshots needed a new stage plus a counter reset.
7. **Phase 2 was underestimated.** A fold inline loop is a new synthetic builtin family
   (emitter arm, unboxed clone, nine-site checklist), not a pattern addition.
8. Added a kill switch, the `TVar`-signature boxed fallback, and the LSP parity check.
