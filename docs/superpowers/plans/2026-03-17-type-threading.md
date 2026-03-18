# Type Threading Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thread inferred types from `Typecheck.check_module` into `Lower.lower_module` via a span-keyed `Hashtbl`, replacing every `TVar "_"` placeholder in TIR with the actual inferred type.

**Architecture:** `check_module` allocates a `(Ast.span, ty) Hashtbl.t`, stores it in the `env` record, and populates it during inference; `check_module` returns `(Err.ctx * type_map)`. `lower_module` receives the map, calls `convert_ty` to translate `Typecheck.ty → Tir.ty`, and uses `lookup_type span` wherever a variable type is needed.

**Tech Stack:** OCaml 5.3.0, dune, menhir, alcotest. Build: `dune build`. Test: `dune runtest`.

---

## File Map

| File | Change |
|------|--------|
| `lib/typecheck/typecheck.ml` | Add `type_map` field to `env`; update `make_env`/`base_env`; add `Hashtbl.replace` recording in `infer_expr`, `check_expr`, `check_fn`, `check_decl`; change `check_module` return type |
| `lib/tir/dune` | Add `march_typecheck` to `libraries` |
| `lib/tir/lower.ml` | Add `Typecheck` module alias; add `convert_ty`; add `_type_map` ref and `lookup_type`; update `lower_module` signature; replace `unknown_ty` with `lookup_type span` at every variable-creation site |
| `bin/main.ml` | Destructure `(errors, type_map)` from `check_module`; pass `type_map` to `lower_module` |
| `test/test_march.ml` | Update `typecheck` helper (line 151) and `lower_module` helper (line 498) to destructure `check_module` tuple; add tests for `convert_ty` and integration |

---

## Task 1: Add `type_map` to `env` and fix `check_module` return type

This task makes the breaking change to `check_module`'s return type and updates all call sites atomically so the build stays green. No recording yet — we just thread the hashtable.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:255-269` (env type, make_env, base_env)
- Modify: `lib/typecheck/typecheck.ml:1429-1466` (check_module)
- Modify: `bin/main.ml:104` (destructure tuple)
- Modify: `test/test_march.ml:151-153` (typecheck helper)

- [ ] **Step 1: Add `type_map` field to `env` record**

In `lib/typecheck/typecheck.ml`, find the `type env = {` block (line 255) and add the new field at the end:

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
  type_map : (Ast.span, ty) Hashtbl.t;
}
```

- [ ] **Step 2: Update `make_env` and `base_env`**

Change `make_env` (line 267) to accept the hashtable:

```ocaml
let make_env errors type_map = {
  vars = []; types = []; ctors = []; records = []; level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
}
```

Change `base_env` (line 466) to accept and thread the hashtable:

```ocaml
let base_env errors type_map =
  let env = make_env errors type_map in
  let env = bind_vars builtin_bindings env in
  { env with types = builtin_types; ctors = builtin_ctors }
```

- [ ] **Step 3: Update `check_module` to return the type map**

Find `check_module` (line 1429). Change its return type annotation and body:

```ocaml
let check_module ?(errors = Err.create ()) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let type_map = Hashtbl.create 256 in
  let pre_env = List.fold_left (fun env d ->
      ...  (* body unchanged *)
    ) (base_env errors type_map) m.Ast.mod_decls
  in
  ignore (List.fold_left check_decl pre_env m.Ast.mod_decls);
  (errors, type_map)
```

The only changes are: `let type_map = Hashtbl.create 256 in`, `base_env errors type_map` (was `base_env errors`), and the return `(errors, type_map)` (was `errors`).

- [ ] **Step 4: Fix `bin/main.ml` — destructure the tuple**

Find line 104 in `bin/main.ml`:
```ocaml
(* before *)
let errors = March_typecheck.Typecheck.check_module desugared in
```
Change to:
```ocaml
let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
```

Also update the `--dump-tir` branch (line 122) and the `run_module` branch. The `type_map` binding is not yet used — add `let _ = type_map in` temporarily to silence the unused warning, or just pass it to `lower_module` right now (see Task 5).

- [ ] **Step 5: Fix `test/test_march.ml` — update both test helpers**

**`typecheck` helper** at line 151:
```ocaml
(* before *)
let typecheck src =
  let m = parse_and_desugar src in
  March_typecheck.Typecheck.check_module m

