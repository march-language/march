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

`--no-opt` skips the entire stage. In `bin/main.ml`, an `opt_enabled` ref cell defaults to `true`; `--no-opt` sets it to `false`. The conditional gates the call to `March_tir.Opt.run` between the `Escape.escape_analysis` call and the dump/emit branch. This is useful for debugging generated IR or bisecting optimization bugs.

---

## TIR Representation of Arithmetic

All arithmetic in the TIR is encoded as `EApp` nodes using string-named built-in functions, not as first-class binary operator constructors. Pattern matching in the optimization passes must use `EApp` with the appropriate `v_name`.

**Integer operators:** `"+"`, `"-"`, `"*"`, `"/"`, `"%"`
**Float operators:** `"+."`, `"-."`, `"*."`, `"/."`
**Integer comparisons:** `"<"`, `"<="`, `">"`, `">="`, `"=="`, `"!="`
**Boolean operators:** `"&&"`, `"||"`, `"not"`
**Negation:** `"~-"` (integer), `"~-."` (float)

Example pattern for integer addition of two literals:

```ocaml
EApp ({v_name = "+"}, [ALit (LitInt a); ALit (LitInt b)])
```

The passes must match on `v_name` strings, exactly as `llvm_emit.ml` does in its `is_int_arith`, `is_float_arith`, and `is_int_cmp` dispatch.

---

## New Files

```
lib/tir/purity.ml     Shared purity oracle used by all passes
lib/tir/inline.ml     Function inlining pass
lib/tir/fold.ml       Constant folding pass
lib/tir/simplify.ml   Algebraic simplification pass
lib/tir/dce.ml        Dead code elimination pass
lib/tir/opt.ml        Coordinator: fixed-point loop over all passes
```

`lib/tir/llvm_emit.ml` gains a `fast_math:bool` config field threading through all FP emit functions.

---

## Shared Purity Oracle (`purity.ml`)

All passes that need to determine whether an expression is pure use a single shared function:

```ocaml
val is_pure : Tir.expr -> bool
```

An expression is pure if it contains no:
- `ESend` (actor message — effectful)
- `EApp` to known-impure builtins: `"print"`, `"println"`, and other IO operations
- Calls to functions that themselves fail the purity check (transitive)

When uncertain (e.g. an indirect call whose target is unknown), `is_pure` returns `false` conservatively. False negatives (treating a pure expression as impure) are safe; false positives are not.

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

The coordinator uses a `changed` boolean flag threaded through each pass rather than structural equality, to avoid expensive deep comparisons on large programs. Each pass sets `changed := true` whenever it rewrites a node. The loop runs until a full iteration completes with `changed` still `false`, or 5 iterations are reached:

```ocaml
let run program =
  let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
  let changed = ref false in
  let apply p =
    changed := false;
    List.fold_left (fun acc pass -> pass ~changed acc) p passes
  in
  let rec loop p n =
    if n = 0 then p
    else let p' = apply p in
         if not !changed then p
         else loop p' (n - 1)
  in
  loop program 5
```

Each pass receives a `~changed` ref it sets to `true` on any rewrite.

---

## Pass Designs

### `inline.ml` — Function Inlining

Inline call sites whose callee meets both criteria:

**Purity check** — uses `Purity.is_pure` on the callee body. If impure, skip.

**Size check** — count TIR nodes in the callee body. Threshold: 15 nodes. This is a named constant (`inline_size_threshold`) so it can be tuned.

**Additional restrictions:**
- No recursive functions (inlining would not terminate)
- No self-referential bodies
- One level of inlining per iteration (chains are handled by fixed-point)

**Substitution** — alpha-rename the callee body with fresh variable names before substituting arguments, to avoid variable capture. The substituted result must remain in ANF: if the inlined body introduces new computations, they must be bound to fresh let-names, not embedded as nested `EApp` arguments.

---

### `fold.ml` — Constant Folding

Evaluate expressions whose operands are all literals at compile time. All patterns match on `EApp` with `v_name` strings as described above.

**Integer arithmetic (operator `"+"`, `"-"`, `"*"`, `"/"`, `"%"`):**

```
EApp("+",  [ALit(LitInt a); ALit(LitInt b)]) → ALit(LitInt (a + b))
EApp("-",  [ALit(LitInt a); ALit(LitInt b)]) → ALit(LitInt (a - b))
EApp("*",  [ALit(LitInt a); ALit(LitInt b)]) → ALit(LitInt (a * b))
EApp("/",  [ALit(LitInt a); ALit(LitInt b)]) → ALit(LitInt (a / b))  -- only when b ≠ 0
EApp("%",  [ALit(LitInt a); ALit(LitInt b)]) → ALit(LitInt (a mod b)) -- only when b ≠ 0
```

Division or modulo by zero is left as-is (runtime error, not a compile-time fold).

**Float arithmetic (operators `"+."`, `"-."`, `"*."`, `"/."`)**

