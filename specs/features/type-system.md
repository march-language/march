# March Language Type System

**Last Updated:** March 22, 2026
**Status:** Production-ready with known limitations

## Overview

March implements a **bidirectional Hindley-Milner type system** with three major extensions:

1. **Linear/Affine Type Tracking** — constrains use of values to exactly once (linear) or at most once (affine)
2. **Type-Level Naturals** — support for `Vec[T, N]` and other dependent types via arithmetic at the type level
3. **Provenance-Driven Error Reporting** — errors carry "reason chains" explaining *why* a type was expected

The type checker is implemented in two stages:
- **Type Checking** (`lib/typecheck/typecheck.ml`) — bidirectional inference with HM polymorphism
- **Monomorphization** (`lib/tir/mono.ml`) — specializes polymorphic functions to their call-site types

---

## 1. Implementation Architecture

### File Structure

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Type Checker | `lib/typecheck/typecheck.ml` | 3389 | Bidirectional HM inference, linearity, session types, interfaces |
| TIR Definition | `lib/tir/tir.ml` | ~120 | Monomorphic, ANF-based IR |
| Monomorphization | `lib/tir/mono.ml` | 315 | Specializes polymorphic functions |
| AST & Types | `lib/ast/ast.ml` | ~320 | Surface syntax, type representations, session types |
| Error Reporting | `lib/errors/errors.ml` | 90 | Diagnostic context and rendering |
| Evaluation | `lib/eval/eval.ml` | 4567 | Runtime including Chan.send/recv/close eval |

### Design Sections in typecheck.ml

The type checker is organized into 16+ sections (file is 3389 lines):

1. **§1 Provenance** (lines 35–70) — `reason` type for error context
2. **§2 Internal Type Representation** (lines 71–107) — `ty`, `tvar`, `scheme`, `constraint_`, `session_ty`, `TChan`
3. **§3 Fresh Variables & Levels** (lines 108–117) — `fresh_var()`, generalization levels
4. **§4 Type Utilities** (lines 118–150) — `repr()`, `occurs()` check, type operations
5. **§5 Pretty-Printing** (lines 151–234) — `pp_ty`, `pp_session_ty`, display names for unification vars
6. **§6 Elm-Style Error Parts** — `message_part`, rich error formatting
7. **§7 Type Environment** — `env`, `lin_entry`, `ctor_info`; includes `protocols` and `sigs` registries
8. **§8 Generalization & Instantiation** — `generalize()`, `instantiate()`
9. **§9 Built-in Types** — `base_env`, `builtin_bindings`, capability hierarchy, Chan.* builtins, interface builtins
10. **§10 Unification** — `unify()`, `session_ty_equal`, error reporting
11. **§11 Surface-Type Conversion** — `surface_ty()`, record expansion
12. **§12 Linearity Tracking** — `record_use()`, `bind_linear_field_sentinels`, `check_linear_all_consumed`
13. **§13 Pattern Inference** — `infer_pattern()`, constructor matching with linearity propagation
14. **§14 Expression Checking** — `infer_expr()`, `check_expr()`, bidirectional flow; Chan.send/recv/close/choose/offer special cases
15. **§15 Declaration Checking** — `check_decl()`; `pub_set` visibility enforcement; sig conformance; protocol duality verification
16. **§16 Module Entry Point** — `check_module()`, main API

---

## 2. Hindley-Milner Type Inference

### Core Type Language (Internal Representation)

The type checker uses an enriched internal type `ty` distinct from surface `Ast.ty`:

```ocaml
type ty =
  | TCon    of string * ty list          (* Int, List(a), Map(k,v) *)
  | TVar    of tvar ref                  (* unification variable *)
  | TArrow  of ty * ty                   (* a -> b *)
  | TTuple  of ty list                   (* (a, b, c); () for unit *)
  | TRecord of (string * ty) list        (* { x : Int; y : Float } *)
  | TLin    of linearity * ty            (* linear / affine wrapper *)
  | TNat    of int                       (* type-level natural literal *)
  | TNatOp  of nat_op * ty * ty          (* n + m, n * m *)
  | TError                               (* error sentinel *)

and tvar =
  | Unbound of int * int   (* id, generalization level *)
  | Link    of ty          (* solved: points to this type *)
```

