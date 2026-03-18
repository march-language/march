# Monomorphization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all `TVar` placeholders from the TIR by (1) threading the typechecker's `type_map` into the lowering pass so variables get real inferred types, and (2) implementing a worklist-based monomorphization pass in `mono.ml` that specializes polymorphic functions per concrete call-site type.

**Architecture:** Two sequential sub-passes over the TIR. First, `lower_module` is extended to accept the `type_map` from `check_module` and uses `convert_ty` to annotate every let-binding and function variable with its real inferred type rather than `TVar "_"`. Second, `mono.ml` builds a function table, seeds the worklist from monomorphic roots, and for each call to a polymorphic function derives a type substitution by matching the callee's parameter types against the concrete argument types, clones the fn_def with the substitution applied and a mangled name, and rewrites the call site. After fixpoint, no `TVar` remains.

**Tech Stack:** OCaml 5.3.0, dune 3.0, alcotest

---

## File Structure

```
lib/tir/
├── lower.ml     # Modify: accept optional type_map, use convert_ty for all nodes
└── mono.ml      # Create: subst_ty/expr/fn, mangle_name, monomorphize
bin/
└── main.ml      # Modify: pass type_map to lower_module, run monomorphize
test/
└── test_march.ml  # Modify: add mono tests
```

**`lower.ml` changes:**
- Add `let _type_map_ref : (Ast.span, Typecheck.ty) Hashtbl.t option ref = ref None`
- In `lower_to_atom_k`, look up `span_of_expr e` in `_type_map_ref` and use `convert_ty` instead of `unknown_ty` for fresh temporaries
- In `lower_expr`, for `EVar`, look up the span; for `EApp`, use the function variable's type from type_map
- `lower_module` gains `?type_map` optional parameter; sets `_type_map_ref` then clears it

**`mono.ml` responsibilities:**
- `has_tvar : Tir.ty -> bool` — detect residual type variables
- `subst_ty/var/atom/branch/expr/fn_def : (string * Tir.ty) list -> _ -> _` — structural substitution
- `mangle_ty : Tir.ty -> string` and `mangle_name : string -> Tir.ty list -> string`
- `match_ty : Tir.ty -> Tir.ty -> (string * Tir.ty) list -> (string * Tir.ty) list` — pattern match poly type against concrete type to build substitution
- `monomorphize : Tir.tir_module -> Tir.tir_module` — worklist entry point

---

### Task 1: Thread type_map into lower.ml

**Files:**
- Modify: `lib/tir/lower.ml`
- Modify: `test/test_march.ml`

The `lower_module` function currently ignores type information, producing `TVar "_"` everywhere. After this task, calling `lower_module ~type_map m` will annotate every variable with the type the typechecker inferred for that expression.

- [ ] **Step 1: Write a failing test**

Add to `test/test_march.ml`:
```ocaml
(** Parse, desugar, typecheck, and lower a March module using the real type_map. *)
let lower_module_typed src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

let test_tir_lower_typed_param () =
  (* x has NO explicit annotation — type comes from type_map, not lower_ty.
     Without type_map threading this would produce TVar "_". *)
  let m = lower_module_typed {|mod Test do
    fn identity(x) do x end
  end|} in
  (* The typechecker infers x : 'a (generic), but after lower_module_typed,
     the param should have whatever the typechecker left for that span.
     At minimum it must not crash — and for a concretely-called version the
     type should flow through. Here we just check it does not remain unknown_ty
     by verifying the ty round-trips through pp without crashing. *)
  let f = find_fn "identity" m in
  let p = List.hd f.March_tir.Tir.fn_params in
  let _ = March_tir.Pp.string_of_ty p.March_tir.Tir.v_ty in
  (* The param type must not be TVar "_" (the no-type-map fallback) —
     it should now be TVar with an actual HM id, or TInt if fully resolved. *)
  Alcotest.(check bool) "param not bare unknown" false
    (p.March_tir.Tir.v_ty = March_tir.Tir.TVar "_")

let test_tir_lower_typed_let () =
  (* let y = x with no annotation: y's type should come from type_map
     (the inferred type of x, which is Int here because of the return annotation). *)
  let m = lower_module_typed {|mod Test do
    fn double(x : Int) : Int do
      let y = x
      y
    end
  end|} in
  let f = find_fn "double" m in
  match f.March_tir.Tir.fn_body with
  | March_tir.Tir.ELet (v, _, _) ->
    Alcotest.(check string) "let binding has TInt" "Int"
      (March_tir.Pp.string_of_ty v.March_tir.Tir.v_ty)
  | _ -> Alcotest.fail "expected ELet"
```

