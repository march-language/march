# Dependent Types — Phase A: Refinement Types with SMT Backend

**Date:** 2026-06-20
**Status:** Draft

## Motivation

March already advertises compile-time dimension checking via `Vector(n, a)` and `Matrix(m, n, a)`, and its existing constraint pipeline (`pending_constraints`, `CNum`, `CInterface`, etc.) accumulates and discharges type obligations at call sites. But the type-level-natural machinery (`TNat`, `TNatOp`, `normalize_tnat`) handles only structural arithmetic between literal naturals — it can't express "this index is in bounds," "this divisor is nonzero," or "this return length equals the sum of the two inputs."

Refinement types close that gap. A refinement `{T | p}` attaches a logical predicate to an existing base type; the predicate is discharged at every use site by an SMT solver (Z3), then erased before monomorphization. The result is:

- **Array/list bounds** checked at compile time, not via `Option`/`panic` at runtime.
- **Integer preconditions** (nonzero divisor, non-negative count, in-range index) enforced on callers.
- **Cross-argument relationships** (`len(result) == len(xs) + len(ys)`) verified by the compiler.
- **`Vector`/`Matrix`/`NDArray` dimension checking** made sound for the first time.

Zero runtime cost. No change to codegen. Contained almost entirely to `lib/typecheck/` plus a new `lib/refine/` bridge.

## Scope

**In scope (Phase A — this spec):**
- `{T | predicate}` refinement type syntax with `_` or named binder.
- Refinement type aliases: `type Nat = {Int | _ >= 0}`.
- **Integer-/Bool-valued predicates only** in v1 (see §Sorts and the Float caveat). This still covers every dimension, bounds, length, and index case, because measures like `len`/`rows`/`cols` are `Nat`-valued regardless of the element type.
- A fixed set of builtin **measures** (`len`, `abs`, `strlen`, field selectors).
- The refinement **subtyping / VC-emission** relation and its integration with HM unification and bidirectional checking (§Refinements in the Type System) — this is core, not an afterthought.
- **Call-site precondition instantiation** (substituting actuals for formals; §Call-Site Instantiation).
- SMT-LIB2 over a single long-lived `z3 -in` process; VC result caching in the CAS under `vc/`.
- Path-sensitive refinement from `if`/`when`/scalar-`match` guards.
- Graceful no-Z3 degradation: `unknown`/missing-Z3 → runtime check + warning.
- Counterexample reporting in diagnostics (`i = 5`, `len(xs) = 3` violates `i < len(xs)`).
- `assume(p)` escape hatch.
- `--require-smt` flag for CI.
- `Vector(n,a)` / `Matrix(m,n,a)` dimension checking **augmented** by VC generation over their `Nat` indices (additive — existing `TNat` literal checking is preserved; see §Vector / Matrix / NDArray).

**Out of scope (Phase B and beyond):**
- **Float-valued predicates** (comparing `Float` *values*, e.g. `{Float | _ >= 0.0}`). Modeling IEEE-754 `Float` as SMT `Real` is unsound at NaN/∞/rounding; modeling it with Z3's `FloatingPoint` theory is slow and is deferred. Note this does **not** block `Matrix(m, n, Float)` — the *dimensions* are `Nat` and fully supported; only refinements on the *Float payload values* are deferred.
- Indexed families / GADT-style indexed datatypes.
- Propositional equality (`refl`, rewrite).
- User-defined measures.
- Refinement inference (you annotate; Z3 verifies).
- Quantifiers in user predicates, nonlinear arithmetic, inductive proofs.
- Termination / totality checking.

## Surface Syntax

### Refinement types

```march
-- binder form: _ is the refined value
{Int | _ >= 0}
{List(a) | len(_) > 0}
{Int | _ >= 0 && _ < len(xs)}   -- xs is an in-scope program variable (reflectable; see §Sorts)

-- named binder form (required when predicate mentions two refined values)
{v: Int | v > 0 && v < limit}

-- DEFERRED (Phase B): predicates over Float *values* are not in v1.
-- {Float | _ >= 0.0}   -- unsound under Real modeling; see Scope.
```

