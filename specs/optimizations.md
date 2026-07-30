# March — Compiler Optimization Catalog

**Last updated:** 2026-03-24

This document catalogs every compiler optimization for March — implemented, in-progress, and planned. Each entry describes what the optimization does, why it matters for March specifically, estimated effort, expected impact, dependencies, and the pipeline stage where it lives.

---

## Pipeline Overview

Optimizations run at different stages:

```
Source
  ↓ Parse / Desugar / Typecheck
AST
  ↓ Lower (lib/tir/lower.ml)
TIR (Typed Intermediate Representation)
  ↓ Mono     — monomorphize polymorphic functions
  ↓ Defun    — defunctionalize / closure conversion
  ↓ Perceus  — reference-count insertion / FBIP
  ↓ Escape   — escape analysis / stack promotion
  ↓ Fusion   — stream fusion / deforestation        ← --opt flag
  ↓ Opt      — Inline → CProp → Fold → Simplify → DCE (fixed-point)
LLVM IR
  ↓ TCO      — self-tail-call → loop transformation
  ↓ clang -O2/-O3
Native binary
```

The `--no-opt` flag skips Fusion and Opt. The `--opt N` flag sets the clang optimization level (default 2).

---

## Implemented Optimizations

### 1. Constant Folding  ✅

**Location:** `lib/tir/fold.ml`
**Stage:** TIR (Opt coordinator)

Evaluates pure expressions whose operands are all literals at compile time.

**What it folds:**
- Integer arithmetic: `3 + 4 → 7`, `10 / 2 → 5`, `7 % 3 → 1`
- Float arithmetic: `1.5 +. 2.5 → 4.0`
- Boolean operators: `not true → false`, `false && expr → false`, `true || expr → true`
- Conditionals: `if true then e1 else e2 → e1`, `if false then e1 else e2 → e2`

**Why it matters for March:** March encourages small numeric helpers and named constants. Folding makes `let max_retries = 3 * 5` free and eliminates dead branches from guard expressions known at compile time.

**Effort:** Low (done) | **Impact:** Medium
**Dependencies:** None
**Tests:** `test_fold_*` group in `test/test_march.ml`

---

### 2. Constant Propagation  ✅

**Location:** `lib/tir/cprop.ml`
**Stage:** TIR (Opt coordinator, runs before Fold)

Substitutes known-literal variables into their use sites. Enables further folding.

**Example:**
```
let x = 7
let y = x + 1     →   let y = 7 + 1  (Fold then gives: 8)
```

Without propagation, `fold.ml` sees `x + 1` and cannot fold it because `x` is a variable, not a literal. With propagation, the variable is replaced with its constant value first, unlocking the fold.

**Scope:**
- Only propagates variables bound to `EAtom (ALit ...)` (bare literals)
- Does not propagate variables bound to complex expressions (no code duplication risk)
- Conservative: stops propagation at any branch point where the variable may be rebound

**Why it matters for March:** March programs use named bindings heavily (idiomatic functional style). Constant propagation unlocks cascading folds across let-chains that would otherwise remain un-optimized.

**Effort:** Low | **Impact:** Medium (especially cascading)
**Dependencies:** Runs before Fold for maximum cascade benefit
**Tests:** `test_cprop_*` group in `test/test_march.ml`

---

### 3. Algebraic Simplification  ✅

**Location:** `lib/tir/simplify.ml`
**Stage:** TIR (Opt coordinator)

Peephole rewrites based on algebraic identity and strength-reduction rules.

**Rules (selection):**
- `x + 0 → x`, `0 + x → x`, `x - 0 → x`
- `x * 1 → x`, `1 * x → x`, `x / 1 → x`
- `x * 0 → 0`, `0 * x → 0`, `0 / x → 0`
- `x * 2 → x + x` (strength reduction)
- `x - x → 0`
- Float equivalents: `x +. 0.0 → x`, `x *. 1.0 → x`, etc.
- Boolean: `x && true → x`, `x || false → x`

**Why it matters for March:** Loop induction variables and accumulator patterns frequently produce `n - 0` or `acc + 0` forms after inlining. Simplification eliminates them without requiring the programmer to avoid idiomatic code.

**Effort:** Low (done) | **Impact:** Medium
**Dependencies:** Benefits from Fold and CProp first
**Tests:** `test_simplify_*` group in `test/test_march.ml`

---

### 4. Function Inlining  ✅

**Location:** `lib/tir/inline.ml`
**Stage:** TIR (Opt coordinator)

Inlines small, pure, non-recursive functions at call sites. Alpha-renames inlined bodies to prevent variable capture.

**Eligibility criteria:**
- Function body ≤ 50 TIR nodes (configurable via `inline_size_threshold`)
- Function body is pure (no effects; checked by `lib/tir/purity.ml`)
- Function is non-recursive (does not call itself)
- Does not call another inlining candidate (prevents infinite fixed-point expansion)

**Fixed-point loop:** The `opt.ml` coordinator runs the pass set up to 5 times, so chained calls `f → g → h` are fully inlined across iterations.

**Why it matters for March:** March's standard library is built on small, composable functions (`List.map`, `Option.unwrap_or`, etc.). Without inlining, every call pays a closure dispatch overhead. With inlining, the entire call chain fuses into a single loop body.

**Effort:** Low (done) | **Impact:** High
**Dependencies:** Pairs with Fold and Simplify for maximum benefit
**Tests:** `test_inline_*` group in `test/test_march.ml`

---

### 4a. Single-Use Private-Function Inlining  ✅

**Location:** `lib/tir/single_use_inline.ml`
**Stage:** TIR (Opt coordinator), after ordinary `inline` and before `cprop`

Relocates a small, syntactically impure top-level function into its only
direct call site. The pass retains `Inline.inline_size_threshold = 50` and
runs in the fixed-point order `inline → single-use-inline → cprop → fold →
simplify → fusion → dce`.

Eligibility requires exactly one **total** free top-level reference in the
current artifact, not merely one caller. That occurrence must be an
arity-correct direct `EApp`; any occurrence as a value, argument, closure
field, indirect-call target, `ADefRef`, or other atom position makes the
function address-taken and excludes it. Syntactically pure functions remain
the ordinary inliner's responsibility.

The impure-body case is sound because one substitution relocates observable
operations rather than duplicating them. The pass excludes DCE roots
(`main`/qualified main, exports, tests, setup, migrations, and the no-seed
fallback), every recursive direct-call SCC, collision-dispatch targets, and
hot-code-reload boundary functions. Existing alpha-renaming and
arity-checked ANF substitution preserve lexical scope and argument binding.

Perceus runs before this optimization, so ownership operations are already
explicit. Inlining must preserve every `EIncRC`, `EDecRC`, atomic RC, `EFree`,
and `EReuse` operation and their order; it does not synthesize, combine,
remove, or reorder RC work. Downstream impurity-aware DCE may remove only
bindings and now-unreachable named definitions under its existing rules.

**Measured emitted-LLVM result (2026-07-27):** all 93 current non-JS top-level
native fixtures compiled successfully. Their final output contains 1,869
matched March definitions and 2,310 residual direct calls to those
definitions. On the exact 91-fixture set used by the published baseline,
2,029 definitions became 1,853 (176 removed), while the published 2,468
residual calls became 2,294 (174 fewer, 7.05%). A same-source no-pass control
at `91afbe99` measured 2,470 → 2,294 calls and 2,029 → 1,853 definitions,
attributing 176 removed calls and definitions across the same 51 fixtures;
the two-call difference from the published baseline predates this pass.

Across all 93 current fixtures, the same no-pass control measured 2,049 →
1,869 definitions and 2,490 → 2,310 calls: 180 removed call/definition
occurrences, 156 distinct bodies, across 53 fixtures. Of those occurrences,
159 contain explicit RC operations. The final-phase dump distributions were:

| Serialized `body_size` | Removed definitions |
| ---: | ---: |
| 1–10 | 23 |
| 11–20 | 71 |
| 21–25 | 30 |
| 26–30 | 17 |
| 31–40 | 21 |
| 41–50 | 13 |
| 51+ | 5 |

| Serialized `rc_ops` | Removed definitions |
| ---: | ---: |
| 0 | 21 |
| 1 | 42 |
| 2 | 39 |
| 3 | 32 |
| 4 | 20 |
| 5–9 | 20 |
| 10–19 | 6 |

The pass still enforces `Inline.node_count <= 50`. The dump serializer's
`body_size` is a visualization counter that weights aggregate atom lists
differently, so five removed definitions serialize as 51–56 even though they
meet the pass's 50-node predicate. These are compiler-output measurements;
no runtime speedup was measured.

**Tests:** `single_use_inline`, `inline`, DCE, hot-reload boundary, mutual-TCO,
reduction-check, TIR property, raw-LLVM elimination, and native RC-order
regressions

**Corpus-count correction (2026-07-27):** the 93-fixture count above holds at
the commit it was measured (`d3315b36`). A later rebase onto `main` added one
unrelated fixture (`native_arr_map_inline_float_box_reuse.march`, float-boxing
Stage 4 Option A), making the current corpus 94. That fixture was checked
directly rather than re-running the full corpus pass: its `--dump-phases`
trace shows identical TIR node counts immediately before and after both
`tir-opt-{1,2}-single-use-inline` phases, so the pass is a no-op on it and the
93-fixture aggregate figures above are unchanged for the 94-fixture corpus.
See `specs/progress.md`'s matching 2026-07-27 entry.

---

### 5. Dead Code Elimination  ✅

**Location:** `lib/tir/dce.ml`
**Stage:** TIR (Opt coordinator)

Two-phase DCE:

1. **Local DCE:** Pure `let` bindings whose bound variable is unused in the continuation are removed entirely. Impure unused bindings are converted to `ESeq` (effect preserved, binding dropped).

2. **Whole-module DCE:** Computes transitive reachability from `main`. All top-level functions not reachable from `main` are removed from the module. If no `main` exists (library mode), all functions are considered roots.

**Why it matters for March:** The standard library is large. Without DCE, every compiled binary embeds the entire stdlib regardless of what it uses. With DCE, a program that only uses `List.map` does not pay for `Http.get`.

**Effort:** Low (done) | **Impact:** High (binary size and compile time)
**Dependencies:** Must run after Defun (closure apply-functions need to be reachable via EApp, not just ECallPtr)
**Tests:** `test_dce_*` group in `test/test_march.ml`