Add to the `"tir"` test group:
```ocaml
          Alcotest.test_case "typed param annot"    `Quick test_tir_lower_typed_param;
          Alcotest.test_case "typed let annot"      `Quick test_tir_lower_typed_let;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune runtest --force`
Expected: Tests fail because `fn_params` still have `TVar "_"`.

- [ ] **Step 3: Add type_map threading to lower.ml**

Add after `let reset_counter () = ...` in `lib/tir/lower.ml`:
```ocaml
(* ── Type map reference (set by lower_module, used by lower_expr) ── *)

(** Optional typechecker type_map threaded through lowering.
    Looked up by expression span to produce concrete types instead
    of [unknown_ty] placeholders. Set at [lower_module] entry. *)
let _type_map_ref : (Ast.span, Typecheck.ty) Hashtbl.t option ref = ref None

(** Look up the TIR type for an expression from the type_map.
    Falls back to [unknown_ty] when no type_map is set or the span
    is not present (e.g. spans introduced by desugaring). *)
let ty_of_span (sp : Ast.span) : Tir.ty =
  match !_type_map_ref with
  | None -> unknown_ty
  | Some tbl ->
    (match Hashtbl.find_opt tbl sp with
     | Some t -> convert_ty t
     | None   -> unknown_ty)

let ty_of_expr (e : Ast.expr) : Tir.ty =
  ty_of_span (Typecheck.span_of_expr e)
```

- [ ] **Step 4: Update `lower_to_atom_k` to use real types for temporaries**

Find this block in `lower.ml`:
```ocaml
  | _ ->
    let rhs = lower_expr e in
    let v = fresh_var unknown_ty in
    Tir.ELet (v, rhs, k (Tir.AVar v))
```

Replace with:
```ocaml
  | _ ->
    let rhs = lower_expr e in
    let v = fresh_var (ty_of_expr e) in
    Tir.ELet (v, rhs, k (Tir.AVar v))
```

- [ ] **Step 5: Update `lower_expr` for `EVar` to use real types**

Find:
```ocaml
  | Ast.EVar { txt = name; _ } ->
    Tir.EAtom (Tir.AVar { v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr })
```

Replace with:
```ocaml
  | Ast.EVar { txt = name; span; _ } ->
    Tir.EAtom (Tir.AVar { v_name = name; v_ty = ty_of_span span; v_lin = Tir.Unr })
```

And similarly in `lower_to_atom_k`:
```ocaml
  | Ast.EVar { txt = name; _ } ->
    k (Tir.AVar { v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr })
```

Replace with:
```ocaml
  | Ast.EVar { txt = name; span; _ } ->
    k (Tir.AVar { v_name = name; v_ty = ty_of_span span; v_lin = Tir.Unr })
```

- [ ] **Step 6a: Update `EBlock/ELet` case in `lower_expr` to use type_map for binding type**

The `EBlock (Ast.ELet (b, _) :: rest, sp)` case creates `v_ty` from `b.bind_ty`. Unannotated let bindings (`let y = x` with no `: T`) still get `unknown_ty`. Fix the fallback:

Find in `lower.ml`:
```ocaml
    let v : Tir.var = {
      v_name = bind_name;
      v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> unknown_ty);
      v_lin = lower_linearity b.bind_lin;
    } in
```

Replace with:
```ocaml
    let v : Tir.var = {
      v_name = bind_name;
      v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> ty_of_expr b.bind_expr);
      v_lin = lower_linearity b.bind_lin;
    } in
```

- [ ] **Step 6b: Update `lower_fn_def` param lowering to use type_map**

In `lower_fn_def`, find the `FPNamed` case:
```ocaml
      | Ast.FPNamed p ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
          v_lin = lower_linearity p.param_lin }
```