**Key Design:**
- Unification variables (`TVar`) carry both an **id** (for identity) and a **level** (for scope-based generalization)
- `TError` is a **recovery sentinel** — unifies with anything to allow error recovery
- **Linearity qualifiers** (`TLin`) wrap types to encode linear/affine constraints
- **Type-level naturals** (`TNat`, `TNatOp`) represent dependent-type positions

### Type Schemes & Polymorphism

```ocaml
type scheme =
  | Mono of ty                          (* monomorphic *)
  | Poly of int list * constraint_ list * ty  (* ∀α₁…αₙ. τ *)
```

**Poly Interpretation:**
- `Poly (ids, cs, ty)` represents `∀α₁ … αₙ. τ` where:
  - `ids` = list of quantified variable IDs
  - `cs` = class constraints that must be discharged at each instantiation
  - `ty` = the quantified type body

**Generalization:** After a `let` binding, all unbound type variables at levels *strictly greater* than the enclosing scope are quantified (Damas-Milner).

**Instantiation:** Each use of a polymorphic binding replaces quantified variables with fresh unification variables, and appends constraints to `env.pending_constraints` for discharge at declaration boundaries.

### Bidirectional Type Checking

The type checker implements two dual judgments:

```
infer_expr : env → expr → ty
(synthesize the type of an expression)

check_expr : env → expr → ty → unit
(verify an expression against a known type)
```

**Decision Points:**
- **Annotations & return types** drive the "check" direction (top-down)
- **Everything else** is inferred (bottom-up)
- **Function applications** infer the function type, then check arguments

**Function Type Checking** (`check_fn`, lines ~1335–1400):
1. Enter a new level
2. Bind parameters with their annotated types (or fresh vars)
3. Infer the body's type
4. Check body against declared return type (if present)
5. Generalize the inferred signature
6. Discharge constraints

---

## 3. Linear Type System

### Linearity Qualifiers

Three levels of usage restriction (surface syntax in `Ast.linearity`):

```ocaml
type linearity =
  | Unrestricted  (* normal: use any number of times *)
  | Linear        (* exactly once *)
  | Affine        (* at most once *)
```

### Tracking Mechanism

**Environment Entry:**
```ocaml
type lin_entry = {
  le_name : string;
  le_lin  : linearity;
  le_used : bool ref;  (* mutable flag *)
}
```

**Process:**
1. When a linear/affine variable enters scope, an entry is added to `env.lin`
2. Each variable **use** calls `record_use()` (line 876), which:
   - For `Linear`: errors if already used, then marks as used
   - For `Affine`: errors if already used, then marks as used
   - For `Unrestricted`: no-op
3. When a scope closes (e.g., function ends), `check_linear_all_consumed()` (line 897) verifies:
   - All `Linear` variables were used exactly once
   - Errors if a linear var was never consumed

### Error Messages

**Double use:**
```
The linear value `x` is used more than once here.
Linear values must be consumed exactly once — they cannot be copied or ignored.
```

**Never used:**
```
The linear value `x` was never used.
Linear values must be consumed exactly once — did you mean to pass it somewhere?
```

### Limitations

- **Record fields** can be declared linear (e.g., `{ x : linear Int }`), but the checker does not yet enforce per-field linearity constraints within record operations.

> **Update (March 20, 2026):** Two previous limitations have been fixed in commit d8e4566 (Track A):
> - ~~Pattern matching does not propagate linearity constraints to bound variables.~~ **FIXED:** `infer_pattern` now propagates `TLin` qualifier to pattern-bound variables.
> - ~~Closures do not track capture of linear variables.~~ **FIXED:** Captures of linear values are now tracked; capturing a linear variable marks it as consumed in the enclosing scope.

### Design Intent: Linear + Affine as First-Class Options

Both **linear** and **affine** types are supported as first-class options in the type system:

- **Linear** (`linear T`): Resources that *must* be consumed exactly once. Use cases: session channels, file handles, database transactions.
- **Affine** (`affine T`): Resources where dropping is acceptable but duplication is not. Use cases: unique buffers, capability tokens, one-shot continuations.

