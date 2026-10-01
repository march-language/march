# Spec: unboxed Float calls through closures

**Date:** 2026-09-30
**Todo:** `specs/todos/2026-09-30-float-closure-unboxing.md`
**Depends on:** `specs/plans/2026-09-30-nativearray-fold-inline-loop.md` for the
generalized unboxed-clone helper (land that first; this spec reuses it).

## As built (2026-10-01)

Implemented in `lib/tir/hof_spec.ml`, wired into `lib/tir/contract_pipeline.ml`.
Where it differs from the design below, on purpose:

- **The clone keeps the closure parameter.** The design removed it from the
  signature. Keeping it means the same closure value is still passed, so no
  ownership changes at all; only `call_ptr f(...)` becomes the direct
  `EApp(apply, f :: args)` form `Known_call` already produces. Perceus and the
  rest of the pipeline handle that form as they always have.
- **No stdlib rewrite was needed.** `List.map`, `filter` and `filter_map` are now
  written in natural recursion (main changed them for TRMC), so their closure is
  already a static argument. TRMC splits `map` into an entry and a `$dps` loop;
  a worklist carries the known closure into each clone's body, so the loop is
  specialized too. Functions whose callback reaches a local `go` helper
  (`each`, `scan_left`, `zip_with`) are not covered.
- **Opt does most of Part 1's work.** Once the call is direct, Opt's inliner
  usually inlines the lambda body into the clone, so no call is left at all.
  `redirect_unboxed` (the `$ufast$` clone) covers direct calls the inliner
  leaves in place.
- **Reachable functions only.** Every program lowers the whole stdlib.
  Specializing every call site minted 939 clones for a small program and cost
  about 8% compile time; restricting call-site rewriting to functions reachable
  from the program's roots (`Dce.reachable_fns`, which fails open) brought it to
  12 clones and +0.1%.