Replace with:
```ocaml
      | Ast.FPNamed p ->
        let ty = match p.param_ty with
          | Some t -> lower_ty t
          | None   -> ty_of_span p.param_name.span
        in
        { Tir.v_name = p.param_name.txt;
          v_ty = ty;
          v_lin = lower_linearity p.param_lin }
```

- [ ] **Step 7: Update `lower_module` to accept and set type_map**

Find the `lower_module` signature:
```ocaml
let lower_module (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
```

Replace with:
```ocaml
let lower_module ?type_map (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  _type_map_ref := type_map;
```

`?type_map` is an OCaml optional labeled parameter — inside the function body its type is `(Ast.span, Typecheck.ty) Hashtbl.t option`. When callers omit it, `type_map = None` and `ty_of_span` falls back to `unknown_ty`. When callers pass `~type_map:tbl`, it arrives as `Some tbl`.

And at the end of `lower_module`, before the return, add cleanup:
```ocaml
  _type_map_ref := None;
```

The full updated function ending:
```ocaml
  let result = { tm_name = m.mod_name.txt;
    tm_fns = List.rev !fns;
    tm_types = List.rev !types } in
  _type_map_ref := None;
  result
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `dune runtest --force`
Expected: All 105 tests pass including the 2 new typed annotation tests.

- [ ] **Step 9: Commit**

```bash
git add lib/tir/lower.ml test/test_march.ml
git commit -m "feat(tir): thread type_map into lower_module for concrete type annotations"
```

---

### Task 2: Type substitution and name mangling in mono.ml

**Files:**
- Create: `lib/tir/mono.ml`
- Modify: `test/test_march.ml`

This task builds the pure infrastructure needed by the worklist: substituting type variables in TIR nodes, detecting residual type variables, and generating mangled names.

- [ ] **Step 1: Write failing tests for substitution and mangling**

Add to `test/test_march.ml`:
```ocaml
let test_mono_subst_ty () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  let s = [("a", TInt); ("b", TBool)] in
  Alcotest.(check string) "subst TVar a → Int" "Int"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "a")));
  Alcotest.(check string) "subst nested" "List(Int)"
    (March_tir.Pp.string_of_ty (subst_ty s (TCon ("List", [TVar "a"]))));
  Alcotest.(check string) "no TVar left" "Bool"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "b")))

let test_mono_mangle () =
  let open March_tir.Mono in
  Alcotest.(check string) "no args" "f" (mangle_name "f" []);
  Alcotest.(check string) "one arg" "map$Int" (mangle_name "map" [March_tir.Tir.TInt]);
  Alcotest.(check string) "two args" "map$Int$Bool"
    (mangle_name "map" [March_tir.Tir.TInt; March_tir.Tir.TBool])

let test_mono_has_tvar () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  Alcotest.(check bool) "TInt no tvar"   false (has_tvar TInt);
  Alcotest.(check bool) "TVar has tvar"  true  (has_tvar (TVar "a"));
  Alcotest.(check bool) "nested has tvar" true
    (has_tvar (TCon ("List", [TVar "a"])))

let test_mono_match_ty () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  let s = match_ty (TVar "a") TInt [] in
  Alcotest.(check string) "matched TVar a = Int" "Int"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "a")));
  let s2 = match_ty (TCon ("List", [TVar "a"])) (TCon ("List", [TBool])) [] in
  Alcotest.(check string) "matched nested TVar a = Bool" "Bool"
    (March_tir.Pp.string_of_ty (subst_ty s2 (TVar "a")))
```

Add to `"tir"` test group:
```ocaml
          Alcotest.test_case "mono subst_ty"        `Quick test_mono_subst_ty;
          Alcotest.test_case "mono mangle_name"     `Quick test_mono_mangle;
          Alcotest.test_case "mono has_tvar"        `Quick test_mono_has_tvar;
          Alcotest.test_case "mono match_ty"        `Quick test_mono_match_ty;