This dual design allows library authors to choose the appropriate restriction level for their resource types. Linear types enforce the strictest discipline (no drop, no dup), while affine types relax the "must use" requirement for cases where cleanup can happen implicitly (e.g., via destructors or RC).

---

## 4. Type-Level Naturals & Dependent Types

### Representation

Type-level natural numbers appear in the AST and internal types:

```ocaml
(* AST (surface syntax) *)
| TyNat of int                    (* 3 *)
| TyNatOp of nat_op * ty * ty     (* n + m, n * m *)

(* Internal type *)
| TNat of int
| TNatOp of nat_op * ty * ty
```

### Unification Rules

Type-level naturals unify structurally:
- `TNat n1` unifies with `TNat n2` only if `n1 = n2`
- `TNatOp (op1, a1, b1)` unifies with `TNatOp (op2, a2, b2)` only if:
  - `op1 = op2` (same operator)
  - `a1` unifies with `a2`
  - `b1` unifies with `b2`

### Use Cases

**Vector Types:**
```march
type Vec(T, N) = ...
fn dot_product(v1: Vec(Int, 3), v2: Vec(Int, 3)) : Int
```

Allows compile-time verification that operand dimensions match.

### Limitations

- **Arithmetic is not simplified** — `1 + 2` does not reduce to `3` at type-check time
- **No constraint solving** — the unifier does not solve equations like `N + 1 = 3` for `N`
- **No dependent pattern matching** — cannot match on natural structure in patterns
- Primarily a **placeholder** for future dependent-type extensions (Coq-style)

---

## 5. Unification & Occurs Check

### The `unify` Function

```ocaml
let rec unify env ~span ?(reason = None) t1 t2 =
  let t1 = repr t1 and t2 = repr t2 in
  match t1, t2 with
  (* 10 cases — see lines 723–776 *)
```

**Cases:**
1. **Error sentinel** (`TError`) — absorbs any type, returns silently
2. **Same variable** — trivially unified
3. **Variable binding** — unifies with occurs check (line 736)
4. **Type constructors** — unify args if names and arities match
5. **Function types** — unify domain and codomain
6. **Tuples** — unify element-wise (must have same length)
7. **Records** — unify field types (must have same fields, sorted)
8. **Linearity wrappers** — unify inner types if qualifiers match
9. **Type-level naturals** — structural equality
10. **Type-level operations** — unify both operands if operators match
11. **Anything else** — type mismatch error

### Occurs Check & Level Adjustment

```ocaml
let rec occurs id level = function
  | TVar r ->
    (match !r with
     | Unbound (id', l) ->
       if id = id' then true
       else (if l > level then r := Unbound (id', level); false)
     | Link t -> occurs id level t)
  | ... (* recursive descent *)
```

**Dual Purpose:**
1. **Occurs Check:** prevents infinite types (e.g., `a ~ a -> a`)
2. **Level Adjustment (Rémy Trick):** lowers the generalization level of encountered variables to enable proper let-polymorphism

### Error Recovery

On mismatch, `report_mismatch()` (lines 695–718):
- Renders a conversational message: "I expected `X` but found `Y`."
- Includes a **reason label** explaining why `X` was expected
- Returns without throwing an exception
- The variable is linked to `TError` so later constraints unify silently

---

## 6. Provenance & Error Context

### The `reason` Type

```ocaml
type reason =
  | RAnnotation of Ast.span           (* user wrote : T *)
  | RFnReturn of string * Ast.span    (* declared return of fn name *)
  | RFnArg of Ast.span * int          (* argument #i at call site *)
  | RMatchArm of Ast.span             (* all match arms must agree *)
  | RLetBind of Ast.span              (* RHS of let binding *)
  | RBuiltin of string                (* language invariant *)
  | RBecause of reason * string       (* chain: A because "..." *)
```

Every `unify()` call passes a `~reason` parameter that explains the origin of the expected type.

### Error Message Construction

When a mismatch occurs, the reason becomes a **label** pointing to the source of the expectation:

```
Expected type:        Int
Found:                String

This is the declared return type of `foo`.
(↑ label points to the fn signature)
```

