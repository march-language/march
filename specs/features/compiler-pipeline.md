# March Language Compiler Pipeline

**Document Date**: March 20, 2026
**Total Lines Analyzed**: ~14,262 (across 23 source files)

## Overview

The March compiler transforms source code through a series of passes, from surface syntax to LLVM IR emission. The pipeline emphasizes type safety (bidirectional Hindley-Milner type checking), memory safety (linear/affine types, reference counting), and performance (escape analysis, defunctionalization, optimization).

### High-Level Architecture

```
Source Code
    ↓
[Lexer] (lib/lexer/lexer.mll:1-183)
    ↓
[Parser] (lib/parser/parser.mly:1-688)
    ↓
[Desugaring] (lib/desugar/desugar.ml:1-263)
    ↓
[Type Checking] (lib/typecheck/typecheck.ml:1-2006)
    ↓
[AST → TIR Lowering] (lib/tir/lower.ml:1-1122)
    ↓
[Monomorphization] (lib/tir/mono.ml:1-314)
    ↓
[Defunctionalization] (lib/tir/defun.ml:1-336)
    ↓
[Escape Analysis] (lib/tir/escape.ml:1-279)
    ↓
[Perceus RC Analysis] (lib/tir/perceus.ml:1-498)
    ↓
[Optimization Loop] (lib/tir/opt.ml:1-19)
  ├─ [Inlining] (lib/tir/inline.ml:1-179)
  ├─ [Constant Folding] (lib/tir/fold.ml:1-91)
  ├─ [Simplification] (lib/tir/simplify.ml:1-107)
  └─ [Dead Code Elimination] (lib/tir/dce.ml:1-130)
    ↓
[LLVM IR Emission] (lib/tir/llvm_emit.ml:1-1659)
    ↓
[Code Generation] (lib/codegen/codegen.ml:1-10)
```

---

## 1. Lexical Analysis

**File**: `lib/lexer/lexer.mll` (183 lines, OCamllex)
**Status**: Complete

### Key Features

- **Token types**: Integers, floats, strings (with interpolation), atoms (`:ok`, `:error`), identifiers, keywords
- **String interpolation**: `"hello ${name}!"` — parsed into `INTERP_START`, `INTERP_MID`, `INTERP_END` tokens for nested expression evaluation
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

**File**: `lib/parser/parser.mly` (688 lines, Menhir)
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

**File**: `lib/desugar/desugar.ml` (263 lines)
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

### Data Structures

- `fresh_arg_name` (lines 48-51): Generates `__arg0`, `__arg1`, ... to avoid user shadowing
- `is_trivial_param` (lines 56-59): Detects simple parameters (no pattern matching)

### Module Entry Point

- `desugar_module` (line 262): Entire module transformation

---

## 4. Type Checking

**File**: `lib/typecheck/typecheck.ml` (2006 lines)
**Status**: Complete, heavily featured

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

**File**: `lib/tir/lower.ml` (1122 lines)
**Status**: Complete

### Target Intermediate Representation

`Tir.tir_module`: A-Normal Form (ANF) — all function arguments are atoms (vars/literals)

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

**File**: `lib/tir/tir.ml` (107 lines)
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
          | EReuse of atom * ty * atom list
          | ESeq of expr * expr
