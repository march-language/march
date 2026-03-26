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
**Status:** Planned

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

**Motivation:** The compiler emits scalar LLVM IR for numeric loops. LLVM's auto-vectorizer can sometimes promote these to SIMD (AVX2/NEON), but it's unreliable without explicit hints. Two levels of support:

**Level 1 — Vectorization hints (low effort):**
- Emit `!llvm.loop.vectorize.enable` metadata on loops over arrays
- Add `align 32` annotations on array allocations for AVX2
- Use `nonnull` and `dereferenceable` attributes to help LLVM's alias analysis

**Level 2 — Explicit SIMD codegen (medium effort):**
- Detect known patterns: `Array.map(arr, fn x -> x + 1)`, `Array.fold`, `Array.zip_with`
- Lower to LLVM vector types: `<4 x i64>`, `<4 x double>`
- Generate vector load → vector op → vector store with scalar tail loop

**Example (what gets generated):**
```llvm
; Array.map(arr, fn x -> x * 2) with Level 2
loop:
  %vec = load <4 x i64>, ptr %arr_ptr, align 32
  %res = mul <4 x i64> %vec, <i64 2, i64 2, i64 2, i64 2>
  store <4 x i64> %res, ptr %out_ptr, align 32
  ; ... scalar tail for remaining 0-3 elements
```

**Why it matters for March:** Numeric array operations are the backbone of DataFrame queries, statistical computation, and scientific computing. Without vectorization, March leaves 4-8x performance on the table for these workloads. Combined with columnar layout (P9), this makes March's data processing genuinely competitive.

**Effort:** Low (L1) to Medium (L2) | **Impact:** High (4-8x for numeric array ops)
**Dependencies:** Monomorphization (arrays must be concretely typed); pairs with P9 (columnar layout provides the contiguous arrays)
**Stage:** LLVM IR emission — extends `lib/tir/llvm_emit.ml`
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
| `bench/mutual_recursion.march` | Mutual TCO (even/odd, state machine, collatz-like) |

After modifying any optimization pass, run the corresponding benchmark(s) to catch regressions. The cross-language benchmark suite (`bench/run_benchmarks.sh`) compares against OCaml, Rust, and Elixir.