### Benefit

Users understand not just *what* is wrong (type mismatch) but *why* the type was expected (annotation, call site, match arm, etc.).

---

## 7. Constraints & Interface Typeclass System

### Constraint Types

```ocaml
type constraint_ =
  | CNum of ty        (* must be Int or Float — arithmetic operators *)
  | COrd of ty        (* must be Int, Float, or String — comparison ops *)
  | CInterface of string * ty  (* must implement named interface *)
```

> **Update (March 20, 2026):** The `CInterface` variant was added in commit d8e4566 (Track A). Interface constraints like `when Eq(a)` are now emitted during instantiation and discharged by verifying that a matching `impl` exists for the concrete type.

### Polymorphic Operator Schemes

Arithmetic operators like `+` are polymorphic with constraints:

```ocaml
("+",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
```

This encodes: `∀a:Num. a -> a -> a`

**Constraint Table:**
- `Num`: `Int`, `Float` (line 467)
- `Ord`: `Int`, `Float`, `String` (line 480)

### Constraint Discharge

After type checking a declaration, `discharge_constraints()` (lines 1560–1579) validates:

```ocaml
| CNum t when repr t = Int | Float -> ()  (* valid *)
| CNum t -> error "type does not support arithmetic"
| COrd t when repr t in {Int, Float, String} -> ()
| COrd t -> error "type does not support comparison"
| TVar _ -> ()  (* unresolved — polymorphic, constraint preserved *)
```

### Interface System Integration — Partially Complete

The AST includes `DInterface` (line 134) and `DImpl` (line 135) declarations. As of commit d8e4566 (Track A):

- ✅ **Interface constraints are now discharged** — `when Eq(a)` clauses are checked at call sites via `CInterface` constraints
- ✅ **Impl existence verified** — calling a constrained function with a type lacking the required impl produces a type error
- ❌ **Interface method dispatch is not yet implemented** — no vtable or dictionary passing
- ❌ **Superclass constraints are not transitive** — `impl Ord for T` does not require `impl Eq for T`

The constraint system now handles built-in `Num`, `Ord`, and user-defined interface constraints.

---

## 8. Monomorphization

### Purpose

After type checking, all functions may be polymorphic. Before code generation, `lib/tir/mono.ml` specializes each polymorphic function to its concrete call-site types.

### Algorithm

**Input:** TIR module with functions containing `TVar` placeholders
**Output:** TIR module where every reachable function has monomorphic types

**Steps:**

1. **Build fn_table** — map function names to their original definitions (line 276)
2. **Seed worklist** with:
   - All monomorphic functions (no `TVar` in params or return type)
   - Functions named "main" or "*.main" (entry points)
3. **Process queue:**
   - Pop `(target_name, orig_fn, subst)` from worklist
   - Apply substitution to get specialized version
   - Rewrite all `EApp` calls in the body:
     - If callee is polymorphic, derive substitution from arg types
     - Create mangled name (e.g., `map$Int$Bool`)
     - Enqueue specialization if not already done
   - Add result to output list
4. **Output** — all reachable functions, monomorphized

### Type Matching & Substitution

```ocaml
let rec match_ty (poly : ty) (conc : ty) (acc : subst) : subst =
  match poly, conc with
  | TVar name, t -> if not already_bound then (name, t) :: acc else acc
  | TCon (n1, ps1), TCon (n2, ps2) when n1=n2 -> fold_left2 match_ty acc ps1 ps2
  | ...
```

Matches a polymorphic type against a concrete type, accumulating variable bindings.

### Name Mangling

```ocaml
let mangle_name (base : string) (tys : ty list) : string =
  base ^ "$" ^ String.concat "$" (List.map mangle_ty tys)
```

Example: `map` instantiated with `Int` and `Bool` → `map$Int$Bool`

### Unreachable Code Elimination

Polymorphic functions with no monomorphic callers are **dropped** — they don't appear in the output TIR module.

---

## 9. Built-in Bindings & Type Environment

### Base Environment

`base_env()` (lines 685–688) seeds the type checker with:

