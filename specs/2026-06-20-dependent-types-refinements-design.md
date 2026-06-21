# Dependent Types — Phase A: Refinement Types with SMT Backend

**Date:** 2026-06-20
**Status:** Draft

## Motivation

March already advertises compile-time dimension checking via `Vector(n, a)` and `Matrix(m, n, a)`, and its existing constraint pipeline (`pending_constraints`, `CNum`, `CInterface`, etc.) accumulates and discharges type obligations at call sites. But the type-level-natural machinery (`TNat`, `TNatOp`, `normalize_tnat`) handles only structural arithmetic between literal naturals — it can't express "this index is in bounds," "this divisor is nonzero," or "this return length equals the sum of the two inputs."

Refinement types close that gap. A refinement `{T | p}` attaches a decidable logical predicate to an existing base type; the predicate is discharged at every use site by an SMT solver (Z3), then erased before monomorphization. The result is:

- **Array/list bounds** checked at compile time, not via `Option`/`panic` at runtime.
- **Numeric preconditions** (nonzero divisor, non-negative sqrt argument) enforced on callers.
- **Cross-argument relationships** (`len(result) == len(xs) + len(ys)`) verified by the compiler.
- **`Vector`/`Matrix`/`NDArray` dimension checking** made sound for the first time.

Zero runtime cost. No change to codegen. Contained almost entirely to `lib/typecheck/` plus a new `lib/refine/` bridge.

## Scope

**In scope (Phase A — this spec):**
- `{T | predicate}` refinement type syntax with `_` or named binder.
- Refinement type aliases: `type Nat = {Int | _ >= 0}`.
- A fixed set of builtin **measures** (`len`, `abs`, `strlen`, field selectors).
- SMT-LIB2 shell-out to the `z3` binary; VC result caching in the CAS under `vc/`.
- Path-sensitive refinement from `if`/`when`/`match` scalar guards.
- Graceful no-Z3 degradation: `unknown`/missing-Z3 → runtime check + warning.
- Counterexample reporting in diagnostics (`i = 5`, `len(xs) = 3` violates `i < len(xs)`).
- `assume(p)` escape hatch.
- `--require-smt` flag for CI.
- Re-specification of `Vector(n,a)` / `Matrix(m,n,a)` as refinement sugar over `len`.

**Out of scope (Phase B — see §Phase B below):**
- Indexed families / GADT-style indexed datatypes.
- Propositional equality (`refl`, rewrite).
- User-defined measures.
- Refinement inference (you annotate; Z3 verifies).
- Quantifiers, nonlinear arithmetic, inductive proofs.
- Termination / totality checking.

## Surface Syntax

### Refinement types

```march
-- binder form: _ is the refined value
{Int | _ >= 0}
{Float | _ >= 0.0}
{List(a) | len(_) > 0}
{Int | _ >= 0 && _ < len(xs)}   -- xs is an in-scope program variable

-- named binder form (required when predicate mentions two refined values)
{v: Int | v > 0 && v < limit}
```

Parser disambiguation: `{x: T, y: U}` is a record type (field names, colon, comma). `{T | p}` is a refinement (a type expression, then `|`). The `|` cannot appear in a raw type expression, so the grammar is unambiguous.

### Refinement type aliases

```march
type Nat             = {Int | _ >= 0}
type Percent         = {Int | _ >= 0 && _ <= 100}
type NonEmpty(a)     = {List(a) | len(_) > 0}
type BoundedInt(lo, hi) = {Int | _ >= lo && _ <= hi}  -- lo, hi are type-level Nat params in scope as predicate variables
```

Aliases are structural: a `Nat` is a subtype of `{Int | _ >= 0}` and of `Int`; the predicate flows with the alias.

### Function signatures

```march
-- preconditions on parameters, postcondition on return
fn get(xs: List(a), i: {Int | _ >= 0 && _ < len(xs)}) -> a

fn divide(n: Int, d: {Int | _ != 0}) -> Int

fn append(xs: List(a), ys: List(a)) -> {List(a) | len(_) == len(xs) + len(ys)}

fn split(xs: List(a), i: {Int | _ >= 0 && _ <= len(xs)})
  -> ({List(a) | len(_) == i}, {List(a) | len(_) == len(xs) - i})

-- Vector dimension checking (re-specified as refinement sugar)
fn mat_mul(a: Matrix(m, k, Float), b: Matrix(k, n, Float)) -> Matrix(m, n, Float)
-- desugars to: a: {Matrix(_, _, Float) | rows(_) == m && cols(_) == k} etc.
```

## The Predicate Language

