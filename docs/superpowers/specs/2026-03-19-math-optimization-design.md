# Math Optimization Passes for March

**Date:** 2026-03-19
**Status:** Approved

## Overview

Add a TIR optimization stage to the March compiler that performs constant folding, algebraic simplification, function inlining, and dead code elimination before LLVM IR emission. Complement with LLVM-side flags for floating-point relaxation and machine-level optimization.

## Goals

- Reduce redundant computation in compiled output without requiring programmer annotations
- Enable LLVM's auto-vectorizer and fast-math transforms on FP-heavy code via explicit IR attributes
- Keep each optimization unit independently testable and auditable
- Fit naturally into the existing TIR pipeline style

## Non-Goals

- Full symbolic algebra / loop transformations (LLVM handles these)
- Per-expression fast-math annotations (global flag is sufficient for v1)
- Separate compilation of optimized modules (whole-program monomorphization already precludes this)

---

## Pipeline Placement

The new `Opt` stage runs between Escape Analysis and LLVM emit:

```
Lower → Mono → Defun → Perceus → Escape → Opt → LLVM emit
```

`--no-opt` skips the entire stage. Useful for debugging generated IR or bisecting optimization bugs.

---

## New Files

```
lib/tir/inline.ml     Function inlining pass
lib/tir/fold.ml       Constant folding pass
lib/tir/simplify.ml   Algebraic simplification pass
lib/tir/dce.ml        Dead code elimination pass
lib/tir/opt.ml        Coordinator: fixed-point loop over all passes
```

`lib/tir/llvm_emit.ml` gains a `fast_math:bool` config field threading through all FP emit functions.

---

## Pass Order and Fixed-Point Loop

Within `opt.ml`, passes run in this order each iteration:

```
Inline → Fold → Simplify → DCE
```

**Rationale for order:**
- Inlining first exposes constant arguments to callers
- Folding evaluates constants revealed by inlining
- Simplification catches algebraic patterns on the folded tree
- DCE removes bindings and branches that the other passes rendered dead

The coordinator runs all four passes in a loop until the program is unchanged (structural equality) or 5 iterations are reached, whichever comes first.

```ocaml
let run program =
  let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
  let apply p = List.fold_left (fun acc pass -> pass acc) p passes in
  let rec loop p n =
    if n = 0 then p
    else let p' = apply p in
         if p' = p then p
         else loop p' (n - 1)
  in
  loop program 5
```

---

## Pass Designs

### `inline.ml` — Function Inlining

Inline call sites whose callee meets both criteria:

**Purity check** — walk the callee body for:
- `ESend` (actor message — effectful)
- Calls to known-impure builtins (`print`, `println`, IO operations)
- Calls to other impure functions (transitively)

If uncertain, conservatively skip. Purity is an over-approximation — false negatives (not inlining a pure function) are safe; false positives are not.

**Size check** — count TIR nodes in the callee body. Threshold: 15 nodes. This is a named constant (`inline_size_threshold`) so it can be tuned.

**Additional restrictions:**
- No recursive functions (inlining would not terminate)
- No self-referential bodies
- One level of inlining per iteration (chains are handled by fixed-point)

**Substitution** — alpha-rename the callee body with fresh variable names before substituting arguments, to avoid variable capture.

---

### `fold.ml` — Constant Folding

Evaluate expressions whose operands are all literals at compile time.

**Arithmetic:**
- `ELit(Int a) + ELit(Int b)` → `ELit(Int (a + b))` (and `-`, `*`, `/`, `%`)
- `ELit(Float a) + ELit(Float b)` → `ELit(Float (a +. b))` (and `-`, `*`, `/`)
- Integer division/modulo by zero: leave as-is (runtime error, not compile-time)

**Boolean:**
- `ELit(Bool false) && _` → `ELit(Bool false)` (short-circuit, drop RHS if pure)
- `ELit(Bool true) || _` → `ELit(Bool true)` (short-circuit, drop RHS if pure)
- `not (ELit(Bool b))` → `ELit(Bool (not b))`

**Conditionals:**
- `if ELit(Bool true) then e1 else e2` → `e1`
- `if ELit(Bool false) then e1 else e2` → `e2`

**Match on literal constructor:**
- `match ELit(...) | EConstructor(...)` — reduce to the single matching arm, drop others

---

### `simplify.ml` — Algebraic Simplification

Peephole rewrites on expression shape, independent of literal values.