---

### 6. Escape Analysis / Stack Promotion  ✅

**Location:** `lib/tir/escape.ml`
**Stage:** TIR (after Perceus, before Opt)

Identifies heap allocations whose lifetime is provably bounded to the current stack frame, and promotes `EAlloc` to `EStackAlloc`. Dead RC operations on stack-allocated values are also removed.

**Three-phase algorithm:**
1. Collect `EAlloc`-bound candidates
2. Mark escaping: any candidate that flows to a function argument, is stored in another allocation, appears in an `EAtom` tail return, or is captured in a `ELetRec` inner function
3. Rewrite non-escaping candidates to `EStackAlloc`, drop dead `EDecRC`/`EFree`

**Why it matters for March:** Functional programs allocate frequently. Stack-promoting short-lived allocations eliminates GC pressure and improves cache locality without changing semantics.

**Effort:** Medium (done) | **Impact:** High (GC pressure)
**Dependencies:** Runs after Perceus (RC ops must already be inserted)
**Tests:** `escape_analysis` group in `test/test_march.ml`

---

### 7. Stream Fusion / Deforestation  ✅

**Location:** `lib/tir/fusion.ml`
**Stage:** TIR (after Mono, before Defun)

Detects chains of pure list operations where intermediate lists are single-use, and replaces them with a single-pass fused function that avoids materializing intermediate lists.

**Fused patterns:**
- `map(xs, f) |> fold(acc, g)` → `$fused_mf_N(xs, f, acc, g)`
- `filter(xs, p) |> fold(acc, g)` → `$fused_ff_N(xs, p, acc, g)`
- `map(xs, f) |> filter(t, p) |> fold(acc, g)` → `$fused_mff_N(xs, f, p, acc, g)`

**Guards:** Both producer and consumer must be pure; intermediate list must be used exactly once; effectful operations (IO, send, tap>) are never fused.

**Why it matters for March:** Pipeline-style list processing (`xs |> List.map ... |> List.filter ... |> List.fold_left ...`) is idiomatic. Without fusion each step allocates an intermediate list. Fusion eliminates all intermediate allocations.

**Effort:** High (done) | **Impact:** High (allocation-heavy code)
**Dependencies:** Must run before Defun (closures are still `TFn`, not yet struct-wrapped)
**Tests:** `fusion` group in `test/test_march.ml`

---

### 7b. Struct Update Fusion  ✅

**Location:** `lib/tir/fusion.ml` (`run_struct`)
**Stage:** TIR (Opt coordinator — after Defun, Perceus, Escape)

Detects chains of record-update operations where each intermediate struct is
single-use, and merges them into a single `EUpdate` that applies all field
modifications at once.

**Pattern:**
```
let conn1 = { conn0 | headers = h }
let conn2 = { conn1 | status = 200 }     -- conn1 used exactly once
→
let conn2 = { conn0 | headers = h; status = 200 }
```

**Semantics:** When both updates touch the same field, the later write wins
(`merge_fields` filters duplicates in favour of the downstream update).

**Guards:** The intermediate variable must be used exactly once in the
continuation (`use_count` check).  Multi-use intermediates are never fused
(the base record copy would become observable).

**Why it matters for March:** HTTP response building chains multiple helper
functions (`put_resp_header |> put_resp_header |> text |> send_resp`) where
each step takes a `Conn` record, modifies one field, and returns the updated
struct.  Without fusion each step allocates a new copy of the Conn struct.
Fusion collapses the entire chain to a single allocation with all fields set.

**Effort:** Low (done) | **Impact:** High (HTTP/record-heavy code)
**Dependencies:** Runs in the Opt coordinator; uses `use_count` from `fusion.ml`
**Tests:** `struct_fusion` group in `test/test_march.ml`

---

### 8. Self-TCO (Tail-Call to Loop)  ✅

**Location:** `lib/tir/llvm_emit.ml` (`has_self_tail_call`, `emit_fn`)
**Stage:** LLVM IR emission

Self-tail-recursive functions are detected at emit time and compiled to a loop rather than a recursive call. The function body is wrapped in a `tco_loop` basic block; self-tail-calls store new argument values into parameter alloca slots and branch back to the loop header.

**Example:** `factorial(n, acc)` with tail call `factorial(n-1, n*acc)` → single loop, O(1) stack.

**Why it matters for March:** March enforces TCE (tail-call enforcement) — unbounded non-tail recursion is a compile error. Self-TCO closes the loop by ensuring the common case (self-recursion) runs in O(1) stack space.

**Effort:** Medium (done) | **Impact:** Critical for correctness + performance
**Dependencies:** None (LLVM pass, independent)
**Tests:** `tco_codegen` group in `test/test_march.ml`

---

### 9. Perceus RC / FBIP  ✅

**Location:** `lib/tir/perceus.ml`
**Stage:** TIR (after Defun, before Escape)

Inserts reference-count operations (`EIncRC`, `EDecRC`, `EFree`) based on linearity analysis. When an allocation is the unique owner of a constructor being pattern-matched (FBIP — Functional But In Place), the reuse token (`EReuse`) is passed back to the constructor in the arm, reusing the cell in place rather than freeing and reallocating.

**Why it matters for March:** Functional data transformations (tree traversals, list processing) traditionally allocate new nodes for every structural change. FBIP reuses the old cell's memory when it's uniquely owned, delivering performance close to in-place mutation without sacrificing functional semantics.

**Effort:** High (done) | **Impact:** Very high (allocation-heavy workloads)
**Dependencies:** Runs after Defun; Escape runs after Perceus
**Tests:** `perceus` group in `test/test_march.ml`

---

### 10. Unboxed Primitives in LLVM  ✅

**Location:** `lib/tir/llvm_emit.ml` (type lowering)
**Stage:** LLVM IR emission

TIR primitive types are lowered to native LLVM machine types without boxing:

| TIR type | LLVM type |
|----------|-----------|
| `TInt`   | `i64`     |
| `TFloat` | `double`  |
| `TBool`  | `i64`     |
| `TUnit`  | `i64`     |

Function arguments, return values, and local `let`-bindings of these types are all register-valued — no heap allocation, no tag bits, no indirection. When `Int` or `Float` values are stored as fields in a constructor, they are stored at their natural width (`i64` or `double` at 8-byte offsets) and loaded out as the same type when pattern-matched. This is the "unboxed struct field" model from GHC's `UnboxedSums`/`UnboxedFields`, applied uniformly.

**Why it matters for March:** Numeric kernels (statistical computation, simulations, matrix math) would be catastrophically slow if every integer addition required a heap indirection. Native types make March competitive with C for tight arithmetic loops.

**Effort:** Low (structural — done as part of LLVM emit) | **Impact:** Very high
**Dependencies:** Monomorphization (type must be concrete before lowering)

---

### 11. Monomorphization  ✅

**Location:** `lib/tir/mono.ml`
**Stage:** TIR (first pass after Lower)

Generates type-specialized copies of polymorphic functions at all call sites. Type variables are replaced with concrete types; the resulting module has no `TVar` nodes.

**Why it matters for March:** Unboxed primitives require monomorphic types. Inlining works better on monomorphic code. Most critically, LLVM IR cannot represent polymorphism — monomorphization is required for code generation.

**Effort:** Medium (done) | **Impact:** Essential (enables all downstream passes)
**Dependencies:** None (first TIR pass)

---

### 12. Defunctionalization / Closure Conversion  ✅

**Location:** `lib/tir/defun.ml`
**Stage:** TIR (after Mono, before Perceus)

Converts higher-order functions to first-order code:
1. Each unique lambda/closure type becomes a `TDClosure` struct carrying its free variables
2. Each closure application site is replaced with an `ECallPtr` through a dispatch table
3. Apply-functions (`apply_N_M`) are generated for each arity

This eliminates the need for a general function-pointer representation and makes closure allocation explicit (one `EAlloc` per closure creation site), enabling Escape analysis and Perceus to handle closure lifetimes.

**Effort:** High (done) | **Impact:** Essential (required for LLVM)
**Dependencies:** After Mono; before Perceus/Escape

---

### 13. Static Capture-Free Closures  ✅

**Location:** `lib/tir/llvm_ctx.ml` (`intern_static_closure` + `static_clos` memo), `lib/tir/llvm_emit.ml` (both closure-materialization sites, plus the `EAlloc` arm covering capture-free lambdas)
**Stage:** LLVM emission (codegen), after Defunctionalization

When a top-level function is materialized as a first-class value (`let f = some_fn`, passed as a callback, stored in a data structure, etc.) and the closure it produces captures nothing, the previous codegen allocated a fresh 24-byte closure object on the heap (`march_alloc(i64 24)`) at *every* materialization site, every time it executed. Because the closure never escapes to anything that would free it via normal RC, and because each materialization allocates independently of any other, repeatedly materializing the same function value as a first-class value leaked one object per materialization — unbounded growth in a loop.

The fix replaces per-materialization heap allocation with a single immortal `internal global` per top-level function used as a value: `@<fn>$static_clo`, of LLVM type `{i64, i32, i32, ptr}` (refcount, tag, `march_hdr.pad`, code pointer — see `runtime/march_runtime.h`), refcount pre-set to `MARCH_RC_IMMORTAL` (1099511627776). RC inc/dec on the global still execute — e.g. `march_incrc_local` is emitted directly against `@<fn>$static_clo` at ordinary call sites — but because the refcount starts (and stays) at the immortal sentinel, those atomic read-modify-writes never drive it to zero and so never free the object: they are *never-freeing*, not no-ops. `intern_static_closure` memoizes by function name so repeated materializations of the same function within a module resolve to the same global, and distinct functions get distinct globals (no collision — verified in `test/native/static_closure_semantics.march`).

**Why this object can be fully static, unlike (e.g.) the string-literal cell pattern:** a capture-free closure's entire contents are compile-time constants — the code pointer is a fixed address, and there is no per-instance captured environment to fill in at runtime. A string-literal cell still needs a runtime fill-once (length, hash) because those depend on the literal's own bytes, which is why that pattern uses lazy initialization instead of a fully-constant global. Here there is nothing left to compute at runtime, so the global can be emitted with its final contents baked in at compile time.

