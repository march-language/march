# Type Threading: Span-Keyed Type Map Design

## Goal

Thread inferred types from the type checker into the TIR lowering pass so every TIR variable carries its actual inferred type instead of the placeholder `TVar "_"`. This is a prerequisite for monomorphization.

## Approach: Span-Keyed Type Map

During type checking, build a `(Ast.span, Typecheck.ty) Hashtbl.t` that records the resolved type of every expression and binding. Pass this map to the TIR lowering pass, which looks up types by span when creating `Tir.var` records.

**Why span-keyed?** Every AST node already carries a span. No AST modifications required. The table is write-once per span, read-many during lowering.

## Architecture

```
Typecheck.check_module
  ├── builds (Ast.span, Typecheck.ty) Hashtbl.t during inference
  └── returns (Err.ctx * type_map)
         │
         ▼
Lower.lower_module (module_, type_map)
  ├── looks up spans in type_map
  ├── converts Typecheck.ty → Tir.ty via convert_ty
  └── produces Tir.tir_module with real types
```

## Changes

### 1. Type Checker: Add `type_map` to `env`

The internal `env` record gains a new field:

```ocaml
type env = {
  vars    : (string * scheme) list;
  types   : (string * int) list;
  ctors   : (string * ctor_info) list;
  records : (string * (string list * (string * Ast.ty) list)) list;
  level   : int;
  lin     : lin_entry list;
  errors  : Err.ctx;
  pending_constraints : constraint_ list ref;
  type_map : (Ast.span, ty) Hashtbl.t;   (* NEW *)
}
```

The `type_map` is allocated once in `check_module` and shared by reference through all recursive calls (same `Hashtbl.t` instance). The `make_env` function is updated to accept and store the hashtable:

```ocaml
let make_env errors type_map = {
  vars = []; types = []; ctors = []; records = []; level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
}
```

### 2. Type Checker: Record Types at Key Points

All types are recorded after calling `repr` to follow unification links.

**`infer_expr`** — At the end, after computing the result type. The existing `span_of_expr` function (line 785 of `typecheck.ml`) always returns an `Ast.span` (not optional), so recording is straightforward:

```ocaml
let rec infer_expr env (e : Ast.expr) : ty =
  let result = match e with ... in
  (* Record the inferred type for this expression *)
  Hashtbl.replace env.type_map (span_of_expr e) (repr result);
  result
```

**`check_expr`** — Also records types. `check_expr` sometimes falls back to `infer_expr` (which records), but lambda and match arms have special check-mode handling that bypasses `infer_expr`. To ensure complete coverage, `check_expr` records the `expected` type (after `repr`) for the expression's span:

```ocaml
and check_expr env (e : Ast.expr) (expected : ty) ~reason =
  let sp = span_of_expr e in
  Hashtbl.replace env.type_map sp (repr expected);
  match e, repr expected with ...
```

**`check_fn`** — Record each parameter's type after binding, and the overall function type. Parameters are accessed via `clause.fc_params` (not `def.fn_params`), and each is either `FPNamed of param` or `FPPat of pattern`:

```ocaml
(* After binding parameters and computing param_tys *)
List.iter2 (fun fp pty ->
  match fp with
  | Ast.FPNamed p ->
    Hashtbl.replace env.type_map p.param_name.span (repr pty)
  | Ast.FPPat _ -> ()  (* pattern params have no single span to record *)
) clause.fc_params param_tys;

(* After computing fn_ty *)
Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty)
```

**`check_decl` for `DLet`** — Record the binding's type using the declaration's span (from the `DLet(binding, span)` constructor):

```ocaml
| Ast.DLet (bind, sp) ->
  let rhs_ty = infer_expr env' bind.bind_expr in
  Hashtbl.replace env.type_map sp (repr rhs_ty);
  ...
```

### 3. Type Checker: Change `check_module` Return Type

Before:
```ocaml
let check_module ?(errors = Err.create ()) (m : Ast.module_) : Err.ctx
```

After:
```ocaml
let check_module ?(errors = Err.create ()) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t
```

The function creates the `Hashtbl.t`, passes it to `make_env`, and returns it alongside the error context:

```ocaml
let check_module ?(errors = Err.create ()) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let type_map = Hashtbl.create 256 in
  let pre_env = List.fold_left (fun env d -> ...) (base_env errors type_map) m.Ast.mod_decls in
  ignore (List.fold_left check_decl pre_env m.Ast.mod_decls);
  (errors, type_map)
```

### 4. TIR Lowering: Type Conversion Function

A new `convert_ty` function in `lower.ml` converts `Typecheck.ty` to `Tir.ty`. The key subtlety: `Typecheck.TArrow` is curried (`TArrow of ty * ty`), while `Tir.TFn` is uncurried (`TFn of ty list * ty`). Multi-parameter functions like `Int -> Int -> Int` are represented as nested `TArrow(Int, TArrow(Int, Int))` in the type checker but must become `TFn([Int; Int], Int)` in TIR.