**Arithmetic identities:**
- `x + ELit(Int 0)` → `x`
- `ELit(Int 0) + x` → `x`
- `x - ELit(Int 0)` → `x`
- `x * ELit(Int 1)` → `x`
- `ELit(Int 1) * x` → `x`
- `x * ELit(Int 0)` → `ELit(Int 0)` (only when `x` is pure)
- `ELit(Int 0) * x` → `ELit(Int 0)` (only when `x` is pure)
- `x / ELit(Int 1)` → `x`
- `x - x` → `ELit(Int 0)` (only when `x` is pure and has no side effects; uses structural equality)

Same rules apply symmetrically for `Float` variants where mathematically valid.

**Strength reduction (integers only — avoids FP rounding change):**
- `x * ELit(Int 2)` → `x + x`

**Double negation:**
- `EUnary(Neg, EUnary(Neg, x))` → `x`
- `EUnary(Not, EUnary(Not, x))` → `x`

**Boolean identities:**
- `x && ELit(Bool true)` → `x`
- `ELit(Bool true) && x` → `x`
- `x || ELit(Bool false)` → `x`
- `ELit(Bool false) || x` → `x`

**Boolean normalization:**
- `if b then ELit(Bool true) else ELit(Bool false)` → `b`
- `if b then ELit(Bool false) else ELit(Bool true)` → `EUnary(Not, b)`

---

### `dce.ml` — Dead Code Elimination

**Dead let bindings:**

```
let x = e in body
```

If `x` is not free in `body` and `e` is pure (no side effects), drop the entire binding. If `e` is impure (e.g. has observable effects), keep `e` but drop the binding name.

**Unreachable match arms:**

After folding, a `match` expression on a known literal or constructor can be reduced to its single matching arm. All other arms are dead and removed.

**Unreachable top-level functions:**

Functions not reachable from `main` or any `pub`-exported declaration are removed from the program. Reachability is computed via a call graph walk from entry points.

---

## LLVM-Side Changes

### `--fast-math` flag

When `--fast-math` is passed, `llvm_emit.ml` emits the `fast` attribute on all floating-point instructions:

```llvm
%r = fadd fast double %a, %b
```

This is more precise than passing `-ffast-math` to clang (which applies to the whole compilation unit) — it annotates at the instruction level in our IR.

`fast` is shorthand for all of: `nnan`, `ninf`, `nsz`, `arcp`, `contract`, `afn`, `reassoc`. This enables LLVM to: reassociate FP expressions, replace division with reciprocal multiplication, fuse multiply-add, and assume no NaN/Inf inputs.

### `--opt=N` flag

Passed through to clang when compiling the `.ll` file:

- `--opt=0` → `clang -O0` (no optimization, fastest compile)
- `--opt=1` → `clang -O1`
- `--opt=2` → `clang -O2` (default when `--compile` is used)
- `--opt=3` → `clang -O3`

LLVM at `-O2`/`-O3` performs: auto-vectorization (SLP and loop), instruction scheduling, register allocation improvements, and additional inlining beyond what our TIR pass does.

---

## CLI Summary

| Flag | Effect |
|------|--------|
| `--no-opt` | Skip TIR optimization passes entirely |
| `--fast-math` | Emit `fast` on all FP LLVM instructions |
| `--opt=N` | Pass `-ON` to clang (default: 2) |

---

## Testing

Each pass gets a dedicated test section in `test/test_march.ml`.

**Fold tests:** Construct specific TIR trees with literal operands; assert the folded result matches the expected literal.

**Simplify tests:** Construct TIR with identity patterns (e.g. `x * 1`); assert the result is structurally equal to the simplified form.

**Inline tests:** Define a small pure function and a call site; assert the call is replaced by the inlined body with correct substitution. Verify that impure and recursive functions are not inlined.

**DCE tests:** Construct TIR with unused pure bindings and unreachable arms; assert they are removed. Verify impure unused bindings are kept.

**Integration tests:** End-to-end `.march` programs that compile with `--emit-llvm` and produce correct output; verify IR contains expected patterns (e.g. folded constants, no trivial identity operations).

---

## What LLVM Handles (Not Duplicated in TIR)

These are deliberately left to LLVM:

- **Auto-vectorization** — LLVM's SLP and loop vectorizers handle this; our TIR has no SIMD type representation
- **Reciprocal multiplication** (`x / c` → `x * (1/c)`) — enabled automatically under `--fast-math` via LLVM
- **Loop unrolling** — LLVM loop pass
- **Register allocation and instruction scheduling** — LLVM backend

The TIR passes handle what LLVM cannot see: language-level identities, March-specific algebraic laws, and inlining of stdlib wrappers that haven't been lowered to IR yet.
