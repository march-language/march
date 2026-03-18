# March Defunctionalization — Design Spec

## Overview

Defunctionalization (Pass 3) eliminates all first-class function values from the TIR.
Every lambda becomes a concrete closure struct; every indirect call becomes `ECallPtr`.

After this pass:
- No `ELetRec` nodes representing lambdas remain in function bodies
- All `EApp` calls target statically-known top-level functions
- `ECallPtr (clo, args)` expresses indirect dispatch; the codegen resolves it
- `TDClosure` type definitions enumerate every closure shape in the program
- Lifted lambda bodies appear as new top-level `fn_def`s in `tm_fns`

## Position in the Pipeline

```
Lower  →  Mono  →  Defun  →  Perceus RC  →  Escape  →  LLVM emit
```

Input: a monomorphized `tir_module` (no `TVar` anywhere in reachable fns).
Output: a `tir_module` with no `ELetRec`-lambda nodes and no closure-typed `EApp`s.

## Key Invariant

After monomorphization every function type `TFn([T1,...,Tn], Tret)` is fully concrete.
The defun pass exploits this: each closure can be given a concrete struct layout, and
each call site knows the exact signature needed for dispatch.

---

## TIR Constructs Used

### Pre-defun (produced by lowering)

Lambdas lower to a local `ELetRec` wrapping a single `fn_def`, immediately returned
as a variable (the reference to the function):

```ocaml
ELetRec ([{
  fn_name   = "$lam1";
  fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
  fn_ret_ty = TInt;
  fn_body   = <body referencing captured vars>;
}], EAtom (AVar { v_name = "$lam1"; v_ty = TFn([TInt], TInt); v_lin = Unr }))
```

Calls to a function-typed variable appear as plain `EApp`:

```ocaml
EApp ({ v_name = "f"; v_ty = TFn([TInt], TBool); v_lin = Unr }, [AVar x])
```

### Post-defun

Lambda creation becomes heap allocation of a closure struct:

```ocaml
EAlloc (TCon ("Clo_$lam1", []), [AVar captured_y])
```

Indirect calls become `ECallPtr`:

```ocaml
ECallPtr (AVar { v_name = "f"; v_ty = TFn([TInt], TBool); v_lin = Unr }, [AVar x])
```

New in `tm_types`:

```ocaml
TDClosure ("Clo_$lam1", [TInt])   (* one captured TInt *)
```

New in `tm_fns`:

```ocaml
(* lifted body: free vars become extra leading params *)
{ fn_name = "$lam1$apply";
  fn_params = [{ v_name = "captured_y"; v_ty = TInt; v_lin = Unr };
               { v_name = "x";          v_ty = TInt; v_lin = Unr }];
  fn_ret_ty = TInt;
  fn_body   = <original body, now referencing captured_y as a normal param> }
```

---

## Algorithm

### Phase 0 — Collect top-level names

Build a `StringSet` of every `fn_def.fn_name` in `tm_fns`.
A variable reference is *statically known* iff its `v_name` is in this set.
All other function-typed references are closures.

### Phase 1 — Lambda collection

Walk every top-level `fn_body`, collecting:

1. **Lambda sites** — `ELetRec ([fn], EAtom (AVar ref))` where `ref.v_name = fn.fn_name`.
   Record `(fn_def, parent_fn_name)` for each.

2. **Free variables** — for each lambda `fn`, compute
   `free_vars(fn.fn_body, fn.fn_params, top_level_names)`:
   variables referenced in the body that are neither lambda params nor top-level names.
   Sort by name for determinism.

3. **Call sites** — `EApp (f_var, args)` where `f_var.v_ty = TFn(...)` and
   `f_var.v_name` is NOT in `top_level_names`.

### Phase 2 — Closure struct generation

For each collected lambda `lam` with free variables `[(n₁, T₁); …; (nₖ, Tₖ)]`:

1. Closure struct name: `"$Clo_" ^ lam.fn_name` (e.g. `"$Clo_$lam1"`).
   The `$` prefix is a synthetic-identifier sigil — it cannot appear in user identifiers,
   preventing collisions with user-defined type names.