let has_errors ctx = March_errors.Errors.has_errors ctx
```
Change to:
```ocaml
let typecheck src =
  let m = parse_and_desugar src in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
  errors

let has_errors ctx = March_errors.Errors.has_errors ctx
```

**`lower_module` helper** at line 498:
```ocaml
(* before *)
let lower_module src =
  let m = parse_and_desugar src in
  March_tir.Lower.lower_module m
```
Change to:
```ocaml
let lower_module src =
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module m type_map
```

This is critical — there are 20+ TIR tests that call `lower_module` and they will all fail to compile if this helper is not updated when `lower_module` gains its second parameter.

- [ ] **Step 6: Build and run tests**

```bash
dune build 2>&1
dune runtest 2>&1
```

Expected: builds clean, all 92 tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml bin/main.ml test/test_march.ml
git commit -m "Add type_map to typecheck env, change check_module return type"
```

---

## Task 2: Record types in `infer_expr` and `check_expr`

Add `Hashtbl.replace` calls so that every time the type checker synthesises or verifies a type, it is stored in the map.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:808` (`infer_expr`)
- Modify: `lib/typecheck/typecheck.ml:1030` (`check_expr`)

- [ ] **Step 1: Write a failing test**

In `test/test_march.ml`, add a test that checks the type map has an entry for a simple expression. Add near the end of the file, before `let () = Alcotest.run`:

```ocaml
let test_type_map_populated () =
  let src = {|mod Test do
    fn go(x : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ March_lexer.Lexer.token lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "type map is non-empty" true
    (Hashtbl.length type_map > 0)
```

Register it in the `let () = Alcotest.run` block:
```ocaml
( "type_map", [ Alcotest.test_case "populated after check" `Quick test_type_map_populated ] );
```

- [ ] **Step 2: Run to confirm it fails**

```bash
dune runtest 2>&1 | grep -A 5 "type_map"
```

Expected: test passes trivially right now because `type_map` always has 0 entries... actually it may pass vacuously since we have no recording yet. Change the test to assert a specific span is present — but that requires knowing a span. Simpler: just assert it fails to hold a specific entry. Actually let's assert `Hashtbl.length type_map > 0` and it will fail (returns 0) before recording is added. Confirm it fails.

- [ ] **Step 3: Wrap `infer_expr` body to record the result**

The current `infer_expr` is (line 808):
```ocaml
let rec infer_expr env (e : Ast.expr) : ty =
  match e with
  | ...
```

Change it to capture the result and record it. The entire `match e with` block becomes the body of a `let result = ... in`:

```ocaml
let rec infer_expr env (e : Ast.expr) : ty =
  let result =
    match e with
    | ...  (* all existing arms unchanged *)
  in
  Hashtbl.replace env.type_map (span_of_expr e) (repr result);
  result
```

The `match e with` block ends at line 1028 (the last arm is `ESpawn`). The `in` goes after the closing `TCon ("Pid", [...])` line. Everything inside is indented one more level.

- [ ] **Step 4: Add recording in `check_expr`**

`check_expr` starts at line 1030. It already extracts `let sp = span_of_expr e in` on line 1031. Add a `Hashtbl.replace` immediately after:

```ocaml
and check_expr env (e : Ast.expr) (expected : ty) ~reason =
  let sp = span_of_expr e in
  Hashtbl.replace env.type_map sp (repr expected);
  match e, repr expected with
  ...
```

(The `infer_expr` fallback path will overwrite this with the actual inferred type, which is correct.)

- [ ] **Step 5: Build and run tests**

```bash
dune build 2>&1
dune runtest 2>&1
```

Expected: all 93 tests pass (92 old + 1 new type_map test).

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_march.ml
git commit -m "Record expression types in type_map during inference"
```

---

## Task 3: Record types in `check_fn` and `check_decl`

Record parameter types and function types so that function definitions carry real types in TIR.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:1158` (`check_fn`)
- Modify: `lib/typecheck/typecheck.ml:1289` (`check_decl`)

- [ ] **Step 1: Write a failing test**

Add a test that verifies the type map is populated specifically for a parameter span. This is hard to test directly without inspecting spans, so instead write an integration test that will catch real types flowing into TIR — add it after the type_map test:

```ocaml
let test_type_map_fn_recorded () =
  (* After type checking, the map should contain an entry for the function name span *)
  let src = {|mod Test do
    fn add(x : Int, y : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ March_lexer.Lexer.token lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  (* Map should have multiple entries: at least params + function name + body *)
  Alcotest.(check bool) "type map has many entries" true
    (Hashtbl.length type_map >= 3)
```

Register it:
```ocaml
Alcotest.test_case "fn params recorded" `Quick test_type_map_fn_recorded;
```

- [ ] **Step 2: Run to confirm current state**

```bash
dune runtest 2>&1 | grep -A 5 "fn params"
```

Expected: may pass or fail depending on how many entries `infer_expr` already recorded. Run it to see the baseline.

- [ ] **Step 3: Add param recording in `check_fn`**

In `check_fn` (line 1158), after `param_tys, body_env = List.fold_right ... clause.fc_params ...` (line 1200), add:

```ocaml
(* Record each named parameter's type in the type map *)
List.iter2 (fun fp pty ->
    match fp with
    | Ast.FPNamed p ->
      Hashtbl.replace env.type_map p.param_name.span (repr pty)
    | Ast.FPPat _ -> ()
  ) clause.fc_params param_tys;
```

- [ ] **Step 4: Add function name recording in `check_fn`**

After `let fn_ty = List.fold_right ... param_tys body_ty` (line 1245–1246), add:

```ocaml
(* Record the function's overall type at the function name's span *)
Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty);
```

- [ ] **Step 5: Add recording in `check_decl` for `DLet`**

In `check_decl`, the `DLet` branch (line 1296):
```ocaml
| Ast.DLet (b, sp) ->
  let env' = enter_level env in
  let rhs_ty = infer_expr env' b.bind_expr in
  ...
```

After `let rhs_ty = infer_expr env' b.bind_expr in`, add:
```ocaml
  Hashtbl.replace env.type_map sp (repr rhs_ty);
```

- [ ] **Step 6: Build and run tests**

```bash
dune build 2>&1
dune runtest 2>&1
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_march.ml
git commit -m "Record fn param and decl types in type_map"
```

---

## Task 4: Add `convert_ty` and `march_typecheck` dependency to TIR lowering

Add the `Typecheck.ty → Tir.ty` conversion function and wire the dune dependency.

**Files:**
- Modify: `lib/tir/dune`
- Modify: `lib/tir/lower.ml` (add convert_ty near top, after lower_ty)

- [ ] **Step 1: Write a failing test for `convert_ty`**

In `test/test_march.ml`, add tests for the conversion function. Add near the TIR tests:

```ocaml
let test_convert_ty_int () =
  let tc = March_typecheck.Typecheck.t_int in
  let result = March_tir.Lower.convert_ty tc in
  Alcotest.(check string) "Int converts to TInt" "TInt"
    (match result with March_tir.Tir.TInt -> "TInt" | _ -> "other")

let test_convert_ty_arrow_uncurried () =
  (* Int -> Int -> Int should become TFn([TInt; TInt], TInt) *)
  let tc = March_typecheck.Typecheck.(TArrow (t_int, TArrow (t_int, t_int))) in
  let result = March_tir.Lower.convert_ty tc in
  Alcotest.(check string) "curried arrow uncurried" "TFn([TInt; TInt], TInt)"
    (match result with
     | March_tir.Tir.TFn ([March_tir.Tir.TInt; March_tir.Tir.TInt], March_tir.Tir.TInt) ->
       "TFn([TInt; TInt], TInt)"
     | _ -> "other")
```

Register them in the test runner under a `"convert_ty"` group.

- [ ] **Step 2: Run to confirm failure**

```bash
dune runtest 2>&1 | grep -A 5 "convert_ty"
```

Expected: compile error — `March_tir.Lower.convert_ty` doesn't exist yet, and `March_typecheck.Typecheck.t_int` may not be exposed.

- [ ] **Step 3: Expose `t_int` and other needed types from typecheck**

Check if `t_int` is accessible: it's defined at around line 400 as `let t_int = TCon ("Int", [])`. Since there's no `.mli`, it's already public as `March_typecheck.Typecheck.t_int`. Verify with a build attempt.

- [ ] **Step 4: Add `march_typecheck` to `lib/tir/dune`**

Change `lib/tir/dune` from:
```
(library
 (name march_tir)
 (libraries march_ast)
 (preprocess (pps ppx_deriving.show)))
```
To:
```
(library
 (name march_tir)
 (libraries march_ast march_typecheck)
 (preprocess (pps ppx_deriving.show)))
```

- [ ] **Step 5: Add `Typecheck` alias and `convert_ty` in `lower.ml`**

In `lib/tir/lower.ml`, add a module alias after `module Ast = March_ast.Ast`:

```ocaml
module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck
```

Then add `convert_ty` after the `lower_linearity` function (around line 62), before the CPS section:

```ocaml
(* ── Type conversion: Typecheck.ty → Tir.ty ─────────────────── *)

(** Convert an internal typechecker type to a TIR type.
    [Typecheck.TArrow] is curried; we uncurry into [Tir.TFn]. *)
let rec convert_ty (t : Typecheck.ty) : Tir.ty =
  match Typecheck.repr t with
  | Typecheck.TCon ("Int",    []) -> Tir.TInt
  | Typecheck.TCon ("Float",  []) -> Tir.TFloat
  | Typecheck.TCon ("Bool",   []) -> Tir.TBool
  | Typecheck.TCon ("String", []) -> Tir.TString
  | Typecheck.TCon ("Unit",   []) -> Tir.TUnit
  | Typecheck.TCon (name, args)   -> Tir.TCon (name, List.map convert_ty args)
  | Typecheck.TArrow _ as t ->
    let rec collect acc = function
      | Typecheck.TArrow (a, b) -> collect (convert_ty a :: acc) (Typecheck.repr b)
      | ret -> (List.rev acc, convert_ty ret)
    in
    let (params, ret) = collect [] t in
    Tir.TFn (params, ret)
  | Typecheck.TTuple tys ->
    Tir.TTuple (List.map convert_ty tys)
  | Typecheck.TRecord fields ->
    Tir.TRecord (List.map (fun (n, t) -> (n, convert_ty t)) fields)
  | Typecheck.TVar r ->
    (match !r with
     | Typecheck.Unbound (id, _) -> Tir.TVar (Printf.sprintf "_%d" id)
     | Typecheck.Link _ -> assert false)
  | Typecheck.TLin (_, inner) -> convert_ty inner
  | Typecheck.TNat n          -> Tir.TCon (Printf.sprintf "Nat_%d" n, [])
  | Typecheck.TNatOp _        -> Tir.TVar "_natop"
  | Typecheck.TError          -> Tir.TVar "_err"
```

- [ ] **Step 6: Build and run tests**

```bash
dune build 2>&1
dune runtest 2>&1
```

Expected: all tests pass, including the new `convert_ty` tests.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/dune lib/tir/lower.ml test/test_march.ml
git commit -m "Add convert_ty to TIR lowering, add march_typecheck dependency"
```

---

## Task 5: Thread `type_map` into `lower_module` and replace `unknown_ty`

Wire the type map into every variable-creation site in `lower.ml`.

**Files:**
- Modify: `lib/tir/lower.ml` (add `_type_map` ref, `lookup_type`, update `lower_module`, replace `unknown_ty`)
- Modify: `bin/main.ml` (pass `type_map` to `lower_module`, remove `let _ = type_map`)

- [ ] **Step 1: Write a failing integration test**

Add a test that lowers a typed snippet and checks that the TIR var for `x` has type `TInt`, not `TVar "_"`:

```ocaml
let test_tir_var_has_real_type () =
  let src = {|mod Test do
    fn identity(x : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ March_lexer.Lexer.token lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module m type_map in
  let fn_def = List.find (fun f -> f.March_tir.Tir.fn_name = "identity") tir.March_tir.Tir.tm_fns in
  let param = List.hd fn_def.March_tir.Tir.fn_params in
  Alcotest.(check string) "param type is TInt" "TInt"
    (match param.March_tir.Tir.v_ty with
     | March_tir.Tir.TInt -> "TInt"
     | March_tir.Tir.TVar s -> "TVar " ^ s
     | _ -> "other")
```

Register it.

- [ ] **Step 2: Run to confirm failure**

```bash
dune runtest 2>&1 | grep -A 5 "tir_var_has_real_type"
```

Expected: compile error — `lower_module` doesn't accept `type_map` yet.

- [ ] **Step 3: Add `_type_map` ref and `lookup_type` to `lower.ml`**

After the `unknown_ty` definition (line 34), add:

```ocaml
(** Module-level type map, set by [lower_module] before lowering begins.
    Consistent with the [_lower_counter] pattern used for fresh names. *)
let _type_map : (Ast.span, Typecheck.ty) Hashtbl.t ref =
  ref (Hashtbl.create 0)

(** Look up the inferred type for a span. Falls back to [unknown_ty]
    if the span was not recorded (e.g. synthetic desugared nodes). *)
let lookup_type (span : Ast.span) : Tir.ty =
  match Hashtbl.find_opt !_type_map span with
  | Some t -> convert_ty t
  | None   -> unknown_ty
```

- [ ] **Step 4: Update `lower_module` to accept and install the type map**

Change `lower_module` (line 320):
```ocaml
(* before *)
let lower_module (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  ...

(* after *)
let lower_module (m : Ast.module_) (type_map : (Ast.span, Typecheck.ty) Hashtbl.t) : Tir.tir_module =
  reset_counter ();
  _type_map := type_map;
  ...
```

- [ ] **Step 5: Replace `unknown_ty` with `lookup_type span` at variable-creation sites**

There are several sites in `lower.ml` that create `Tir.var` records with `unknown_ty`. Replace each with `lookup_type span`:

**In `lower_to_atom_k` (line 75–79):**
```ocaml
| Ast.EVar { txt = name; span; _ } ->
  k (Tir.AVar { v_name = name; v_ty = lookup_type span; v_lin = Tir.Unr })
| _ ->
  let rhs = lower_expr e in
  let v = fresh_var (lookup_type (span_of_expr e)) in
  Tir.ELet (v, rhs, k (Tir.AVar v))
```

Note: `span_of_expr` is a helper that returns the span of an expression, or a dummy if unavailable. Since all `Ast.expr` variants carry spans (see the existing `span_of_expr` in `typecheck.ml`), we can add the same helper locally in `lower.ml`:

```ocaml
let span_of_expr (e : Ast.expr) : Ast.span =
  match e with
  | Ast.ELit  (_, sp)              -> sp
  | Ast.EVar  name                 -> name.span
  | Ast.EApp  (_, _, sp)           -> sp
  | Ast.ECon  (_, _, sp)           -> sp
  | Ast.ELam  (_, _, sp)           -> sp
  | Ast.EBlock (_, sp)             -> sp
  | Ast.ELet  (_, sp)              -> sp
  | Ast.EMatch (_, _, sp)          -> sp
  | Ast.ETuple (_, sp)             -> sp
  | Ast.ERecord (_, sp)            -> sp
  | Ast.ERecordUpdate (_, _, sp)   -> sp
  | Ast.EField (_, _, sp)          -> sp
  | Ast.EIf   (_, _, _, sp)        -> sp
  | Ast.EPipe (_, _, sp)           -> sp
  | Ast.EAnnot (_, _, sp)          -> sp
  | Ast.EHole (_, sp)              -> sp
  | Ast.EAtom (_, _, sp)           -> sp
  | Ast.ESend (_, _, sp)           -> sp
  | Ast.ESpawn (_, sp)             -> sp
```

Add this helper after `_type_map` / `lookup_type`.

**In `lower_expr` for `EVar` (line 97–98):**
```ocaml
| Ast.EVar { txt = name; span; _ } ->
  Tir.EAtom (Tir.AVar { v_name = name; v_ty = lookup_type span; v_lin = Tir.Unr })
```

**In `lower_expr` for `EApp` (line 162):**
```ocaml
| Tir.ALit _ ->
  { v_name = "<lit>"; v_ty = unknown_ty; v_lin = Tir.Unr }
```
Leave this one as `unknown_ty` — it's an unreachable case for well-typed programs.

**In `lower_expr` for `EBlock`'s `ELet` arm (line 113–116):**
```ocaml
let v : Tir.var = {
  v_name = bind_name;
  v_ty = (match b.bind_ty with
    | Some t -> lower_ty t
    | None   ->
      let _, sp = (b.bind_expr, match b.bind_expr with
        | Ast.ELit (_, s) -> s | Ast.EVar n -> n.span | e -> span_of_expr e) in
      lookup_type sp);
  v_lin = lower_linearity b.bind_lin;
}
```

Simpler — look up using the `ELet`'s span (from `EBlock (Ast.ELet (b, let_sp) :: rest, _sp)`):

```ocaml
| Ast.EBlock (Ast.ELet (b, let_sp) :: rest, sp) ->
  let rhs = lower_expr b.bind_expr in
  let bind_name = match b.bind_pat with
    | Ast.PatVar n -> n.txt
    | _ -> fresh_name "p"
  in
  let v : Tir.var = {
    v_name = bind_name;
    v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> lookup_type let_sp);
    v_lin = lower_linearity b.bind_lin;
  } in
  let body = lower_expr (Ast.EBlock (rest, sp)) in
  Tir.ELet (v, rhs, body)
```

**In `lower_fn_def` for `FPNamed` params (line 290–292):**
```ocaml
| Ast.FPNamed p ->
  { Tir.v_name = p.param_name.txt;
    v_ty = (match p.param_ty with
      | Some t -> lower_ty t
      | None   -> lookup_type p.param_name.span);
    v_lin = lower_linearity p.param_lin }
```

**In `lower_fn_def` for `FPPat (PatVar n)` (line 293–294):**
```ocaml
| Ast.FPPat (Ast.PatVar n) ->
  { Tir.v_name = n.txt; v_ty = lookup_type n.span; v_lin = Tir.Unr }
```

**In `lower_fn_def` for return type (line 297–299):**
```ocaml
let ret_ty = match def.fn_ret_ty with
  | Some t -> lower_ty t
  | None   -> lookup_type def.fn_name.span
in
```

**In `lower_match` for constructor branch vars (line 249):**
```ocaml
{ Tir.v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr }
```
Leave as `unknown_ty` for now — pattern variable types require deeper analysis and can be addressed in a follow-up.

**In `lower_match` for default PatVar arm (line 272):**
```ocaml
let v : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr } in
```
Leave as `unknown_ty` — same reason.

**In `lower_to_atom_k` for the non-atomic fallback `fresh_var` (line 79):**
```ocaml
let v = fresh_var (lookup_type (span_of_expr e)) in
```

**In `lower_expr` for `ELam` params (line 174–177):**
```ocaml
let params' = List.map (fun (p : Ast.param) ->
    { Tir.v_name = p.param_name.txt;
      v_ty = (match p.param_ty with
        | Some t -> lower_ty t
        | None   -> lookup_type p.param_name.span);
      v_lin = lower_linearity p.param_lin }
  ) params in
```

**In `lower_expr` for `ELam` ret_ty (line 180):**
```ocaml
let ret_ty = lookup_type (match lam_sp with sp -> sp) in
```
Where `lam_sp` is the span from `Ast.ELam (params, body, lam_sp)`. Update the pattern:
```ocaml
| Ast.ELam (params, body, lam_sp) ->
  let fn_name = fresh_name "lam" in
  let params' = ... in
  let body' = lower_expr body in
  let ret_ty = lookup_type lam_sp in
  ...
```

**In `lower_expr` for `ESend` and `ESpawn` builtins (lines 217, 222):**
Leave as `unknown_ty` — these are builtins with no user-visible span.

- [ ] **Step 6: Fix `bin/main.ml` and `test/test_march.ml` `lower_module` helper**

**`bin/main.ml`** — find the `--dump-tir` branch (line 122):
```ocaml
(* before *)
let tir = March_tir.Lower.lower_module desugared in

(* after *)
let tir = March_tir.Lower.lower_module desugared type_map in
```
Remove any `let _ = type_map in` added in Task 1.

**`test/test_march.ml` `lower_module` helper** at line 498 — this is the second call site for `lower_module` and it must also be updated (see Task 1 Step 5 for the exact change). Verify it was already updated there; if not, update it now:
```ocaml
let lower_module src =
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module m type_map
```

- [ ] **Step 7: Build and run tests**

```bash
dune build 2>&1
dune runtest 2>&1
```

Expected: all tests pass, including the new integration test where `identity`'s param `x` has type `TInt`.

- [ ] **Step 8: Commit**

```bash
git add lib/tir/lower.ml bin/main.ml test/test_march.ml
git commit -m "Thread type_map into lower_module, replace unknown_ty with lookup_type"
```

---

## Task 6: Integration smoke test with `--dump-tir`

Verify the full pipeline produces real types in `--dump-tir` output.

**Files:**
- No code changes — this is a manual smoke test

- [ ] **Step 1: Run `--dump-tir` on the example file**

```bash
dune exec march -- --dump-tir examples/list_lib.march 2>&1 | head -40
```

Expected: TIR output shows actual types (e.g., `TInt`, `TCon("List", [TInt])`) instead of `TVar "_"` for the functions that have explicit type annotations. Some variables may still show `TVar "_N"` for fully inferred polymorphic types — that's expected pre-monomorphization.

- [ ] **Step 2: Verify actors example**

```bash
dune exec march -- --dump-tir examples/actors.march 2>&1 | head -40
```

Expected: TIR output with real types for typed parameters.

- [ ] **Step 3: Run full test suite one final time**

```bash
dune runtest 2>&1
```

Expected: all tests pass.

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "Verify type threading end-to-end via --dump-tir smoke test"
```

---

## Summary of Files Changed

| File | Why |
|------|-----|
| `lib/typecheck/typecheck.ml` | Add `type_map` to `env`; record types in `infer_expr`, `check_expr`, `check_fn`, `check_decl`; change `check_module` return type |
| `lib/tir/dune` | Add `march_typecheck` dependency |
| `lib/tir/lower.ml` | Add `Typecheck` alias, `convert_ty`, `_type_map` ref, `lookup_type`, local `span_of_expr`; update `lower_module` signature; replace `unknown_ty` with `lookup_type` |
| `bin/main.ml` | Destructure `check_module` result; pass `type_map` to `lower_module` |
| `test/test_march.ml` | Update `typecheck` helper (line 151) and `lower_module` helper (line 498); add tests for `convert_ty` and integration |

## Future Work

After this plan is complete, the next passes in order are:

1. **Monomorphization** (`lib/tir/mono.ml`) — specialize polymorphic functions per call site using the type map
2. **Defunctionalization** (`lib/tir/defun.ml`) — closures become tagged structs + dispatch
3. **Perceus RC Analysis** (`lib/tir/perceus.ml`) — insert/elide reference counts
4. **Escape Analysis** (`lib/tir/escape.ml`) — stack-promote non-escaping allocations
5. **LLVM IR Emission** (`lib/tir/llvm_emit.ml`) — TIR → LLVM IR