Predicates are a **closed, decidable fragment** so every VC stays inside Z3's complete theories. The compiler rejects predicates outside this fragment with a parse/type error — never silently falling through to `unknown`.

**Allowed:**
| Form | Examples |
|------|---------|
| Logical connectives | `&&`, `\|\|`, `!`, `==>` |
| Comparisons | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Linear arithmetic | `+`, `-`, `*`**by a literal constant**, unary `-` |
| Refinement variable | `_` or named binder |
| In-scope program variables | scalar `let`-bindings and parameters |
| Builtin measures | `len(e)`, `abs(e)`, `strlen(e)`, `fst(e)`, `snd(e)`, field selectors |
| Literals | integer, float, bool |

**Explicitly rejected** (compile error, not `unknown`):
- General nonlinear `x * y` where both are variable.
- Calls to arbitrary user functions.
- Quantifiers (`forall`, `exists`).
- Recursion inside predicates.
- Side-effecting expressions.

## Measures

A **measure** is a pure, total, structurally-recursive function liftable to SMT-LIB logic. Measures are the bridge between March's value language and the predicate language.

**v1 builtin measures:**

| Measure | Type | SMT encoding |
|---------|------|-------------|
| `len` | `List(a) -> Nat` | uninterpreted function + axioms (nil=0, cons=len+1) |
| `len` | `Vector(n,a) -> Nat` | same axioms |
| `abs` | `Int -> Nat` | SMT `abs` |
| `strlen` | `String -> Nat` | uninterpreted function + axioms |
| `fst` | `(a,b) -> a` | tuple selector |
| `snd` | `(a,b) -> b` | tuple selector |
| field selectors | `{x:T,...} -> T` | record selector (auto-generated per type) |

Each measure is axiomatized once in a preamble shared across all VCs in a compilation unit. The axioms are included in the cache key.

**Phase B:** user-defined measures declarable via an `@measure` annotation.

## VC Pipeline and Z3 Integration

### Constraint accumulation

During `check_expr`, every subtyping check `{T|p} <: {T|q}` and every call-site precondition emits a **verification condition** — an implication:

```
path_assumptions ==> goal_predicate
```

VCs are accumulated as a new `CRefine(formula, span)` variant in `typecheck.ml`'s existing `constraint_` type and `pending_constraints` list.

### Path context

The typechecker maintains a **path context** — a stack of assumptions added by:
- `if cond do ... end` — adds `cond` in the then-branch, `!cond` in the else-branch.
- `when` guards — adds the guard formula.
- `match` arms — adds scalar facts only: matching a literal pattern (`1`, `true`) adds `v == literal`; matching a scalar range arm adds the corresponding inequality. Constructor/structural discrimination (e.g., matching `None` vs `Some`) does **not** inject equations in Phase A — that is Phase B's structural refinement on pattern match.
- `let x = expr` where `expr` has a refined return type — adds the postcondition with `x` substituted for `_`.

Path context is purely additive (never narrows on join points in v1 — sound but incomplete, fine for a first pass).

### Discharge

At a **discharge point** (end of each function body — VCs are batched per function and discharged together), each outstanding `CRefine` is:
1. Canonicalized to SMT-LIB2.
2. BLAKE3-hashed (VC key = hash of formula + path assumptions + measure axioms).
3. Looked up in the CAS `vc/` namespace — if present, result is cached.
4. If absent: spawned as a `z3` subprocess over stdin/stdout, result cached.

### Solver boundary

**Shell out to the `z3` binary over SMT-LIB2, not OCaml bindings.**

Rationale:
- Z3 is an optional external tool, not a hard compiler dependency.
- Keeps the compiler binary self-contained; users without Z3 still get runtime-check fallback.
- SMT-LIB2 is stable across Z3 versions; OCaml bindings track upstream more tightly.
- CAS caching means the subprocess cost is paid once per unique VC, not per build.

Discovery: `MARCH_Z3` env var overrides; otherwise `which z3` at process start; result cached in the driver for the compilation unit's lifetime.

### Caching

March's content-addressed compiler makes VC caching natural:
- The CAS key for a VC is `BLAKE3(canonical_smtlib2 || measure_axiom_set_hash)`.
- Results (`sat` / `unsat` / `unknown`) are stored as tiny blobs under `<project>/.march/cas/vc/`.
- A counterexample model (for `sat` on the negated goal) is stored alongside for error reporting.
- The compiler executable hash and runtime-source hash are included in the measure-axiom-set hash, so a compiler upgrade naturally invalidates.

### Outcomes and fallbacks