```

- [ ] **Step 2: Run to confirm they fail**

Run: `dune runtest --force`
Expected: Compilation error — `March_tir.Mono` does not exist.

- [ ] **Step 3: Create `lib/tir/mono.ml` with substitution and mangling**

Create `lib/tir/mono.ml`:
```ocaml
(** Monomorphization pass for the March TIR.

    Specializes all polymorphic function definitions to their concrete
    call-site types, eliminating all [Tir.TVar] placeholders.

    Algorithm:
    1. Build a table of all fn_defs by name.
    2. Seed the worklist with all root functions (no TVar in params).
    3. For each dequeued (fn_def, subst): apply subst, walk body for
       EApp calls to functions whose type has TVar, derive a new
       substitution from arg types, clone + rename callee, enqueue.
    4. Output: only the reachable monomorphic fn_defs. *)

(* ── Type detection ─────────────────────────────────────────────── *)

let rec has_tvar : Tir.ty -> bool = function
  | Tir.TVar _        -> true
  | Tir.TTuple ts     -> List.exists has_tvar ts
  | Tir.TRecord fs    -> List.exists (fun (_, t) -> has_tvar t) fs
  | Tir.TCon (_, args)-> List.exists has_tvar args
  | Tir.TFn (ps, ret) -> List.exists has_tvar ps || has_tvar ret
  | Tir.TPtr t        -> has_tvar t
  | _                 -> false   (* TInt, TFloat, TBool, TString, TUnit *)

(* ── Type substitution ──────────────────────────────────────────── *)

type ty_subst = (string * Tir.ty) list

let rec subst_ty (s : ty_subst) : Tir.ty -> Tir.ty = function
  | Tir.TVar name      ->
    (match List.assoc_opt name s with Some t -> t | None -> Tir.TVar name)
  | Tir.TTuple ts      -> Tir.TTuple (List.map (subst_ty s) ts)
  | Tir.TRecord fs     -> Tir.TRecord (List.map (fun (n, t) -> (n, subst_ty s t)) fs)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (subst_ty s) args)
  | Tir.TFn (ps, ret)  -> Tir.TFn (List.map (subst_ty s) ps, subst_ty s ret)
  | Tir.TPtr t         -> Tir.TPtr (subst_ty s t)
  | t                  -> t

let subst_var (s : ty_subst) (v : Tir.var) : Tir.var =
  { v with Tir.v_ty = subst_ty s v.Tir.v_ty }

let subst_atom (s : ty_subst) : Tir.atom -> Tir.atom = function
  | Tir.AVar v -> Tir.AVar (subst_var s v)
  | a          -> a

