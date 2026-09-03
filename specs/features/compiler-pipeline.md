# March Language Compiler Pipeline

**Document Date**: March 22, 2026 (body); execution modes and status table revised 2026-08-25
**Scope**: the compiler pipeline, stage by stage. Intentionally no file sizes;
see `specs/2026-08-25-file-decomposition-analysis.md` for current, re-derivable
measurements.

**Implementation:** `lib/` directory: `typecheck/`, `tir/`, `jit/`, `repl/`, `cas/`, `debug/`, `scheduler/`

> **Parenthetical line numbers are historical and unverified.** Many sections
> below still carry pointers of the form "(lines 212-330)" or "(line 65)". These
> date from the March 2026 draft and were **not** worked out again during the
> 2026-08-25 claim audit; several that were spot-checked were stale by tens of
> lines (in §14, for instance, `free_vars`/`called_fns`/`reachable_fns` were
> cited at lines 11/55/71 against actual 12/61/123). They have been stripped from
> the sections this audit corrected and left in place elsewhere. **Locate things by
> name (`forge search "<name>"`), not by the numbers in this file.** New line
> numbers must not be added; see the intentional no-sizes decision recorded at the
> Implementation Status Summary.

## Overview

The March compiler transforms source code through a series of passes, from surface syntax to LLVM IR emission. The pipeline emphasizes type safety (bidirectional Hindley-Milner type checking), memory safety (linear/affine types, reference counting), and performance (escape analysis, defunctionalization, optimization).

### High-Level Architecture

```
Source Code
    ↓
[Lexer] (lib/lexer/lexer.mll)
    ↓
[Parser] (lib/parser/parser.mly)
    ↓
[Desugaring] (lib/desugar/desugar.ml)
    ↓
[Type Checking] (lib/typecheck/typecheck.ml — Typecheck.check_module / check_module_full)
    ↓
[Session Type Verification] (typecheck.ml: infer_expr Chan.* cases + project_protocol)
    ↓
[Refinement Check] (lib/refinecheck/refine_check.ml — Refine_check.check_module, post-typecheck)
    ↓
[Division Safety Check] (lib/refinecheck/division_safety.ml — Division_safety.check_module, `cap no_panic` modules only)
    ↓
[No-Alloc Check] (lib/refinecheck/no_alloc.ml — No_alloc.check_module, `cap no_alloc` modules only)
    ↓
[Capability Inference Hints] (lib/refinecheck/cap_infer.ml — Cap_infer.check_module, emits `needs` hints)
    ↓
[Return Refinement Inference] (lib/refinecheck/return_infer.ml — Return_infer.infer_module, Z3 sign probing)
    ↓
[AST → TIR Lowering] (lib/tir/lower.ml — Lower.lower_module)
    ↓
[Monomorphization] (lib/tir/mono.ml — Mono.monomorphize)
    ↓
[Fusion] (lib/tir/fusion.ml — Fusion.run)
    ↓
[Defunctionalization] (lib/tir/defun.ml — Defun.defunctionalize)
    ↓
[Known-call] (lib/tir/known_call.ml — Known_call.run)   ← before Perceus
    ↓
[Beta-ADT] (lib/tir/beta_adt.ml — Beta_adt.run)         ← before Perceus
    ↓
[Join points (pre)] (lib/tir/join_points.ml — Join_points.run_pre)
    ↓
[Perceus RC Analysis] (lib/tir/perceus.ml — Perceus.perceus)
    ↓
[Escape Analysis] (lib/tir/escape.ml — Escape.escape_analysis)   ← AFTER Perceus
    ↓
[Optimization Loop] (lib/tir/opt.ml)  ← fixed-point over NINE passes, in this order
  ├─ [Join points]        (lib/tir/join_points.ml)
  ├─ [Known-call]         (lib/tir/known_call.ml)
  ├─ [Inlining]           (lib/tir/inline.ml)
  ├─ [Single-use inline]  (lib/tir/single_use_inline.ml)
  ├─ [Constant propagation] (lib/tir/cprop.ml)
  ├─ [Constant Folding]   (lib/tir/fold.ml)
  ├─ [Simplification]     (lib/tir/simplify.ml)
  ├─ [Struct fusion]      (lib/tir/fusion.ml — Fusion.run_struct)
  └─ [Dead Code Elimination] (lib/tir/dce.ml)
  (+ [Purity Analysis] (lib/tir/purity.ml) — not a loop member; an oracle
     consulted by Inline, Fusion and DCE)
    ↓
[LLVM IR Emission] (lib/tir/llvm_emit.ml — Llvm_emit.emit_module)
    ↓
[Code Generation] (lib/codegen/codegen.ml)  ← thin shim, clang invoked from bin/main.ml
```

> **This diagram is the `--compile` (AOT) path only.** March has three execution
> modes and they do not share one pipeline: the interpreter never builds TIR at
> all, and `--jit` runs a shorter TIR pipeline than `--compile` does. See §18.1
> for the three paths side by side.

> **Pass-order note.** The actual ordering enforced by `bin/main.ml` is
>
> **Lower → Vectorize_mark → Trmc → Mono → Fusion → *(Policy-DCE audit)* → Defun → Known_call → Beta_adt → Join_points.run_pre → Simplify(pre-Perceus) → Perceus → Drop → Escape → Opt → Llvm_emit.**
>
> In particular **Perceus runs *before* Escape** (see `bin/main.ml`, `Perceus.perceus` then `Escape.escape_analysis`). Earlier revisions of this document had the two reversed; that was wrong.
>
> **Correction (2026-08-25 claim audit).** The version of this note immediately
> above read *Lower → Mono → Fusion → Defun → Known_call → Beta_adt →
> Join_points → Perceus → Escape → Opt → Llvm_emit*, omitting five real steps.
> That was wrong, and the omissions matter to anyone inserting a pass:
> - **`Vectorize_mark.mark`** runs immediately after Lower, and *must*: it is the
>   only point where a TIR function's name is still exactly its source name
>   (Mono has not mangled anything, Defun has not lifted anything), so
>   `@[vectorize]` attributes can be matched by name equality. Skipped for the
>   JS target.
> - **`Trmc.report` + `Trmc.transform_module`** run between Lower and Mono. The
>   transform is **off by default** (gated on `--trmc` / `MARCH_TRMC`); the
>   report is gated on `MARCH_TRMC_REPORT`. It must run this early because by
>   Perceus the stdlib's nested `go` helpers are closures invoked via
>   `ECallPtr`, so self-recursion is no longer syntactically visible.
> - **`Policy_dce.audit`** runs after Fusion. It is an audit, not a transform:
>   it reports policy-tag violations and `exit 1`s on any.
> - **`Simplify.run ~pre_perceus:true`** runs just before Perceus, applying only
>   the rewrites that are sound *before* RC insertion (currently the empty-string
>   concat identities). The post-Perceus `Opt` loop runs Simplify with
>   `pre_perceus:false` and never applies these.
> - **`Drop.run`** runs *between* Perceus and Escape (deep-drop synthesis: routes
>   a bare `EDecRC` on a heap-owning aggregate through a generated destructuring
>   drop so children are released too). Skipped for the JS target, the runtime
>   of which is GC'd. A reader who believed Escape immediately followed Perceus would
>   place a new pass on the wrong side of this.
>
> Also note that **Fusion, Known_call, Beta_adt, Join_points.run_pre and the
> pre-Perceus Simplify are all conditional on `!opt_enabled`**: at `--opt 0`
> they do not run at all. Lower, Mono, Defun, Perceus, Drop and Escape are
> unconditional.

---

## 1. Lexical Analysis

**File**: `lib/lexer/lexer.mll`
**Status**: Complete

### Key Features

- **Token types**: Integers, floats, strings (with interpolation), atoms (`:ok`, `:error`), identifiers, keywords
- **String interpolation**: `"hello ${name}!"`: parsed into `INTERP_START`, `INTERP_MID`, `INTERP_END` tokens for nested expression evaluation
- **Comments**: Single-line (`--`) and nested block comments (`{- ... -}`)
- **Keyword table** (lines 13-62): Keywords like `fn`, `let`, `do`, `end`, `if`, `match`, `actor`, `protocol`, `interface`, `impl`
- **Linearity qualifiers**: `linear`, `affine` for type-level usage constraints
- **Capability declarations**: `needs`, `use`, `extern`

### Data Structures

- `interp_depth` (ref, lines 11): Tracks brace nesting in string interpolation
- `keyword_table` (Hashtbl, lines 13-62): Maps strings to tokens

### Main Entry Point

- `token` (line 72): Lexbuf → token, handles all lexical rules

---

## 2. Parsing

**File**: `lib/parser/parser.mly`
**Status**: Complete

### Key Features