**`internal global` vs `constant`:** the global is declared mutable (`internal global`, not `internal constant`) because the refcount field is still touched by ordinary RC inc/dec code emitted at call sites that don't know the pointee is immortal — those operations must remain valid stores. They genuinely execute (they are never-freeing, not no-ops — see above); they simply never drive the refcount out of the immortal range. Marking it `constant` would make those routine RC stores undefined behavior under LLVM's constant-global rules.

**Extended to capture-free lambdas (2026-07-28):** the same mechanism now also covers anonymous lambda expressions that capture nothing (`fn x -> x * 2` passed directly as a value), not just top-level named functions. The discriminator is derived purely at emission — no `defun.ml` change was needed: any closure-struct allocation (`Tir_names.is_clo_struct`) whose `EAlloc` carries **exactly one** argument (the code pointer; no captured-environment fields) is by construction a capture-free closure and routes to `intern_static_closure` exactly like a top-level function value does. A capturing closure's `EAlloc` always carries at least one additional argument per captured variable, so it never matches this shape and keeps allocating fresh — see "Capturing closures still allocate" below. No `$clo_wrap` trampoline needs to be generated for the lambda case: the lifted apply function defunctionalization already produces has the `(clo_ptr, params…)` closure-call ABI, which is exactly what `intern_static_closure`'s global's code-pointer field expects, so the named-function and lambda cases share the same interning path with no extra indirection.

**Scope is broader than "anonymous lambda literals":** `defun.ml` lifts *every* `ELetRec`-bound local function through this same closure-struct path, so any capture-free defunctionalized closure is covered — including local named helpers, not only `fn ... -> ...` expressions written inline. For example, compiling a `List.map` call and inspecting the emitted IR (`--emit-llvm`) shows `@$Clo_go$3418$static_clo` and `@$Clo_go$5102$static_clo`: the stdlib's recursive `go` accumulator (a local named helper, not an anonymous lambda) is capture-free and gets the exact same immortal-global treatment. This is behaviorally sound — the discriminator only inspects the `EAlloc` arity, not how the closure was written — but it means module-lifetime shared objects now show up for stdlib hot-path helpers, not just user-written lambda literals.

**Capturing closures still allocate, deliberately:** a closure that captures a free variable has contents that differ per instance (the captured value), so unlike a capture-free closure it cannot be represented as a single module-lifetime static object — collapsing distinct captured environments into one shared global would be a correctness bug, not an optimization. Making capturing closures avoid the per-materialization allocation is a separate, still-open item (see `specs/todos.md`) that needs real ownership work in `lib/tir/perceus.ml`/`lib/tir/borrow.ml` (e.g. proving a closure never escapes its call site), not a codegen-only change like this one.

**Exclusions (gated off via a single shared `static_closure_ok` predicate for the named-function case):**
- **REPL / JIT** (`ctx.repl`): each REPL evaluation compiles and links a fresh module; a `static_closure_ok`-gated `internal global` baked into one JIT'd module cannot be safely reused or safely thrown away across the REPL's incremental-compilation lifecycle the way an AOT module's globals can.
- **Hot-reload boundary functions** (`ctx.hr_config` + `Hot_reload.is_reloadable`): this exclusion is defensive, not a fix for a demonstrated staleness bug. The fresh-alloc fallback bakes in the identical `@<fn>$clo_wrap` pointer, and `clo_wrap_define` (`lib/tir/llvm_calls.ml:180-190`) already emits a hardcoded direct `call @<fn>` that bypasses the versioned HCR dispatch table regardless of which materialization path is used — a pre-existing, already-documented HCR gap this change does not touch. The exclusion keeps this change strictly non-regressive for HCR rather than claiming to fix that gap.