```
EApp("+.", [ALit(LitFloat a); ALit(LitFloat b)]) → ALit(LitFloat (a +. b))
EApp("-.", [ALit(LitFloat a); ALit(LitFloat b)]) → ALit(LitFloat (a -. b))
EApp("*.", [ALit(LitFloat a); ALit(LitFloat b)]) → ALit(LitFloat (a *. b))
EApp("/.", [ALit(LitFloat a); ALit(LitFloat b)]) → ALit(LitFloat (a /. b))  -- only when b ≠ 0.0
```

**Boolean (operators `"&&"`, `"||"`, `"not"`):**

```
EApp("&&", [ALit(LitBool false); rhs]) when is_pure(rhs) → ALit(LitBool false)
EApp("||", [ALit(LitBool true);  rhs]) when is_pure(rhs) → ALit(LitBool true)
EApp("not",[ALit(LitBool b)])                            → ALit(LitBool (not b))
```

The `when is_pure(rhs)` guard is required: if `rhs` has side effects, it must still be evaluated even though the logical result is determined. When `rhs` is impure, leave the expression as-is.

**Conditionals:**

```
if ALit(LitBool true)  then e1 else e2 → e1
if ALit(LitBool false) then e1 else e2 → e2
```

**Match on literal constructor:**

When the scrutinee of a `match` expression is a literal or known constructor, reduce to the single matching arm and discard the rest. This is the only location in the spec where match reduction is defined; `dce.ml` does not duplicate it.

---

### `simplify.ml` — Algebraic Simplification

Peephole rewrites on expression shape, matching on `EApp` with `v_name` strings. All rewrites must produce results that remain in ANF. If a rewrite introduces a new operation (e.g. strength reduction), the new operation is bound to a fresh `let` variable before being returned, not embedded as a nested argument.

The simplifier operates on fully ANF-normalized trees (guaranteed by the time it runs in the pipeline). Strength reduction and any other rewrites that produce new `EApp` nodes must be accompanied by fresh `let` bindings.

**Integer arithmetic identities (operator `"+"`):**

```
EApp("+", [x; ALit(LitInt 0)]) → x
EApp("+", [ALit(LitInt 0); x]) → x
```

**Subtraction (operator `"-"`):**

```
EApp("-", [x; ALit(LitInt 0)]) → x
EApp("-", [AVar a; AVar b])    → ALit(LitInt 0)  when a.v_name = b.v_name
```

The `x - x → 0` rule matches only when both operands are the same `AVar` by `v_name` (not general structural equality), to avoid false matches in the presence of Perceus RC-inserted variables. **This rule is intentionally integer-only**: under IEEE 754, `NaN -. NaN = NaN`, not `0.0`.

**Multiplication (operator `"*"`):**

```
EApp("*", [x; ALit(LitInt 1)]) → x
EApp("*", [ALit(LitInt 1); x]) → x
EApp("*", [x; ALit(LitInt 0)]) → ALit(LitInt 0)  when is_pure(x)
EApp("*", [ALit(LitInt 0); x]) → ALit(LitInt 0)  when is_pure(x)
```

**Division (operator `"/"`):**

```
EApp("/", [x;            ALit(LitInt 1)]) → x
EApp("/", [ALit(LitInt 0); x])           → ALit(LitInt 0)  when is_pure(x)
```

**Float arithmetic identities (operators `"+."`, `"-."`, `"*."`, `"/."`)**

The following rules are safe for floats (IEEE 754 compliant; do not require `--fast-math`):

```
EApp("+.", [x; ALit(LitFloat 0.0)]) → x
EApp("+.", [ALit(LitFloat 0.0); x]) → x
EApp("-.", [x; ALit(LitFloat 0.0)]) → x
EApp("*.", [x; ALit(LitFloat 1.0)]) → x
EApp("*.", [ALit(LitFloat 1.0); x]) → x
EApp("/.", [x; ALit(LitFloat 1.0)]) → x
```

The `x -. x → 0.0` rewrite is **not** applied for floats (unsound when `x = NaN`).

**Strength reduction (integer only):**

```
EApp("*", [x; ALit(LitInt 2)]) → let t = x + x in t
EApp("*", [ALit(LitInt 2); x]) → let t = x + x in t
```

The result introduces a fresh `let` binding to maintain ANF. Float strength reduction is skipped — it would change rounding behavior.

**Double negation (integer `"~-"`, float `"~-."`, boolean `"not"`):**

```
EApp("~-",  [AVar v])  where v is bound to EApp("~-",  [y]) → y
EApp("~-.", [AVar v])  where v is bound to EApp("~-.", [y]) → y
EApp("not", [AVar v])  where v is bound to EApp("not", [y]) → y
```

In ANF, negation of a negation requires looking through the let-binding of the inner variable.

**Boolean identities (operators `"&&"`, `"||"`):**