- **Grammar**: ML/Elixir hybrid with `do...end` blocks, `fn` definitions, pipe operators
- **Multi-clause functions**: Parser groups consecutive `fn name` clauses into a single `DFn` declaration via `group_fn_clauses` (lines 36-54)
- **Expression desugaring**: String interpolation is desugared during parsing via `desugar_interp` (lines 27-34)
- **Pattern matching**: Comprehensive support for constructors, atoms, tuples, literals, records, list literals (`[a, b]` → `Cons(a, Cons(b, Nil))`)
- **Operator precedence**: Pipe (`|>`), logical (`||`, `&&`), comparison, addition, multiplication, unary negation/not
- **Type annotations**: Function return types (`:T`), parameter types, let bindings
- **Module system**: Modules (`mod Name do ... end`), signatures (`sig`), implementations (`impl`)
- **Actors**: State machines with handlers (`on Message do ... end`)
- **Protocols**: Binary session types (`protocol Name do ... end`)

### Parse Entry Points

- `module_` (line 93): Full program = `mod Name do decls end`
- `expr_eof` (line 682): Standalone expression
- `repl_input` (line 685): REPL line (decl, expr, or EOF)

### Error Recovery

Detailed error messages with hints (lines 97-105, 152-161, etc.). Example:
```
I was expecting `do` to start the function body here:
fn name(params) do
    body
end
```

---

## 3. Desugaring Pass

**File**: `lib/desugar/desugar.ml`
**Status**: Complete

### Transformations

1. **Pipe desugaring** (lines 83-95):
   - `x |> f(a,b)` → `f(x, a, b)` (Elixir-style, LHS becomes first arg)
   - Recursive descent into all expression nodes

2. **Multi-head function desugaring** (lines 176-228):
   - Multi-clause `fn` → single clause with `EMatch` on synthesized arg names
   - Example:
     ```
     fn fib(0) do 0 end
     fn fib(1) do 1 end
     fn fib(n) do fib(n-1) + fib(n-2) end
     ```
     becomes:
     ```
     fn fib(__arg0) do
       match __arg0 with
       | 0 -> 0
       | 1 -> 1
       | n -> fib(n-1) + fib(n-2)
       end
     end
     ```

3. **Module member access desugaring** (lines 135-141):
   - `Mod.fn(...)` → `EVar "Mod.fn"` (qualified names as single atoms)