2. Add `TDClosure ("$Clo_$lam1", [T₁; …; Tₖ])` to `tm_types`.
3. Generate lifted function `lam.fn_name ^ "$apply"` (e.g. `"$lam1$apply"`):
   - Params: free-var params (nᵢ : Tᵢ) prepended to the original lambda params.
   - Body: original `lam.fn_body` unchanged (already references the names correctly).
   - Add to `tm_fns`.

Field access convention: the codegen uses index-based access into the `TDClosure`
field list (offset 0 = first field). Lifted bodies receive free vars as ordinary
function parameters — no field extraction is needed in the TIR.

### Phase 3 — Rewrite expressions

Walk every top-level `fn_body`, performing two rewrites:

**Rewrite A — lambda creation:**

```
ELetRec ([fn], EAtom (AVar ref))
  where fn.fn_name is a collected lambda
```
→
```
EAlloc (TCon ("$Clo_" ^ fn.fn_name, []),
        [AVar {v_name = nᵢ; v_ty = Tᵢ; v_lin = Unr} | (nᵢ, Tᵢ) ← free_vars(fn)])
```

The result variable (bound by the surrounding `ELet`) keeps its `TFn(...)` type —
`TFn` is now the closure-pointer type, pointing to a `TDClosure` struct.

**Rewrite B — indirect call:**

```
EApp (f_var, args)
  where f_var.v_ty = TFn(...) and f_var.v_name ∉ top_level_names
```
→
```
ECallPtr (AVar f_var, args)
```

Recurse into all subexpressions (`ELet`, `ECase`, `ESeq`, `ELetRec` bodies).

### Phase 4 — Clean up lifted ELetRec nodes

After rewriting, strip `ELetRec` nodes whose `fn_def`s have been lifted to top-level:
any `ELetRec ([fn], body)` where `fn.fn_name` ∈ lifted-set gets replaced by `body`.

---

## Free Variable Analysis

```
free_vars : expr → VarSet → StringSet → (string * ty) list
```

(Arguments: body expression, bound-so-far vars, top-level names)

```
free_vars(EAtom (AVar v), bound, tl)
  | v.v_name ∈ bound ∨ v.v_name ∈ tl  → {}
  | otherwise                           → {(v.v_name, v.v_ty)}

free_vars(EAtom (ALit _), _, _) → {}

free_vars(EApp (f_var, atoms), bound, tl)
  → free_vars_var(f_var, bound, tl) ∪ ⋃ free_vars_atom(aᵢ, bound, tl)

free_vars(ECallPtr (a, atoms), bound, tl)
  → free_vars_atom(a, bound, tl) ∪ ⋃ free_vars_atom(aᵢ, bound, tl)

free_vars(ELet (v, e1, e2), bound, tl)
  → free_vars(e1, bound, tl) ∪ free_vars(e2, bound ∪ {v.v_name}, tl)

free_vars(ELetRec (fns, body), bound, tl)
  let fn_names = {fn.fn_name | fn ∈ fns}
  let inner    = bound ∪ fn_names
  → ⋃ free_vars(fn.fn_body, inner ∪ {p.v_name | p ∈ fn.fn_params}, tl) (for fn ∈ fns)
     ∪ free_vars(body, inner, tl)

free_vars(ECase (a, brs, def), bound, tl)
  → free_vars_atom(a, bound, tl)
     ∪ ⋃ free_vars(br.br_body, bound ∪ {v.v_name | v ∈ br.br_vars}, tl)
     ∪ free_vars(def?, bound, tl)

free_vars(ESeq (e1, e2), bound, tl)
  → free_vars(e1, bound, tl) ∪ free_vars(e2, bound, tl)

(ETuple, ERecord, EField, EUpdate, EAlloc, etc. — recurse into atoms)
```

The lambda's free-variable list is:

```
free_vars(fn.fn_body,
          StringSet.of_list (List.map (fun v -> v.v_name) fn.fn_params),
          top_level_names)
  |> List.sort_uniq (fun (a,_) (b,_) -> String.compare a b)
```

---

## ECallPtr Semantics