1. **Builtin types** (lines 657–669):
   - Scalars: `Int`, `Float`, `Bool`, `String`, `Char`, `Atom`, `Unit`
   - Containers: `List(a)`, `Option(a)`, `Result(a, e)`, `Set(a)`, `Array(a)`
   - Concurrency: `Pid(a)`, `Cap(a)`, `Task(a)`, `WorkPool`, `Node`
   - Advanced: `Vector(a, b)`, `Matrix(a, b, c)`, `NDArray(a, b)`
   - IO capabilities: `IO`, `IO.Console`, `IO.FileSystem`, `IO.FileRead`, `IO.FileWrite`, `IO.Network`, `IO.Process`, `IO.Clock`

2. **Builtin constructors** (lines 673–683):
   - `Some`, `None` (Option)
   - `Ok`, `Err` (Result)
   - `Cons`, `Nil` (List)

3. **Builtin operations** (lines 439–655):
   - **Arithmetic:** `+`, `-`, `*`, `/`, `%`, `negate`, `+.`, `-.`, `*.`, `/.`
   - **Comparison:** `<`, `>`, `<=`, `>=`, `==`, `!=`, `&&`, `||`
   - **String:** `++`, `string_*` (20+ functions), `string_split`, `string_join`, etc.
   - **List:** `head`, `tail`, `is_nil`
   - **Type conversion:** `int_to_string`, `float_to_string`, `string_to_int`, `string_to_float`
   - **Primitives:** `print`, `println`, `read_line`, `not`
   - **Math:** `math_sqrt`, `math_sin`, `math_cos`, etc. (30+ functions)
   - **Actor/Task:** `respond`, `kill`, `is_alive`, `task_spawn`, `task_await`, `task_yield`
   - **Capability:** `root_cap`, `cap_narrow`
   - **I/O:** `file_*`, `dir_*` (20+ functions)
   - **Special:** `panic`, `todo_`, `unreachable_`

### Capability Hierarchy

The checker implements a **subtyping relationship** for capability types:

```ocaml
let io_cap_hierarchy = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ...
]
```

**Subtyping Rule:** `cap_subsumes parent child` — parent is an ancestor of (or equal to) child.

**Application:** When a function signature requires `Cap(X)`, a `needs X` declaration in the module must list X (or an ancestor).

---

## 10. Testing & Coverage

### Test File: `test/test_march.ml`

Key type-system test categories:

| Category | Tests | Line Range |
|----------|-------|------------|
| **Parsing** | `test_parse_*` | 1108–1180 |
| **Type Checking** | `test_tc_*` | 1020–1068 |
| **Constraints** | `test_tc_num_*`, `test_tc_ord_*` | 1020–1068 |
| **TIR Lowering** | `test_tir_lower_*` | 579–700 |
| **Type Map Population** | `test_type_map_*` | 1296–1340 |
| **Monomorphization** | `test_mono_*` | 614–700 |
| **Full Pipeline** | `test_end_to_end_*` | 1336–1400+ |

### Key Test Patterns

**Type Inference:**
```march
fn identity(x) do x end
fn add(x: Int, y: Int) do x + y end
```
Tests bidirectional inference with and without annotations.

**Polymorphism & Constraints:**
```march
fn add(x, y) do x + y end  (* infers Num constraint *)
fn compare(a, b) do a < b end  (* infers Ord constraint *)
```

**Monomorphization:**
```march
fn id(x) do x end
fn main do id(42); id("hello") end
```
Tests that `id` is specialized to `id$Int` and `id$String`.

**Type Map Consistency:**
Tests that the `type_map` (expression → type mapping) is populated for all subexpressions and used during lowering.

---

## 11. Known Limitations & Future Work

### Complete Limitations

1. ~~**Interface constraints not discharged**~~ ✅ **FIXED** (commit d8e4566)
   - Interface constraints are now discharged via `CInterface` constraint variant
   - `when Eq(a)` clauses are verified at call sites

2. **No constraint simplification**
   - Type-level naturals like `1 + 2` are not evaluated to `3`
   - No solving of linear equations (e.g., `N + 1 = 5` for `N`)

3. **Linearity not propagated through records**
   - Fields marked `linear` in record definitions don't enforce consumption
   - Record operations (update, projection) don't check field linearity

