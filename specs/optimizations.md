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
- Function body ≤ 15 TIR nodes (configurable via `inline_size_threshold`)
- Function body is pure (no effects; checked by `lib/tir/purity.ml`)
- Function is non-recursive (does not call itself)
- Does not call another inlining candidate (prevents infinite fixed-point expansion)

**Fixed-point loop:** The `opt.ml` coordinator runs the pass set up to 5 times, so chained calls `f → g → h` are fully inlined across iterations.

**Why it matters for March:** March's standard library is built on small, composable functions (`List.map`, `Option.unwrap_or`, etc.). Without inlining, every call pays a closure dispatch overhead. With inlining, the entire call chain fuses into a single loop body.

**Effort:** Low (done) | **Impact:** High
**Dependencies:** Pairs with Fold and Simplify for maximum benefit
**Tests:** `test_inline_*` group in `test/test_march.ml`

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
**Stage:** TIR pass, before Opt coordinator
**Status:** Planned — `lib/tir/join_points.ml`

---

### P2 — Known-Call Optimization

**Motivation:** When a higher-order argument is statically known (e.g., `List.map(xs, fn x -> x + 1)` where the lambda is visible at the call site), the indirect `ECallPtr` dispatch can be replaced with a direct `EApp` call to the lambda's lifted function.

**Why it matters for March:** After Defun, all closure calls go through `ECallPtr` dispatch. Known-call conversion restores direct calls where the closure is visible, enabling further inlining.

**Effort:** Medium | **Impact:** High (combined with Inline)
**Dependencies:** After Defun; feeds into Inline
**Stage:** TIR pass, between Defun and Opt
**Status:** Planned — `lib/tir/known_call.ml`

---

### P3 — Mutual TCO (Trampoline / Shared Loop)

**Motivation:** Self-TCO is already implemented. Mutually recursive tail calls (`f` tail-calls `g` which tail-calls `f`) require a different strategy: either a trampoline (return a thunk, loop in a driver) or a shared loop with a "next function" discriminant.

**Why it matters for March:** Mutual recursion is common in state machines and parser combinators. Without mutual TCO, these blow the stack on deep inputs.

**Effort:** High | **Impact:** Medium (niche but correctness-critical when hit)
**Dependencies:** Self-TCO; Mono (functions must be monomorphic to share a loop)
**Stage:** LLVM IR emission (extends `emit_fn` logic)
**Status:** Planned

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

### P7 — Borrow Inference and Elision

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

**Effort:** Medium | **Impact:** High (reduces RC overhead 30-50% in typical code)
**Dependencies:** Runs before Perceus; benefits from Escape analysis information
**Stage:** TIR pass — `lib/tir/borrow.ml`
**Status:** Planned

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
**Status:** Planned

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

After modifying any optimization pass, run the corresponding benchmark(s) to catch regressions. The cross-language benchmark suite (`bench/run_benchmarks.sh`) compares against OCaml, Rust, and Elixir.