Parser disambiguation: `{x: T, y: U}` is a record type (field names, colon, comma). `{T | p}` is a refinement (a type expression, then `|`). The `|` cannot appear in a raw type expression, so the grammar is unambiguous.

### Refinement type aliases

```march
type Nat             = {Int | _ >= 0}
type Percent         = {Int | _ >= 0 && _ <= 100}
type NonEmpty(a)     = {List(a) | len(_) > 0}
type BoundedInt(lo, hi) = {Int | _ >= lo && _ <= hi}  -- lo, hi are type-level Nat params in scope as predicate variables
```

Aliases are structural: a `Nat` *flows into* a context expecting `{Int | _ >= 0}` with a trivially-discharged VC, and into a bare `Int` for free (weakening — dropping a predicate never emits a VC); the predicate travels with the alias. (There is no nominal subtyping; "flows into" is the directional check of §Refinements in the Type System.)

### Function signatures

```march
-- preconditions on parameters, postcondition on return
fn get(xs: List(a), i: {Int | _ >= 0 && _ < len(xs)}) -> a

fn divide(n: Int, d: {Int | _ != 0}) -> Int

fn append(xs: List(a), ys: List(a)) -> {List(a) | len(_) == len(xs) + len(ys)}

fn split(xs: List(a), i: {Int | _ >= 0 && _ <= len(xs)})
  -> ({List(a) | len(_) == i}, {List(a) | len(_) == len(xs) - i})

-- Vector dimension checking: indices reflected as Nat measures (additive; see §Vector / Matrix)
fn mat_mul(a: Matrix(m, k, Float), b: Matrix(k, n, Float)) -> Matrix(m, n, Float)
-- a contributes the facts rows(a) == m, cols(a) == k; the shared k is an equality VC.
-- (The Float *payload* carries no value-refinement in v1 — only the Nat dimensions do.)
```

## The Predicate Language

Predicates **reuse March's expression grammar** (so the parser needs no new expression productions — `TyRefine` holds an ordinary `expr`), but are validated post-parse against a **restricted fragment** chosen to keep VCs inside Z3's well-supported theories (linear integer arithmetic + EUF). The compiler rejects predicates outside this fragment with a dedicated diagnostic at the predicate's span, rather than emitting an ill-formed query.

**Allowed:**
| Form | Examples |
|------|---------|
| Logical connectives | `&&`, `\|\|`, `!`, `==>` |
| Comparisons | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Linear integer arithmetic | `+`, `-`, `*`**by an integer literal**, unary `-` |
| Refinement variable | `_` or named binder |
| Reflectable in-scope variables | `Int`/`Bool` params and `let`-bindings, or any variable appearing **only** as the argument of a measure (§Sorts) |
| Builtin measures | `len(e)`, `abs(e)`, `strlen(e)`, `fst(e)`, `snd(e)`, field selectors |
| Literals | integer, bool |

**Explicitly rejected** (compile error at the predicate span, not `unknown`):
- Float-valued terms (deferred; see Scope).
- General nonlinear `x * y` where both are variable.
- Calls to arbitrary user functions (only registered measures may be applied).
- Quantifiers (`forall`, `exists`) in user predicates.
- Recursion inside predicates.
- Side-effecting expressions.

**Decidability caveat.** Restricting *user predicates* to this fragment does **not** guarantee Z3 always returns `sat`/`unsat`. The measure axioms in the preamble (§Measures) are themselves universally quantified (`forall xs h. len(cons(h, xs)) == len(xs) + 1`), so VCs that depend on measure reasoning route through quantifier instantiation and can return `unknown`. The §Outcomes table treats `unknown` as a first-class result with a defined fallback — the system never *relies* on completeness.

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

## Sorts and Reflectable Variables

A predicate is only meaningful if every term in it can be given an SMT **sort**. v1 supports two sorts: `Int` and `Bool`. A term is **reflectable** into the logic iff:

