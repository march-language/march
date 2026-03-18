# March TIR — Typed Intermediate Representation

## Purpose

The TIR sits between the type checker and LLVM IR emission. It is the substrate for:

- **Monomorphization** — specialize all polymorphic functions per concrete type
- **Defunctionalization** — replace closures with tagged struct + dispatch
- **Perceus RC analysis** — insert/elide reference-count operations, detect FBIP reuse sites
- **Linearity lowering** — turn linear/affine bindings into explicit `free` insertion
- **Escape analysis** — promote non-escaping values to stack allocations

The GC design (Perceus RC + per-actor arenas + FBIP) requires a typed IR with explicit ownership. These passes cannot be done on the desugared AST (no explicit ownership) or on LLVM IR (ownership is gone). The TIR is the right level.

## Key Properties

1. **A-normal form (ANF)**: all function call arguments are *atoms* — literals or variable references. No nested calls. Eliminates ambiguity about evaluation order and makes last-use analysis unambiguous.

2. **Explicit types everywhere**: every let-binding, function parameter, and return position carries a fully monomorphic `ty`. No type variables after monomorphization.

3. **Explicit linearity**: every binding is annotated `Lin | Aff | Unr`. The Perceus pass uses `Lin` to skip RC entirely; the lowering pass inserts `free` at `Lin`/`Aff` last-use sites.

4. **No closures**: after defunctionalization, all higher-order values are represented as a tagged struct (closure environment) plus a known function pointer. The TIR introduces a `TFn` variant for closure struct types.

5. **Explicit sequencing**: all side effects (allocation, RC ops, I/O) are made explicit via `ELet` bindings. There are no implicit effects.

## Types

```ocaml
type ty =
  | TInt | TFloat | TBool | TString | TUnit
  | TTuple  of ty list
  | TRecord of (string * ty) list          (* sorted by field name *)
  | TCon    of string * ty list            (* monomorphic named type *)
  | TFn     of ty list * ty               (* closure struct type after defun *)
  | TPtr    of ty                          (* raw heap pointer (FFI only) *)

type linearity = Lin | Aff | Unr
```

After monomorphization, `TCon("List", [TInt])` is a concrete type — no type variables remain anywhere.

## Variables

```ocaml
type var = {
  v_name : string;
  v_ty   : ty;
  v_lin  : linearity;
}
```

Every variable has a type and a linearity annotation. The Perceus pass will add a `v_last_use` annotation during analysis.

## Atoms

Atoms are values that require no computation — they are safe to duplicate without side effects.

```ocaml
type atom =
  | AVar  of var
  | ALit  of March_ast.Ast.literal
```

After defunctionalization, constructor applications like `Cons(x, xs)` also become atoms (since the constructor is a known function, not a closure).

## Expressions (ANF)

```ocaml
type expr =
  | EAtom    of atom                              (* variable or literal *)
  | EApp     of var * atom list                   (* known function call: all atoms *)
  | ECallPtr of atom * atom list                  (* indirect call through closure dispatch *)
  | ELet     of var * expr * expr                 (* let x : T = e1 in e2 *)
  | ELetRec  of fn_def list * expr                (* mutually recursive functions *)
  | ECase    of atom * branch list * expr option  (* case + default arm *)
  | ETuple   of atom list
  | ERecord  of (string * atom) list
  | EField   of atom * string                     (* record projection *)
  | EUpdate  of atom * (string * atom) list       (* record functional update *)
  | EAlloc   of ty * atom list                    (* heap-allocate a constructor *)
  | EFree    of atom                              (* explicit deallocation (linear) *)
  | EIncRC   of atom                              (* RC increment *)
  | EDecRC   of atom                              (* RC decrement (may free) *)
  | EReuse   of atom * ty * atom list             (* FBIP: reuse dead cell's memory *)
  | ESeq     of expr * expr                       (* sequence (first result discarded) *)
```

`EIncRC`/`EDecRC`/`EReuse`/`EFree` do not appear in the TIR output of the lowering pass — they are inserted by the Perceus pass. The lowering pass emits `EAlloc` only.

`ECase` scrutinizes an atom against constructor patterns. The optional `expr` is the default arm. All patterns at this level are constructor tags (flat), not nested — nested patterns are desugared into nested `ECase` during TIR lowering.

## Function definitions

```ocaml
type fn_def = {
  fn_name   : string;
  fn_params : var list;
  fn_ret_ty : ty;
  fn_body   : expr;
}
```

After monomorphization, each polymorphic source function becomes one or more monomorphic `fn_def`s, distinguished by a mangled name like `map_Int_String`.

## Modules

```ocaml
type tir_module = {
  tm_name  : string;
  tm_fns   : fn_def list;
  tm_types : type_def list;
}

type type_def =
  | TDVariant of string * (string * ty list) list   (* name, [(ctor, args)] *)
  | TDRecord  of string * (string * ty) list        (* name, [(field, ty)] *)
  | TDClosure of string * ty list                   (* defun closure struct *)
```

## Pass Order

### Pass 1: Lower AST → TIR (pre-mono)

Lower the desugared `Ast.module_` to a TIR module, preserving polymorphism as explicit type-variable abstraction. This is a mostly structural translation with these key transformations:

- Convert expressions to ANF: name every intermediate result with a fresh `ELet`
- Flatten nested patterns into nested `ECase` chains
- Convert `EBlock` to right-nested `ELet` sequence
- Convert `ELet` in blocks to `ELet` in TIR
- Each `fn_clause` (already single after desugaring) becomes a `fn_def`

At this stage, type variables from HM may still exist — they will be eliminated by monomorphization.

### Pass 2: Monomorphization

Starting from `main` (or all public functions), collect all call sites. For each polymorphic call `f[T1, T2]`, create a specialized `fn_def` with concrete types substituted. Memoize by `(fn_name, [ty list])` to avoid exponential blowup.

Implementation: a worklist of `(fn_name, type_subst)` pairs. Process each, specializing the body, enqueue new polymorphic calls found. After fixpoint, only monomorphic `fn_def`s remain.

Named types: `TCon("List", [TInt])` remains as-is. Type definitions are specialized too: `TDVariant("List(Int)", [("Cons", [TInt; TCon("List", [TInt])]); ("Nil", [])])`.

### Pass 3: Defunctionalization

Replace higher-order values (closures) with concrete representations:

1. Collect all distinct closure shapes (free variables + function pointer) in the program.
2. For each, create a `TDClosure` struct type.
3. Replace `ELam` with `EAlloc` of the closure struct.
4. Replace `apply(f, args)` with `ECallPtr(f, args)` — a dispatch on the closure tag.
5. Add a dispatch function per closure type.

After defunctionalization, `TFn` types appear in the IR for closure struct pointers, but no `ELam` nodes remain.

### Pass 4: Perceus RC Analysis

For each function, compute last-use information:

1. **Backwards dataflow**: for each variable `v`, find the last use on every control-flow path.
2. At each last-use point:
   - If `v.v_lin = Lin` or `v.v_lin = Aff`: insert `EFree(v)` (no RC needed, type system guarantees uniqueness)
   - If `v.v_lin = Unr`: insert `EDecRC(v)`
3. At each non-last use: insert `EIncRC(v)`.
4. **RC elision**: if a use is both a decrement (last use of the caller's ref) and an increment (first use by callee), the pair cancels and both are removed.
5. **FBIP detection**: if a `EDecRC` at last-use point coincides with an `EAlloc` of the same constructor shape, replace both with `EReuse(dead_cell, ctor, args)`. The runtime reuses the memory in-place.

This pass operates on the TIR in a purely local (per-function) analysis since the actor isolation guarantee means no cross-function aliasing of mutable state.

### Pass 5: Escape Analysis + Stack Promotion

For each `EAlloc`, determine if the allocated value escapes its allocating function (is returned, stored in a field, or passed to an unknown function). If it does not escape, replace `EAlloc` with a stack reference (`ELet` with a stack-allocated binding).

With whole-program monomorphization, most intermediate values (pipe chain results, temporary tuples) are non-escaping and get stack-promoted.

### Pass 6: Lower TIR → LLVM IR

Mechanical translation:
- `ty` → LLVM type (structs for records and tuples, tagged unions for variants)
- `fn_def` → LLVM function
- `ELet` → LLVM `alloca` or named `%value`
- `ECase` → LLVM `switch` on tag field
- `EAlloc` → call to `actor_arena_alloc(size)` or `malloc(size)` for large objects
- `EFree` → call to `free()` or arena return (deferred)
- `EIncRC`/`EDecRC` → atomic or non-atomic RC increment/decrement
- `EReuse` → reuse pointer as the new allocation (no alloc call)

GC roots: for the shadow-stack GC integration (if Boehm or LLVM statepoints are used), each `EAlloc` that escapes is a potential root. The Perceus RC model means most values are freed deterministically, but the deferred cycle collector needs to walk live roots on idle cycles.

## File Layout

```
lib/tir/
├── dune
├── tir.ml          # Type definitions (ty, var, atom, expr, fn_def, tir_module)
├── lower.ml        # AST → TIR lowering (ANF conversion, pattern flattening)
├── mono.ml         # Monomorphization pass
├── defun.ml        # Defunctionalization pass
├── perceus.ml      # Perceus RC analysis + FBIP detection
├── escape.ml       # Escape analysis + stack promotion
└── llvm_emit.ml    # TIR → LLVM IR textual emission
```

## Open Design Questions

1. **Perceus for cyclic types**: march's immutability makes cycles structurally impossible for most values. For the deferred cycle collector, what algorithm? Bacon-Rajan trial deletion is the front-runner.

2. **Arena allocation API**: `actor_arena_alloc(size)` needs to be per-actor. The TIR needs to thread an implicit "current actor" context through all allocation sites. Options: implicit thread-local, explicit parameter, or a capability parameter.

3. **Unboxed integers in constructors**: `Cons(42, xs)` — should the `42` be stored as an unboxed `i64` field in the Cons struct, or boxed? With monomorphization, the answer is always unboxed (we know it's `Int`). The TIR `TInt` type signals this to LLVM emission.

4. **Tail call optimization**: ANF form makes tail calls structurally obvious (`EApp` in tail position of `ELet`). LLVM's `musttail` attribute can enforce this. Should the TIR carry an explicit tail-call annotation, or rely on LLVM detection?

5. **String representation**: March strings are UTF-8. The TIR `TString` type will lower to a struct `{ ptr: i8*, len: i64, rc: i64 }`. String literals become global constants. String concatenation (`++`) is a call to `march_string_concat`, which allocates via `EAlloc`.