4. **Intra-module bare-name qualification** (`qualify_module_refs`,
   `collect_direct_names`, `qualify_expr`): a bare call inside a module body
   (`connect(host, port)` written inside `mod Socket do ... end`) is
   otherwise the same in the AST as a reference to some unrelated
   top-level `connect`: `EVar "connect"` either way. Left unresolved, three
   downstream passes (eval's `base_env` stdlib isolation, typecheck's
   `pre_env` shadowing, and TIR's `rename_tir_vars`) each had to
   independently guess the right binding, which meant a refactor touching
   any one of them could silently re-expose a footgun where a user-defined
   top-level function of the same name shadows a module's own. This pass
   closes the ambiguity at the source: after ordinary desugaring, it walks
   the declaration tree with an accumulated module-path prefix and rewrites
   every bare `EVar` that resolves to a name declared **directly** in the
   enclosing module (not shadowed by a closer binder, not already qualified,
   not brought in via `use`/`DUse` import) to its fully-qualified form
   (`EVar "Socket.connect"`) before typecheck, eval, or TIR see it. The
   three downstream protections still run as defense-in-depth for cases this
   pass doesn't cover (`DUse` aliasing, module-level `DLet` values), but they
   are no longer the primary line of defense.

### Data Structures

- `fresh_arg_name` (lines 48-51): Generates `__arg0`, `__arg1`, ... to avoid user shadowing
- `is_trivial_param` (lines 56-59): Detects simple parameters (no pattern matching)

### Module Entry Point

- `desugar_module` (line 262): Entire module transformation

---

## 4. Type Checking

**File**: `lib/typecheck/typecheck.ml`
**Status**: Complete, heavily featured

Entry points: `Typecheck.check_module` and `check_module_full` (the latter also returns the typecheck env). Capability/`needs` enforcement is embedded here via `check_module_needs`. Pattern-match exhaustiveness (`check_exhaustiveness`/`find_missing_mc`) and redundancy (`check_redundant_arms`) checks run during declaration checking. Type-level naturals are reduced by `normalize_tnat`. Immediately after typecheck, `bin/main.ml` runs `Refine_check.check_module` for refinement-type verification.

### Architecture (16 sections)

1. **Provenance** (lines 36-69): Reason chains explain why types were expected (for error messages)
2. **Internal types** (lines 71-149):
   - `ty`: TCon, TVar, TArrow, TTuple, TRecord, TLin, TNat, TNatOp, TError
   - `tvar`: Unbound (with generalization level) or Link (solved)
   - `constraint_`: CNum, COrd (arithmetic/ordering requirements)
   - `scheme`: Mono or Poly (∀ types + constraints)

3. **Fresh variable generation** (lines 112-116)
4. **Type utilities** (lines 122-149):
   - `repr`: Follow unification links with path compression
   - `occurs`: Occurs check + level adjustment (Rémy/Damas-Milner)

5. **Pretty printing** (lines 155-203): User-friendly type display
6. **Error message parts** (lines 212-233): Composable message fragments (code, type, prose, bullets)
7. **Type environment** (lines 240-298):
   - `env`: vars, types, ctors, records, level, linear use tracking, errors, constraints, type_map, interfaces, protocols
   - `lin_entry`: Tracks linear/affine variable usage via mutable `used` flag

8. **Generalization & instantiation** (lines 307-355):
   - `generalize`: Quantify free variables above current level
   - `instantiate`: Fresh unification vars + constraint discharge

9. **Built-in types** (lines 361-397):
   - Scalars: Int, Float, Bool, String, Unit, Atom
   - Containers: List(a), Option(a), Result(a, e), Pid(a)
   - Capability hierarchy: IO, IO.Console, IO.FileSystem, IO.Network, etc.

10. **Unification** (§10): Core algorithm with provenance
11. **Surface type conversion** (§11): Ast.ty → internal ty
12. **Linearity tracking** (§12): Mutable `used` refs enforce usage rules
13. **Pattern inference** (§13): Patterns constrain types
14. **Expression checking** (§14):
    - `infer_expr`: Synthesize type from expression
    - `check_expr`: Verify against expected type
    - Bidirectional checking for fn return types, annotations

15. **Declaration checking** (§15): Functions, types, modules, actors, interfaces, impls, externs
16. **Module entry** (§16): `check_module` → (errors, type_map)

### Key Functions

- `infer_expr` (§14): Expression → (type, env)
- `check_expr` (§14): Expression → Expected type → (type, env)
- `unify` (§10): Type × Type × Reason → env (with error handling)
- `generalize` (lines 307-324): Quantify free variables
- `instantiate` (lines 326-355): Replace quantified vars with fresh ones
- `check_module` (§16): Module → (error context, type map)

### Type Map

Hashtbl mapping expression span → inferred type. Used by lowering to produce concrete types.

---

## 5. Lowering to TIR

**File**: `lib/tir/lower.ml`
**Status**: Complete

### Target Intermediate Representation

`Tir.tir_module`: A-Normal Form (ANF): all function arguments are atoms (vars/literals)

### Key Transformations

1. **CPS-based ANF** (lines 171-189):
   - `lower_to_atom_k`: Ensure expr result is an atom, wrapping non-atomic results in `ELet`
   - `lower_atoms_k`: Process list of exprs to atoms
   - Example: `f(g(x), y)` becomes `let $t = g(x); f($t, y)`

2. **Type conversion** (lines 31-95):
   - Ast.ty → Tir.ty (scalars, constructors, functions, etc.)
   - Typecheck.ty → Tir.ty (uncurries function types: `TArrow(a, TArrow(b, c))` → `TFn([a, b], c)`)

3. **Expression lowering** (lines 192-300+):
   - Literals, variables, applications
   - Blocks → right-nested `ELet` chains
   - Patterns in let bindings → nested `ELet` + `EField`
   - If expressions → `ECase` on bool
   - Match expressions → `ECase` with branches
   - Lambdas → `ELetRec` (single-clause fn with closure env)
   - Tuples, records, field access
   - Constructors, atoms, actors (`spawn`, `send`)

4. **Use import resolution** (lines 119-127): Rewrite unqualified names via `_use_aliases`
5. **Interface method resolution** (lines 130-160): Dispatch interface calls to impl functions
6. **Type map threading** (lines 96-115): Lookup types by expression span

### Data Structures

- `_lower_counter` (line 20): Fresh name generation
- `_type_map_ref` (line 101): Typecheck type_map option (set at module entry)
- `_use_aliases` (line 121): Maps unqualified → qualified names
- `_iface_methods` (line 133): Maps method names → (type, impl_fn) lists

### Main Entry Points

- `lower_expr` (line 192): Ast.expr → Tir.expr (ANF)
- `lower_to_atom_k` (line 171): CPS version ensuring atomic result

---

## 6. TIR Types and Structures

**File**: `lib/tir/tir.ml`
**Status**: Complete

### ANF-Based IR

```ocaml
type ty = TInt | TFloat | TBool | TString | TUnit
        | TTuple of ty list
        | TRecord of (string * ty) list
        | TCon of string * ty list
        | TFn of ty list * ty
        | TPtr of ty
        | TVar of string

type atom = AVar of var | ADefRef of def_id | ALit of literal

type expr = EAtom of atom
          | EApp of var * atom list
          | ECallPtr of atom * atom list
          | ELet of var * expr * expr
          | ELetRec of fn_def list * expr
          | ECase of atom * branch list * expr option
          | ETuple of atom list
          | ERecord of (string * atom) list
          | EField of atom * string
          | EUpdate of atom * (string * atom) list
          | EAlloc of ty * atom list
          | EStackAlloc of ty * atom list
          | EFree of atom
          | EIncRC of atom
          | EDecRC of atom
          | EAtomicIncRC of atom          (* actor-shared values *)
          | EAtomicDecRC of atom
          | EReuse of atom * ty * atom list
          | ESeq of expr * expr
          | EAllocHole of atom option * ty * atom list * int   (* TRMC *)
          | ESetField  of atom * int * atom                    (* TRMC hole-fill *)
```

> **Correction (2026-08-25 claim audit).** The listing above previously omitted
> four constructors: `EAtomicIncRC`, `EAtomicDecRC`, `EAllocHole` and
> `ESetField`. A pass author writing a `match` over `Tir.expr` from this
> document would have written a non-exhaustive one. The atomic RC pair is the
> actor-shared-value counterpart to `EIncRC`/`EDecRC`; `EAllocHole`/`ESetField`
> are the destination-passing pair introduced by the TRMC transform, and
> `ESetField` is the one expression form the purity oracle must treat as impure
> (§20). This listing is a reading aid, not a substitute for `lib/tir/tir.ml`.

### Type Definitions

- `var`: Variable with type + linearity (Lin, Aff, Unr)
- `def_id`: Content-addressed definition (name + BLAKE3 hash)
- `fn_def`: Function name, params, return type, body
- `branch`: Pattern match arm (tag, bound vars, body)
- `type_def`: Variant, record, or closure struct definition
- `extern_decl`: FFI function declaration
- `tir_module`: Module name, functions, type definitions, externs

---

## 7. Monomorphization Pass

**File**: `lib/tir/mono.ml`
**Status**: Complete

### Purpose

Eliminates all `TVar` type variables by specializing polymorphic functions at call sites.

### Algorithm

1. **Type detection** (lines 16-24): `has_tvar` checks for unresolved type variables
2. **Type substitution** (lines 26-79): Apply type substitutions to types, vars, atoms, exprs
3. **Name mangling** (lines 82-106): `mangle_ty`, `mangle_name` produce readable specialized names
   - Example: `map$Int$Bool` for `map` specialized to `Int → Bool`
4. **Type matching** (lines 108-127): `match_ty` derives substitution by matching concrete args to polymorphic params
5. **Worklist monomorphization** (lines 129+):
   - Build table of all `fn_def`s
   - Seed worklist with root functions (no TVar in params)
   - For each dequeued function + substitution:
     - Apply substitution
     - Walk body for EApp calls to polymorphic functions
     - Derive specialization from arg types
     - Clone + rename callee, enqueue

### Key Functions

- `has_tvar` (line 16): Type contains unresolved variables?
- `match_ty` (line 115): Match polymorphic type against concrete type
- `build_subst` (line 134): Derive substitution from fn params and arg types
- `rewrite_calls` (line 160): Rewrite call sites to specialized function names

---

## 8. Defunctionalization Pass

**File**: `lib/tir/defun.ml`
**Status**: Complete

### Purpose

Eliminate lambdas (higher-order functions) by:
1. Creating closure structs for captured environments
2. Lifting lambda bodies to top-level with free vars as leading params
3. Replacing lambda creation with struct allocation
4. Replacing indirect calls with dispatches through apply functions

### Phases

1. **Collect top-level names**: User functions ∪ `builtin_names`
2. **Free variable analysis** (lines 70-149):
   - `free_vars_of_expr`: Collect unbound variable names used in lambda body
   - Excludes parameters, bound variables, and top-level names
   - Returns sorted list for determinism

3. **Lambda detection** (lines 152-199):
   - `lambda_info`: Detected lambda with free vars + recursion flag
   - Distinguishes self-recursive vs. non-recursive lambdas
   - Self-recursion flag enables recursive apply-function dispatch

4. **Lambda lifting** (lines 200+):
   - Each lambda gets unique ID and lifted function name
   - Closure struct created with free var fields
   - Lifted function params = (free vars) + (original params)

### Data Structures

- `builtin_names`: the set of operator and builtin names that defun must **not**
  treat as first-class functions. Several hundred entries (548 distinct names as
  of 2026-08-25, a figure that moves with every new builtin, so treat it as a
  scale, not a constant; the list itself is the source of truth).
- `lambda_info`: `lam_fn`, `lam_fvs`, `lam_is_recursive`, `lam_uid`
- `lambda_counter`: Global UID generator

> **Correction (2026-08-25 claim audit).** This document gave two mutually
> contradictory sizes for `builtin_names` ("63+ names" in the Phases list and
> "Set of 56" here) and both understate it by roughly an order of magnitude.
> The list is not a small table of arithmetic operators; it spans arithmetic,
> string, math, float, IO, task/cancellation, signal and actor builtins. That
> matters because **a missing entry is a codegen bug, not a missed
> optimization**: `defun.ml` includes a worked example in a comment where an
> absent `task_cancel_by_id` caused defun to emit a `@task_cancel_by_id$clo_wrap`
> trampoline calling a non-existent `@task_cancel_by_id`, producing LLVM "use of
> undefined value". See also the "adding one builtin touches nine sites" note in
> the repo's builtin skill.

---

## 9. Escape Analysis Pass

**File**: `lib/tir/escape.ml` (`Escape.escape_analysis`)
**Status**: Complete

> **Order:** Escape analysis runs **after** Perceus (§10), not before. It examines the RC-annotated TIR and removes dead RC ops on values it promotes to the stack.

### Purpose

Stack-promote heap allocations with lifetimes that don't escape the current function.

### Algorithm

1. **Collect EAlloc candidates** (lines 65-87): Vars bound directly to `EAlloc` in outer scopes
2. **Escape detection** (lines 93-220):
   - A candidate "escapes" if it appears in:
     - Return position (tail atom)
     - Function call arguments
     - Heap allocations (constructor args)
     - Tuples, records, updates
     - Closure captures
3. **Stack allocation** (`promote_expr`): Replace the `EAlloc` of each
   **non-escaping** candidate with `EStackAlloc`
4. **RC cleanup**: Remove dead RC ops on stack-allocated vars

> **Correction (2026-08-25 claim audit).** Step 3 previously read "Replace
> **escaped** `EAlloc` with `EStackAlloc`". That was exactly backwards, and it
> describes a use-after-return bug rather than the optimization: stack-promoting
> a value that escapes the frame is exactly what escape analysis exists to
> prevent. `escape_fn` computes `promotable = candidates − (escaping ∪
> with_incrc)` and rewrites only that set.

Two further conditions the earlier prose omitted:

- The `with_incrc` exclusion: a candidate that has any `EIncRC` taken on it is
  **not** promotable even if it does not otherwise escape.
- Only allocations that actually emit a heap cell are candidates at all
  (`alloc_emits_heap_cell`): Niche- and Newtype-repr constructors are skipped.
  `escape_analysis` derives a `collision_set` from the module's own `tm_types`
  so this Boxed/Niche/Newtype classification agrees with what codegen will emit
  for a same-short-name colliding type.

### Key Functions

- `collect_alloc_candidates`: Find EAlloc binding candidates
- `escaping_vars`: Subset of candidates that escape
- `escape_fn`: Per-function driver computing the promotable set
- `escape_analysis`: Module entry point

---

## 10. Perceus Reference Counting Pass

**File**: `lib/tir/perceus.ml` (`Perceus.perceus`)
**Status**: Complete

> **Order:** Perceus runs **before** Escape analysis (§9). Several earlier passes (Known_call, Beta_adt, Join_points.run_pre) are intentionally sequenced *before* Perceus so RC is inserted once over their already-simplified output.

### Purpose

Insert reference-counting instructions (EIncRC, EDecRC) and linear/affine cleanup (EFree) based on static last-use analysis.

### Algorithm

1. **Liveness analysis** (lines 41-118):
   - Backwards: compute live-after-instruction sets
   - `live_before`: Vars live *before* expr given those live *after*

2. **Last-use detection** (lines 121-210):
   - `last_use`: Find position where var is last referenced
   - If last use is in tail, no decrement needed

3. **RC insertion** (lines 212-330):
   - Linear/affine vars → `EFree` instead of RC
   - Unrestricted vars → `EIncRC` at definition, `EDecRC` at last use

4. **FBIP detection** (`lib/tir/perceus_fbip.ml`):
   - **FBIP = "Functional But In-Place"** (Reinking/Xie/Leijen, the Koka Perceus
     line of work): reuse dead heap objects rather than free-then-allocate
   - When constructing a value of the same shape as a var that just went dead, reuse
     its allocation
   - Emits `EReuse` instead of `EAlloc`

> **Correction (2026-08-25 claim audit).** An earlier revision expanded FBIP as
> "Function Body Inlining and Partial Application". That is not what FBIP stands
> for and describes a different optimization entirely; no code in
> `lib/tir/perceus_fbip.ml` inlines function bodies or handles partial
> application. The acronym is "Functional But In-Place".

5. **Optimization** (lines 330+):
   - Adjacent EIncRC/EDecRC pairs cancel
   - Dead RC ops removed

### Key Functions

- `live_before` (line 41): Liveness computation
- `analyze_rc` (line 212): Main RC analysis
- `insert_rc` (line 330): Insert RC instructions

---

## 11. Inlining Pass

**File**: `lib/tir/inline.ml`
**Status**: Complete

### Heuristics

- **Size threshold**: `inline_size_threshold = 50` TIR nodes. Single-expression
  functions (node count 1) are always eligible regardless of the threshold.

  > **Correction (2026-08-25 claim audit).** This previously read "15 TIR
  > nodes". That was the *original* value; `lib/tir/inline.ml` states so in as
  > many words ("Set higher than the original 15 to capture typical HTTP
  > middleware helpers"). The live threshold is 50, more than 3× the figure
  > this document reported, which materially changes what a reader expects to
  > be inlined.

- **Purity**: Function must be pure (no side effects); see §20, and note that
  purity here is a *blacklist* judgement, not a proof
- **Hot Code Reload**: when `Opt.run` is given a `~hot_reload` config, boundary
  (reloadable) functions are excluded from the candidate set so
  boundary→boundary calls survive to codegen as dispatch-table edges
- **Non-recursive**: Avoids infinite loops
- **Non-mutually-recursive**: Filters functions calling other candidates

### Algorithm

1. **Candidate selection** (lines 142-176):
   - Collect pure, small, non-recursive functions
   - Remove any that call another candidate (conservatively)

2. **Alpha-renaming** (lines 42-106):
   - Freshen all parameter and let-bound variable names
   - Avoids variable capture in inlined body

3. **Argument substitution** (lines 109-116):
   - Wrap arguments in ANF lets so each param = let x = arg; ...

4. **Call rewriting** (lines 118-140):
   - At each `EApp` to an inlining candidate:
     - Alpha-rename function body
     - Substitute args
     - Mark `changed`

---

## 12. Constant Folding Pass

**File**: `lib/tir/fold.ml`
**Status**: Complete

### Operations Folded

- Arithmetic: `+`, `-`, `*`, `/`, `%`, `+.`, `-.`, `*.`, `/.` (integer and float)
- Comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Logical: `&&`, `||`, and `not` (the builtin is spelled `not`, not `!`)
- String: `++` / `string_concat` (concatenation)

> **Correction (2026-08-25 claim audit).** This list previously ended with a
> line reading "**Type checks**: `is_int`, `is_float`, `is_string`, `is_bool`".
> Those four names do not appear anywhere in `lib/tir/fold.ml` and no such
> folding happens. The line was removed rather than fixed, because there is no
> corresponding behavior to describe.

### Algorithm

- Walk TIR, recognize `EApp(builtin, [atom1, atom2, ...])` with literal atoms
- Evaluate at compile time
- Replace with literal result

---

## 13. Simplification Pass

**File**: `lib/tir/simplify.ml`
**Status**: Complete

### Simplifications

Algebraic peephole rewrites on expression *shape*. All results stay in ANF; any
new operation is bound to a fresh let (`let_wrap`).

- **Arithmetic identities**: `x + 0`, `0 + x`, `x - 0`, `x * 1`, `1 * x`,
  `x / 1` → `x`; `x * 0`, `0 * x` → `0`; `x - x` → `0` (integer only);
  `0 / x` → `0` only when `x` is a known non-zero literal
- **Boolean case collapse**: `if x then true else false` → `x`;
  `if x then false else true` → `not x`
- **Reflexive comparison**: `x == x` → `true`, `x != x` → `false`, **guarded by
  `is_float_free`**: IEEE 754 mandates `NaN ≠ NaN`, so these are unsound for
  any type that might contain a float. `TCon` and `TVar` are conservatively
  treated as float-*containing*.
- **`~pre_perceus` mode**: a separate invocation before Perceus applies only the
  rewrites that are sound before RC insertion (currently the empty-string concat
  identities `x ++ "" → x`, `"" ++ x → x`). The post-Perceus `Opt` loop passes
  `pre_perceus:false` and never applies these.

> **Correction (2026-08-25 claim audit).** The previous list here was largely
> not describing this pass. It claimed five items; three were wrong:
> - "**Trivial applications**: `f(atom)` where f is an identity or constant
>   builtin": no such rewrite exists in `simplify.ml`.
> - "**Dead tuple/record fields**: Unused fields" and "**ELet optimization**:
>   Unused bindings": these are **DCE's** job (§14), not Simplify's;
>   `simplify.ml` recurses through `ELet` without dropping a single one.
> - "**Redundant operations**: e.g. `not(true)` → `false`": that specific fold
>   lives in `lib/tir/fold.ml` (§12), not here.
>
> Only "ECase simplification" was in the right neighbourhood, and even it was
> imprecise: the pass collapses the two *boolean-literal* case shapes above, not
> "single-branch cases" in general. The float-freeness guard on `x == x`, which
> is the one truly subtle thing about this pass, went unmentioned entirely.

---

## 14. Dead Code Elimination Pass

**File**: `lib/tir/dce.ml`
**Status**: Complete

### Two Phases

1. **Dead let removal**:
   - If var not used in body → drop `ELet` (if pure) or replace with `ESeq`

2. **Unreachable function removal** (`root_names` → `reachable_fns` →
   `prune_unreachable`). The root set is, in order:
   - every function named `main` or `*.main`
   - the setup / setup-all / migrate functions (`Tir_names.setup_fn_name`,
     `setup_all_fn_name`, `is_migrate_fn_name`)
   - everything in `tm_exports` and everything in `tm_tests`
   - **only if the above is empty**, the caller-supplied `~extra_root` names
   - **only if it is still empty and `~fail_open` is true**, every function

   Reachability is then computed with `free_vars`, *not* `called_fns`, so that
   closure apply-function pointers stored in `EAlloc` args count as references.

> **Correction (2026-08-25 claim audit).** This previously read "Build
> reachability graph from `main` entry point / If no `main`, seed with all
> functions". Both parts were wrong in ways that matter:
> - Exports, tests and the setup/migrate functions are roots too. A reader who
>   believed only `main` roots the graph would expect DCE to delete a module's
>   test functions and its `tm_exports`, which it does not.
> - The all-functions fallback is **not** simply "no `main`". It is gated on
>   `~fail_open`, and `extra_root` gets a turn first. `fail_open:false` is used
>   intentionally for *analysis* callers, where the accurate answer for a module
>   with no entry point is that it reaches no code; the code comment records
>   that failing open there made the capability upper limit report the entire
>   prepended stdlib for a file containing a single `assert true`.
>
> DCE also consults `Purity.is_pure_ext` with the module's transitive
> impure-function set (§20), not the plain `is_pure`, so that a binding like
> `let _ = System.put_env(…)`, with impurity that is invisible at the call site, is
> not deleted.

### Key Functions

- `free_vars`: Free variables in expression
- `called_fns`: Functions called from expression
- `root_names`: Entry-point root set (see above)
- `reachable_fns`: Transitive reachability from those roots
- `prune_unreachable` / `run`: Module-level drivers

---

## 15. Optimization Coordinator

**File**: `lib/tir/opt.ml`
**Status**: Complete

### Fixed-Point Loop

`Opt.named_passes` runs **nine** passes in this order, repeating the whole
sequence up to 5 times, stopping early when an iteration makes no change:

| # | Pass | Why it sits here |
|---|------|------------------|
| 1 | `Join_points.run` | hoists common leading lets above `ECase`, exposing shared structure to everything downstream **in the same iteration** |
| 2 | `Known_call.run` | `ECallPtr` → `EApp` for statically-known closures, so Inline can see and inline the lifted apply functions |
| 3 | `Inline.run` | exposes literal arguments at inlined call sites |
| 4 | `Single_use_inline.run` | inlines functions down to one remaining call site |
| 5 | `Cprop.run` | propagates those literals through let chains |
| 6 | `Fold.run` | evaluates the now-literal arithmetic |
| 7 | `Simplify.run` (`~pre_perceus:false`) | identity laws / strength reduction on folded results |
| 8 | `Fusion.run_struct` | collapses chains of record-update operations |
| 9 | `Dce.run` | removes let bindings made dead by folding/simplification |

`run` also takes an optional `~snap` callback, invoked after each individual
pass with a label `"tir-opt-{iter}-{pass}"`, and an optional `~hot_reload`
config that it installs into `Inline.boundary_config` for the duration of the
run (restored via `Fun.protect`).

> **Correction (2026-08-25 claim audit): this was the worst error in the
> document after §17.** The previous text claimed the loop runs
> "**Inline → Fold → Simplify → DCE**", and illustrated it with a block of
> OCaml presented as the body of `Opt.run`:
>
> ```ocaml
> let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
> ```
>
> **No such code exists in `lib/tir/opt.ml`, and it never did in this shape.**
> Five of the nine real passes (`Join_points`, `Known_call`,
> `Single_use_inline`, `Cprop` and `Fusion.run_struct`) were missing entirely.
> The fabricated snippet was the damaging part: a plausible-looking verbatim
> quotation invites a reader to trust it over the source, and someone adding an
> optimization would have inserted it into a four-element list that is not there.
>
> **`Beta_adt` is intentionally NOT in this loop**: it runs once, pre-Perceus
> (see the pass-order note at the top). `opt.ml` includes a long comment
> explaining that this placement is essential for `Single_use_inline`'s
> capture guard, and that moving `Beta_adt` into the loop (or adding any other
> post-Perceus case-of-known-constructor reduction) would make a
> currently-unreachable variable-capture bug reachable. Read that comment and
> the guard in `lib/tir/single_use_inline.ml` before changing pass membership.

---

## 16. LLVM IR Emission

**File**: `lib/tir/llvm_emit.ml`
**Status**: Substantially complete

### Object Layout

All heap values are opaque pointers to:
```
offset  0: i64 rc        (reference count, init 1)
offset  8: i32 tag       (constructor index)
offset 12: i32 pad       (alignment)
offset 16+8i: field[i]   (i64 for Int/Bool/Unit, double for Float, ptr for others)
```

Allocation size = 16 + arity × 8 bytes.

### Key Components

1. **Context** (lines 22-79):
   - Output buffers: `buf` (code), `preamble` (globals)
   - Counters: `ctr` (fresh names), `blk` (labels), `str_ctr` (strings)
   - Maps: `ctor_info` (now keyed by `"TypeName.CtorName"`), `top_fns`, `field_map`, `poly_ctors`, `type_params`
   - Local vars: `var_slot` (alloca names), `local_names` (uniquification)
   - Closures: `emitted_wraps` (generated wrappers)
   - FFI: `extern_map` (March → C name mapping)

> **Update (March 20, 2026, commit 2c710f7, Track B):**
> - **Constructor name collision fixed:** Constructor metadata in `ctx.ctor_info` is now keyed by type-qualified names (`"TypeName.CtorName"`) instead of bare constructor names. This eliminates the collision bug where two types defining identically-named constructors would silently overwrite each other. The same qualification is applied in TIR `lower.ml`.
> - **Arity mismatch now errors:** The silent `None -> "ptr"` fallback for out-of-range constructor field indices has been replaced with `failwith` + a diagnostic error message. The compiler now raises a hard error instead of silently emitting incorrect LLVM IR.

2. **Type mapping** (lines 114-129):
   - TIR → LLVM types: `Int → i64`, `Float → double`, `Bool → i64`, heap values → `ptr`

3. **Built-in recognition** (lines 142-150):
   - Operators like `+`, `*`, `==` lowered to native LLVM instructions

4. **Function codegen** (lines 250+):
   - `march_main` emitted as `@march_main`
   - C wrapper `@main` appended that calls `@march_main`, returns 0

5. **Expression codegen**:
   - Literals → immediates
   - Variables → alloca loads
   - ELet → new alloca slot + store
   - EApp → direct call or indirect via closure apply
   - ECase → switch on tag + branch code + result alloca

6. **Closure handling**:
   - Closure structs → struct type definitions
   - Apply functions → take closure ptr + args, dispatch to actual fn

### Key Functions

- `make_ctx` (line 62): Create codegen context
- `fresh` (line 83): Fresh LLVM register name
- `llvm_name` (line 104): Sanitize name for LLVM
- `emit_expr` (lines 250+): Lower TIR expr to LLVM IR
- `emit_fn_def` (lines 500+): Emit function definition
- `emit_module` (lines 1600+): Top-level module emission

---

## 17. `lib/codegen`: a vestigial shim, not the code generator

**File**: `lib/codegen/codegen.ml`
**Status**: Empty placeholder. **Code generation itself is implemented and shipping**; it simply does not live here.

This module is a leftover:

```ocaml
let compile _module_ = ()  (* TODO: Implement *)
```

An earlier revision of this document read that literally and reported "full code
generation (linking, assembly) not yet implemented", which is false and badly
misleading: March emits LLVM IR and links native binaries today. The real path
is `lib/tir/llvm_emit.ml` (+ the `llvm_*` family) for IR, and `bin/main.ml` for
the clang invocation that assembles and links it. See §16 and §18.

The shim is retained only because the `march_codegen` library name is still
referenced by the build; no code calls into it.

---

## 18. Main CLI Entry Point

**File**: `bin/main.ml`, one of the largest and most-edited files in the tree.
An earlier revision claimed 334 lines, understating it by more than an order of
magnitude; a figure added on 2026-08-25 to correct that went stale within a day.
Sizes now live only in `specs/2026-08-25-file-decomposition-analysis.md`.
**Status**: Complete

### Key Functions

1. **Stdlib loading** (lines 9-93):
   - `find_stdlib_dir()`: Search development + install paths
   - `load_stdlib_file()`: Parse + desugar a stdlib module
   - `load_stdlib()`: Load prelude, option, result, list, math, string, I/O, HTTP, filesystem, CSV, WebSocket, sort modules

2. **Runtime compilation** (lines 95-141):
   - `ensure_runtime_so()`: Compile C runtime to shared lib if needed
   - Cached at `~/.cache/march/libmarch_runtime.so`

3. **File compilation**:
   - Parse → Desugar → Inject stdlib → Typecheck → Refine-check → Lower → Mono → Fusion → Defun → Known_call → Beta_adt → Join_points → Perceus → Escape → Opt → LLVM emit
   - Error filtering: Show only user file diagnostics
   - Diagnostic rendering with source snippets

4. **Command-line flags** (the execution-relevant subset; `bin/main.ml` declares
   roughly thirty in total, and `march --help` is the authoritative list):
   - *(no flag)*: run the file in the tree-walking interpreter (§18.1)
   - `--compile`: AOT-compile to a native binary via LLVM IR + clang
   - `--jit`: run the whole program in-process through the ORC JIT (§18.1)
   - `--check`: typecheck only, emit no code
   - `--dump-tir`: Print TIR after lowering
   - `--emit-llvm`: Print LLVM IR
   - `--emit-core-ast`: Print the typechecked core AST as JSON
   - `-o file`: Output file
   - `--opt <N>`: Optimization level passed to clang (0-3)
   - `--fast-math`: Enable unsafe math optimizations
   - `--debug`: Enable debugging
   - `--debug-tui`: TUI debugger (REPL-based)

   Two entries in an earlier revision of this list (`-c` and `-O0..3`) do not
   exist; the real spellings are `--emit-llvm` and `--opt <N>`.

### 18.1 Execution modes

Everything above describes one pipeline, but `bin/main.ml` dispatches a source
file to one of **three** engines, and they do not run the same passes. Choosing
the wrong mental model here is the most common way to misread this document.

| Mode | Invocation | Pipeline actually run |
|---|---|---|
| Interpreter | `march file.march` (default) | Parse → Desugar → Typecheck → Refine-check → **eval**. **No TIR at all**; §§5–17 do not apply. |
| In-process JIT | `march --jit file.march` | Parse → Desugar → Typecheck → Lower → TRMC → Mono → Policy-DCE audit → Defun → Perceus → Escape → LLVM IR → **ORC LLJIT**, run in this process. |
| AOT | `march --compile file.march` | The full pipeline diagrammed at the top of this document, ending in a clang link. |

**Interpreter** (`lib/eval/eval.ml`, `Eval.run_module`). The tree-walking
evaluator, and still the default. It consumes the desugared AST directly, so no
TIR pass runs at all. Variable lookup resolves against a `(string * value) list`
environment; its shared builtin/module suffix is additionally indexed by a hash
table, so only the local prefix is scanned (2026-08-25; previously a full linear
scan with polymorphic comparison, which dominated interpreted runtime).

**In-process JIT** (`lib/jit/repl_jit.ml`, `Repl_jit.run_program`). Reuses the
REPL's *fragment* pipeline rather than the AOT one; note what is **absent**
relative to `--compile`: Fusion, Known-call, Beta-ADT, Join-points and the
`Opt` fixed-point loop. `--jit` code is therefore less optimized than
`--compile` code even though both go through `Llvm_emit`. After emission it
calls the same three-symbol entry sequence the native build emits
(`march_remote_init` → `march_spawn_main` → `march_run_scheduler`), which is why
tasks, the scheduler and HTTP servers behave as they do in compiled binaries.

`--jit` is **experimental and opt-in**. It falls back to the interpreter, with a
notice on stderr, for programs that declare actors or that shadow a stdlib
module; a file with no `main` exits 0 silently, matching the interpreter. Known
gaps at the time of writing: `argv` is empty, `--debug` is not routed back to the
interpreter, and one program in the benchmark corpus still faults
(`specs/todos/2026-08-25-jit-whole-program-json-stream-sigbus.md`). See
`specs/progress/2026-08-25-interp-perf-phase-4-whole-program-orc.md` for the
criteria that would have to hold before `--jit` could become the default.

**REPL.** `lib/repl/repl.ml` drives the same fragment pipeline per input line
against a persistent JIT session. Since 2026-08-25 the default backend is the
in-process ORC LLJIT; `MARCH_JIT_BACKEND=clang` restores the previous
clang-subprocess-plus-`dlopen` backend, and any unrecognized value also selects
clang. Details in `specs/features/repl.md`.

**Stdlib typecheck cache.** The "File compilation" step above no longer
re-typechecks the 117 stdlib modules on every invocation: `get_stdlib_tc_env`
seeds the check from a cache under `~/.cache/march/`, keyed by the compiler
binary's own content hash plus a hash of the stdlib sources. A file that shadows
a stdlib module bypasses the cache entirely and takes the from-scratch combined
check, because the shadow-stripped seed environment would be incomplete.

---

## 19. Effects System (Capability-Based)

**File**: `lib/effects/effects.ml` (`Effects.check_capabilities`)
**Status**: Enforced

Capabilities **are** enforced. Enforcement lives in `Typecheck.check_module_needs`, embedded in `Typecheck.check_module`, which `bin/main.ml` runs on both the eval and compile paths via `Typecheck.check_module_full`. Enforcement includes: transitive `needs` checking (a module that imports another module declaring `needs X` must itself declare `X` or a parent capability), and a requirement that `extern` blocks declare their capability via `needs`. This matches `type-system.md` §9 (capability hierarchy and `needs` checking); the "stub / not enforced" claim an earlier revision made here was wrong.

> **Correction (2026-08-25 claim audit): `lib/effects/effects.ml` is not on the
> compile path.** The previous wording ("`lib/effects/effects.ml` is a thin
> wrapper whose `check_capabilities` … `bin/main.ml` runs this") implied that
> `bin/main.ml` calls `Effects.check_capabilities`. It does not. Searching for
> callers of that function finds exactly three: two assertions in
> `test/test_codegen.ml`, and a bare mention inside a `bin/main.ml` **comment**
> ("See also: March_effects.Effects.check_capabilities"). No production code path
> calls it.
>
> The *status* (Enforced) is nonetheless correct, because enforcement does not
> depend on this module: `bin/main.ml` reaches `check_module_needs` directly
> through `Typecheck.check_module_full`. So this is a wiring claim that was
> wrong, not a capability claim. Practically, `effects.ml` occupies the same
> category as `lib/codegen/codegen.ml` (§17): a named module that a reader
> reasonably assumes is the implementation, which is in fact a bypassed shim.
>
> Note also that `effects.ml`'s **own doc comment is wrong** in the same way:
> it claims "All paths (eval and compile) pass through this function via
> [bin/main.ml]". Fixing that comment is a code change and therefore out of
> scope for this docs-only audit; it is logged as
> `specs/todos/2026-08-25-effects-ml-docstring-claims-a-call-path-that-does-not-exist.md`.

---

## 20. Purity Analysis

**File**: `lib/tir/purity.ml`
**Status**: Complete

### Definition

Purity is decided by a **blacklist**, not a proof. `impure_builtins` enumerates
the builtins with observable effects (console/file IO, network/TLS, randomness,
time, actors/tasks/processes, mutable state, and, importantly, `int_div`,
`int_mod`, `/` and `%`, which *trap* on a zero divisor and so must not be
reordered or deleted). **Any builtin not on that list is assumed pure.** The
oracle is conservative in the sense that it returns `false` when uncertain about
*structure*, but it is not conservative about unknown builtin names.

A TIR expression is "pure" if it:
- makes no `ECallPtr` (indirect call: unknown target ⇒ always impure)
- contains no RC or ownership ops (`EIncRC`, `EDecRC`, `EAtomicIncRC`,
  `EAtomicDecRC`, `EFree`, `EReuse`)
- contains no `ESetField` (mutates an already-constructed cell; treating it as
  pure would let the optimizer duplicate, sink or drop the hole-fill that makes
  a TRMC loop produce its result)
- makes no `EApp` to a name on `impure_builtins`, or to a user function known
  to be transitively impure

**Allocation is pure.** `EAlloc`, `EStackAlloc` and `EAllocHole` all return
`true`.

> **Correction (2026-08-25 claim audit).** The previous "Definition" listed
> "Contains no heap allocations (EAlloc, EStackAlloc)" as a condition for
> purity. That is the **opposite** of what `lib/tir/purity.ml` does: the code
> contains `| Tir.EAlloc _ -> true (* allocation is pure, side-effect-free *)`.
> Believing the old text would lead a reader to conclude that essentially no
> allocating function is inlinable, which is not how the inliner behaves. The
> same list also framed purity as a whitelist ("except to pure functions") when
> it is a blacklist, and omitted the `ECallPtr`, `ESetField` and trapping-division
> cases entirely.

Monomorphization rewrites builtin calls to specialized names (`println` →
`println$String`), so `is_pure_ext` matches against
`Tir_names.strip_specialization_suffix` of the call-site name. An exact match
would silently reclassify every specialized impure builtin as pure.

### Usage

- **`is_pure`** (empty impure-function set): used by **Fusion** and **Inline**,
  which only reason about expressions built from known stdlib combinators.
- **`is_pure_ext`** with `impure_fns_of_module` (a fixed point over the module's
  call graph): used by **DCE**, which inspects raw call sites such as
  `EApp(System.put_env, …)` where the impurity is invisible at the call site.

> **Correction (2026-08-25 claim audit).** The previous "Usage" section said
> only "Used by inlining pass to decide which functions are safe to inline".
> DCE is the consumer with the sharpest correctness requirement here, and it is
> the reason the two-variant API exists at all: using plain `is_pure` from DCE
> would delete observable side effects.

---

## 21. Pretty Printing

**File**: `lib/tir/pp.ml`
**Status**: Complete

Renders TIR expressions and types as readable text for debugging (`--dump-tir`).

### Functions

- `string_of_expr`: Expression → string
- `string_of_ty`: Type → string
- `string_of_var`: Variable → string
- `string_of_atom`, `string_of_linearity`, `string_of_fn_def`,
  `string_of_type_def`

> **Correction (2026-08-25 claim audit).** These were previously listed as
> `pp_expr` / `pp_ty` / `pp_var`. No function by any of those three names exists
> in `lib/tir/pp.ml`; the module uses the `string_of_*` convention throughout.
> (The *file* is named `pp.ml`, which is presumably where the guess came from.)

---

## 22. Test Coverage

**Files**: `test/test_compiler.ml`, `test/test_eval.ml`, `test/test_codegen.ml`, `test/test_stdlib_suite.ml` (driven by `test/run_compiler.ml`, `run_eval.ml`, `run_codegen.ml`, `run_stdlib.ml`)
**Status**: Comprehensive

> **Note.** `test/test_march.ml` no longer exists; the monolithic alcotest suite was split into the per-area files above. Line ranges below are approximate / historical.

### Test Categories

**Lexer tests** (lines 3-74):
- Integers, identifiers, keywords, strings, atoms
- Operators, comments (line/block), pipe arrow

**Parser tests** (lines 79-141):
- Expressions: int, atom, pipe, lambda, application
- Modules: multi-head functions, single functions
- Negative tests: error handling

**Desugaring tests** (lines 160-213):
- Pipe desugaring: `x |> f` → `f(x)`
- Multi-head desugaring: Multiple clauses → single with match
- Trivial function detection (no spurious match insertion)

**Type checker tests** (lines 217-271):
- Literals, identity function
- Arithmetic, if/then/else
- Annotations, matches
- Error cases: undefined variables, type mismatches, guards

**Evaluation tests** (lines 281-498):
- Literals, arithmetic, recursion
- If expressions, match on ADTs
- Tuples, let bindings, closures
- List operations, string operations, floating point
- Modulo, multi-statement match arms

**Parser gap tests** (lines 427-470):
- Unary minus, negative literal patterns
- List literals
- Float operations

**Standard library tests** (lines 500+):
- Option operations: map, and_then, or_else, get_or_else
- Result operations: map, and_then, or_else, is_ok, is_err
- List operations: map, filter, fold_left, fold_right, reverse, any, all, find
- String operations: split, join, contains, starts_with, ends_with
- Math operations: sqrt, abs, max, min, sin, cos

---

## Implementation Status Summary

> **File sizes intentionally removed (2026-08-25).** This table used to include a
> `Lines` column. Every figure in it had fallen out of sync: `typecheck.ml` was listed at
> 2,006 lines against an actual 14,958, and the document contradicted itself
> (§4 said ~7,700 for the same file). Because this is the table a reader
> consults when asking "what is too big to work in?", a stale answer here is
> more damaging than no answer. Current, re-derivable measurements (size, largest
> definition, concentration and churn) live in
> `specs/2026-08-25-file-decomposition-analysis.md`, which is the single source
> of truth for file sizes and feeds
> `specs/plans/2026-08-19-compiler-file-decomposition.md`.

> **Status column audited 2026-08-25.** Two rows read as functional gaps but are
> not: `lib/codegen/codegen.ml` ("Stub") and `lib/effects/effects.ml` are both
> **bypassed shims with functionality that ships elsewhere**: the §17 failure mode.
> Their rows now say so inline, because a reader scanning this table for "what
> is missing" is exactly the reader who was misled last time. Conversely `TRMC`
> is a real "present but off" case and is now marked as such. Six passes that
> exist and run (`single_use_inline`, `cprop`, `drop`, `vectorize_mark`,
> `policy_dce`, `trmc`) were missing from this table entirely and have been
> added; the table is not, however, guaranteed exhaustive against `lib/tir/`.

| Pass | File | Status |
|------|------|--------|
| Lexer | `lib/lexer/lexer.mll` | ✓ Complete |
| Parser | `lib/parser/parser.mly` | ✓ Complete |
| AST | `lib/ast/ast.ml` | ✓ Complete |
| Desugaring | `lib/desugar/desugar.ml` | ✓ Complete |
| Type Checking | `lib/typecheck/typecheck.ml` | ✓ Complete |
| Lowering to TIR | `lib/tir/lower.ml` | ✓ Complete |
| TIR Types | `lib/tir/tir.ml` | ✓ Complete |
| Monomorphization | `lib/tir/mono.ml` | ✓ Complete |
| Defunctionalization | `lib/tir/defun.ml` | ✓ Complete |
| Perceus RC | `lib/tir/perceus.ml` | ✓ Complete (runs before Escape) |
| Escape Analysis | `lib/tir/escape.ml` | ✓ Complete (runs after Perceus) |
| Fusion | `lib/tir/fusion.ml` | ✓ Complete |
| Known-call | `lib/tir/known_call.ml` | ✓ Complete |
| Beta-ADT | `lib/tir/beta_adt.ml` | ✓ Complete |
| Join points | `lib/tir/join_points.ml` | ✓ Complete |
| Refinement check | `lib/refinecheck/refine_check.ml` | ✓ Complete (post-typecheck) |
| Division safety | `lib/refinecheck/division_safety.ml` | ✓ Complete (`cap no_panic`: proves divisors ≠ 0 via Z3) |
| No-alloc check | `lib/refinecheck/no_alloc.ml` | ✓ Complete (`cap no_alloc`: bans heap-allocating exprs) |
| Capability inference | `lib/refinecheck/cap_infer.ml` | ✓ Complete (emits `needs` hint at call sites missing cap decl) |
| Return refinement inference | `lib/refinecheck/return_infer.ml` | ✓ Complete (Z3 sign-candidate probing for return type hints) |
| Inlining | `lib/tir/inline.ml` | ✓ Complete |
| Constant Folding | `lib/tir/fold.ml` | ✓ Complete |
| Simplification | `lib/tir/simplify.ml` | ✓ Complete |
| DCE | `lib/tir/dce.ml` | ✓ Complete |
| Optimization Loop | `lib/tir/opt.ml` | ✓ Complete (9 passes, ≤5 iterations; see §15) |
| Single-use inline | `lib/tir/single_use_inline.ml` | ✓ Complete (Opt loop member) |
| Constant propagation | `lib/tir/cprop.ml` | ✓ Complete (Opt loop member) |
| Deep-drop synthesis | `lib/tir/drop.ml` | ✓ Complete (runs between Perceus and Escape) |
| Vectorize marking | `lib/tir/vectorize_mark.ml` | ✓ Complete (runs immediately after Lower) |
| Policy-DCE audit | `lib/tir/policy_dce.ml` | ✓ Complete (audit only: reports and exits, does not transform) |
| TRMC | `lib/tir/trmc.ml` | ⚠ **Off by default**: opt-in via `--trmc` / `MARCH_TRMC`; report gated on `MARCH_TRMC_REPORT` |
| LLVM Emission | `lib/tir/llvm_emit.ml` | ✓ Substantial (constructor collision & arity mismatch fixed) |
| Code Generation | `lib/codegen/codegen.ml` | ⚠ Stub, **but see §17: code generation ships, it just does not live here** |
| Effects System | `lib/effects/effects.ml` | ⚠ Shim, not on the compile path; capabilities **are** enforced, via `Typecheck.check_module_needs` (§19) |
| Purity Analysis | `lib/tir/purity.ml` | ✓ Complete |
| Pretty Printing | `lib/tir/pp.ml` | ✓ Complete |
| Main CLI | `bin/main.ml` | ✓ Complete |
| Tests | `test/test_compiler.ml`, `test_eval.ml`, `test_codegen.ml`, `test_stdlib_suite.ml` | ✓ Comprehensive |

---

## Known Limitations

> **Each entry below was checked again against the code on 2026-08-25.** A
> "limitation" that has been fixed with no visible sign is the most expensive kind of error
> in this document (it makes people build workarounds for problems that no
> longer exist), so each item now includes its verification verdict. (The list
> previously ran 1, 3, 4, 5, 6, 7: item 2 had been deleted without renumbering.
> Renumbered here.)

1. **Code generation**: *verified, and note the phrasing.* `lib/codegen/codegen.ml`
   is a thin shim; LLVM IR emission lives in `lib/tir/llvm_emit.ml` and the
   assembly/link step is a clang invocation driven from `bin/main.ml`. This is a
   **structural** observation, not a functional gap: native binaries are produced
   today. See §17, which corrects an earlier revision that read this as "code
   generation not yet implemented".

2. **Module system: no higher-kinded polymorphism**; *verified true.*
   `Ast.interface_def` includes a single `iface_param : name`, so an interface is
   parameterized by exactly one type, and it cannot abstract over a type
   constructor.

3. **Gradual typing / type-level naturals**: ⚠️ **this entry was stale and has
   been rewritten.** It previously read "Type-level naturals (`Nat`, `NatOp`)
   *mostly unused*; dynamic type-level computation not implemented". The first
   part is no longer true: a **constraint solver for type-level naturals (v1)**
   landed on 2026-07-31: `normalize_tnat` reduces concrete arithmetic plus
   identity/annihilation laws, `solve_nat_eq` solves linear equations such as
   `a + 2 = 5 ⇒ a = 3`, the parser gained `ty_nat_add`/`ty_nat_mul` precedence
   levels and accepts `INT` as a `TyNat`, and there is a `type_level_nat` test
   group in `test/test_stdlib_suite.ml`. `TNat` is referenced ~66 times in
   `lib/typecheck/typecheck.ml`. See
   `specs/progress/2026-07-31-constraint-solver-for-type-level-naturals-v1.md`.
   What remains truly limited: the solver is v1 and linear, and general
   *dynamic* type-level computation is still not implemented.

4. **Linearity checking**: *not fully verified as of 2026-08-25.* The claim that
   there is "no sophisticated must-use-linearly analysis during lowering" was not
   confirmed or refuted within this audit; deciding it requires reading the
   linearity paths in `typecheck.ml` and `lower.ml` in depth. Note that work in
   this area has landed since the claim was written; see
   `specs/progress/2026-07-31-linear-affine-propagation-through-record-fields.md`,
   `specs/progress/2026-08-12-branch-facts-and-linearity-symmetry.md` and
   `specs/progress/2026-07-31-check-linear-all-consumed-never-fires-for-let-with-match-arm.md`;
   and at least one linearity gap remains open in
   `specs/todos/2026-07-10-p2-compiler-linearity-found-during-core-march-widening-slice-7.md`.
   **Treat this entry as unverified rather than as current fact.**

5. **Polymorphic recursion**: *verified true.* `lib/tir/mono.ml` is a worklist
   monomorphizer that derives each specialization from concrete argument types at
   call sites (`build_subst` / `match_ty`), so a function with a recursive call that
   instantiates itself at a *different* type has no fixed point to reach.

6. **Associated types**: *verified true.* `Ast.interface_def` has
   `iface_assoc_types` and `Ast.impl_def` has `impl_assoc_types`, so the syntax
   is passed through the AST, but the only reference to `iface_assoc_types` in
   `lib/typecheck/typecheck.ml` is a construction site initializing it to `[]`.
   No code consumes it during impl resolution.

---

## Dependencies Between Passes

```
Lexer → Parser
Parser → Desugaring
Desugaring → Type Checking
Type Checking → (type_map)
               ↓
           Lowering to TIR
               ↓
         Vectorize_mark (names still == source names here)
               ↓
            TRMC (off by default; --trmc / MARCH_TRMC)
               ↓
         Monomorphization (eliminates TVar)
               ↓
            Fusion
               ↓
        Policy-DCE audit (reports + exits; does not transform)
               ↓
        Defunctionalization (lifts lambdas)
               ↓
       Known_call → Beta_adt → Join_points.run_pre → Simplify(pre-Perceus)
               ↓
       Perceus RC Analysis (inserts RC ops)
               ↓
            Drop (deep-drop synthesis)
               ↓
         Escape Analysis (stack-promotes non-escaping allocs)
               ↓
      Optimization Loop (fixed-point, NINE passes — see §15)
         ├─ Join points
         ├─ Known-call
         ├─ Inlining
         ├─ Single-use inline
         ├─ Constant propagation
         ├─ Constant Folding
         ├─ Simplification
         ├─ Struct fusion
         └─ DCE
               ↓
         LLVM IR Emission
               ↓
      Code Generation (clang link, driven from bin/main.ml)
```

> **Correction (2026-08-25 claim audit).** This diagram previously showed the
> optimization loop as four passes (Inlining / Folding / Simplification / DCE)
> and omitted Vectorize_mark, TRMC, the Policy-DCE audit, the pre-Perceus
> Simplify and, most consequentially, **Drop**, which sits *between* Perceus
> and Escape. See the pass-order note at the top of this document for why each
> one is where it is.

**Critical invariants**:
- Type checking must precede lowering (type_map required); refinement checking runs right after typecheck
- Monomorphization must precede defunctionalization (TVar → concrete types)
- Known_call, Beta_adt, and Join_points.run_pre run **before** Perceus so RC is inserted once over their simplified output. In particular Known_call must precede Perceus because the closure-apply ABI consumes the closure argument, so Perceus must not insert a post-decrement on apply functions.
- **Perceus must precede Escape analysis** (Escape removes dead RC ops on stack-promoted values)
- **`Drop` must run between Perceus and Escape**: it rewrites the bare `EDecRC`s Perceus just inserted into destructuring drops, and Escape's `with_incrc` exclusion inspects the RC ops that survive
- **`Beta_adt` must stay out of the `Opt` loop**: it runs once, pre-Perceus. Moving it (or any other post-Perceus case-of-known-constructor reduction) into the loop makes a currently-unreachable variable-capture bug reachable; see §15 and the guard comment in `lib/tir/single_use_inline.ml`
- **`Vectorize_mark` must run immediately after Lower**: it is the only point at which a TIR function's name is still exactly its source name
- Optimization loop assumes purity + recursion info stable
- DCE assumes defun + mono complete (no polymorphic/lambda code)

---

## Performance Characteristics

> **Unverified as of 2026-08-25.** These are asymptotic sketches brought over
> from the March 2026 draft. The claim audit of that date confirmed only the one
> item below that is checkable by reading code (the iteration bound); the
> complexity classes themselves were **not** derived from the implementations
> and **not** measured. Do not cite them as established. For real numbers, use
> the benchmark corpus and the mapping in `specs/benchmarks.md`, and measure
> compiled (`march --compile --opt 2 …`); interpreted runs of `fib`-shaped
> benchmarks can take hours.

- **Lexing**: O(n) scan, one-pass *(unverified)*
- **Parsing**: O(n) Menhir LR(1), linear shift/reduce *(unverified)*
- **Type checking**: O(n × m) where m = number of unification steps (typically m << n) *(unverified)*
- **Lowering**: O(n) recursive descent + CPS continuation threading *(unverified)*
- **Monomorphization**: O(m × k) where m = functions, k = specializations per function *(unverified)*
- **Optimization**: bounded at **5** iterations of the nine-pass sequence, with
  early termination when an iteration makes no change; *verified* against
  `Opt.run`'s `loop m 5`. Note the per-iteration cost is Σ over **nine** passes,
  not the four this document used to list (§15).

---

## Reference Files

### Core Compiler Modules

| Module | File | Purpose |
|--------|------|---------|
| `March_lexer` | `lib/lexer/lexer.mll` | Tokenization |
| `March_parser` | `lib/parser/parser.mly` | Syntax analysis |
| `March_ast` | `lib/ast/ast.ml` | Surface AST definitions |
| `March_desugar` | `lib/desugar/desugar.ml` | Desugaring transformations |
| `March_typecheck` | `lib/typecheck/typecheck.ml` | Type inference + checking |
| `March_tir` | `lib/tir/tir.ml` | Intermediate representation |
| `March_lower` | `lib/tir/lower.ml` | AST → TIR |
| `March_mono` | `lib/tir/mono.ml` | Monomorphization |
| `March_defun` | `lib/tir/defun.ml` | Defunctionalization |
| `March_escape` | `lib/tir/escape.ml` | Escape analysis |
| `March_perceus` | `lib/tir/perceus.ml` | Reference counting |
| `March_inline` | `lib/tir/inline.ml` | Function inlining |
| `March_fold` | `lib/tir/fold.ml` | Constant folding |
| `March_simplify` | `lib/tir/simplify.ml` | Simplification |
| `March_dce` | `lib/tir/dce.ml` | Dead code elimination |
| `March_opt` | `lib/tir/opt.ml` | Optimization orchestration |
| `March_llvm_emit` | `lib/tir/llvm_emit.ml` | LLVM code generation |
| `March_eval` | `lib/eval/eval.ml` | Tree-walking interpreter (default run mode, §18.1) |
| `March_jit` | `lib/jit/repl_jit.ml` | REPL + `--jit` fragment compilation, ORC LLJIT session (§18.1) |

---

**Last Updated**: August 25, 2026.

Two revisions landed that day. First: §18.1 added (three execution modes:
interpreter, `--jit`, `--compile`), `bin/main.ml` size and flag list corrected,
interpreter and JIT modules added to the module reference.

Second, a **substantive claim audit**, the first this document has had. Its
predecessor pass had checked only for mechanical rot (stale sizes and pointers);
the single substantive claim that had been spot-checked, §17's "full code
generation not yet implemented", turned out to be badly false, which is what
prompted auditing the rest. Roughly 95 claims were checked against the code:
**19 were wrong** and are corrected in place with a `Correction (2026-08-25
claim audit)` note explaining what was claimed and why it was false; about 9
could not be verified in reasonable time and are now explicitly marked
unverified rather than left reading as fact.

The worst of the 19 was §15's description of the optimization loop, which named
four passes when there are nine and illustrated them with a block of OCaml
presented as `Opt.run`'s body that does not exist in the source. Runners-up:
§9 described escape analysis as stack-promoting the values that *escape*
(exactly backwards), §20 listed heap allocation as making an expression impure
when `purity.ml` explicitly states the opposite, and §11 gave an inline threshold
of 15 against an actual 50.

Earlier body sections not touched by that audit still carry their March 2026
review dates, and their parenthetical line numbers remain unverified; see the
note at the top of this document.