1. it is an integer or boolean literal; or
2. it is `_` / the named binder, and the refinement's **base type** is `Int` or `Bool`; or
3. it is an in-scope variable of type `Int` or `Bool`; or
4. it is a measure application `m(e)` whose result sort is `Int`/`Bool` — here `e` may have **any** type (e.g. `len(xs)` where `xs : List(Float)` is fine, because `len` erases the element type and yields `Nat`).

A variable of a non-reflectable type (e.g. a bare `List(a)`, a record, a function) may appear in a predicate **only** under a measure (case 4). Referencing it bare is the "calls to arbitrary functions / unliftable term" error. This rule is what lets `{Int | _ < len(xs)}` work while rejecting `{Int | _ < xs}`.

Each reflectable variable becomes an SMT constant of its sort; each distinct measure application `m(e)` becomes an application of `m`'s uninterpreted function to a constant standing for `e` (two syntactically equal `e`s share the constant — basic congruence, handled by Z3's EUF).

## Refinements in the Type System

This is the load-bearing integration point, and March's checker is **unification-based with no subtyping relation today** — so refinements cannot be "just unified." The design adds a *directional* check that fits the existing bidirectional structure without disturbing inference of base types.

**Internal representation.** Add `TRefine of ty * predicate` to the internal `ty` (mirroring the surface `TyRefine`). The base `ty` is an ordinary March type and participates in unification normally; the `predicate` rides along as metadata.

**Unification (`unify`) ignores predicates.** `unify(TRefine(t1, p), t2)` reduces to `unify(t1, strip(t2))` and vice-versa; two refinements unify iff their *bases* unify. Unification **never** inspects or discharges predicates — it only keeps base-type inference total and unchanged. This is what keeps the blast radius small: every existing `unify` call site behaves as before on the erased base.

**Discharge happens in `check_expr` (the checking direction), not `unify`.** When the checker is pushing an expression `e` against an *expected* refined type `{T | q}` (function argument against a refined parameter, expression against a refined return annotation, value against a refined `let`/field type), it:
1. checks `e` against the base `T` as usual (full inference/unification);
2. computes the **known refinement** of `e` — the predicate `p` such that `e`'s type is `{T | p}` (from its declared type, a postcondition, or `True` if none);
3. emits the VC `path ∧ p[e/_] ==> q[e/_]`.

In the *inference* direction (synthesizing `e`'s type), refinements are simply propagated outward as metadata; no VC is emitted until a checking boundary is hit. This is exactly how bidirectional systems localize obligations.

**Generalization and instantiation.** A refined type may be generalized into a scheme. The predicate travels **inside** the `ty` component of `Poly(vars, constraints, ty)` (it is *not* a `constraint_`). On instantiation, the predicate is substituted alongside the type, so a polymorphic refined function (`fn id_pos(x: {Int | _ > 0}) -> {Int | _ > 0}`) instantiates its predicates by the same substitution that instantiates its type variables. The existing `constraint_` list still carries only the lightweight typeclass/Nat constraints; `CRefine` (below) is a *transient* accumulator for VC emission, never stored in a scheme.

**Immutability is what makes this sound.** March `let`-bindings are immutable and actor state updates produce *new* values (`{state with f = v}`), so a path fact `x > 0` about a binding `x` can never be invalidated by later mutation. Path context is therefore monotonic within a scope. (If mutable bindings are ever added, facts about a reassigned variable must be retracted — out of scope here.)

## VC Pipeline and Z3 Integration

### Constraint accumulation

Every *checking-direction* boundary against a refined expected type (§Refinements in the Type System) and every call-site precondition emits a **verification condition** — an implication:

```
path_assumptions ∧ known_refinement ==> goal_predicate
```

(There is no general subtyping relation in March; the "`{T|p}` flows into `{T|q}`" check is the directional discharge described above, not a `<:` judgment baked into unification.)

VCs are accumulated as a new `CRefine(formula, span)` variant in `typecheck.ml`'s existing `constraint_` type and `pending_constraints` list.

### Call-site instantiation

A function's preconditions are written in terms of its **formal** parameters; at a call they must be re-expressed in terms of the **actuals**. For a call `f(a0, a1, …)` where `f`'s signature is `f(x0: {T0 | p0}, x1: {T1 | p1}, …) -> {R | q}`:

1. For each argument position, build a substitution `σ = [x0 ↦ ⟦a0⟧, x1 ↦ ⟦a1⟧, …]`, where `⟦ai⟧` is the reflection of the actual:
   - if `ai` is a reflectable variable or measure term, it maps to that term;
   - if `ai` is a compound expression (e.g. `i + 1`), it maps to a **fresh logical constant** `k` constrained by `ai`'s own known refinement (so a `{Int | _ > 0}`-typed sub-expression contributes `k > 0` to the assumptions). Earlier parameters' actuals are in scope for later parameters' predicates — preconditions may be dependent across arguments (the `len(xs)` in `get`'s `i` precondition references the `xs` actual).