```
EApp("&&", [x; ALit(LitBool true)])  → x
EApp("&&", [ALit(LitBool true);  x]) → x
EApp("||", [x; ALit(LitBool false)]) → x
EApp("||", [ALit(LitBool false); x]) → x
```

**Boolean normalization:**

```
if b then ALit(LitBool true) else ALit(LitBool false) → b
if b then ALit(LitBool false) else ALit(LitBool true) → EApp("not", [b])
```

---

### `dce.ml` — Dead Code Elimination

**Dead let bindings:**

```
let x = e in body
```

If `x` is not free in `body` and `Purity.is_pure e`, drop the entire binding. If `x` is not free in `body` but `e` is impure, keep `e` as a statement (sequenced effect) but drop the binding name.

**Unreachable top-level functions:**

Functions not reachable from `main` or any `pub`-exported declaration are removed from the program. Reachability is computed via a call graph walk from entry points.

Note: `dce.ml` does **not** implement match-on-literal reduction. That is handled exclusively in `fold.ml`.

---

## LLVM-Side Changes

### `--fast-math` flag

When `--fast-math` is passed, `llvm_emit.ml` emits the `fast` attribute on all floating-point instructions:

```llvm
%r = fadd fast double %a, %b
```

This is more precise than passing `-ffast-math` to clang — it annotates at the instruction level in the IR, so only March-emitted FP operations are affected (not the runtime C code).

`fast` is shorthand for all of: `nnan`, `ninf`, `nsz`, `arcp`, `contract`, `afn`, `reassoc`. This enables LLVM to: reassociate FP expressions, replace division with reciprocal multiplication, fuse multiply-add, and assume no NaN/Inf inputs.

### `--opt=N` flag

Passed through to clang when compiling the `.ll` file:

- `--opt=0` → `clang -O0`
- `--opt=1` → `clang -O1`
- `--opt=2` → `clang -O2`
- `--opt=3` → `clang -O3`

**Behavioral note:** The current `--compile` invocation in `bin/main.ml` passes no `-O` flag, which means clang defaults to `-O0`. Adding `--opt=2` as the default for `--compile` changes this existing behavior. The implementation must make this explicit: either document the change in the commit, or keep the existing default as `-O0` and require `--opt=N` to be passed explicitly. This decision is left to the implementer.

LLVM at `-O2`/`-O3` performs: auto-vectorization (SLP and loop), instruction scheduling, register allocation improvements, and additional inlining beyond what our TIR pass does.

---

## CLI Summary

| Flag | Effect |
|------|--------|
| `--no-opt` | Skip TIR optimization passes entirely |
| `--fast-math` | Emit `fast` on all FP LLVM instructions |
| `--opt=N` | Pass `-ON` to clang |

---

## Testing

Each pass gets a dedicated test section in `test/test_march.ml`.

**Fold tests:** Construct specific TIR trees with `EApp` and `ALit` literal operands; assert the folded result matches the expected `ALit`. Include: integer arithmetic, float arithmetic, boolean short-circuit (pure and impure RHS), conditional on `LitBool`, match on literal constructor.

**Simplify tests:** Construct TIR with identity patterns using `EApp` and `AVar`/`ALit`; assert the result is structurally equal to the simplified form. Include: each arithmetic identity, `x - x` for integers (same `v_name`), strength reduction produces valid ANF (a `let` binding), double-negation via let-binding lookup, boolean normalization.

**Inline tests:** Define a small pure function and a call site; assert the call site is replaced by the inlined body with correct substitution and fresh variable names. Verify that impure functions (containing `ESend`) are not inlined. Verify that recursive functions are not inlined.

**DCE tests:** Construct TIR with unused pure `let` bindings; assert they are removed. Verify that impure unused bindings are kept as sequenced effects. Verify that unreachable top-level functions are eliminated by call graph analysis.

**`--fast-math` IR test:** Compile a March program with `--emit-llvm --fast-math`; assert the emitted `.ll` file contains `fadd fast` (or `fmul fast`, etc.) rather than plain `fadd`. Compile the same program without `--fast-math`; assert plain `fadd` is emitted.

**Integration tests:** End-to-end `.march` programs that compile with `--emit-llvm` and produce correct output; verify IR contains expected patterns (e.g. folded constants appear as LLVM literals, no trivial `x * 1` operations remain in the IR).

---

## What LLVM Handles (Not Duplicated in TIR)

These are deliberately left to LLVM:

- **Auto-vectorization** — LLVM's SLP and loop vectorizers handle this; our TIR has no SIMD type representation
- **Reciprocal multiplication** (`x / c` → `x * (1/c)`) — enabled automatically under `--fast-math` via LLVM
- **Loop unrolling** — LLVM loop pass
- **Register allocation and instruction scheduling** — LLVM backend

The TIR passes handle what LLVM cannot see: language-level identities, March-specific algebraic laws, and inlining of stdlib wrappers that haven't been lowered to IR yet.