| Z3 result | Interpretation | Compiler action |
|-----------|---------------|-----------------|
| `unsat` on `¬goal` | goal holds — verified | pass (no diagnostic) |
| `sat` on `¬goal` | goal can fail | **error** at call-site span, with counterexample |
| `unknown` | solver couldn't decide | warning + runtime-check insertion (see §Fallback) |
| Z3 not found | can't solve | warning per-VC + runtime-check insertion |

`--require-smt`: turns `unknown` and missing-Z3 into hard errors. Intended for CI.

### No-Z3 runtime-check fallback

When Z3 is absent or returns `unknown`, the predicate is compiled to a **runtime guard**:

```march
-- source:
fn divide(n: Int, d: {Int | _ != 0}) -> Int

-- fallback codegen at call site where d's refinement can't be statically verified:
if !(d != 0) do panic("refinement violation: d != 0 [unverified, z3 unavailable]") end
```

The guard is inserted by a post-typecheck lowering pass (between typecheck and `lower.ml`), using the predicate's span for the panic message. This ensures refined code is always memory-safe even without Z3.

## Erasure

Refinement predicates are stripped in the **same pass** that currently strips provenance metadata, immediately after typecheck and before `lower.ml`. `{Int | p}` becomes `Int`. The monomorphization, defunctionalization, Perceus, borrow, fusion, and LLVM-emit passes **never observe refinements**. The only backend exception is the fallback runtime-check lowering pass (§above), which is inserted between typecheck and lower.

## Interaction with Existing March Features

### `Vector` / `Matrix` / `NDArray`

These are re-specified so their `n`/`m` type parameters mean `len == n`. Concretely:
- `Vector(n, a)` desugars to `{List(a) | len(_) == n}` (or equivalently, carries the refinement in its builtin type scheme).
- `Matrix(m, n, a)` carries `rows(_) == m && cols(_) == n`.
- The `TNat` / `TNatOp` machinery in `typecheck.ml` is subsumed: arithmetic across dimensions (`Matrix(m,k)` × `Matrix(k,n)` → `Matrix(m,n)`) becomes a Z3 VC (`k == k` trivially, `m` and `n` flow through), rather than a `normalize_tnat` special case.

This makes dimension checking **sound** — previously `normalize_tnat` could prove concrete-vs-concrete (e.g., `Vec(3)` ++ `Vec(4)` → `Vec(7)`) but not symbolic cross-argument equalities.

### Linear / affine types

Refinements compose orthogonally with linearity: `{linear Ptr(a) | valid(_)}` is legal. The predicate is on the value; linearity is on the binding. The borrow pass sees only the base type after erasure — no change required.

### Actors and message payloads

Refinements on actor message types are checked at the `send` call site. Orthogonal to session sequencing. The session-type checker runs on the structure of sends/receives; refinements run on the payload types within.

### Content-addressed signatures

A refined function's **signature hash** includes the refinement predicates. A change to a precondition or postcondition predicate invalidates all cached specializations downstream, the same as a type change does today.

### Interfaces

An interface method can carry refinements:
```march
interface Container(c, a) do
  fn get(c: c, i: {Int | _ >= 0 && _ < size(c)}) -> a
end
```
Implementations must satisfy the refinement. Checked at `impl` resolution time.

## Error Reporting

Reuses the provenance-chain error infrastructure in `errors.ml`. A failed VC produces:

```
error: refinement violation
  --> src/main.march:42:5
   |
42 |   get(xs, 10)
   |   ^^^^^^^^^^
   | precondition `_ >= 0 && _ < len(xs)` not satisfied
   | counterexample: len(xs) = 3, i = 10 (violates `10 < 3`)
   | note: pass --require-smt to make unknown/unverified cases hard errors
```

`unknown` produces a warning, not an error (unless `--require-smt`):

```
warning: refinement not verified (z3 returned unknown)
  --> src/main.march:55:3
   | predicate `_ != 0` could not be proved; inserting runtime check
   | hint: use `assume(d != 0)` to suppress (audited)
```

## Escape Hatches

```march
-- admit a predicate without proof (audited, warned under --require-smt)
assume(_ != 0)
assume(len(xs) < 1000)

-- in a function body, to assert a fact for downstream reasoning:
assume(n > 0)   -- adds n > 0 to path context, no VC emitted for the assume itself
```

`assume` is tracked in a separate list in the compilation output (surfaced by `--warn-assumes`) so auditors can locate all admitted obligations.

## Testing

New test suite: `test/run_refinement.exe` (mirrors `run_compiler`/`run_eval`/`run_stdlib` harness).