2. Emit one VC per parameter: `path ∧ assumptions ==> σ(pi)`.
3. The **result**'s refinement, instantiated as `σ(q)`, becomes the call expression's known refinement, flowing outward for the caller's own checking.

This substitution is the mechanism that makes cross-argument relationships (`mat_mul`'s shared `k`, `split`'s `len(_) == i`) actually check.

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
3. Looked up in the CAS `vc/` namespace — if present, the cached result is used and the solver is not consulted.
4. If absent: submitted to the solver (below) and the result is cached.

### Solver boundary

**Drive a single long-lived `z3 -in` process over SMT-LIB2, not OCaml bindings and not one process per VC.**

- One `z3` process is started lazily on the first uncached VC and reused for the whole compilation unit. The shared measure-axiom preamble is asserted once at the base scope; each VC is checked inside a `(push)`/`(pop)` pair so its assumptions don't leak. This amortizes both process startup and preamble cost across hundreds of VCs.
- Each check sets a per-VC `(set-option :timeout …)`; a timeout is reported as `unknown`.

Rationale for shelling out rather than binding:
- Z3 is an *optional external tool*, not a hard opam/link dependency — the compiler binary stays self-contained and users without Z3 still get the runtime-check fallback.
- SMT-LIB2 is stable across Z3 versions; the OCaml bindings track upstream releases more tightly and would pin the toolchain.
- CAS caching means the solver is consulted once per *unique* VC across all builds, not per build.

Discovery: `MARCH_Z3` env var overrides the path; otherwise `z3` is looked up on `PATH` at process start; the resolved path (or its absence) is recorded for the compilation unit's lifetime.

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

The change is **additive**, not a rewrite of the existing `TNat` machinery — important for back-compat with code already using `Vector(3, Int)`:
- The `n`/`m` indices are reflected into the logic as the `Nat`-valued measures `len(_) == n`, `rows(_) == m && cols(_) == n`. A `Vector(n, a)` value carries an associated logical fact `len(self) == n`.
- The existing `TNat` / `TNatOp` / `normalize_tnat` path is **retained** for the concrete-literal cases it already decides (e.g. `Vec(3)` ++ `Vec(4)` → `Vec(7)`), so existing programs keep type-checking unchanged and pay no solver cost.
- What is **new** is that *symbolic* cross-dimension relationships — `Matrix(m, k)` × `Matrix(k, n)` → `Matrix(m, n)` with `m`, `n`, `k` all variable — now emit a VC instead of being unprovable. The shared `k` becomes an equality obligation; `m` and `n` flow through.

Net effect: dimension checking becomes **sound for symbolic dimensions** for the first time, with zero regression on the literal cases `normalize_tnat` already handled. (A later cleanup could route literal cases through Z3 too and retire `normalize_tnat`, but that is explicitly not required by this spec.)

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

`assume` is a statement over **in-scope variables** (there is no refinement binder `_` in statement position — `_` exists only inside a `{T | …}` annotation). It adds its predicate to the path context for downstream reasoning and emits no VC for itself:

```march
fn f(xs: List(a), d: Int) -> Int do
  assume(d != 0)        -- admit, unproven: downstream `divide(_, d)` now checks
  assume(len(xs) < 1000)
  ...
end
```