4. ~~**Pattern matching doesn't preserve linearity**~~ ✅ **FIXED** (commit d8e4566)
   - `infer_pattern` now propagates `TLin` qualifier to pattern-bound variables

5. **Row polymorphism not supported**
   - Record operations with unknown record types don't generate constraints
   - `e.field` when `e : TVar` returns a fresh var instead of constraining the record shape

6. **No rank-2 polymorphism**
   - Cannot write `fn apply(f, x) : ∀b. b -> b` with higher-rank types
   - All quantification is at rank 1 (prenex)

7. **No existential types**
   - Cannot pack types with type witnesses (useful for OOP-style interfaces)

8. **No GADTs**
   - Generalized Algebraic Data Types would enable richer type reasoning
   - Currently only simple variants and records

### Partial Implementation

1. **Session types (protocols)** — ✅ **Phases 1–3 implemented** (see `specs/features/session-types.md`)
   - `TChan` type + full `session_ty` AST (`SSend`/`SRecv`/`SChoose`/`SOffer`/`SRec`/`SEnd`)
   - `Chan.send`/`recv`/`close`/`choose`/`offer` are special-cased in `infer_expr` with linear channel advancement
   - Protocol registration, projection, and duality checking
   - Still incomplete: `SRec` recursive protocol unfolding, multi-party (post-v1)

2. **Module signatures** — ✅ **Phase 2 sig conformance implemented**
   - `sig Name do ... end` is checked against the actual `mod Name` — missing declarations are errors
   - Opaque type enforcement (abstract types hiding their representation) not yet implemented

### Performance & Quality

1. **Error recovery could be better**
   - After a mismatch, subsequent checks may produce cascading errors
   - Phantom type errors (errors due to earlier mistakes) are common

2. **Error messages for complex types can be verbose**
   - Nested generic types (`Map(String, List(Vec(Int, N)))`) render very long
   - No pretty-printer with abbreviated names or aliases

3. **Monomorphization can cause code explosion**
   - Generic functions called with many types produce many specializations
   - No strategy for code bloat mitigation (e.g., shared monomorphic versions)

---

## 12. Implementation Status Summary

### Complete & Production-Ready

- Bidirectional Hindley-Milner type inference
- Unification with occurs check and level-based generalization
- Linear/affine type tracking with enforcement
- Polymorphic operator overloading (Num, Ord)
- Type-level naturals (parsed, unified, but not solved)
- Monomorphization with name mangling
- Comprehensive built-in library types and functions
- Provenance-driven error reporting with reason chains
- Capability type hierarchy and module `needs` checking

### Partially Implemented

- Interface/typeclass system (constraints discharged; method dispatch and superclasses not yet implemented)
- Session types / protocols (parsed, not validated)
- Module signatures (parsed, opaque types not enforced)

### Stubbed / Not Implemented

- Constraint solving for dependent types
- Row polymorphism
- Rank-2 / higher-rank polymorphism
- Existential types
- GADTs
- Linear/affine propagation through records

---

## 13. Key Functions & Types Reference

### Core Inference

| Function | Lines | Purpose |
|----------|-------|---------|
| `infer_expr` | 1030+ | Synthesize the type of an expression (bottom-up) |
| `check_expr` | 1250+ | Check an expression against a known type (top-down) |
| `infer_pattern` | 919–998 | Infer the type expected by a pattern, return bindings |
| `infer_app` | 1230+ | Type a function application, unify args |
| `infer_match` | 1270+ | Type a match expression, unify all arms |
| `infer_block` | 1180+ | Type a `do ... end` block |
| `check_fn` | 1330+ | Type check a function definition |

### Unification & Type Operations

| Function | Lines | Purpose |
|----------|-------|---------|
| `unify` | 723–776 | Unify two types, report errors |
| `repr` | 123–132 | Follow unification variable links with path compression |
| `occurs` | 136–150 | Occurs check + level adjustment (Rémy trick) |
| `surface_ty` | 785–868 | Convert surface `Ast.ty` to internal `ty` |
| `generalize` | 307–325 | Quantify unbound variables at proper level |
| `instantiate` | 330–356 | Replace quantified vars with fresh unification vars |