**Categories:**
- **Positive cases:** VCs that Z3 should verify — bounds-checked `get`, dimension-correct `mat_mul`, postcondition-satisfying `append`.
- **Negative cases:** call sites that must produce a counterexample error — `get xs 10` when `len xs = 3`, `divide n 0`.
- **Path sensitivity:** refinements inferred from `if`/`when` branches; `let`-binding postcondition propagation.
- **Measure reasoning:** `len(append xs ys) == len(xs) + len(ys)` via measure axioms.
- **`unknown` fallback:** `MARCH_NO_Z3=1` triggers runtime-check insertion, confirmed by running the binary and checking panic messages.
- **Assume:** admitted obligations show up in `--warn-assumes` output.
- **Alias subtyping:** `Nat` flows into `{Int | _ >= 0}` and into `Int`; `Int` does not flow into `Nat` without proof.

## Consultation Sites

| File | Change |
|------|--------|
| `lib/ast/ast.ml` | Add `TyRefine of ty * string * expr` (base type, binder name, predicate expr) |
| `lib/parser/parser.mly` + `lib/lexer/lexer.mll` | `{ type \| expr }` production; `_` refinement variable token |
| `lib/typecheck/typecheck.ml` | `CRefine` constraint variant; VC emission in `check_expr` subtyping and call sites; path context stack; measure registry; strip-refinements pass |
| `lib/refine/` (new) | SMT-LIB2 renderer; `z3` subprocess driver; CAS `vc/` read/write; counterexample parser; runtime-check AST emitter |
| `lib/errors/errors.ml` | Counterexample diagnostic variant |
| `test/run_refinement.ml` (new) | Alcotest suite for refinement cases |
| `specs/progress.md` + `specs/todos.md` | Update on completion |

---

## Phase B: Rough Path to Indexed Families

*Not specified to implementation depth — captured here so Phase A's design decisions deliberately enable Phase B.*

Phase B adds **GADT-style indexed datatypes** where a value structurally appears as a type argument and pattern-matching *refines* that argument. Z3 remains the backend; the Phase A plumbing is reused wholesale.

### What's added

**1. GADT constructor signatures.** Today every constructor of a type shares the same result type (`TCon(name, args)`). Phase B lets constructors declare individual result types:

```march
type Vec(n, a) =
  | VNil  : Vec(0, a)
  | VCons : (a, Vec(n, a)) -> Vec(n + 1, a)
```

Touches `ast.ml` (`TyGadt` constructor sig), `parser.mly`, and `typecheck.ml` unification (per-constructor result-type instantiation).

**2. Type refinement on structural pattern match.** Matching `VNil` introduces the equation `n = 0` into the *same path context* Phase A already built. Matching `VCons` introduces `n_outer = n_inner + 1`. These become Z3 VCs via the *same discharge path*.

```march
fn vmap(f: a -> b, xs: Vec(n, a)) -> Vec(n, b) do
  match xs with
  | VNil        -> VNil              -- path context: n = 0; VNil : Vec(0,b) checks trivially
  | VCons(h, t) -> VCons(f(h), vmap(f, t))  -- path context: n = k+1; result Vec(k+1,b) checks
  end
end
```

**3. Index erasure in mono.** `Vec(0,_)` and `Vec(3,_)` must monomorphize to *one* representation. Functions polymorphic in `n` must not specialize per-`n`. The erasure rule: **type indices that are type-level naturals are erased before mono**; mono only specializes on the base type arguments. Touches `lower.ml` (convert indexed types → unindexed base types before TIR) and `mono.ml` (don't specialize on `TNat` indices).

**4. Manual-proof escape hatch.** For VCs where Z3 returns `unknown` (e.g., symbolic nonlinear arithmetic), Phase B adds a propositional equality type `Eq(a, b)` and a `refl` term. Users can thread proof terms through functions where the solver can't help:

```march
fn reverse_append_len(xs: Vec(n, a), ys: Vec(m, a)) -> Eq(n + m, m + n)
```

This is the capability Phase A structurally lacks — its only escape hatch is `assume`.

**5. User-defined measures.** Declared with a `@measure` annotation; the compiler generates SMT axioms from the function definition (must be structurally recursive and total).

### Phase A design decisions that enable Phase B

- The **path context** built in Phase A is exactly what Phase B uses for equation injection on pattern match.
- The **`CRefine` constraint accumulator and Z3 discharge pipeline** handle Phase B's residual equations unchanged.
- The **CAS `vc/` cache** works for Phase B VCs without modification.
- The **counterexample diagnostic infrastructure** is reused.
- Phase A's **erasure pass** is extended, not replaced — indices erase the same way predicates do.

The main new surface in Phase B is in the type and pattern-matching machinery (`ast.ml`, `typecheck.ml` unification, `lower.ml`/`mono.ml` erasure), not in the solver plumbing. Phase A builds the hard part; Phase B builds the expressive part on top.