`assume` is tracked in a separate list in the compilation output (surfaced by `--warn-assumes`) so auditors can locate all admitted obligations. Under `--require-smt`, each `assume` is reported as a warning (admitted obligations are the audit surface CI cares about).

## Testing

New test suite: `test/run_refinement.exe` (mirrors `run_compiler`/`run_eval`/`run_stdlib` harness).

**Categories:**
- **Positive cases:** VCs that Z3 should verify — bounds-checked `get`, dimension-correct `mat_mul`, postcondition-satisfying `append`.
- **Negative cases:** call sites that must produce a counterexample error — `get xs 10` when `len xs = 3`, `divide n 0`.
- **Path sensitivity:** refinements inferred from `if`/`when` branches; `let`-binding postcondition propagation.
- **Measure reasoning:** `len(append xs ys) == len(xs) + len(ys)` via measure axioms.
- **`unknown` fallback:** `MARCH_NO_Z3=1` triggers runtime-check insertion, confirmed by running the binary and checking panic messages.
- **Assume:** admitted obligations show up in `--warn-assumes` output.
- **Alias flow / weakening:** `Nat` flows into `{Int | _ >= 0}` and into bare `Int`; a bare `Int` does **not** flow into `Nat` without a discharged VC.

## Implementation Order

Phase A is itself built in checkpointable increments, each independently testable:

- **A0 — Plumbing, no solver.** `TyRefine` in AST + parser; `TRefine` in the internal `ty`; `unify` ignores predicates (base-type inference must be unchanged — regression-test the full existing suite here). Predicates parsed and fragment-validated but **not discharged**. Exit criterion: every existing test still passes; refined annotations parse and erase.
- **A1 — Solver bridge + Int-only preconditions.** `lib/refine/` with the SMT-LIB2 renderer, long-lived `z3 -in` driver, CAS cache, and counterexample parser. VC emission for parameter preconditions and call-site instantiation over `Int`/`Bool`. No measures, no path sensitivity yet. Exit criterion: `divide(n, 0)` errors with a counterexample; `divide(n, 1)` passes.
- **A2 — Measures + postconditions.** Builtin measure registry and axiom preamble; postcondition VCs (`append`'s `len` relation). Exit criterion: `len(append(xs, ys)) == len(xs) + len(ys)` verifies.
- **A3 — Path sensitivity + Vector/Matrix.** `if`/`when`/scalar-`match` assumptions; `Vector`/`Matrix` dimension VCs. Exit criterion: bounds checks discharged via a guarding `if`; symbolic `mat_mul` checks.
- **A4 — Robustness.** No-Z3 runtime-check fallback pass; `--require-smt`; `assume` + `--warn-assumes`. Exit criterion: `MARCH_NO_Z3=1` build runs and panics on violation.

## Consultation Sites

| File | Change |
|------|--------|
| `lib/ast/ast.ml` | Add `TyRefine of ty * string option * expr` (base type, optional binder name — `None` means `_`, predicate reuses `expr`) |
| `lib/parser/parser.mly` + `lib/lexer/lexer.mll` | `{ type \| expr }` and `{ name : type \| expr }` productions; `_` legal as an expression atom inside a predicate |
| `lib/typecheck/typecheck.ml` | `TRefine` in internal `ty`; `unify` strips predicates; directional discharge + VC emission in `check_expr`; call-site instantiation/substitution; path-context stack; sort/reflectability check; measure registry; predicate-fragment validator; strip-refinements pass; predicates carried in `Poly` scheme `ty` |
| `lib/refine/` (new) | SMT-LIB2 renderer + measure-axiom preamble; long-lived `z3 -in` driver with push/pop; CAS `vc/` read/write; counterexample-model parser |
| `bin/main.ml` (or the pass driver) | Post-typecheck runtime-check fallback lowering pass (between typecheck and `lower.ml`); `--require-smt` / `--warn-assumes` flags |
| `lib/errors/errors.ml` | Counterexample diagnostic variant (model → human-readable witness) |
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