The lambda arm (`lib/tir/llvm_emit.ml`'s `EAlloc (TCon (tcon_name, _), [fn_ptr_atom]) when Tir_names.is_clo_struct tcon_name` case) mirrors `static_closure_ok` for the REPL/JIT exclusion (`not ctx.repl`) but is **more conservative** for hot-reload: `static_closure_ok` resolves a March-level dotted name via `Hot_reload.module_of_name` to check whether that *specific* function is a reload boundary, but a defunctionalized lambda's synthetic type-constructor name (`"$Clo_" ^ fn_name ^ "$" ^ uid`) cannot always be unambiguously demangled back to the owning function name (it may itself embed `$`, e.g. inside an interface-impl mangled name). Rather than risk resolving the wrong module, static lambdas are disabled outright whenever `ctx.hr_config` is set at all (`Some _ -> false`, no `is_reloadable` lookup), not just for functions hot-reload actually tracks as boundaries.

**Measured impact, named top-level function values** (4,000,000 materializations, compiled `--opt 2`):

| | obj_allocs | peak RSS | wall |
|---|---:|---:|---:|
| Before | 4,000,000 | 125.4 MB | 0.09s |
| After | 0 | 2.9 MB | 0.01s |
| Control (direct call, no fn value) | 0 | 2.9 MB | 0.01s |

**Measured impact, capture-free lambda values** (4,000,000 iterations of `apply_it(fn x -> x * 2, i)`, compiled `--opt 2`):

| | obj_allocs | peak RSS |
|---|---:|---:|
| Before | 4,000,000 | ~131.5 MB |
| After | 0 | ~2.99 MB |

Compiled and interpreted output are byte-identical before and after. Materializing a capture-free function value is now as cheap as calling it directly (a claim backed by a wall-clock control for the named-function case); for lambdas, the measured win is allocations and RSS as shown above — no wall-clock benchmark was run for the lambda case, so no "as cheap as calling it directly" claim is made there (see `specs/progress.md`'s "No wall-clock speedup is claimed" note). In both cases the per-materialization leak is gone. This does **not** cover closures that capture a free variable — see `specs/todos.md` for that distinct, still-open leak.

**Effort:** Medium (done) | **Impact:** Removes an unbounded-growth leak; makes capture-free function values free to materialize (wall-clock-verified) and eliminates per-materialization allocation/RSS for capture-free lambdas
**Dependencies:** After Defunctionalization (needs closure representation established); orthogonal to Perceus/borrow (no ownership-pass changes)
**Tests:** `llvm_builtins_preamble_golden` ("static closure global replaces per-materialization march_alloc", "static closure global is not emitted in REPL mode"), `test/native/static_closure_no_leak.march` (named-function growth-bounded regression), `test/native/static_closure_semantics.march` (compiled/interpreted parity, no cross-function collision). Lambda case: `test_lambda_static_closure_materialization_no_leak_compiled` (`test/test_codegen.ml`, "compiled capture-free lambda materialization does not leak per use"), `test/native/static_lambda_no_leak.march` (native golden: two distinct capture-free lambdas resolve to 4 distinct `$static_clo` globals with none shared, plus a capture-free lambda alongside a capturing one to confirm the discriminator separates them at runtime).
**Status:** Done (2026-07-28)

---

## Planned Optimizations

### P1 — Let-Floating / Join Points

**Motivation:** In a match expression with N arms, if each arm contains the same sub-expression `e`, the compiler currently emits N copies of `e`. Let-floating hoists `e` above the match (or to a shared join point).

**Example:**
```march
-- Before
match x do
| A -> expensive_fn(y) + 1
| B -> expensive_fn(y) + 2
end

-- After (join-point style)
let v = expensive_fn(y)
match x do
| A -> v + 1
| B -> v + 2
end
```

**Why it matters for March:** Pattern matching is pervasive. Shared match-arm computations are the norm, not the exception. GHC considers join points its single biggest optimization.

**Effort:** High | **Impact:** Very high
**Dependencies:** Must run before Inline and Fold (to expose shared structure)
**Stage:** TIR pass — `lib/tir/join_points.ml`; `run_pre` pre-Perceus + `run` first in `lib/tir/opt.ml` fixed-point loop
**Status:** Layer 1 done (alpha-merge, pre-Perceus). Layers 2–3 open.

**Implementation:** `lib/tir/join_points.ml` detects and hoists `let` bindings that appear identically at the start of EVERY case branch (including the default), structurally equal RHS (via `expr_eq`), RHS not mentioning any pattern-bound variable, floated name not pattern-bound. `expr_eq` checks deep structural equality of atoms and all expression forms.

Two entry points:
- **`run`** (conservative): requires identical *binder names* across arms. Runs in the `opt.ml` fixed-point loop as the first pass (before `known-call`, `inline`, `cprop`) so floated lets are visible downstream in the same iteration. Safe post-Perceus because the hoisted let is identical (incl. RC ops) in every arm.
- **`run_pre`** (Layer 1 — alpha-merge): allows arms to bind the shared RHS under *different* names (the common case after ANF, where each arm gets a fresh temporary). Floats one fresh `$jp…` binder and substitutes each arm's binder onto it via `rename_expr`. Wired in `bin/main.ml` **before** `Perceus.perceus` (after `beta-adt`, gated on `opt_enabled`) so RC is inserted once for the hoisted binding — renaming RC-decorated bindings post-Perceus is unsafe (double-free class). Loops internally to a fixpoint. 6 tests in `join_points` group (`pre_float_alpha`, `pre_no_float_diff_rhs` added).

Because TIR is in ANF, a shared inline sub-expression like `expensive(y)` in `expensive(y)+1` / `expensive(y)+2` is already a head `let` with a fresh temporary per arm — so Layer 1 captures the spec's motivating example.

**Remaining:**
- **Layer 2 — non-leading / interleaved common lets.** Today only the *first* let of each arm is peeled. Generalize to a common pure binding anywhere in each arm's leading let-chain whose RHS does not depend on arm-specific earlier bindings, with reordering. Medium.
- **Layer 3 — general non-let-bound cross-arm CSE.** Hoist shared sub-expressions ANF did not already lift to a head let. Mostly subsumed by ANF; low marginal value. Would gate on `Purity.is_pure`.
- **(Not planned) true GHC continuation join points.** March lowers `ECase` straight to an LLVM `switch` with a natural CFG merge block, so the continuation-duplication that join points solve in GHC does not arise here; little payoff absent aggressive case-of-case floating.

---

### P2 — Known-Call Optimization  ✅

**Location:** `lib/tir/known_call.ml`
**Stage:** TIR pass — runs between Defun and Perceus (for max inlining benefit),
and again in the Opt coordinator fixed-point loop.

After Defun, every lambda becomes a TDClosure struct allocated with `EAlloc`, and
every call site becomes `ECallPtr` (indirect dispatch through a function pointer
stored in field 0 of the struct).  When the closure variable is provably bound to a
specific `EAlloc` in scope, the indirect dispatch is unnecessary:

```
ELet(clo, EAlloc("$Clo_foo$N", [AVar(foo$apply$N); fv1; ...]), body)
  body contains: ECallPtr(AVar clo, args)
→
  body contains: EApp(mk_var "foo$apply$N", [AVar clo] ++ args)
```

**What it detects:**
- Heap-allocated closures: `ELet(v, EAlloc(TCon("$Clo_...", _), fn_ptr :: _), body)`
- Stack-promoted closures (after Escape): same pattern with `EStackAlloc`
- Both covered by `is_clo_name` prefix check

**Pipeline interaction:** Running before Perceus means the apply functions (which
consist of `EField` loads — pure) are still pure and eligible for inlining by
`inline.ml`.  Running again in the Opt loop catches closures revealed by other
optimizations after Perceus/Escape.

**Inline threshold update:** `inline.ml` threshold raised from 15 → 50 TIR nodes
to cover typical HTTP middleware helpers (header accessors, Conn builders) that are
slightly larger than utility functions but still profitable to inline.

**Why it matters for March:** HTTP middleware pipelines pass closures (plug handlers)
as arguments.  Without known-call, every plug dispatch is an indirect call through a
function pointer loaded from a heap struct — unpredictable for the branch predictor
and invisible to the inliner.  With known-call, the dispatch becomes a direct call
that can then be inlined.

**Effort:** Medium (done) | **Impact:** High (combined with Inline)
**Dependencies:** After Defun; feeds into Inline
**Tests:** `known_call` group in `test/test_march.ml`

---

### P3 — Mutual TCO (Shared Loop with Dispatch)  ✅

**Location:** `lib/tir/llvm_emit.ml` (`find_mutual_tco_groups`, `emit_mutual_tco_group`)
**Stage:** LLVM IR emission

Extends self-TCO to handle mutually recursive tail calls. When a group of ≥ 2 functions form a strongly connected component in the tail-call graph and all cross-group calls are in tail position, the group is compiled into a single combined dispatch function with a shared loop.

**How it works:**
1. **Detection (Tarjan's SCC):** `tarjan_sccs` builds the tail-call adjacency graph and finds SCCs. `find_mutual_tco_groups` filters SCCs where (a) all cross-group calls are tail calls and (b) all functions share the same LLVM return type.
2. **Combined function:** `emit_mutual_tco_group` emits one `@__mutco_f_g__` function with an extra `i64 %__tag__.arg` dispatch parameter. Each original function's parameters get their own alloca slots. The loop header switches on the tag to dispatch to each function's body.
3. **Back-edge:** The `EApp` handler in `emit_expr` detects calls to group members and emits: update dispatch tag → update target's param slots → `br label %mutual_loop`.
4. **Wrapper functions:** Each original function name emits as a thin wrapper that calls the combined function with the appropriate tag and `undef` for the other functions' params.

**Example IR for `even/odd`:**
```llvm
define i64 @__mutco_even_odd__(i64 %__tag__.arg, i64 %even__n.arg, i64 %odd__n.arg) {
mutual_loop:
  switch i64 %tag_v [ i64 0, label %case_even   i64 1, label %case_odd ]
case_even:   ; if n==0: ret 1; else store 1/tag, store n-1/odd_slot; br mutual_loop
case_odd:    ; if n==0: ret 0; else store 0/tag, store n-1/even_slot; br mutual_loop
}
define i64 @even(i64 %n.arg) { %r = call i64 @__mutco_even_odd__(0, %n.arg, undef); ret }
define i64 @odd(i64 %n.arg)  { %r = call i64 @__mutco_even_odd__(1, undef,  %n.arg); ret }
```

**Why it matters for March:** Mutual recursion is common in state machines, parser combinators, and parity-style algorithms. Without mutual TCO, these blow the stack on deep inputs. With it, even 10M-iteration mutual loops run in O(1) stack space.

**Effort:** High (done) | **Impact:** Medium (niche but correctness-critical when hit)
**Dependencies:** Self-TCO; Mono (functions must be monomorphic to share a loop)
**Tests:** `mutual_tco_codegen` group in `test/test_march.ml` (5 tests)
**Benchmark:** `bench/mutual_recursion.march`
**Status:** Implemented

---

### P4 — Lambda Lifting (Complementary to Defun)

**Motivation:** Defun converts closures to structs + apply-functions. Lambda lifting is an alternative that converts closures to top-level functions by adding free variables as explicit parameters. For closures with few free variables, lifting produces smaller code than struct allocation.

**When to apply:** Closures with ≤ 2 free variables, where Escape analysis cannot stack-promote the struct. Currently Defun handles all closures uniformly.

**Effort:** Medium | **Impact:** Low-Medium
**Dependencies:** After Escape; before LLVM emit
**Stage:** TIR pass
**Status:** Deferred (Perceus + Escape already handle most cases)

---

### P5 — Specialization of Stdlib Polymorphic Functions

**Motivation:** Monomorphization already specializes user code. Some stdlib functions (e.g., `List.sort_by`, `Map.lookup`) are called with many different type instantiations. Specialization caches the most common instantiations.

**Why it matters for March:** Compile time and binary size. Currently mono generates one copy per unique type; specialization with sharing would reduce binary size for programs that use the same type in many places via different call paths.

**Effort:** Medium | **Impact:** Low-Medium (binary size / compile speed)
**Dependencies:** After Mono
**Stage:** TIR pass (merge duplicate mono specializations)
**Status:** Deferred

---

### P6 — Representation Polymorphism / Unboxed ADT Fields

**Motivation:** Currently `type Point = Point(Int, Int)` always allocates a heap struct with an RC word, even when the `Point` is immediately pattern-matched and never escapes. Full unboxing would represent a `Point(3, 4)` as two `i64` values on the stack rather than a heap pointer.

This is distinct from escape analysis (which stack-allocates the struct) — true unboxing eliminates the struct entirely, representing the constructor's payload as a flat sequence of machine values in registers/on stack.

**Why it matters for March:** Zero-cost wrapper types and newtype-style patterns would have zero overhead. Critical for performance-sensitive numeric types.

**Effort:** Very high | **Impact:** Very high (but complex)
**Dependencies:** Escape analysis; linear/affine type information
**Stage:** TIR type system + LLVM emit
**Status:** Research — requires TIR type extension for unboxed variants

---

### P7 — Borrow Inference and Elision  ✅

**Location:** `lib/tir/borrow.ml` (analysis) + `lib/tir/perceus.ml` (RC integration)
**Stage:** TIR (before Perceus RC insertion)

**Motivation:** When a value is passed to a function that only reads it (doesn't store, return, or alias it), the compiler can insert a *borrow* instead of an RC increment/decrement pair. Borrow elision goes further: when the borrowed value's lifetime is trivially scoped (e.g., read within the callee and never escapes), the borrow tracking itself is elided — no refcount operations at all.

**Example:**
```march
fn sum_lengths(xs, ys) do
  -- xs and ys are only read here, not consumed
  List.length(xs) + List.length(ys)
end
```

Without borrow inference, `xs` and `ys` each get `inc_rc` on entry and `dec_rc` on exit. With borrow inference, both are borrowed (no RC ops). With borrow elision, the borrow annotation itself is stripped since the lifetime is trivially contained.

**Why it matters for March:** Perceus RC is already implemented, but every function call currently pays inc/dec costs even for read-only parameters. In tight loops and deeply nested function calls (common in functional style), the cumulative RC traffic is significant. Borrow inference can eliminate 30-50% of RC operations in typical March programs.

**Interaction with linear/affine types:** If a value is declared `affine`, the compiler already knows it can be borrowed freely (at most one owner). If `linear`, borrowing is even simpler since there's exactly one owner — no RC at all. Borrow inference extends this benefit to regular (non-annotated) values by analyzing usage patterns.

**Implementation approach:**
1. Add a pre-Perceus analysis pass (`lib/tir/borrow.ml`) that marks each variable use as "consume" or "borrow"
2. A use is a borrow if: the callee doesn't store the value in a constructor, doesn't return it, and doesn't alias it into a longer-lived binding
3. Perceus then skips `EIncRC`/`EDecRC` for borrow-marked uses
4. Elision: if all uses of a binding are borrows and the binding's scope is a single basic block, skip even the borrow marker

**Effort:** Medium (done) | **Impact:** High (reduces RC overhead 30-50% in typical code)
**Dependencies:** Runs before Perceus; benefits from Escape analysis information
**Stage:** TIR pass — `lib/tir/borrow.ml`
**Tests:** `borrow_inference` group in `test/test_march.ml` (10 tests)
**Status:** Implemented

---

### P8 — Constructor Reuse (FBIP Extension)

**Motivation:** Perceus already implements basic FBIP with `EReuse` tokens for pattern-match-and-rebuild patterns. This extension broadens constructor reuse to cover cases where the rebuilt constructor has a *different* tag but the same allocation size, and cases where the destruction and reconstruction are separated by intervening code.

**Example:**
```march
-- Current FBIP handles: same constructor, immediate rebuild
fn inc_leaf(t) do
  match t do
  | Leaf(n) -> Leaf(n + 1)       -- reuses Leaf cell in-place
  | Node(l, r) -> Node(inc_leaf(l), inc_leaf(r))  -- reuses Node cell
  end
end

-- Extended reuse: different tag, same size
fn leaf_to_node(t) do
  match t do
  | Leaf(n) -> Node(Leaf(0), Leaf(n))  -- Leaf cell reused for one of the new Leafs
  end
end
```

**Why it matters for March:** Tree transformations that change node types (e.g., balancing a tree, converting AST node kinds) currently allocate fresh even when the old cell has the right size. Extended reuse captures these cases.

**Effort:** Medium | **Impact:** Medium-High (tree-heavy workloads)
**Dependencies:** Perceus (extends existing reuse logic)
**Stage:** TIR pass — extends `lib/tir/perceus.ml`
**Status:** Done

**Implementation:** Replaced `shape_matches` (name equality) with `same_arity` (field-count equality) in `lib/tir/perceus.ml`. `add_scrutinee_free_for` encodes the consumed constructor's arity as dummy `TUnit` type-args in the DecRC var's type (`TCon(qualified_tag, [TUnit; …])`), so `same_arity` can compare field counts without type definitions. `try_fbip_sink` and `fbip_expr` both use `same_arity dec_v.v_ty (List.length args)` instead of name equality. Cross-ctor reuse is safe because March allocates `[tag + nfields × ptr]` blocks — same arity ⟺ same block size; the new tag is written into the reused cell by `llvm_emit`. 5 new tests in `fbip_p8` group (`same_arity` unit tests + `fbip_expr` integration tests).

---

### P9 — Columnar DataFrame Layout (Struct-of-Arrays)

**Motivation:** The current DataFrame implementation stores data row-oriented (each row is a record/tuple). Analytical workloads (filter, aggregate, group-by) typically touch a few columns out of many. A columnar (Struct-of-Arrays) layout stores each column as a contiguous typed array (`i64[]`, `double[]`, `string[]`), which delivers:

1. **Cache efficiency** — scanning a single column reads sequential memory, not strided
2. **SIMD friendliness** — contiguous typed arrays can be processed 4-8 elements at a time with vector instructions
3. **Compression** — same-type columns compress much better (dictionary encoding, run-length, delta)
4. **Predicate pushdown** — filter expressions evaluate on column arrays without materializing full rows

**Example (internal representation):**
```march
-- Row-oriented (current):  [{name="Alice", age=30}, {name="Bob", age=25}]
-- Columnar (SoA):          {names=["Alice","Bob"], ages=[30,25]}

-- Column scan for sum:
fn sum_ages(df) do
  let col = df.column("age")   -- contiguous i64 array
  Array.fold(col, 0, fn acc x -> acc + x)  -- sequential memory access
end
```

**Why it matters for March:** March already has a DataFrame stdlib, but row-oriented layout makes it fundamentally non-competitive with Polars/DuckDB for analytical queries. Columnar layout is the single biggest architectural change to make March DataFrames production-grade. Combined with stream fusion (already implemented), column operations would fuse into tight vectorizable loops.

**Implementation approach:**
1. Internal `ColumnStore` type: `type Column = IntCol(Array(Int)) | FloatCol(Array(Float)) | StrCol(Array(String)) | BoolCol(Array(Bool)) | NullableCol(Column, BitArray)`
2. DataFrame becomes `{ columns: Map(String, Column), row_count: Int }`
3. Operations (filter, map, agg) work on column arrays directly
4. Lazy evaluation: chain of column transforms compiles to a single fused pass
5. Optional: Apache Arrow IPC format for zero-copy interop

**Effort:** High | **Impact:** Very high (10-100x for analytical workloads)
**Dependencies:** Array primitives in runtime; benefits from loop vectorization (P10)
**Stage:** Stdlib + runtime — `stdlib/dataframe.march` rewrite + native array builtins
**Status:** Implemented (interpreter-level) — `VTypedArray of value array` added to `lib/eval/eval.ml` with 10 builtins (`typed_array_create/get/set/length/slice/map/filter/fold/from_list/to_list`); `TypedArray(a)` registered in `lib/typecheck/typecheck.ml`; `stdlib/dataframe.march` Column variants rewritten from `List(X)` to `TypedArray(X)` with null bitmaps as `TypedArray(Bool)`; `filter_col_by_mask` using single-pass `typed_array_filter`; all operations updated. 75/75 DataFrame tests pass.

---

### P10 — Array Loop Vectorization

**Motivation:** Numeric array operations (sum, map, fold) are the backbone of DataFrame
queries, statistical computation, and scientific computing.  Without contiguous memory and
vectorization hints, March leaves 4–8× performance on the table for these workloads.

**Key constraint discovered during implementation:** The stdlib `Array` module is a
32-way persistent trie (`PVec`).  This means there are no contiguous numeric loops in
the current LLVM IR — TCO loops traverse linked-list/trie structures, not flat memory.
Real vectorization requires a flat-array primitive type.

---

**Phase 0 — Alias-analysis hints (done, 2026-03-25):**

Added `nonnull dereferenceable(16)` to all `ptr` function parameters in
`lib/tir/llvm_emit.ml`.  Every March heap object has a 16-byte header (rc + tag + pad)
and `march_alloc` calls `exit(1)` on OOM so pointers are never null.  This allows LLVM
to eliminate null-check branches and perform more aggressive alias analysis across all
March programs — not just numeric ones.

Files changed: `lib/tir/llvm_emit.ml` (added `llvm_param_ty` helper).

---

**Phase 1 — NativeArray interpreter fast path (done, 2026-03-25):**

Added flat OCaml array types `VNativeIntArr` / `VNativeFloatArr` to the interpreter
value type in `lib/eval/eval.ml`, with the following builtins:

| Builtin | Description |
|---|---|
| `native_int_arr_make(n, init)` | Allocate flat int array |
| `native_int_arr_length(arr)` | O(1) length |
| `native_int_arr_get(arr, i)` | O(1) element access |
| `native_int_arr_set(arr, i, v)` | O(n) functional update |
| `native_int_arr_sum(arr)` | **Tight loop** — sum all elements |
| `native_int_arr_map(arr, f)` | **Tight loop** — map a function |
| `native_int_arr_fold(acc, arr, f)` | **Tight loop** — left fold |
| `native_int_arr_from_list(lst)` | Build from List(Int) |
| `native_int_arr_to_list(arr)` | Convert to List(Int) |
| *(float variants: same API, prefix `native_float_arr_*`)* | |

Wrapped in `stdlib/native_array.march` (NativeArray module).

Benchmark: `bench/array_numeric.march` measures List fold vs NativeArray tight loop
for sum, map, and fold over 100 000 elements.

---

**Phase 2 — NativeArray compiled path (done, 2026-06-18):**

Pragmatic approach: register C runtime functions directly as builtins in the LLVM emitter without adding a new `TNativeArray` TIR constructor. This avoids touching the TIR type algebra while delivering full compiled-path support.

Changes:
- `lib/tir/llvm_emit.ml`:
  - All 16 `native_int_arr_*` / `native_float_arr_*` functions added to `is_builtin_fn` (prevents erroneous RC wrapping and reduction-counter insertion)
  - `builtin_ret_ty` entries: `i64` for length/get/sum; `ptr` (TCon("NativeIntArr/NativeFloatArr", [])) for make/set/map/from_list/to_list; `double` for float get/sum
  - 16 explicit `declare` lines in the LLVM preamble (correct LLVM types: `i64` vs `double` vs `ptr` per builtin)
- `runtime/march_runtime.c`:
  - `native_int_arr_from_list`: reads tagged ptr fields (`(raw & 1) ? raw >> 1 : raw`) before writing to flat array
  - `native_int_arr_to_list`: tags before storing to Cons cells (`(v << 1) | 1`)
  - Float from_list/to_list: correct as-is (floats use bitcast convention, not tag-bit scheme)

Testing: 2 new IR-level tests in `native_arrays` group (`int arr IR`, `float arr IR`) verify all 16 builtins appear in the emitted LLVM IR with correct return types.

**Correction (2026-07-24):** the Phase 2 claim above ("LLVM auto-vectorizes the runtime C loops at `-O2`/`-O3`") only held for `native_int_arr_sum`. `native_float_arr_sum` was **not** actually vectorizing — clang emitted vector *loads* for memory bandwidth but fell back to sequential scalar `fadd`s for the reduction itself, because strict IEEE 754 forbids reassociating floating-point addition (the compiler can't prove `(a+b)+c == a+(b+c)` for arbitrary doubles) and reduction vectorization requires reassociating across SIMD lanes. Fixed in `runtime/march_runtime.c` `native_float_arr_sum` by scoping `#pragma clang fp reassociate(on)` to just that loop (not a blanket `-ffast-math`, which would also relax NaN/Inf/subnormal handling program-wide). Confirmed via `-S -emit-llvm`/asm inspection: before the fix the loop had zero `fadd.2d`/`vaddpd` instructions; after, it vectorizes to 4-way unrolled 128-bit NEON/SSE lane adds. A compiled microbenchmark (20× `sum_float` over 5M elements) measured ~3× lower CPU time after the fix; results match to within last-bit rounding (expected — multi-lane summation is a different but no-less-accurate reduction order than strict left-to-right). `native_int_arr_map`/`native_float_arr_map` remain unvectorized and unvectorizable as C runtime functions: the loop body calls an opaque closure pointer per element (`clo_call_int_int`/`clo_call_dbl_dbl`), which blocks the auto-vectorizer regardless of flags — fixing that requires Phase 3's approach (inlining the loop, and the closure call, directly into the caller's LLVM IR so simple non-capturing lambda bodies can be inlined and vectorized).

**Fixed (2026-07-25):** while probing `native_float_arr_map` for this fix, discovered its compiled path segfaulted (`bench/array_numeric.march --compile` crashed at the "NativeFloatArr map" step; reproduced on unmodified HEAD, pre-existing and unrelated to the sum fix above). Root cause: `clo_call_int_int`/`clo_call_dbl_dbl` (`runtime/march_runtime.c`) reinterpreted a closure's fn pointer as a native C signature (`int64_t(void*,int64_t)` / `double(void*,double)`), but every March closure actually presents the uniform erased-`ptr` ABI documented at `lib/tir/llvm_calls.ml`'s `clo_wrap_define`/`is_apply_fn`: scalar args/returns are wire-tagged `(n<<1)|1`, Float args/returns are boxed via `march_alloc_float`/`march_unbox_float`. For Float this is a hard register-class mismatch (the argument lands in an XMM/vector register while the real apply function reads a GPR) — total corruption, hence the SIGSEGV. For Int it happened to occupy the right register (int64 and ptr share the GPR calling convention) but skipped the tag/untag round-trip, so it silently returned **wrong answers for every element**, not just odd ones (verified: `[1,2,3,4] map (*2) sum` returned 20 instead of 24) — the "int map works fine compiled" assumption in the original bug report was itself wrong. Fixed by routing both helpers through the closure's actual ptr-ABI fn pointer (still at offset 16, that part was correct) with proper tag/box on the way in and untag/unbox on the way out. Regression test: `test/native/native_arr_map_closure_abi.march` (in the `test_oracle` curated allowlist), exercising both int and float map+sum round-trips compiled.

**Phase 2b — inline non-capturing `map` closures (done, 2026-07-25):** unblocks the "requires Phase 3's approach" note above for the common case. New pass `lib/tir/native_map_inline.ml` runs after Opt (inlining must have already flattened the `NativeArray.map_int`/`map_float` stdlib wrapper into its call site — at Defun time the closure allocation and the `native_int_arr_map`/`native_float_arr_map` call are still in two different function bodies). It detects the specific shape Defun always produces for a *fresh, non-capturing* lambda used exactly once as the map callback (walking past the `let f = clo in ...` alias hop Cprop leaves behind, since Cprop deliberately never propagates closure-typed copies) and rewrites the call to a synthetic `__native_int_arr_map_inline`/`__native_float_arr_map_inline` node carrying the lifted apply fn's name directly, dropping the now-unneeded closure allocation. `lib/tir/llvm_emit.ml` emits a hand-rolled loop (GEP load, tag/box the element into the closure ABI's wire `ptr`, a **direct** call to the apply fn — same LLVM module as the caller, unlike the old call through the C runtime's opaque closure-pointer field, which crosses a translation-unit boundary and can never be inlined — untag/unbox, GEP store). Two tiny new runtime helpers (`native_int_arr_alloc_raw`/`native_float_arr_alloc_raw`) allocate the uninitialized result buffer. Native/wasm `--compile` only (the JS backend has no matching codegen arm, guarded off in `bin/main.ml`); a capturing lambda, one reused elsewhere, or one whose closure survives Perceus with extra RC traffic simply doesn't match the pattern and falls back to the general (correct, per Phase 2's ABI fix above) closure-call path — never a correctness risk, only a missed optimization.

Verified via `-S -emit-llvm` + clang asm inspection: for `fn x -> x * x * 3 + x * 7 - 5`, LLVM's own inliner folds the now-direct apply-fn call into the loop, and instcombine cancels the tag/untag round-trip entirely for Int, leaving a plain scalar loop that clang vectorizes to NEON (`shl.2d` observed for a `* 2` body). **Honest result:** this doesn't show up as a measurable wall-clock win in a straightforward `map`-then-`sum` benchmark over a multi-megabyte array — the loop is memory-bandwidth-bound (one read + one write of the whole array dominates a few cycles of now-vectorized ALU work), not compute-bound, so per-element compute latency wasn't the bottleneck to begin with. The codegen change is real (allocation removed, indirect call removed, vectorizable instructions emitted) but the workload shape it was aimed at — `sum`'s pure-reduction Phase 2 fix above — is where the technique actually pays off; `map` benefits mainly for `NativeArray` element bodies expensive enough to be compute- rather than bandwidth-bound. Regression test: `test/native/native_arr_map_inline_vectorize.march` (odd/even/negative ints, non-trivial arithmetic, float, empty array, and a capturing-closure fallback case, all compiled).

**Fixed (2026-07-26): inline path never fired when the mapped array was reused afterward.** `strip_alias_chain` (the helper that walks past the `let f = clo in ...` alias hop) only pattern-matched a bare `ELet` immediately following the closure alloc. Whenever `arr` is used again after the `map` call — e.g. a self-recursive loop function that maps `arr` and then passes `arr` on to its own tail call — Perceus inserts an `inc_rc arr;` (`ESeq`) between the alloc and the alias-let to keep `arr` alive for the later use. `strip_alias_chain` had no case for `ESeq`, so it bailed out and silently fell back to the slower closure-indirection path for this shape — not a correctness bug, but "map an array you're about to use again in a loop" is an extremely common pattern, so this quietly ate most of the practical benefit of Phase 2b. Fixed by having `strip_alias_chain` return the list of wrapper expressions it peels through (in original order) alongside the alias name, so `rewrite_expr` can re-wrap the rewritten body in the same `ESeq`s afterward — the wrapper is relocated, never dropped or reordered, which matters because an `EIncRC`/`EDecRC`/`EFree` there is a real reference-count operation (dropping it would be a UAF/premature-free bug, not just a missed optimization). As a safety guard, a wrapper is only peeled through when it does *not* itself mention the alias name being tracked (an RC op on the closure var itself, rather than some unrelated var, stops the walk instead of risking a miscounted "used exactly once" check). Regression test: `test/native/native_arr_map_inline_reuse.march`, which asserts both correctness (a self-recursive loop mapping and reusing an array) and — via `--emit-llvm` grepped for the `nmap_pre`/`nmap_cond` block-label prefixes the codegen arm emits — that the inline path actually fires for this shape.

**Phase 2c — inline CAPTURING `map` closures (done, 2026-07-27):** extends Phase 2b beyond non-capturing lambdas to the more common `stdlib/dataframe.march` shape — `fn x -> x +. f` / `fn x -> x *. f`, where `f` is a captured scalar (DataFrame's `col +. scalar` / `col *. scalar`). A capturing closure's apply body genuinely reads its free variables from `$clo` (via `EField`), so unlike Phase 2b it can't just drop the allocation — `Native_map_inline.ml` instead leaves the allocation, any alias-copy lets, and any Perceus RC ops around it completely untouched, and rewrites only the terminal call site to a 3-argument form (`EApp(inline_name, [arr; apply_fn; clo])`) that keeps the real closure pointer instead of dropping it. `llvm_emit.ml`'s loop codegen was factored into a shared `emit_native_map_inline_loop` helper parameterized on the `$clo` register — Phase 2b's call site passes the literal `"null"`, Phase 2c's passes the real (coerced-to-`ptr`) closure value; everything else about the loop (length, alloc, GEP, tag/box, direct call, untag/unbox, store) is unchanged and shared between both. Once the direct call is inlined, the free-variable load is a plain GEP+load on a loop-invariant pointer, which LLVM's LICM typically hoists above the loop entirely — so `fn x -> x +. f` reduces to one hoisted load of `f` plus a per-element `fadd`, the same vectorization shape as Phase 2b's non-capturing case.

One bug found and fixed during implementation: the eligibility check for the capturing case initially called `count_uses` on the *unstripped* tree (which still contains the closure's own alias-copy `let`), and `count_uses`'s `ELet` case treats a rebinding of the tracked name as "a distinct shadowed variable, stop counting" — exactly wrong when the "rebinding" in question *is* the tracked variable's own binding site, which zeroed out the real downstream use and made the pass never fire. Fixed by checking uses against the alias-stripped tree (`strip_alias_chain`'s third return value) instead, while still reconstructing the *unstripped* tree in the output (nothing is dropped for the capturing case, only substituted in place). Regression test: `test/native/native_arr_map_inline_capture.march` — single capture (Float, the dataframe shape), multiple captures (Int), a capture combined with the Phase 2b array-reuse-in-a-loop shape, and a closure that captures AND is reused elsewhere (must fall back, since it's used more than once) — checked for correctness and, via the same `nmap_pre`/`nmap_cond` IR grep as the reuse test, that exactly 3 of the fixture's 4 map calls take the inline path.

**Float-boxing Stage 4, Option A — reuse the `map_float` wire-argument box (done, 2026-07-27):** every float crossing the closure-call ABI boundary is heap-boxed (`march_alloc_float`) — this is what blocks `map_float` from vectorizing (see Phase 2c above) and is a known, deliberate tradeoff from an earlier design decision (`specs/plans/archive/2026-07-13-float-boxing-design.md`), not a bug: boxing fixed real correctness issues (RC-on-raw-float-bits SIGSEGV, negative floats sorting wrong under a raw-bits integer compare) that a plain register-guard fix provably couldn't. That design doc named its own deferred "Stage 4 — perf pass" for the cost, with two options: `EReuse` on the float box, or unbox-on-entry at monomorphized boundaries. `emit_native_map_inline_loop` (`lib/tir/llvm_emit.ml`) now does the first, scoped to the *argument* side: it allocates ONE `march_alloc_float` box before the loop and overwrites its `.val` field (a GEP to byte offset 16, per `march_float_box`'s `[rc:8][tag:4][pad:4][val:8]` layout) each iteration, instead of a fresh box per element. Safe because every apply function unconditionally unboxes its argument as its very first instruction and never retains the pointer (confirmed via `-emit-llvm`: the generated prologue is always `call double @march_unbox_float(ptr %x.arg)` before any user code runs) — nothing can observe a specific box's identity across calls, so reuse is indistinguishable from fresh-boxing at 1/N the allocation cost. Confirmed via a 3000-iteration, 200K-element stress test that this wasn't cosmetic: the loop was visibly pressuring the runtime's tracing GC (RSS oscillating 1.3-3.2GB rather than growing unboundedly — not a leak, but real avoidable churn), and wall-clock dropped ~1.9x (18.96s → 10.18s) via file-copy-swap A/B on an otherwise-identical binary. Scoped narrowly on purpose: only the argument box is reused; the *return*-value box (the apply body's own fresh allocation for its result) is untouched — reusing that would need the callee's own codegen to cooperate (an out-parameter or FBIP-style hint), a larger change than this loop controls, and is effectively "Stage 4, Option B" (see below) territory. `Int` has no equivalent box (its wire value is a tagged immediate, no allocation) so is unaffected. This does **not** unlock Float vectorization — the return-side box still blocks the auto-vectorizer — it only cuts allocation traffic. Regression test: `test/native/native_arr_map_inline_float_box_reuse.march` (correctness + an `--emit-llvm` structural check that no `march_alloc_float` call appears inside the loop-body block).

**Float-boxing Stage 4, Option B — unboxed apply-fn clone for `map_float` (done, 2026-07-27):** the deeper fix, and the only path to genuine Float vectorization — Option A only cut allocation traffic. Turned out much lower-risk than the "second calling convention, real work in `defun.ml`" estimate above: `Tir_names.is_apply_fn` (the single predicate every box/unbox decision in `lib/tir/llvm_toplevel.ml`'s function-emission code keys off) is a pure name check — does the function's name contain the literal substring `"$apply$"` — not a structural/TIR-level marker. A lifted lambda's `fn_def` already carries its natural, concrete parameter/return types; boxing is applied purely because the name matches at emission time. So `Native_map_inline.ml`, on finding a `map_float` callback whose signature is concretely all-`Float` (no `TVar` — captures are fine, since a captured Float is already stored/loaded at its own concrete type in the closure struct, never boxed, regardless of which apply-fn variant reads it), clones the *exact same* already-Perceus-processed `fn_def` under a renamed `fn_name` that does **not** contain `"$apply$"` (`"$mapfast$"` instead) and adds it to the module. The existing, completely unmodified emission code in `llvm_toplevel.ml` then treats the clone as an ordinary function: natural `double` params and return, no `march_alloc_float`/`march_unbox_float` anywhere — argument or return side, loop or callee. `llvm_emit.ml`'s `emit_native_map_inline_loop` gained an `~unboxed` parameter selecting a plain-`double` load/call/store path with no box allocation at all (vs. Option A's box-once-and-reuse path, still used for anything that doesn't qualify — Int, or a still-generic signature). New synthetic builtin name `__native_float_arr_map_inline_unboxed` (both 2-arg non-capturing and 3-arg capturing forms) dispatches to it.

Verified via `-S -emit-llvm` + `clang -O2` disassembly on `fn x -> x *. 2.0 +. 1.0` over a 1M-element array: `march_main`'s inlined loop shows LLVM's own vectorizer block markers (`%vector.ph`/`%vector.body`) and real 8-wide-unrolled NEON (`fadd.2d` — `*2.0` strength-reduced to self-add) — genuine Float SIMD, the first time this has actually fired for `map_float`. Known, accepted cost: the *original* boxed apply fn is left in the module alongside its unboxed clone (Native_map_inline runs after Opt's DCE, so the now-dead original isn't swept) — dead code, not a correctness issue, just unnecessary compile/link work; a reachability check to drop it is a possible follow-up, not done here. Regression test: `test/native/native_arr_map_inline_unboxed.march` — non-capturing and capturing all-Float cases, checked for correctness and (via `--emit-llvm`) that exactly 2 `$mapfast$` clones exist with zero boxing calls in either clone's own body (a stronger check than Option A's "not inside the loop" — the callee itself must be clean too, since it now takes/returns a raw `double`). Actual vector-instruction assertions were deliberately left out of the automated test (clang-version/target-architecture dependent, not portable across CI runners) — verified manually instead, as described above.

**Deferred (Phase 3):** GEP-based vectorizable loop emission with `!llvm.loop.vectorize.enable` metadata and `align 32` allocation (requires `posix_memalign`) for `sum`/`fold`, and extending Phase 2b/2c's direct-call inlining to `fold` (same closure-inlining pattern, same win). The current Phase 2 calls the C runtime's tight loops for `sum`/`fold`; LLVM auto-vectorizes the runtime `sum` loop at `-O2`/`-O3` (see correction above) without needing this, so remaining value here is mostly `fold` and any future ops that don't already have a hand-rolled emitter.

Example of what the Level 2 emit produces for `native_float_arr_map(arr, fn x -> x *. 2.0)`:
```llvm
; Vectorized body (4 doubles at a time for AVX2)
loop.body:
  %vec = load <4 x double>, ptr %arr_ptr, align 32
  %res = fmul <4 x double> %vec, <double 2.0, double 2.0, double 2.0, double 2.0>
  store <4 x double> %res, ptr %out_ptr, align 32
  br label %loop.check
; Scalar tail for remaining 0–3 elements
```

Change clang invocation from `-msse4.2` to `-mavx2` (or `-march=native`) to unlock
256-bit vector registers.

---

**Phase 3 — Auto-vectorize stdlib:**

`IntCol`/`FloatCol` were already migrated from `List`-backed to `NativeArray`-backed
(`NativeIntArr`/`NativeFloatArr`) as part of the P10 Phase 3 column-representation
work (see the "P10 Phase 3 — NativeArray-backed DataFrame columns" entry above) —
that part of this note is done and predates the description here, which was stale.
What's left is making the *operations* on those columns actually use the fast
`NativeArray` primitives instead of round-tripping through `List` anyway:

- **Done (2026-07-27):** `DataFrame.eval_agg`'s `Sum`/`Mean` now call
  `native_int_arr_sum`/`native_float_arr_sum` directly (new `col_native_sum` helper)
  instead of materializing the column to a `List(Float)` and folding with
  `Stats.sum`/`Stats.mean_safe` — reuses the already-vectorized `sum_float` fix
  (P10 Phase 2 correction, above) for free. `Min`/`Max`/`Std`/`Variance`/`Median`
  unchanged: no vectorized reduction primitive exists for those (would need new
  runtime builtins), and `Median` needs the full sorted list regardless.
- **Done (2026-07-27):** `NativeArray.map2_int`/`map2_float` — a genuine two-array
  zip-with primitive (`f(a_elem, b_elem) = out_elem`, panics on length mismatch),
  plus `NativeArray.to_float_arr` (widen a `NativeIntArr` to `NativeFloatArr`) for
  mixed-type column arithmetic. Full stack: runtime C (`native_{int,float}_arr_map2`
  in `runtime/march_runtime.c`, using the same wire-tagged/boxed closure-call ABI as
  `map`'s `clo_call_*` helpers, plus 2-arg variants `clo_call_int_int_int`/
  `clo_call_dbl_dbl_dbl`), interpreter (`lib/eval/eval.ml`), typechecker
  (`lib/typecheck/typecheck.ml`), and compiled-path registration (`llvm_builtins.ml`
  table + preamble `PDeclare`s, `defun.ml`'s `builtin_names`). `DataFrame.col_add_col`
  now uses these instead of `List.zip`/`List.map`/`native_*_arr_from_list` for all
  four `IntCol`/`FloatCol` combinations. Regression test: `test/native/native_arr_map2.march`.
  Shipped correctness-first — `map2` did not initially get its own
  Phase-2b/2c/Option-A/B-style closure-inlining or vectorization treatment (still
  dispatched through the C runtime's opaque closure-pointer call per element).
- **Done (2026-07-27, same day):** `map2` closure-inlining/vectorization. Extended
  `lib/tir/native_map_inline.ml` (the Phase 2b/2c/Stage-4 pass behind `map`'s
  numbers above) to also recognize the two-array `map2` call shape — same
  eligibility bar (fresh, single-use, non-capturing-or-single-capture callback),
  same synthetic-inline-name mechanism, same `Float`-boxing Stage 4 Option B
  unboxed clone for a concrete-`Float` signature — via four new mirror functions
  (`find_target_call2`/`subst_call2`/`find_target_call_var2`/`subst_call_capturing2`)
  matching a 3-arg call (2 leading `NativeArray` args + closure) instead of `map`'s
  2-arg one, plus `apply_fn_table`'s arity filter widened to accept a 2-param
  ($clo+a+b) apply fn alongside the existing 1-param one. `lib/tir/llvm_emit.ml`
  gained `emit_native_map2_inline_loop`, mirroring `emit_native_map_inline_loop`
  with two source-array reads and a 2-argument direct call. One thing with no
  single-array equivalent: the inlined loop bypasses
  `native_int_arr_map2`/`native_float_arr_map2` (and their own length checks)
  entirely, so it needed its own length-mismatch panic
  (`native_arr_map2_check_len`, `runtime/march_runtime.c`, emitted once in the
  loop's preheader — no per-iteration cost) to preserve
  `NativeArray.map2_*`'s documented contract; verified with a dedicated
  regression fixture expecting exit 1
  (`test/native/native_arr_map2_inline_length_panic.march`), not just the happy
  path. Measured **~47x** on the `bench/simd_map2.march` cross-language
  benchmark: 299.2 ms → 6.4 ms (5M elements), now beating hand-written OCaml and
  within 3x of NumPy — see `docs/simd-benchmarks.md`'s "Fix history: map2".
  Regression test: `test/native/native_arr_map2_inline.march` (correctness — Int
  and Float, non-capturing and capturing, plus a reused-closure fallback case)
  plus an `--emit-llvm` structural check
  (exactly 2 unboxed `$mapfast$` clones, zero boxing calls in either, exactly 1
  remaining general non-inlined `native_int_arr_map2` call for the
  reused-elsewhere case).
- **Still out of scope:** `ColExpr::Add/Sub/Mul/Div` (the lazy-expression path, as
  opposed to `col_add_col`'s eager one) and `fill_null` (data array zipped against a
  `TypedArray(Bool)` null-bitmap, not another `NativeArray` — a different shape than
  `map2` covers) have not been rewired.
- **Found, filed separately, not fixed:** `DataFrame.eval_agg` has ~40ms of fixed
  per-call overhead in compiled builds, unrelated to the actual aggregation —
  confirmed via isolated benchmark and confirmed pre-existing (not caused by the
  `col_native_sum` change above). Dwarfs any vectorization win for aggregations run
  in a loop (e.g. `group_by`). Root cause not yet investigated.
- Row filtering (`native_int_arr_filter_mask`/`native_float_arr_filter_mask`) and
  `group_by`/`join`/`sort` (`Hamt`/`List`-based) were surveyed and are correctly
  **not** SIMD targets — filtering is a branchy compaction loop clang won't
  auto-vectorize at `-O2` without AVX-512-style compress instructions, and the
  others are pointer/hash-heavy, not data-parallel.

Combined with P9 (columnar layout), the column representation and the now-vectorized
aggregations AND two-array arithmetic move March DataFrame queries closer to
Polars-competitive — `ColExpr`'s lazy-expression path and `fill_null` are the main
remaining pieces.

---

**Effort:** Phase 0–1 done (low); Phase 2 medium; Phase 3 (aggregations) low, done; Phase 3 (two-array ops) medium, done
**Impact:** 5–10× interpreter speedup for numeric ops (measured); 4–8× compiled speedup after Phase 2; ~47× for map2 specifically (299ms → 6.4ms, 5M elements)
**Dependencies:** Phase 2 needs monomorphization; Phase 3 pairs with P9
**Benchmark:** `bench/array_numeric.march`, `bench/simd_sum.march`/`simd_map.march`/`simd_map2.march` (cross-language, see `docs/simd-benchmarks.md`)
**Status:** Phase 0–2c done; Phase 3 aggregations done; Phase 3 two-array ops done (primitive, `col_add_col` rewiring, AND inlining/vectorization all done)

---

### P11 — Case-of-Known-Constructor (Beta-ADT Reduction)

**Location (planned):** `lib/tir/cprop.ml` or new `lib/tir/beta_adt.ml`
**Stage:** TIR (Opt coordinator — after CProp, before Fold)

When code constructs an ADT value and immediately pattern-matches it in the same expression, the allocation and case dispatch can be eliminated entirely:

```
-- Before
let r = Ok(x) in
match r do
  Ok(v) -> body       -- reduce to: body[v := x]
  Err(e) -> fallback
end

-- After
body[v := x]          -- no heap allocation, no dispatch
```

This is the single most impactful optimization absent from the current pipeline. GHC calls it "case-of-known-constructor" and documented it as their highest-payoff single pass. For March it fires after inlining any function that returns `Option` or `Result`:

```march
-- List.head inlined:
let r = Option.map(fn x -> x + 1)(Some(5)) in ...
-- After inline of Option.map: let r = match Some(5) do Some(v) -> Some(v+1) None -> None end
-- After beta-ADT: let r = Some(6)
-- After outer match on r: no allocation at all if immediately destructured
```

The pattern occurs constantly in `let?` chains, `Option.and_then`, `Result.map_err`, and any function returning a sum type.

**Implementation:**
Track `let v = EAlloc(ctor_tag, args)` in a second CProp env. When an `ECase(AVar v, branches, default)` is reached and `v` is in this env, find `branches` with matching `br_tag`, substitute `br_vars` → `args` in `br_body`, and emit the reduced body. The dead `let v = EAlloc(...)` binding is then removed by DCE; orphaned `EIncRC`/`EDecRC` on `v` are cleaned up by Perceus / the existing DCE-for-impure pass.

Edge cases:
- Multi-use: if `v` is used more than once (EIncRC present), don't reduce (would need to copy args into multiple contexts)
- Reuse token: if `v` has an `EReuse` associated, keep the binding
- Scrutinee in escaped position: if `v` escapes (stored, returned), don't reduce

**Effort:** Medium (~100 lines) | **Impact:** Very high
**Dependencies:** CProp (same env-tracking pattern); DCE (cleans up residuals)
**Tests:** `beta_adt` group — `ok_inline`, `qualified_tag`, `no_fire_non_case` (3 tests)
**Status:** Done — `lib/tir/beta_adt.ml` (new file); wired as pre-Perceus pass in `bin/main.ml`. NOT in post-Perceus opt loop (Perceus inserts EDecRC(scrutinee) in matching branch body, which would reference an unbound var after P11 drops the ELet). Uses `short_name` helper + `tags_match` for qualified-vs-bare tag matching.

---

### P12 — Variable Copy Propagation

**Location (planned):** `lib/tir/cprop.ml` (extend existing pass)
**Stage:** TIR (Opt coordinator — CProp)

The current CProp only propagates `let x = <literal>` into use sites. It leaves `let x = y` (variable aliasing) intact. These alias chains appear everywhere after inlining, because `subst_args` in `inline.ml` creates:

```
let param_i1 = arg_a in   -- EAtom (AVar arg_a), not a literal → not propagated today
let param_i2 = 3 in       -- literal → propagated
param_i1 + param_i2       -- remains as: param_i1 + 3
```

With copy propagation:
```
let param_i1 = arg_a in
arg_a + 3               -- substitute param_i1 → arg_a
```
DCE then drops the dead `let param_i1`. This also enables Fold to make further progress in cascaded inline → fold chains.

**Implementation:** ~30 additional lines in `cprop.ml`. Extend the env to carry `(string * March_ast.Ast.literal) list` OR `(string * Tir.atom) list` (atom-level). When RHS is `EAtom (AVar y)`, add `x → AVar y` to env. `subst_atom` for a var looks up the env for either a literal OR an atom alias.

RC-safety: same rule as existing CProp — skip EFree/EIncRC/EDecRC argument positions (their argument must remain the original binding for RC semantics).

**Effort:** Low (~30 lines) | **Impact:** Medium — fires after every inline call
**Dependencies:** Inline (creates alias chains); feeds Fold
**Tests:** `cprop` group — `var_alias`, `var_chain`, `no_alias_closure` (3 new tests)
**Status:** Done — added `avar_env : (string * Tir.var) list` to `lib/tir/cprop.ml`. Excludes `TFn`/`TVar` (closure) types to protect ECallPtr dispatch; uses `~allow_avar:false` for ECallPtr's function argument. RC positions unchanged (EFree/EIncRC/EDecRC not substituted).

---

### P13 — EField of Known Record, Update, or Tuple  ✅

**Location:** `lib/tir/cprop.ml`
**Stage:** TIR (Opt coordinator — after Known_call/Inline/Single_use_inline, before Fold)

When a record or tuple is constructed and a field/element is accessed immediately, the allocation and field load can be eliminated:

```
let r = { x = a, y = b } in r.x          →   a
let r2 = { r with x = new_val } in r2.x  →   new_val
let t = (a, b) in t.$fv0                 →   a
```

Fires after inlining record/tuple-returning functions, constructor accessors, and `EUpdate` chains (of which struct fusion already handles the update→update case, but not update→field). The tuple case shares the exact same `field_env`/`EField` fold machinery as the record case — a tuple's positional fields are keyed by `Tir_names.fv_field i` (0-based), matching `lib/tir/lower.ml`'s tuple-destructure lowering convention, so `let (a, b) = rhs` (which desugars to that same `EField` shape) benefits automatically with no lowering change.

**Implementation:** `field_env : (string * (string * Tir.atom) list) list` in `cprop.ml`, populated from `let v = ERecord(fields)`, `let v = ETuple(atoms)` (keyed positionally), `EUpdate(base, new_fields)` (record-only — merged with the base's known fields), and known-shape aliases (`let v2 = v1`). `EField(AVar v, k)` looks up `v` in `field_env` and substitutes `fields[k]` when found, for either origin.

**Safety note:** `Tir_names.fv_field`'s `"$fv" ^ i` naming is shared with closure-capture struct fields (`lib/tir/defun.ml`, 1-based) — collision-safe because `field_env` is populated purely by a binding's own shape, never by the field-name string; a closure-capture struct is built via `EAlloc`, never `ETuple`, so it can never enter `field_env`.

**Effort:** Small (~15 lines, on top of the already-shipped record case) | **Impact:** Small–Medium (DCE-enabling; removes an allocation/struct wherever a tuple literal is built and immediately destructured — e.g. multi-value-return-then-destructure, pair accumulators)
**Dependencies:** CProp (same env extension pattern, no new pass); DCE (removes the now-dead tuple binding in the same fixed-point iteration, unchanged)
**Tests:** `cprop` group — `field_fold_tuple`, `field_fold_tuple_second_element`, `field_fold_tuple_alias`, `field_fold_tuple_non_literal_element`, `no_tuple_field_collision_with_closure_capture`, `tuple_field_result_escape_unchanged`, `tuple_dce_removes_allocation_from_llvm`; native golden `tuple_destructure_dce`
**Status:** Done (record case: commit 471bb42 + review fixes; tuple extension: this plan)
**Known pre-existing, unrelated gap found during this work (not fixed here):** `lib/tir/perceus.ml`'s `dup_field_results` (the pre-Perceus escape-safety normalization for a field returned bare in result position) matches only `Tir.TRecord`, never `Tir.TTuple` — a tuple field returned directly from a function may not get the same dup-on-escape a record field gets. Orthogonal to this post-Perceus cprop peephole; filed as a follow-up, not addressed by this change.

---

### P14 — Extended Simplify Peepholes

**Location (planned):** `lib/tir/simplify.ml`
**Stage:** TIR (Opt coordinator — Simplify)

Additional algebraic rules missing from the current `simplify.ml`:

```
-- Boolean / conditional
if x then true else false     →  x
if x then false else true     →  not x
not (not x)                   →  x

-- Comparison
x == x   →  true    (only for non-float atoms; name equality implies value equality after mono)
x != x   →  false

-- String  
String.is_empty("") →  true    (complementary to existing string_is_empty fold)

-- Arithmetic (extends existing rules)
x mod 1  →  0
0 mod x  →  0   (when x is a known non-zero literal — same guard as existing 0/x rule)
```

These patterns arise from desugaring guards (`when x == x`), from inlining boolean helper functions, and from partial evaluation of comparison expressions where `x` is the same ANF variable.

**Implementation:** ~40 lines in `simplify_expr`. The `x == x` rule requires checking that both atoms are `AVar v` with the same `v_name`; safe for scalars and heap pointers (same variable = same address after monomorphization).

**Effort:** Low (~40 lines) | **Impact:** Low-Medium
**Dependencies:** None (standalone peepholes)
**Tests:** `simplify` group — `if_then_true_else_false`, `if_then_false_else_true`, `eq_self`, `ne_self`, `eq_self_float_no_reduce`, `eq_self_tuple_float_no_reduce`, `and_false_rhs`, `and_false_lhs`, `or_true_rhs`, `not_true`, `not_false`
**Status:** Done (P15 additions: `x && false = false`, `false && x = false`, `x || true = true`, `true || x = true`, `not true = false`, `not false = true`; P14 original: `if x then true else false`, `if x then false else true`, `x==x`, `x!=x`; `not (not x)` deferred — not yet needed)

---

## Optimization Interactions

The Opt coordinator (`lib/tir/opt.ml`) runs `[Inline; CProp; Fold; Simplify; DCE]` in a fixed-point loop (up to 5 iterations). The interaction order matters:

```
Inline   — exposes literal arguments to inlined call sites
  ↓
CProp    — propagates those literals through let chains
  ↓
Fold     — evaluates the now-literal arithmetic
  ↓
Simplify — applies identity laws to folded results
  ↓
DCE      — removes let bindings that became dead after folding
```

Each pass sets `~changed` when it modifies the TIR. The loop terminates when no pass changes anything (fixed point) or after 5 iterations (safety bound).

---

## Benchmark Coverage

| Benchmark | Exercises |
|-----------|-----------|
| `bench/tree_transform.march` | Perceus/FBIP, escape analysis, TCO |
| `bench/list_ops.march` | Stream fusion, inlining, fold/simplify |
| `bench/binary_trees.march` | Allocation, GC pressure, escape |
| `bench/dataframe_bench.march` | Map/filter chains, nullable joins |
| `bench/mutual_recursion.march` | Mutual TCO (even/odd, state machine, collatz-like) |

After modifying any optimization pass, run the corresponding benchmark(s) to catch regressions. The cross-language benchmark suite (`bench/run_benchmarks.sh`) compares against OCaml, Rust, and Elixir.