```

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

**File**: `lib/tir/mono.ml` (314 lines)
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

**File**: `lib/tir/defun.ml` (336 lines)
**Status**: Complete

### Purpose

Eliminate lambdas (higher-order functions) by:
1. Creating closure structs for captured environments
2. Lifting lambda bodies to top-level with free vars as leading params
3. Replacing lambda creation with struct allocation
4. Replacing indirect calls with dispatches through apply functions

### Phases

1. **Collect top-level names** (lines 59-62): User functions + builtins (63+ names)
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

- `builtin_names`: Set of 56 known operators and library functions
- `lambda_info`: `lam_fn`, `lam_fvs`, `lam_is_recursive`, `lam_uid`
- `lambda_counter`: Global UID generator

---

## 9. Escape Analysis Pass

**File**: `lib/tir/escape.ml` (279 lines)
**Status**: Complete

### Purpose

Stack-promote heap allocations whose lifetimes don't escape the current function.

### Algorithm

1. **Collect EAlloc candidates** (lines 65-87): Vars bound directly to `EAlloc` in outer scopes
2. **Escape detection** (lines 93-220):
   - A candidate "escapes" if it appears in:
     - Return position (tail atom)
     - Function call arguments
     - Heap allocations (constructor args)
     - Tuples, records, updates
     - Closure captures
3. **Stack allocation** (lines 222+): Replace escaped `EAlloc` with `EStackAlloc`
4. **RC cleanup** (lines 222+): Remove dead RC ops on stack-allocated vars

### Key Functions

- `collect_alloc_candidates` (line 65): Find EAlloc binding candidates
- `escaping_vars` (line 93): Subset of candidates that escape

---

## 10. Perceus Reference Counting Pass

**File**: `lib/tir/perceus.ml` (498 lines)
**Status**: Complete

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

4. **FBIP detection** (lines 212+):
   - **Function Body Inlining and Partial Application**: Reuses dead heap objects
   - When constructing same type as a dead var, reuse its allocation
   - Emits `EReuse` instead of `EAlloc`

5. **Optimization** (lines 330+):
   - Adjacent EIncRC/EDecRC pairs cancel
   - Dead RC ops removed

### Key Functions

- `live_before` (line 41): Liveness computation
- `analyze_rc` (line 212): Main RC analysis
- `insert_rc` (line 330): Insert RC instructions

---

## 11. Inlining Pass

**File**: `lib/tir/inline.ml` (179 lines)
**Status**: Complete

### Heuristics

- **Size threshold**: 15 TIR nodes (line 6)
- **Purity**: Function must be pure (no side effects)
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

**File**: `lib/tir/fold.ml` (91 lines)
**Status**: Complete

### Operations Folded

- Arithmetic: `+`, `-`, `*`, `/`, `%`, `+.`, `-.`, `*.`, `/.` (integer and float)
- Comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Logical: `&&`, `||`, `!` (not)
- String: `++` (concatenation)
- Type checks: `is_int`, `is_float`, `is_string`, `is_bool`

### Algorithm

- Walk TIR, recognize `EApp(builtin, [atom1, atom2, ...])` with literal atoms
- Evaluate at compile time
- Replace with literal result

---

## 13. Simplification Pass

**File**: `lib/tir/simplify.ml` (107 lines)
**Status**: Complete

### Simplifications

- **Trivial applications**: `f(atom)` where f is an identity or constant builtin
- **ECase simplification**: Single-branch cases → direct body
- **Dead tuple/record fields**: Unused fields
- **Redundant operations**: e.g., `not(true)` → `false`
- **ELet optimization**: Unused bindings

### Algorithm

- Pattern match on common trivial forms
- Rewrite → simpler equivalent

---

## 14. Dead Code Elimination Pass

**File**: `lib/tir/dce.ml` (130 lines)
**Status**: Complete

### Two Phases

1. **Dead let removal**:
   - If var not used in body → drop `ELet` (if pure) or replace with `ESeq`

2. **Unreachable function removal**:
   - Build reachability graph from `main` entry point
   - If no `main`, seed with all functions
   - Remove unreachable functions from module

### Key Functions

- `free_vars` (line 11): Free variables in expression
- `called_fns` (line 55): Functions called from expression
- `reachable_fns` (line 71): Transitive reachability from entry points

---

## 15. Optimization Coordinator

**File**: `lib/tir/opt.ml` (19 lines)
**Status**: Complete

### Fixed-Point Loop

Runs **Inline → Fold → Simplify → DCE** in sequence, repeating up to 5 times until no pass makes changes.

```ocaml
let run (m : Tir.tir_module) : Tir.tir_module =
  let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
  let loop p n =
    if n = 0 then p
    else let p' = (apply passes p) in
         if not !changed then p'
         else loop p' (n - 1)
  in
  loop m 5