let rec subst_expr (s : ty_subst) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a           -> Tir.EAtom (subst_atom s a)
  | Tir.EApp (f, args)    -> Tir.EApp (subst_var s f, List.map (subst_atom s) args)
  | Tir.ECallPtr (f, args)-> Tir.ECallPtr (subst_atom s f, List.map (subst_atom s) args)
  | Tir.ELet (v, e1, e2)  -> Tir.ELet (subst_var s v, subst_expr s e1, subst_expr s e2)
  | Tir.ELetRec (fns, body)->
    Tir.ELetRec (List.map (subst_fn_def s) fns, subst_expr s body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (subst_atom s a, List.map (subst_branch s) brs,
               Option.map (subst_expr s) def)
  | Tir.ETuple atoms      -> Tir.ETuple (List.map (subst_atom s) atoms)
  | Tir.ERecord fs        -> Tir.ERecord (List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EField (a, n)     -> Tir.EField (subst_atom s a, n)
  | Tir.EUpdate (a, fs)   ->
    Tir.EUpdate (subst_atom s a, List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EAlloc (ty, args) -> Tir.EAlloc (subst_ty s ty, List.map (subst_atom s) args)
  | Tir.EFree a           -> Tir.EFree (subst_atom s a)
  | Tir.EIncRC a          -> Tir.EIncRC (subst_atom s a)
  | Tir.EDecRC a          -> Tir.EDecRC (subst_atom s a)
  | Tir.EReuse (a, ty, args) ->
    Tir.EReuse (subst_atom s a, subst_ty s ty, List.map (subst_atom s) args)
  | Tir.ESeq (e1, e2)     -> Tir.ESeq (subst_expr s e1, subst_expr s e2)

and subst_branch (s : ty_subst) (br : Tir.branch) : Tir.branch =
  { br with Tir.br_vars = List.map (subst_var s) br.Tir.br_vars;
            Tir.br_body = subst_expr s br.Tir.br_body }

and subst_fn_def (s : ty_subst) (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_params = List.map (subst_var s) fn.Tir.fn_params;
            Tir.fn_ret_ty = subst_ty s fn.Tir.fn_ret_ty;
            Tir.fn_body   = subst_expr s fn.Tir.fn_body }

(* ── Name mangling ──────────────────────────────────────────────── *)

(** Produce a stable, readable string for a monomorphic type.
    Used to construct specialized function names like [map$Int$Bool]. *)
let rec mangle_ty : Tir.ty -> string = function
  | Tir.TInt          -> "Int"
  | Tir.TFloat        -> "Float"
  | Tir.TBool         -> "Bool"
  | Tir.TString       -> "String"
  | Tir.TUnit         -> "Unit"
  | Tir.TTuple ts     -> "T_" ^ String.concat "_" (List.map mangle_ty ts)
  | Tir.TRecord fs    ->
    "R_" ^ String.concat "_" (List.map (fun (n, t) -> n ^ "_" ^ mangle_ty t) fs)
  | Tir.TCon (n, [])  -> n
  | Tir.TCon (n, args)-> n ^ "_" ^ String.concat "_" (List.map mangle_ty args)
  | Tir.TFn (ps, ret) ->
    "Fn_" ^ String.concat "_" (List.map mangle_ty ps) ^ "_" ^ mangle_ty ret
  | Tir.TPtr t        -> "Ptr_" ^ mangle_ty t
  | Tir.TVar name     -> "V_" ^ name

(** [mangle_name base tys] appends a "$"-separated mangled suffix to [base].
    Returns [base] unchanged if [tys] is empty (already monomorphic). *)
let mangle_name (base : string) (tys : Tir.ty list) : string =
  match tys with
  | [] -> base
  | _  -> base ^ "$" ^ String.concat "$" (List.map mangle_ty tys)

(* ── Type matching (poly → concrete → subst) ────────────────────── *)

(** [match_ty poly conc acc] extends substitution [acc] by matching
    the polymorphic type [poly] (which may contain TVar) against the
    concrete type [conc]. Does not fail — unmatched combinations are
    silently skipped (this is not unification; types must be structurally
    compatible after lowering). *)
let rec match_ty (poly : Tir.ty) (conc : Tir.ty) (acc : ty_subst) : ty_subst =
  match poly, conc with
  | Tir.TVar name, t ->
    if List.mem_assoc name acc then acc else (name, t) :: acc
  | Tir.TCon (n1, ps1), Tir.TCon (n2, ps2) when n1 = n2 && List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TTuple ps1, Tir.TTuple ps2 when List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TFn (ps1, r1), Tir.TFn (ps2, r2) when List.length ps1 = List.length ps2 ->
    let acc = List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2 in
    match_ty r1 r2 acc
  | Tir.TPtr p, Tir.TPtr c -> match_ty p c acc
  | _ -> acc
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest --force`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/mono.ml test/test_march.ml
git commit -m "feat(tir): add mono.ml with type substitution, name mangling, and match_ty"
```

---

### Task 3: Worklist monomorphization pass

**Files:**
- Modify: `lib/tir/mono.ml`
- Modify: `test/test_march.ml`

This task implements the full `monomorphize` entry point. After this task, calling `Mono.monomorphize tir_module` will return a new module where every `fn_def` is monomorphic.

- [ ] **Step 1: Write failing tests**

Add to `test/test_march.ml`:
```ocaml
(** Lower with type_map and then monomorphize. *)
let mono_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  March_tir.Mono.monomorphize tir

let test_mono_identity () =
  (* identity is polymorphic; called with Int → should produce identity$Int,
     and the generic identity (with TVar params) should NOT appear. *)
  let m = mono_module {|mod Test do
    fn identity(x) do x end
    fn main() : Int do identity(42) end
  end|} in
  let names = List.map (fun f -> f.March_tir.Tir.fn_name) m.March_tir.Tir.tm_fns in
  (* The specialized version must exist *)
  Alcotest.(check bool) "identity$Int present" true
    (List.exists (fun n -> n = "identity$Int") names);
  (* The unspecialized generic version must NOT be present *)
  Alcotest.(check bool) "bare identity absent" false
    (List.mem "identity" names);
  (* No fn should have TVar in its params after mono *)
  List.iter (fun fn ->
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "param %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns

let test_mono_no_tvar_after_mono () =
  (* After mono, no fn_def in the module has TVar in any type *)
  let m = mono_module {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  let rec ty_ok t = not (March_tir.Mono.has_tvar t) in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "fn %s ret_ty has no TVar" fn.March_tir.Tir.fn_name)
      true (ty_ok fn.March_tir.Tir.fn_ret_ty);
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "fn %s param %s has no TVar" fn.March_tir.Tir.fn_name v.March_tir.Tir.v_name)
        true (ty_ok v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns

let test_mono_two_instantiations () =
  (* apply called with Int and Bool at separate call sites → two specializations *)
  let m = mono_module {|mod Test do
    fn apply(f, x) do f(x) end
    fn inc(n : Int) : Int do n + 1 end
    fn main() : Int do
      let a = apply(inc, 1)
      a
    end
  end|} in
  (* main should be present *)
  let main_fn = find_fn "main" m in
  (* main's return type must be concrete Int, not TVar *)
  Alcotest.(check bool) "main ret is Int" true
    (main_fn.March_tir.Tir.fn_ret_ty = March_tir.Tir.TInt);
  (* apply must have been specialized (not present with TVar params) *)
  List.iter (fun fn ->
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "fn %s param %s concrete" fn.March_tir.Tir.fn_name v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns
```

Add to `"tir"` test group:
```ocaml
          Alcotest.test_case "mono identity"         `Quick test_mono_identity;
          Alcotest.test_case "mono no TVar after"    `Quick test_mono_no_tvar_after_mono;
          Alcotest.test_case "mono two instances"    `Quick test_mono_two_instantiations;
```

- [ ] **Step 2: Run to confirm they fail**

Run: `dune runtest --force`
Expected: Compilation error — `March_tir.Mono.monomorphize` does not exist.

- [ ] **Step 3: Implement the monomorphize worklist**

Add to `lib/tir/mono.ml`:
```ocaml
(* ── Worklist monomorphization ──────────────────────────────────── *)

(** Derive the type substitution for calling [fn_def] with arguments
    of types [arg_tys]. Matches each parameter's type against the
    corresponding argument type to collect TVar bindings. *)
let build_subst (fn : Tir.fn_def) (arg_tys : Tir.ty list) : ty_subst =
  let param_tys = List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params in
  let pairs =
    if List.length param_tys = List.length arg_tys
    then List.combine param_tys arg_tys
    else []   (* arity mismatch — don't substitute *)
  in
  List.fold_left (fun acc (poly, conc) -> match_ty poly conc acc) [] pairs

(** Rewrite all [EApp] and [ELetRec] calls in [expr] that target
    polymorphic functions, replacing them with calls to the
    specialized (mangled) version and enqueuing the specialization
    if not already done. *)
let rec rewrite_calls
    (fn_table  : (string, Tir.fn_def) Hashtbl.t)
    (done_set  : (string, unit) Hashtbl.t)
    (worklist  : (string * Tir.fn_def * ty_subst) Queue.t)
    (expr      : Tir.expr)
  : Tir.expr =
  match expr with
  | Tir.EApp (f_var, args) ->
    (* Check if the *callee's definition* is polymorphic (has TVar in params),
       NOT whether f_var.v_ty has TVar. After Task 1, call sites have concrete
       types from the type_map, so f_var.v_ty is already monomorphic there —
       but the fn_def it refers to may still be the generic version. *)
    let orig_name = f_var.Tir.v_name in
    (match Hashtbl.find_opt fn_table orig_name with
     | None -> expr   (* builtin or external, leave as-is *)
     | Some orig_fn
       when not (List.exists (fun v -> has_tvar v.Tir.v_ty) orig_fn.Tir.fn_params) ->
       (* Callee is already monomorphic — recurse into args (no-op here, atoms) *)
       expr
     | Some orig_fn ->
       let lit_ty = function
         | March_ast.Ast.LitInt _    -> Tir.TInt
         | March_ast.Ast.LitFloat _  -> Tir.TFloat
         | March_ast.Ast.LitBool _   -> Tir.TBool
         | March_ast.Ast.LitString _ -> Tir.TString
         | March_ast.Ast.LitAtom _   -> Tir.TUnit
       in
       let arg_tys = List.map (function
           | Tir.AVar v -> v.Tir.v_ty
           | Tir.ALit l -> lit_ty l
         ) args in
       let subst = build_subst orig_fn arg_tys in
       if subst = [] then expr
       else begin
         let param_tys_concrete = List.map (fun v -> subst_ty subst v.Tir.v_ty)
             orig_fn.Tir.fn_params in
         let mangled = mangle_name orig_name param_tys_concrete in
         if not (Hashtbl.mem done_set mangled) then
           Queue.add (mangled, orig_fn, subst) worklist;
         let f_var' = { f_var with Tir.v_name = mangled;
                                   v_ty = subst_ty subst f_var.Tir.v_ty } in
         Tir.EApp (f_var', args)
       end)
  (* All other EApp cases fall through to structural recursion below *)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v,
      rewrite_calls fn_table done_set worklist e1,
      rewrite_calls fn_table done_set worklist e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
        { fn with Tir.fn_body = rewrite_calls fn_table done_set worklist fn.Tir.fn_body }
      ) fns in
    Tir.ELetRec (fns', rewrite_calls fn_table done_set worklist body)
  | Tir.ECase (a, brs, def) ->
    let brs' = List.map (fun br ->
        { br with Tir.br_body = rewrite_calls fn_table done_set worklist br.Tir.br_body }
      ) brs in
    Tir.ECase (a, brs', Option.map (rewrite_calls fn_table done_set worklist) def)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (rewrite_calls fn_table done_set worklist e1,
              rewrite_calls fn_table done_set worklist e2)
  | other -> other

(** Main entry point. Returns a new [tir_module] with no [TVar] in
    any fn_def that is reachable from a monomorphic root. Polymorphic
    fn_defs with no monomorphic callers are dropped (unreachable). *)
let monomorphize (m : Tir.tir_module) : Tir.tir_module =
  (* Build lookup table for original fn_defs *)
  let fn_table : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 32 in
  List.iter (fun fn -> Hashtbl.replace fn_table fn.Tir.fn_name fn) m.Tir.tm_fns;

  let result   : Tir.fn_def list ref = ref [] in
  let done_set : (string, unit) Hashtbl.t = Hashtbl.create 32 in
  (* worklist entries: (target_name, original_fn_def, subst_to_apply) *)
  let worklist : (string * Tir.fn_def * ty_subst) Queue.t = Queue.create () in

  (* Seed: all fns that are already monomorphic (no TVar in params or ret) *)
  List.iter (fun fn ->
    let is_mono =
      (not (List.exists (fun v -> has_tvar v.Tir.v_ty) fn.Tir.fn_params)) &&
      not (has_tvar fn.Tir.fn_ret_ty)
    in
    if is_mono then Queue.add (fn.Tir.fn_name, fn, []) worklist
  ) m.Tir.tm_fns;

  while not (Queue.is_empty worklist) do
    let (target_name, orig_fn, subst) = Queue.pop worklist in
    if not (Hashtbl.mem done_set target_name) then begin
      Hashtbl.add done_set target_name ();
      (* Apply substitution to get the specialized version *)
      let fn' = subst_fn_def subst orig_fn in
      let fn' = { fn' with Tir.fn_name = target_name } in
      (* Rewrite calls in the body, enqueuing new specializations *)
      let body' = rewrite_calls fn_table done_set worklist fn'.Tir.fn_body in
      result := { fn' with Tir.fn_body = body' } :: !result
    end
  done;

  { m with Tir.tm_fns = List.rev !result }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest --force`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/mono.ml test/test_march.ml
git commit -m "feat(tir): implement monomorphization worklist in mono.ml"
```

---

### Task 4: Wire monomorphization into the compiler pipeline

**Files:**
- Modify: `bin/main.ml`
- Modify: `test/test_march.ml`

After this task, `march --dump-tir file.march` will produce a fully monomorphic TIR with no `TVar "_"` placeholders.

- [ ] **Step 1: Write a failing integration test**

Add to `test/test_march.ml`:
```ocaml
let test_mono_pipeline_no_tvar () =
  (* Full pipeline: lower with type_map + monomorphize.
     Verify no TVar remains in a simple typed program. *)
  let m = mono_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
    fn main() : Int do add(1, 2) end
  end|} in
  let rec check_expr_no_tvar = function
    | March_tir.Tir.EAtom (March_tir.Tir.AVar v) ->
      Alcotest.(check bool)
        (Printf.sprintf "var %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    | March_tir.Tir.ELet (v, e1, e2) ->
      Alcotest.(check bool)
        (Printf.sprintf "let %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty);
      check_expr_no_tvar e1; check_expr_no_tvar e2
    | March_tir.Tir.ESeq (e1, e2) ->
      check_expr_no_tvar e1; check_expr_no_tvar e2
    | _ -> ()
  in
  List.iter (fun fn -> check_expr_no_tvar fn.March_tir.Tir.fn_body)
    m.March_tir.Tir.tm_fns
```

Add to `"tir"` test group:
```ocaml
          Alcotest.test_case "mono pipeline"        `Quick test_mono_pipeline_no_tvar;
```

- [ ] **Step 2: Run to confirm they fail (or pass if pipeline already wired)**

Run: `dune runtest --force`
Expected: The new test may already pass — if so, verify manually. If not, proceed.

- [ ] **Step 3: Update `bin/main.ml` to pass type_map and run mono**

The existing binding uses `_type_map` (underscore-prefixed to silence unused warnings). First rename it, then pass it to the lowerer.

Find:
```ocaml
  let (errors, _type_map) = March_typecheck.Typecheck.check_module desugared in
```

Replace with:
```ocaml
  let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
```

Then find:
```ocaml
  if March_errors.Errors.has_errors errors then exit 1
  else if !dump_tir then begin
    let tir = March_tir.Lower.lower_module desugared in
```

Replace with:
```ocaml
  if March_errors.Errors.has_errors errors then exit 1
  else if !dump_tir then begin
    let tir = March_tir.Lower.lower_module ~type_map desugared in
    let tir = March_tir.Mono.monomorphize tir in
```

- [ ] **Step 4: Run all tests**

Run: `dune runtest --force`
Expected: All tests pass.

- [ ] **Step 5: Manually verify `--dump-tir` output is monomorphic**

Run: `dune exec march -- --dump-tir examples/actors.march`
Expected: TIR printed to stdout with no `'_` or `'a` type variable placeholders (the `'` prefix appears when `ppx_deriving.show` renders a `TVar`).

If `examples/actors.march` doesn't exist, create a minimal test file:
```
dune exec march -- --dump-tir /dev/stdin <<'EOF'
mod Smoke do
  fn add(x : Int, y : Int) : Int do x + y end
  fn main() : Int do add(1, 2) end
end
EOF
```

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml test/test_march.ml
git commit -m "feat(tir): wire type_map and monomorphization into --dump-tir pipeline"
```

---

## Summary

| Task | What it builds | Tests added |
|------|----------------|-------------|
| 1 | Thread `type_map` into `lower_module` for concrete type annotations | 2 |
| 2 | `mono.ml` substitution infrastructure + name mangling | 4 |
| 3 | `monomorphize` worklist pass | 3 |
| 4 | Pipeline wiring + integration | 1 |

**Total: ~4 commits, ~10 new tests, 1 new file.**

## Known Limitations

- **Mutual recursion**: two mutually recursive polymorphic functions where each is called by the other with different types will be handled correctly by the worklist (each specialization is enqueued separately).
- **Higher-order polymorphism**: `map(fn x -> x + 1, 0)` — the lambda gets its own `ELetRec`, which is monomorphic at its call site. The lambda's body is inlined and specialized.
- **Unused polymorphic functions**: functions with type variables that are never called with a concrete type are dropped from the output (not reachable from any monomorphic root). This is correct behavior.
- **`TVar "_"` in unknown positions**: if a node was not visited by the typechecker (e.g. a node introduced by desugaring without a source span), it may retain `TVar "_"`. These are benign pre-mono and will be handled in the monomorphization worklist by falling back to identity substitution.