- **Off under hot reload**, for JS, and with `MARCH_NO_HOF_SPEC=1` (also a CAS
  key tag, so an A/B run never reuses the other variant's binary).
- **Int and non-scalar lambdas are specialized too**, answering the open
  question below: the pass is the same, and making the call direct costs
  nothing.

Measured (`bench/float_closure_calls.march`, M3 Max, best of 3 runs, same
compiler with the pass on and off): Float `fold_left` 192.3 ms to 8.5 ms
(22.6×), Float `map` 192.0 ms to 65.6 ms (2.9×), Int `fold_left` 11.4 ms to
10.2 ms. The 2× target against the hand-written loop is **not** met: Float
`fold_left` is 8.5 ms against 2.6 ms. The remaining cost is one closure
refcount increment per iteration (a runtime call; it is balanced, not a leak)
plus the scheduler yield check. The inline RC fast path
(`specs/plans/2026-09-30-inline-rc-fast-path.md`) is the natural next step for
it. `map` stays slower than `fold_left` because a `List(Float)` stores its
elements boxed.

## Problem

Every closure call uses one erased ABI: arguments and results are `ptr`, Ints
cross wire-tagged, and **Floats cross heap-boxed** (`march_alloc_float` in,
`march_unbox_float` out; see `clo_wrap_define` in `lib/tir/llvm_calls.ml`). The
rule is keyed purely on the callee's *name*: `Tir_names.is_apply_fn` tests for
`$apply$`, and `llvm_toplevel.ml` / `llvm_emit_call.ml` box whenever it matches.

Measured 2026-09-30 (`bench/float_closure_calls.march`, M3 Max, 2M-element lists,
best of 14 rounds):

| | Int | Float | Float cost |
|---|---:|---:|---:|
| `List.fold_left(xs, acc, fn (s, x) -> ...)` | 16.3 ms | 194.0 ms | 11.9× |
| `List.map(xs, fn x -> ...)` | 58.2 ms | 244.7 ms | 4.2× |
| same fold hand-written, no closure | 9.0 ms | 11.1 ms | 1.2× |

That is about 90 ns per element spent on boxing. Any Float code that goes through
a higher-order function pays it: list pipelines, `Enum`/`Map` callbacks,
numeric code written functionally.

## Why the existing trick doesn't reach this

`Native_map_inline`'s `$mapfast$` clone works because the map loop is emitted in
the caller, so the callee is *statically known* at the one call site that matters.
Inside `List.fold_left$...` the call `f(acc, h)` is an `ECallPtr` on a
**parameter**: nothing at that site knows which lambda it is, so it has to use
the universal ABI. `Known_call` only resolves closures bound in the same function
body.

So there are two sub-problems:

1. **Known calls still box.** When `Known_call` does resolve a call, it produces
   `EApp(apply_fn, [clo; args])`, and the emitter still boxes Float arguments
   because the target's name matches `$apply$`.
2. **Higher-order functions hide the callee.** The closure arrives as a
   parameter, so no call inside the function is known.

## Design

### Part 1: route known calls to unboxed clones

After `Known_call` in the Opt loop, rewrite each `EApp(f, [clo; args…])` where `f`
is an apply fn with a concrete scalar signature (all-Float, all-Int, or a mix of
Float/Int with no `TVar`) to call its unboxed clone. The clone is the same
`fn_def` under a name without `$apply$`, as `$mapfast$` does it; use the helper
generalized by the fold spec. Keep one clone per apply fn, shared by all its known
call sites.

This part alone helps local lambdas only, but it is small, low risk, and a
prerequisite for Part 2.

### Part 2: specialize higher-order functions on a known closure argument

A new TIR pass, `lib/tir/hof_spec.ml`, runs after Defun and before `Known_call`,
inside the Opt fixed point.

**Trigger.** A call `EApp(g, args)` where:
- one argument is a fresh closure allocation (`EAlloc` of a `$Clo_*` type) or an
  alias of one, used once, as in `Native_map_inline`'s eligibility bar;
- `g` passes that parameter **unchanged** to every recursive self-call (a
  "static argument"), as `List.fold_left` does with `f`;
- `g` is small and not a hot-reload boundary (`Inline.is_reloadable_name`). The
  budget should be larger than `Inline`'s `inline_size_threshold` of 50, because
  a specialized clone is emitted once per lambda rather than at every call site.
  Start at 200 nodes and tune it with the benchmark.

**Rewrite.** Clone `g` as `g$spec$<apply-fn-hash>` with the closure parameter
**removed from the signature** and replaced inside the body by a fresh local bound
to the closure argument, or by its captures when non-capturing reduces it to a
constant. Recursive self-calls go to the clone. Inside the clone, `ECallPtr(f, …)`
now targets a closure whose allocation site is known, so `Known_call` resolves it
and Part 1 sends it to the unboxed clone. LLVM then inlines the lambda body.

**Nested helpers.** `List.map` is written as `fn map(xs, f) = go(xs, Nil)` with a
local `go` that captures `f`. After Defun, `go` is a lifted function reaching `f`
through its environment, not a static parameter. Two options:

- (a) Extend the trigger to "`g` calls a local recursive helper that captures the
  closure": specialize the helper too.
- (b) Handle only direct static-argument recursion in v1, and rewrite the handful
  of hot stdlib HOFs (`map`, `filter`, `each`, …) in static-argument style.

**Recommendation:** (b) first. It is a mechanical stdlib edit, keeps the pass
simple, and covers the measured cases. Do (a) only if profiling shows other
shapes matter.

**Code growth.** Specialization is per distinct lambda. Cap it at N clones per HOF
per module (for example 16), then fall back to the generic call. Clones are keyed by
apply-fn identity, so the same lambda passed twice shares one clone.

**Hot code reload.** A specialized clone bakes a lambda into a copy of the stdlib
function. The same rule as `Inline` applies: never specialize a reloadable
boundary function, and include the clone's dependencies in the impl hash that the
HCR identity pass computes. Read the `project_hcr_patch_boundary_fixture_traps`
memory before writing the HCR test.

## What this does not change

- The universal closure ABI stays as is. Closures stored in data structures,
  passed to the C runtime, or called through unknown parameters still box. That is
  correct, just slower.
- There is no new closure layout. The alternative, a second "unboxed entry" code
  pointer in every Float-typed closure, was rejected: it shifts capture offsets that
  at least six runtime call sites read at `closure+16` (see the
  `project_clo_drop_runtime_boundary_audit` memory), and it cannot help closures
  built by the runtime.

## Tests

- **Parity:** the fixture covers fold_left, map, filter, and a user-written
  static-argument HOF, with Float, Int and mixed signatures, capturing and
  non-capturing lambdas, one lambda used at two call sites, and a lambda that
  returns its argument unchanged.
- **Snapshot:** a TIR snapshot of `hof_spec` output for one fold_left call (the
  counter reset, harness slot and fixture rule applies; the pass has a fresh-name
  counter).
- **Structure:** an `--emit-llvm` check that the specialized fold loop contains no
  `march_alloc_float`.
- **Negative:** a HOF that passes `f` changed in recursion, one over the size
  budget, and a reloadable boundary are all not specialized.
- **Code-size guard:** a module with 20 distinct lambdas into one HOF produces at
  most 16 clones.
- **HCR:** a patch that changes a lambda passed to a specialized HOF actually
  deploys.
- **ASAN** sweep, and `scripts/ir-oracle.sh` over the corpus. Diffs are expected
  wherever a HOF takes a lambda literal; read each class of diff.

## Benchmark and acceptance

`bench/float_closure_calls.march`, plus `bench/list_ops.march` (closure/HOF) and
`bench/tree_transform.march` as a no-regression check, same box, pass on vs off.

Accept when:
- Float `fold_left` comes within 2× of the hand-written loop (from 17×);
- Float `map` improves at least 2×;
- nothing regresses by more than noise;
- compile time on the stdlib test suite grows by less than 5%.

## Effort

- Part 1: about half a day.
- Part 2: about 2 to 3 days of agent work plus the stdlib rewrite; HCR and
  code-size tests are the long pole.
- Total with verification: about 3 to 4 days.

## Open question

Should specialization also apply to non-Float lambdas? Int calls avoid the box but
still pay an indirect call that blocks inlining (fold_left Int 16.3 ms against
9.0 ms hand-written, 1.8×). The pass is the same; only the trigger differs.
Recommendation: yes, gated on the same size cap, measured in the same benchmark.