`ECallPtr (clo_atom, args)` means:

> The value in `clo_atom` is a closure pointer. Its type (`TFn([T1,...], Tret)`)
> identifies the function signature. At runtime, dispatch to the correct lifted
> function by examining the closure's tag field (the first word of every
> `TDClosure` struct is a tag discriminant).

The **codegen** synthesizes the dispatch:

1. Enumerate all `TDClosure` structs whose field layout matches the `TFn` signature.
2. Emit a `switch` on the tag field.
3. In each arm: unpack the free-variable fields, call the corresponding `$lam$apply`
   function with those fields prepended to `args`.

This keeps the TIR clean — `ECallPtr` is a single transparent node — while giving
the codegen enough information to materialize dispatch.

---

## Worked Examples

### Example 1 — Zero-capture closure

March source:
```
fn main() : Int do
  let add1 = fn x -> x + 1
  add1(41)
end
```

Pre-defun TIR (`main` body):
```
let add1 : TFn([Int], Int) =
  letrec [$lam1(x : Int) : Int = x + 1] in $lam1
in
EApp ({v_name="add1"; v_ty=TFn([Int],Int)}, [ALit 41])
```

Post-defun:
```
-- tm_types gains:
TDClosure ("$Clo_$lam1", [])    (* no free vars *)

-- tm_fns gains:
fn $lam1$apply(x : Int) : Int =
  x + 1

-- main body becomes:
let add1 : TFn([Int], Int) =
  alloc $Clo_$lam1()
in
ECallPtr (AVar add1, [ALit 41])
```

### Example 2 — Closure capturing a variable

March source:
```
fn make_adder(n : Int) : (Int -> Int) do
  fn x -> x + n
end
```

Pre-defun TIR (`make_adder` body):
```
letrec [$lam2(x : Int) : Int = x + n] in $lam2
   (* n is free here — defined in make_adder's params *)
```

Free vars of `$lam2`: `[(n, TInt)]` (sorted; `x` is bound, `make_adder` not relevant).

Post-defun:
```
-- tm_types gains:
TDClosure ("$Clo_$lam2", [TInt])   (* captures n : TInt *)

-- tm_fns gains:
fn $lam2$apply(n : Int, x : Int) : Int =
  x + n

-- make_adder body becomes:
alloc $Clo_$lam2(AVar {v_name="n"; v_ty=TInt})
```

### Example 3 — Higher-order function receives a closure

March source:
```
fn apply(f : Int -> Int, x : Int) : Int do f(x) end
fn main() : Int do
  let add2 = fn x -> x + 2
  apply(add2, 40)
end
```

Pre-defun `apply` body:
```
EApp ({v_name="f"; v_ty=TFn([Int],Int)}, [AVar x])
```

Post-defun `apply` body:
```
ECallPtr (AVar {v_name="f"; v_ty=TFn([Int],Int)}, [AVar x])
```

`apply` is a top-level known function — its `EApp (apply_var, ...)` call sites stay
as `EApp`. The `f` parameter inside `apply` is not in `top_level_names`, so its
call site becomes `ECallPtr`.

---

## Edge Cases

### Nested closures

A closure capturing another closure: the inner closure's free vars include the outer
closure variable. The outer closure variable has type `TFn(...)`. This is fine —
`TFn` types are valid `TDClosure` field types. The free-variable analysis handles
nesting naturally because it recurses into `ELetRec` bodies.

### Self-referential lambdas (recursive closures)

A `ELetRec ([fn], body)` where `fn.fn_body` references `fn.fn_name` (i.e. a
recursive lambda). The `fn.fn_name` is in the `ELetRec`'s own `fn_names` set, so
the recursive reference is NOT counted as a free variable. The lifted function
becomes a plain recursive `fn_def`.

### Lambda passed directly without let-binding

If a lambda appears inline as a function argument (CPS lowering produces an
intermediate ELet for it), the pattern is still `ELetRec` followed by the atom.
The surrounding `ELet` binding captures the result. This is handled identically.

### Top-level functions used as values