### Linearity

| Function | Lines | Purpose |
|----------|-------|---------|
| `record_use` | 876–895 | Mark a variable as used, error on excess use |
| `check_linear_all_consumed` | 897–908 | After scope close, verify all linear vars consumed |
| `bind_linear` | 294–299 | Bind a variable with linearity qualifier |

### Environment

| Function | Lines | Purpose |
|----------|-------|---------|
| `bind_var` | 287–289 | Add a variable binding to the environment |
| `bind_vars` | 290–292 | Batch add multiple bindings |
| `lookup_var` | 283 | Find a variable's scheme |
| `lookup_type` | 284 | Find a type constructor's arity |
| `lookup_ctor` | 285 | Find a data constructor's info |
| `enter_level` / `leave_level` | 280–281 | Push/pop the generalization level stack |

### Constraints & Capabilities

| Function | Lines | Purpose |
|----------|-------|---------|
| `discharge_constraints` | 1560–1579 | Validate accumulated class constraints |
| `cap_ancestors` | 402–410 | Get the capability subtyping chain |
| `cap_subsumes` | 411–415 | Check if one capability subsumes another |
| `check_module_needs` | 1620–1673 | Validate module capability declarations |

### Declaration Checking

| Function | Lines | Purpose |
|----------|-------|---------|
| `check_decl` | 1675+ | Type check a single top-level declaration |
| `check_module` | 1770+ | Main entry point; type check a whole module |

---

## 14. Type Representation Examples

### Simple Types

```ocaml
(* Int *)
TCon ("Int", [])

(* List(a) where a is a fresh unification variable *)
TCon ("List", [TVar (ref (Unbound (1, 0)))])

(* a -> b -> Int *)
TArrow (
  TVar (ref (Unbound (2, 0))),
  TArrow (
    TVar (ref (Unbound (3, 0))),
    TCon ("Int", [])
  )
)
```

### Polymorphic Scheme

```ocaml
(* ∀a:Num. a -> a -> a *)
Poly (
  [1],  (* quantified var id *)
  [CNum (TVar (ref (Unbound (1, 0))))],  (* constraint *)
  TArrow (TVar (ref (Unbound (1, 0))),
          TArrow (TVar (ref (Unbound (1, 0))),
                  TVar (ref (Unbound (1, 0)))))
)
```

### Linear Type

```ocaml
(* linear Int *)
TLin (Ast.Linear, TCon ("Int", []))

(* affine (a -> b) *)
TLin (Ast.Affine, TArrow (TVar (...), TVar (...)))
```

### Type-Level Natural

```ocaml
(* Vec(Int, 3) *)
TCon ("Vec", [TCon ("Int", []); TNat 3])

(* Vec(Int, N + 1) *)
TCon ("Vec", [TCon ("Int", []); TNatOp (NatAdd, TNat (NatVar "N"), TNat 1)])
```

---

## 15. Error Reporting Examples

### Type Mismatch with Reason

```
Expected type:        Int -> Int
Found:                String -> Bool

This is argument #1 of a function call.
The expected type comes from here: (points to call site)
```

### Linearity Violation

```
The linear value `resource` is used more than once here.
Linear values must be consumed exactly once — they cannot be copied or ignored.
```

### Constraint Discharge Failure

```
String does not implement Num (only Int and Float do).
```

---

## References

- **Type Checker:** `lib/typecheck/typecheck.ml` (2006 lines, 16 sections)
- **TIR Definition:** `lib/tir/tir.ml` (monomorphic IR types)
- **Monomorphization:** `lib/tir/mono.ml` (specialization algorithm)
- **Tests:** `test/test_march.ml` (1300+ lines, type system tests at ~1020+)
- **AST Types:** `lib/ast/ast.ml` (surface syntax, including type expressions)
- **Error System:** `lib/errors/errors.ml` (diagnostic reporting)

---

**Document Version:** 1.1
**Last Verified:** March 22, 2026
**Maintainer:** Type System Team

**Implementation:** `lib/typecheck/typecheck.ml` (3389 lines), `lib/ast/ast.ml`, `lib/tir/mono.ml`