```ocaml
let rec convert_ty (t : Typecheck.ty) : Tir.ty =
  match Typecheck.repr t with
  | Typecheck.TCon ("Int", [])    -> Tir.TInt
  | Typecheck.TCon ("Float", [])  -> Tir.TFloat
  | Typecheck.TCon ("Bool", [])   -> Tir.TBool
  | Typecheck.TCon ("String", []) -> Tir.TString
  | Typecheck.TCon ("Unit", [])   -> Tir.TUnit
  | Typecheck.TCon (name, args)   -> Tir.TCon (name, List.map convert_ty args)
  | Typecheck.TArrow _ as t ->
    (* Uncurry nested TArrow chain into flat param list *)
    let rec collect_arrows acc = function
      | Typecheck.TArrow (a, b) -> collect_arrows (convert_ty a :: acc) (Typecheck.repr b)
      | ret -> (List.rev acc, convert_ty ret)
    in
    let (params, ret) = collect_arrows [] t in
    Tir.TFn (params, ret)
  | Typecheck.TTuple tys          -> Tir.TTuple (List.map convert_ty tys)
  | Typecheck.TRecord fields      ->
    Tir.TRecord (List.map (fun (n, t) -> (n, convert_ty t)) fields)
  | Typecheck.TVar r              ->
    (match !r with
     | Typecheck.Unbound (id, _) -> Tir.TVar (Printf.sprintf "_%d" id)
     | Typecheck.Link _ -> assert false) (* repr already followed links *)
  | Typecheck.TLin (_, inner)     -> convert_ty inner (* linearity tracked separately *)
  | Typecheck.TNat n              -> Tir.TCon (Printf.sprintf "Nat_%d" n, [])
  | Typecheck.TNatOp _            -> Tir.TVar "_natop"
  | Typecheck.TError              -> Tir.TVar "_err"
```

**Dependency change:** `lib/tir/dune` must add `march_typecheck` to its `libraries` list so `lower.ml` can reference `Typecheck.ty` and `Typecheck.repr`.

### 5. TIR Lowering: Consume the Type Map

**Signature change:**

```ocaml
let lower_module (m : Ast.module_) (type_map : (Ast.span, Typecheck.ty) Hashtbl.t) : Tir.tir_module
```

The type map is stored in a module-level ref for access by all lowering functions (set at the start of `lower_module`, reset at the end):

```ocaml
let _type_map : (Ast.span, Typecheck.ty) Hashtbl.t ref = ref (Hashtbl.create 0)

let lookup_type (span : Ast.span) : Tir.ty =
  match Hashtbl.find_opt !_type_map span with
  | Some t -> convert_ty t
  | None   -> Tir.TVar "_"  (* graceful fallback *)
```

All sites that currently use `unknown_ty` are replaced with `lookup_type span` where `span` is available from the AST node being lowered.

Note: The module-level ref is set once per `lower_module` call. This is consistent with the existing `_lower_counter` ref pattern already used in `lower.ml`.

### 6. Pipeline Change in `bin/main.ml`

```ocaml
(* Before *)
let errors = March_typecheck.Typecheck.check_module desugared in
...
let tir = March_tir.Lower.lower_module desugared in

(* After *)
let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
...
let tir = March_tir.Lower.lower_module desugared type_map in
```

### 7. Test Strategy

- **Unit tests for `convert_ty`**: Check each `Typecheck.ty` variant converts to the expected `Tir.ty`, including multi-parameter arrow uncurrying.
- **Integration tests**: Parse + desugar + typecheck a snippet, verify the type map has entries, then lower and check TIR vars carry real types (not `TVar "_"`).
- **Regression**: Existing 92 tests must continue to pass. The `check_module` return type change requires updating all call sites — in `bin/main.ml` and `test/test_march.ml` — to destructure the tuple.

## What This Enables (Future Work)

These passes depend on having real types in the TIR and are not part of this plan:

1. **Monomorphization** (Pass 2 in `specs/tir.md`) — Starting from `main`, collect all call sites. For each polymorphic call `f[T1, T2]`, create a specialized `fn_def` with concrete types. The type map provides the concrete types needed at each call site.

2. **Defunctionalization** (Pass 3) — Replace closures with tagged structs + dispatch. Requires knowing the types of free variables captured by each closure.

3. **Perceus RC Analysis** (Pass 4) — Insert/elide reference-count operations. Requires linearity annotations on all variables, which come from the types.

4. **Escape Analysis** (Pass 5) — Promote non-escaping allocations to stack. Requires type information to determine allocation sizes.

5. **LLVM IR Emission** (Pass 6) — Mechanical translation from TIR to LLVM IR. Requires fully monomorphic types to determine struct layouts, calling conventions, and memory sizes.

## Risk and Mitigation

- **Span collisions**: Two expressions with the same span could overwrite each other in the hashtable. Mitigation: `check_expr` records `expected` type early, but `infer_expr` (called as fallback) may overwrite with the inferred type — this is the correct final type. For dedicated `check_expr` paths (lambda, match), the `expected` type recorded at the top is the right answer.
- **Missing spans**: Some synthetic expressions (from desugaring) may lack meaningful spans. Mitigation: graceful fallback to `TVar "_"` — same as current behavior, no regression.
- **Circular dependency risk**: `march_tir` depending on `march_typecheck` creates a one-way dependency. This is fine — there is no reverse dependency. The dependency graph remains: `ast → typecheck → tir`.
- **Top-level `DLet` not lowered**: The current `lower_module` silently drops `DLet` declarations (only lowers `DFn` and `DType`). Types recorded for `DLet` spans have no consumer in the lowering pass yet. This is harmless — the entries sit unused in the hashtable until `DLet` lowering is added.