```

---

## 16. LLVM IR Emission

**File**: `lib/tir/llvm_emit.ml` (1659 lines)
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

> **Update (March 20, 2026, commit 2c710f7 — Track B):**
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

## 17. Code Generation Stub

**File**: `lib/codegen/codegen.ml` (10 lines)
**Status**: Placeholder

```ocaml
let compile _module_ = ()  (* TODO: Implement *)
```

Currently a stub. Full code generation (linking, assembly) not yet implemented.

---

## 18. Main CLI Entry Point

**File**: `bin/main.ml` (334 lines)
**Status**: Complete

### Key Functions

1. **Stdlib loading** (lines 9-93):
   - `find_stdlib_dir()`: Search development + install paths
   - `load_stdlib_file()`: Parse + desugar a stdlib module
   - `load_stdlib()`: Load prelude, option, result, list, math, string, I/O, HTTP, filesystem, CSV, WebSocket, sort modules

2. **Runtime compilation** (lines 95-141):
   - `ensure_runtime_so()`: Compile C runtime to shared lib if needed
   - Cached at `~/.cache/march/libmarch_runtime.so`

3. **File compilation** (lines 157-334):
   - Parse → Desugar → Inject stdlib → Typecheck → Lower → Mono → Defun → Escape → Perceus → Opt → LLVM emit
   - Error filtering: Show only user file diagnostics
   - Diagnostic rendering with source snippets

4. **Command-line flags**:
   - `--dump-tir`: Print TIR after lowering
   - `--emit-llvm`: Print LLVM IR
   - `-c`: Emit LLVM IR without executing
   - `-o file`: Output file
   - `-O0..3`: Optimization levels
   - `--fast-math`: Enable unsafe math optimizations
   - `--debug`: Enable debugging
   - `--debug-tui`: TUI debugger (REPL-based)

---

## 19. Effects System (Capability-Based)

**File**: `lib/effects/effects.ml` (9 lines)
**Status**: Stub

Currently a placeholder. Capability-based effects system (for I/O, Network, etc.) is declared in AST (`needs` directive) but not actively enforced in type checker.

---

## 20. Purity Analysis

**File**: `lib/tir/purity.ml` (25 lines)
**Status**: Complete

### Definition

A TIR expression is "pure" if it:
- Contains no EApp calls (except to pure functions)
- Contains no heap allocations (EAlloc, EStackAlloc)
- Contains no free operations
- Contains no RC operations

### Usage

Used by inlining pass to decide which functions are safe to inline.

---

## 21. Pretty Printing

**File**: `lib/tir/pp.ml` (98 lines)
**Status**: Complete

Renders TIR expressions and types as readable text for debugging (`--dump-tir`).

### Functions

- `pp_expr`: Expression → string
- `pp_ty`: Type → string
- `pp_var`: Variable → string

---

## 22. Test Coverage

**File**: `test/test_march.ml` (5499 lines)
**Status**: Comprehensive

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

| Pass | File | Lines | Status |
|------|------|-------|--------|
| Lexer | `lib/lexer/lexer.mll` | 183 | ✓ Complete |
| Parser | `lib/parser/parser.mly` | 688 | ✓ Complete |
| AST | `lib/ast/ast.ml` | 306 | ✓ Complete |
| Desugaring | `lib/desugar/desugar.ml` | 263 | ✓ Complete |
| Type Checking | `lib/typecheck/typecheck.ml` | 2006 | ✓ Complete |
| Lowering to TIR | `lib/tir/lower.ml` | 1122 | ✓ Complete |
| TIR Types | `lib/tir/tir.ml` | 107 | ✓ Complete |
| Monomorphization | `lib/tir/mono.ml` | 314 | ✓ Complete |
| Defunctionalization | `lib/tir/defun.ml` | 336 | ✓ Complete |
| Escape Analysis | `lib/tir/escape.ml` | 279 | ✓ Complete |
| Perceus RC | `lib/tir/perceus.ml` | 498 | ✓ Complete |
| Inlining | `lib/tir/inline.ml` | 179 | ✓ Complete |
| Constant Folding | `lib/tir/fold.ml` | 91 | ✓ Complete |
| Simplification | `lib/tir/simplify.ml` | 107 | ✓ Complete |
| DCE | `lib/tir/dce.ml` | 130 | ✓ Complete |
| Optimization Loop | `lib/tir/opt.ml` | 19 | ✓ Complete |
| LLVM Emission | `lib/tir/llvm_emit.ml` | 1659 | ✓ Substantial (constructor collision & arity mismatch fixed) |
| Code Generation | `lib/codegen/codegen.ml` | 10 | ⚠ Stub |
| Effects System | `lib/effects/effects.ml` | 9 | ⚠ Stub |
| Purity Analysis | `lib/tir/purity.ml` | 25 | ✓ Complete |
| Pretty Printing | `lib/tir/pp.ml` | 98 | ✓ Complete |
| Main CLI | `bin/main.ml` | 334 | ✓ Complete |
| Tests | `test/test_march.ml` | 5499 | ✓ Comprehensive |

---

## Known Limitations

1. **Effects system**: Capability-based effects (I/O, Network) are declared but not enforced at compile time
2. **Code generation**: Currently emits LLVM IR; linking/assembly generation (final executable) not implemented
3. **Module system**: No higher-kinded polymorphism; interfaces use simple parameter `a`
4. **Gradual typing**: Type-level naturals (`Nat`, `NatOp`) mostly unused; dynamic type-level computation not implemented
5. **Linearity checking**: Enforced at type check time but no sophisticated "must use linearly" analysis during lowering
6. **Polymorphic recursion**: Not fully supported; monomorphization works only on call-site types
7. **Associated types**: Declared in interfaces but not fully integrated with impl resolution

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
         Monomorphization (eliminates TVar)
               ↓
        Defunctionalization (lifts lambdas)
               ↓
         Escape Analysis (stack-promotes)
               ↓
       Perceus RC Analysis (inserts RC ops)
               ↓
      Optimization Loop (fixed-point)
         ├─ Inlining
         ├─ Constant Folding
         ├─ Simplification
         └─ DCE
               ↓
         LLVM IR Emission
               ↓
      Code Generation (stub)
```

**Critical invariants**:
- Type checking must precede lowering (type_map required)
- Monomorphization must precede defunctionalization (TVar → concrete types)
- Defunctionalization must precede escape analysis (lambdas → top-level)
- Escape analysis must precede perceus (identifies stack-allocatable values)
- Optimization loop assumes purity + recursion info stable
- DCE assumes defun + mono complete (no polymorphic/lambda code)

---

## Performance Characteristics

- **Lexing**: O(n) scan, one-pass
- **Parsing**: O(n) Menhir LR(1), linear shift/reduce
- **Type checking**: O(n × m) where m = number of unification steps (typically m << n)
- **Lowering**: O(n) recursive descent + CPS continuation threading
- **Monomorphization**: O(m × k) where m = functions, k = specializations per function
- **Optimization**: O(5 × Σ(pass_i)) with early termination when no change

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

---

**Last Updated**: March 20, 2026