If a top-level function is passed as a first-class value (e.g. `map(xs, double)`
where `double` is a top-level `fn`), the variable reference has type `TFn(...)` but
`v_name` IS in `top_level_names`. This is **not** a closure — no struct is created.
At the call site inside `map`, `f` is not in `top_level_names`, so `EApp(f, args)`
→ `ECallPtr`.

For codegen: when constructing the dispatch switch for `ECallPtr`, top-level
functions used as values can be passed as thin wrappers (zero-capture closures) or
the codegen can use a separate "known function pointer" representation. This is a
**codegen concern**, not a defun-pass concern. The defun pass treats them as
non-closures and does not create `TDClosure` structs for them.

> **Open question**: should the defun pass synthesize zero-capture `TDClosure`
> wrappers for top-level functions passed as values, so `ECallPtr` dispatch is
> uniform? This avoids a special case in the codegen at the cost of wrapping
> allocations at every pass-through site. Defer until codegen is designed.

---

## File Layout

```
lib/tir/
├── defun.ml       (* NEW — defunctionalization pass *)
└── ...
```

`defun.ml` exports one function:

```ocaml
val defunctionalize : Tir.tir_module -> Tir.tir_module
```

Internal structure:

```
(* Phase 0 *)  collect_top_level_names : tir_module → StringSet.t
(* Phase 1 *)  collect_lambdas         : fn_def list → StringSet.t → lambda_info list
(* Utility *)  free_vars               : expr → StringSet.t → StringSet.t → (string * ty) list
(* Phase 2 *)  gen_closure_types       : lambda_info list → type_def list * fn_def list
(* Phase 3 *)  rewrite_module          : tir_module → lambda_info list → tir_module
(* Entry *)    defunctionalize         : tir_module → tir_module
```

### dune

Add `defun` to the `march_tir` library in `lib/tir/dune`:

```
(library
 (name march_tir)
 (modules tir pp lower mono defun)    (* add defun *)
 ...)
```

---

## Integration

### `--dump-tir` flag in `bin/main.ml`

After monomorphization, run defunctionalization:

```ocaml
let tir = March_tir.Lower.lower_module ~type_map desugared in
let tir = March_tir.Mono.monomorphize tir in
let tir = March_tir.Defun.defunctionalize tir in
```

### `pp.ml`

`ECallPtr` and `EAlloc` already have pretty-printer cases. `TDClosure` pretty-printing
should be added to `string_of_type_def` (currently not present):

```ocaml
let string_of_type_def = function
  | TDVariant (n, ctors) -> ...
  | TDRecord  (n, fs)    -> ...
  | TDClosure (n, fs)    -> "closure " ^ n ^ "(" ^
      String.concat ", " (List.map string_of_ty fs) ^ ")"
```

---

## Open Questions

1. **Top-level functions as values** — should they get zero-capture closure wrappers
   in the defun pass, or is this a codegen concern? (See Edge Cases above.)

2. **Mutual recursion in lambdas** — `ELetRec` can hold multiple `fn_def`s. If two
   lambdas are mutually recursive, they share free variables. The current algorithm
   handles this (the `ELetRec` free-var rule collects across all fns), but naming
   and lifting get more complex. For now, treat multi-fn `ELetRec` as a single
   closure group sharing one struct.

3. **Linearity of captured values** — if a linear variable is captured by a closure,
   the closure inherits linearity. The Perceus pass handles this, but the defun
   pass must propagate `v_lin` to the closure struct fields and lifted function
   params. Decision: copy `v_lin` from the free-var binding; the Perceus pass
   validates usage counts.

4. **Partial application** — the surface language does not currently support partial
   application (all functions must be fully applied). If added later, partial
   application desugars to a lambda during lowering; defun handles it uniformly.

5. **`ECallPtr` vs explicit apply functions** — the current design leaves dispatch
   to the codegen (`ECallPtr` is the terminal form). An alternative is to generate
   explicit `apply$Sig` dispatch functions in the TIR itself, making the module
   fully self-describing without codegen knowledge. Trade-off: more generated
   boilerplate in the TIR vs. simpler codegen. Revisit when the LLVM emit pass
   is designed.
