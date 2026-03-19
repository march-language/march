# Math Optimization Passes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TIR optimization stage (purity oracle, constant folding, algebraic simplification, function inlining, dead code elimination) between Escape Analysis and LLVM emit, plus `--fast-math` and `--opt=N` CLI flags.

**Architecture:** Six new modules in `lib/tir/` (`purity`, `fold`, `simplify`, `inline`, `dce`, `opt`) follow the same pattern as existing passes — each takes `~changed:bool ref -> tir_module -> tir_module`. A coordinator `opt.ml` runs them in a fixed-point loop (max 5 iterations). LLVM-side: `llvm_emit.ml` gets a `fast_math` bool on its context; `bin/main.ml` gets three new CLI flags.

**Tech Stack:** OCaml 5.3.0, dune, Alcotest (tests), existing `March_tir` library, `March_ast.Ast.literal` for atom literals.

**Build command:** `/Users/80197052/.opam/march/bin/dune build`
**Test command:** `/Users/80197052/.opam/march/bin/dune runtest`

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `lib/tir/purity.ml` | Shared `is_pure : Tir.expr -> bool` oracle |
| Create | `lib/tir/fold.ml` | Constant folding pass |
| Create | `lib/tir/simplify.ml` | Algebraic simplification pass |
| Create | `lib/tir/inline.ml` | Pure+small function inlining pass |
| Create | `lib/tir/dce.ml` | Dead code + unreachable function elimination |
| Create | `lib/tir/opt.ml` | Fixed-point coordinator |
| Modify | `lib/tir/dune` | Add 6 new modules to library |
| Modify | `lib/tir/llvm_emit.ml` | Add `fast_math` to ctx; conditional `fast` attribute on FP ops |
| Modify | `bin/main.ml` | Add `--no-opt`, `--fast-math`, `--opt=N` flags; wire `Opt.run` into pipeline |
| Modify | `test/test_march.ml` | Test sections for each pass |

---

## TIR Quick Reference

The passes work directly with `March_tir.Tir` types:

```ocaml
(* Helpers used throughout tests *)
let mk_var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr }
let mk_fn name params ret_ty body =
  { Tir.fn_name = name; fn_params = params; fn_ret_ty = ret_ty; fn_body = body }
let mk_module fns =
  { Tir.tm_name = "test"; tm_fns = fns; tm_types = [] }
let int_var name = mk_var name Tir.TInt
let float_var name = mk_var name Tir.TFloat
let bool_var name = mk_var name Tir.TBool
let app op args = Tir.EApp (mk_var op (Tir.TFn ([], Tir.TInt)), args)
let ilit n = Tir.ALit (March_ast.Ast.LitInt n)
let flit f = Tir.ALit (March_ast.Ast.LitFloat f)
let blit b = Tir.ALit (March_ast.Ast.LitBool b)
let avar name ty = Tir.AVar (mk_var name ty)
```

`if cond then e1 else e2` lowers to:
```ocaml
Tir.ECase (cond_atom, [{ br_tag = "True"; br_vars = []; br_body = e1 }], Some e2)
```

---

## Task 1: Purity Oracle (`purity.ml`)

**Files:**
- Create: `lib/tir/purity.ml`
- Modify: `lib/tir/dune` (add `purity` to modules list)
- Modify: `test/test_march.ml` (add purity test section)

- [ ] **Step 1: Write failing tests**

Add to `test/test_march.ml`:

```ocaml
(* ── Purity oracle ───────────────────────────────────────────────── *)

let mk_var name ty = { March_tir.Tir.v_name = name; v_ty = ty; v_lin = March_tir.Tir.Unr }
let app op args = March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TInt)), args)
let ilit n = March_tir.Tir.ALit (March_ast.Ast.LitInt n)
let blit b = March_tir.Tir.ALit (March_ast.Ast.LitBool b)

let test_purity_atom () =
  Alcotest.(check bool) "literal is pure" true
    (March_tir.Purity.is_pure (March_tir.Tir.EAtom (ilit 5)))

let test_purity_arith () =
  Alcotest.(check bool) "int add is pure" true
    (March_tir.Purity.is_pure (app "+" [ilit 1; ilit 2]))

let test_purity_println () =
  Alcotest.(check bool) "println is impure" false
    (March_tir.Purity.is_pure (app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_print () =
  Alcotest.(check bool) "print is impure" false
    (March_tir.Purity.is_pure (app "print" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_send () =
  Alcotest.(check bool) "send is impure" false
    (March_tir.Purity.is_pure (app "send" [March_tir.Tir.ALit (March_ast.Ast.LitString "msg")]))

let test_purity_let_pure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt, app "+" [ilit 2; ilit 3], body) in
  Alcotest.(check bool) "let with pure rhs is pure" true
    (March_tir.Purity.is_pure expr)

let test_purity_let_impure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")], body) in
  Alcotest.(check bool) "let with impure rhs is impure" false
    (March_tir.Purity.is_pure expr)
```

Add to the test suite list:
```ocaml
("purity", [
  Alcotest.test_case "atom"         `Quick test_purity_atom;
  Alcotest.test_case "arith"        `Quick test_purity_arith;
  Alcotest.test_case "println"      `Quick test_purity_println;
  Alcotest.test_case "print"        `Quick test_purity_print;
  Alcotest.test_case "send"         `Quick test_purity_send;
  Alcotest.test_case "let_pure"     `Quick test_purity_let_pure;
  Alcotest.test_case "let_impure"   `Quick test_purity_let_impure;
]);
```

- [ ] **Step 2: Confirm tests fail**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 purity
```
Expected: compile error — `March_tir.Purity` does not exist yet.

- [ ] **Step 3: Add `purity` to dune**

Edit `lib/tir/dune`:
```
(library
 (name march_tir)
 (modules tir pp lower mono defun perceus escape llvm_emit purity)
 (libraries march_ast march_typecheck)
 (preprocess (pps ppx_deriving.show)))
```

- [ ] **Step 4: Implement `lib/tir/purity.ml`**

```ocaml
(** Shared purity oracle.
    Conservative: returns [false] when uncertain.
    False negatives (treating pure as impure) are safe; false positives are not. *)

let impure_builtins = ["print"; "println"; "send"; "kill"; "march_print"; "march_println"]

let rec is_pure : Tir.expr -> bool = function
  | Tir.EAtom _                -> true
  | Tir.ETuple _               -> true
  | Tir.ERecord _              -> true
  | Tir.EField _               -> true
  | Tir.EAlloc _               -> true   (* allocation is pure, side-effect-free *)
  | Tir.EStackAlloc _          -> true
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ | Tir.EReuse _ -> true
  | Tir.EApp (f, _)            ->
    not (List.mem f.Tir.v_name impure_builtins)
  | Tir.ECallPtr _             -> false  (* indirect call — unknown target *)
  | Tir.ELet (_, rhs, body)    -> is_pure rhs && is_pure body
  | Tir.ELetRec (fns, body)    ->
    List.for_all (fun fd -> is_pure fd.Tir.fn_body) fns && is_pure body
  | Tir.ECase (_, branches, default) ->
    List.for_all (fun b -> is_pure b.Tir.br_body) branches
    && Option.fold ~none:true ~some:is_pure default
  | Tir.EUpdate _              -> true
  | Tir.ESeq (e1, e2)          -> is_pure e1 && is_pure e2
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 purity
```
Expected: all 7 purity tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/purity.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add purity oracle"
```

---

## Task 2: Constant Folding (`fold.ml`)

**Files:**
- Create: `lib/tir/fold.ml`
- Modify: `lib/tir/dune`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write failing tests**

Add to `test/test_march.ml` (after purity section, reusing the helpers defined there):

```ocaml
(* ── Constant folding ────────────────────────────────────────────── *)

let mk_fn name body =
  { March_tir.Tir.fn_name = name; fn_params = [];
    fn_ret_ty = March_tir.Tir.TInt; fn_body = body }
let mk_module fns = { March_tir.Tir.tm_name = "test"; tm_fns = fns; tm_types = [] }
let avar name ty = March_tir.Tir.AVar (mk_var name ty)
let flit f = March_tir.Tir.ALit (March_ast.Ast.LitFloat f)
let fapp op args =
  March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args)

(* Helper: extract body of first function in module *)
let first_body m = (List.hd m.March_tir.Tir.tm_fns).March_tir.Tir.fn_body

let test_fold_int_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "+" [ilit 2; ilit 3])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "2+3=5" "EAtom (ALit (LitInt 5))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_mul () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "*" [ilit 6; ilit 7])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "6*7=42" "EAtom (ALit (LitInt 42))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_div_by_zero () =
  (* division by zero must NOT be folded *)
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 5; ilit 0])] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_fold_float_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (fapp "+." [flit 1.5; flit 2.5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "1.5+.2.5=4.0" "EAtom (ALit (LitFloat 4.))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_bool_not () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "not" [blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "not true = false" "EAtom (ALit (LitBool false))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_pure () =
  (* false && <pure rhs> → false *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [blit false; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "false && true = false" "EAtom (ALit (LitBool false))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_impure () =
  (* false && println(...) must NOT be folded (impure rhs) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let impure = app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")] in
  (* In ANF, impure is bound first. For this test we check that the top-level && is not folded *)
  let print_var = mk_var "p" March_tir.Tir.TBool in
  let body = March_tir.Tir.ELet (print_var, impure,
               bapp "&&" [blit false; March_tir.Tir.AVar print_var]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "not changed (impure rhs)" false !changed

let test_fold_if_true () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit true,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if true → then" "EAtom (ALit (LitInt 1))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_if_false () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit false,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if false → else" "EAtom (ALit (LitInt 2))"
    (March_tir.Tir.show_expr (first_body m'))
```

Add to the test suite list:
```ocaml
("fold", [
  Alcotest.test_case "int_add"               `Quick test_fold_int_add;
  Alcotest.test_case "int_mul"               `Quick test_fold_int_mul;
  Alcotest.test_case "int_div_by_zero"       `Quick test_fold_int_div_by_zero;
  Alcotest.test_case "float_add"             `Quick test_fold_float_add;
  Alcotest.test_case "bool_not"              `Quick test_fold_bool_not;
  Alcotest.test_case "and_shortcircuit_pure" `Quick test_fold_and_shortcircuit_pure;
  Alcotest.test_case "and_shortcircuit_impure" `Quick test_fold_and_shortcircuit_impure;
  Alcotest.test_case "if_true"               `Quick test_fold_if_true;
  Alcotest.test_case "if_false"              `Quick test_fold_if_false;
]);
```

- [ ] **Step 2: Add `fold` to `lib/tir/dune`**

```
(modules tir pp lower mono defun perceus escape llvm_emit purity fold)
```

- [ ] **Step 3: Confirm tests fail (compile error)**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep fold
```

- [ ] **Step 4: Implement `lib/tir/fold.ml`**

```ocaml
(** Constant folding pass.
    Evaluates pure expressions whose operands are all literals.
    Sets [~changed] on any rewrite. *)

let int_ops = ["+"; "-"; "*"; "/"; "%"]
let float_ops = ["+."; "-."; "*."; "/."]

let fold_int_op op a b =
  match op with
  | "+" -> Some (a + b)
  | "-" -> Some (a - b)
  | "*" -> Some (a * b)
  | "/" -> if b = 0 then None else Some (a / b)
  | "%" -> if b = 0 then None else Some (a mod b)
  | _   -> None

let fold_float_op op a b =
  match op with
  | "+." -> Some (a +. b)
  | "-." -> Some (a -. b)
  | "*." -> Some (a *. b)
  | "/." -> if b = 0.0 then None else Some (a /. b)
  | _    -> None

let mk_int n = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt n))
let mk_float f = Tir.EAtom (Tir.ALit (March_ast.Ast.LitFloat f))
let mk_bool b = Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool b))

let rec fold_expr ~changed : Tir.expr -> Tir.expr = function
  (* Integer arithmetic on two literals *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a); Tir.ALit (March_ast.Ast.LitInt b)])
    when List.mem f.Tir.v_name int_ops ->
    (match fold_int_op f.Tir.v_name a b with
     | Some n -> changed := true; mk_int n
     | None   -> Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a); Tir.ALit (March_ast.Ast.LitInt b)]))

  (* Float arithmetic on two literals *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a); Tir.ALit (March_ast.Ast.LitFloat b)])
    when List.mem f.Tir.v_name float_ops ->
    (match fold_float_op f.Tir.v_name a b with
     | Some v -> changed := true; mk_float v
     | None   -> Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a); Tir.ALit (March_ast.Ast.LitFloat b)]))

  (* not <bool_literal> *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool b)]) when f.Tir.v_name = "not" ->
    changed := true; mk_bool (not b)

  (* false && <pure rhs> → false *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); rhs])
    when f.Tir.v_name = "&&"
      && Purity.is_pure (Tir.EAtom rhs) ->
    changed := true; mk_bool false

  (* true || <pure rhs> → true *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); rhs])
    when f.Tir.v_name = "||"
      && Purity.is_pure (Tir.EAtom rhs) ->
    changed := true; mk_bool true

  (* if true → then branch; if false → else branch *)
  | Tir.ECase (Tir.ALit (March_ast.Ast.LitBool true),
               [{ Tir.br_tag = "True"; br_body; _ }], _) ->
    changed := true; fold_expr ~changed br_body

  | Tir.ECase (Tir.ALit (March_ast.Ast.LitBool false),
               [{ Tir.br_tag = "True"; _ }], Some else_e) ->
    changed := true; fold_expr ~changed else_e

  (* Recurse into all other nodes *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, fold_expr ~changed rhs, fold_expr ~changed body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun b ->
      { b with Tir.br_body = fold_expr ~changed b.Tir.br_body }) branches in
    let default' = Option.map (fold_expr ~changed) default in
    Tir.ECase (a, branches', default')
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = fold_expr ~changed fd.Tir.fn_body }) fns in
    Tir.ELetRec (fns', fold_expr ~changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (fold_expr ~changed e1, fold_expr ~changed e2)
  | other -> other

let run_fn ~changed fd =
  { fd with Tir.fn_body = fold_expr ~changed fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "(fold|FAIL|OK)"
```
Expected: all 9 fold tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/fold.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add constant folding pass"
```

---

## Task 3: Algebraic Simplification (`simplify.ml`)

**Files:**
- Create: `lib/tir/simplify.ml`
- Modify: `lib/tir/dune`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write failing tests**

Add to `test/test_march.ml`:

```ocaml
(* ── Algebraic simplification ────────────────────────────────────── *)

let test_simplify_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "+" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+0=x" "EAtom (AVar {v_name = \"x\"; v_ty = TInt; v_lin = Unr})"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*1=x" "EAtom (AVar {v_name = \"x\"; v_ty = TInt; v_lin = Unr})"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_zero_pure () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*0=0" "EAtom (ALit (LitInt 0))"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_self () =
  (* x - x → 0, same v_name *)
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "x" March_tir.Tir.TInt])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x-x=0" "EAtom (ALit (LitInt 0))"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_different () =
  (* x - y must NOT be simplified *)
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "y" March_tir.Tir.TInt])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_simplify_div_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x/1=x" "EAtom (AVar {v_name = \"x\"; v_ty = TInt; v_lin = Unr})"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [ilit 0; x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "0/x=0" "EAtom (ALit (LitInt 0))"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_strength_reduce () =
  (* x * 2 → let t = x + x in t *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 2])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* result should be an ELet binding an addition *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EApp (f, _), _) ->
     Alcotest.(check string) "strength reduce to add" "+" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected ELet wrapping EApp(+)")

let test_simplify_float_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TFloat in
  let fapp' op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args) in
  let m = mk_module [mk_fn "f" (fapp' "+." [x; flit 0.0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+.0.0=x" "EAtom (AVar {v_name = \"x\"; v_ty = TFloat; v_lin = Unr})"
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_bool_and_true () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [x; blit true])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x&&true=x" "EAtom (AVar {v_name = \"x\"; v_ty = TBool; v_lin = Unr})"
    (March_tir.Tir.show_expr (first_body m'))
```

Add to test suite:
```ocaml
("simplify", [
  Alcotest.test_case "add_zero"          `Quick test_simplify_add_zero;
  Alcotest.test_case "mul_one"           `Quick test_simplify_mul_one;
  Alcotest.test_case "mul_zero_pure"     `Quick test_simplify_mul_zero_pure;
  Alcotest.test_case "sub_self"          `Quick test_simplify_sub_self;
  Alcotest.test_case "sub_different"     `Quick test_simplify_sub_different;
  Alcotest.test_case "div_one"           `Quick test_simplify_div_one;
  Alcotest.test_case "zero_div"          `Quick test_simplify_zero_div;
  Alcotest.test_case "strength_reduce"   `Quick test_simplify_strength_reduce;
  Alcotest.test_case "float_add_zero"    `Quick test_simplify_float_add_zero;
  Alcotest.test_case "bool_and_true"     `Quick test_simplify_bool_and_true;
]);
```

- [ ] **Step 2: Add `simplify` to `lib/tir/dune`**

```
(modules tir pp lower mono defun perceus escape llvm_emit purity fold simplify)
```

- [ ] **Step 3: Confirm tests fail**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep simplify
```

- [ ] **Step 4: Implement `lib/tir/simplify.ml`**

```ocaml
(** Algebraic simplification pass.
    Peephole rewrites on expression shape.
    All results remain in ANF; new operations are bound to fresh lets. *)

let gensym =
  let ctr = ref 0 in
  fun prefix ->
    incr ctr;
    Printf.sprintf "%s_s%d" prefix !ctr

let mk_var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr }

let atom_is_pure a = Purity.is_pure (Tir.EAtom a)

(** Wrap a new EApp in a fresh let binding (for ANF-safe rewrites). *)
let let_wrap ty op args =
  let name = gensym "sr" in
  let var = mk_var name ty in
  let rhs = Tir.EApp (mk_var op (Tir.TFn ([], ty)), args) in
  Tir.ELet (var, rhs, Tir.EAtom (Tir.AVar var))

let rec simplify_expr ~changed : Tir.expr -> Tir.expr = function
  (* x + 0 | 0 + x → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 0)]) when f.Tir.v_name = "+" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); x]) when f.Tir.v_name = "+" ->
    changed := true; Tir.EAtom x

  (* x - 0 → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 0)]) when f.Tir.v_name = "-" ->
    changed := true; Tir.EAtom x

  (* x - x → 0 (integer only, v_name equality) *)
  | Tir.EApp (f, [Tir.AVar a; Tir.AVar b])
    when f.Tir.v_name = "-" && a.Tir.v_name = b.Tir.v_name ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* x * 1 | 1 * x → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 1)]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 1); x]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom x

  (* x * 0 | 0 * x → 0 (when x is pure) *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 0)])
    when f.Tir.v_name = "*" && atom_is_pure x ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); x])
    when f.Tir.v_name = "*" && atom_is_pure x ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* x / 1 → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 1)]) when f.Tir.v_name = "/" ->
    changed := true; Tir.EAtom x

  (* 0 / x → 0 (when x is pure) *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); x])
    when f.Tir.v_name = "/" && atom_is_pure x ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* Strength reduction: x * 2 → let t = x + x in t (integer only) *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 2)]) when f.Tir.v_name = "*" ->
    changed := true; let_wrap Tir.TInt "+" [x; x]
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 2); x]) when f.Tir.v_name = "*" ->
    changed := true; let_wrap Tir.TInt "+" [x; x]

  (* Float identities (IEEE 754 safe) *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitFloat 0.0)]) when f.Tir.v_name = "+." ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat 0.0); x]) when f.Tir.v_name = "+." ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitFloat 0.0)]) when f.Tir.v_name = "-." ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitFloat 1.0)]) when f.Tir.v_name = "*." ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat 1.0); x]) when f.Tir.v_name = "*." ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitFloat 1.0)]) when f.Tir.v_name = "/." ->
    changed := true; Tir.EAtom x

  (* Boolean identities *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool true)]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); x]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool false)]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); x]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom x

  (* Recurse *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, simplify_expr ~changed rhs, simplify_expr ~changed body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun b ->
      { b with Tir.br_body = simplify_expr ~changed b.Tir.br_body }) branches in
    Tir.ECase (a, branches', Option.map (simplify_expr ~changed) default)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = simplify_expr ~changed fd.Tir.fn_body }) fns in
    Tir.ELetRec (fns', simplify_expr ~changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (simplify_expr ~changed e1, simplify_expr ~changed e2)
  | other -> other

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (fun fd ->
      { fd with Tir.fn_body = simplify_expr ~changed fd.Tir.fn_body }
    ) m.Tir.tm_fns }
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "(simplify|FAIL)"
```
Expected: all 10 simplify tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/simplify.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add algebraic simplification pass"
```

---

## Task 4: Function Inlining (`inline.ml`)

**Files:**
- Create: `lib/tir/inline.ml`
- Modify: `lib/tir/dune`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
(* ── Function inlining ───────────────────────────────────────────── *)

let test_inline_pure_small () =
  (* fn double(x) = x + x; fn main() = double(5) → inlined: let x_1 = ... in x_1 + x_1 *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let double_body = app "+" [March_tir.Tir.AVar x_param; March_tir.Tir.AVar x_param] in
  let double_fn = { March_tir.Tir.fn_name = "double"; fn_params = [x_param];
                    fn_ret_ty = March_tir.Tir.TInt; fn_body = double_body } in
  let call = March_tir.Tir.EApp (mk_var "double" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                                  [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [double_fn; main_fn] in
  let m' = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* main body should no longer be a bare EApp to "double" *)
  (match first_body m' with
   | March_tir.Tir.EApp (f, _) when f.March_tir.Tir.v_name = "double" ->
     Alcotest.fail "call was not inlined"
   | _ -> ())

let test_inline_impure_not_inlined () =
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  (* fn bad(x) = println("hi"); x *)
  let bad_body = March_tir.Tir.ESeq (
    app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
    March_tir.Tir.EAtom (March_tir.Tir.AVar x_param)) in
  let bad_fn = { March_tir.Tir.fn_name = "bad"; fn_params = [x_param];
                 fn_ret_ty = March_tir.Tir.TInt; fn_body = bad_body } in
  let call = March_tir.Tir.EApp (mk_var "bad" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                                  [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [bad_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (impure)" false !changed

let test_inline_recursive_not_inlined () =
  let changed = ref false in
  let n_param = mk_var "n" March_tir.Tir.TInt in
  (* fn fact(n) = if n == 0 then 1 else n * fact(n-1) — recursive, must not inline *)
  let fact_call = March_tir.Tir.EApp (mk_var "fact" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                                       [March_tir.Tir.AVar n_param]) in
  let fact_fn = { March_tir.Tir.fn_name = "fact"; fn_params = [n_param];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = fact_call } in
  let call = March_tir.Tir.EApp (mk_var "fact" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                                  [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [fact_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (recursive)" false !changed
```

Add to test suite:
```ocaml
("inline", [
  Alcotest.test_case "pure_small"            `Quick test_inline_pure_small;
  Alcotest.test_case "impure_not_inlined"    `Quick test_inline_impure_not_inlined;
  Alcotest.test_case "recursive_not_inlined" `Quick test_inline_recursive_not_inlined;
]);
```

- [ ] **Step 2: Add `inline` to `lib/tir/dune`**

```
(modules tir pp lower mono defun perceus escape llvm_emit purity fold simplify inline)
```

- [ ] **Step 3: Confirm tests fail**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep inline
```

- [ ] **Step 4: Implement `lib/tir/inline.ml`**

```ocaml
(** Function inlining pass.
    Inlines pure, small, non-recursive functions at call sites.
    Alpha-renames inlined bodies to avoid variable capture.
    Each pass does one level of inlining; the fixed-point loop handles chains. *)

let inline_size_threshold = 15

(** Count TIR nodes in an expression (approximate size). *)
let rec node_count : Tir.expr -> int = function
  | Tir.EAtom _ | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _
  | Tir.EUpdate _ | Tir.EAlloc _ | Tir.EStackAlloc _
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ | Tir.EReuse _ -> 1
  | Tir.EApp (_, args) -> 1 + List.length args
  | Tir.ECallPtr (_, args) -> 1 + List.length args
  | Tir.ELet (_, rhs, body) -> 1 + node_count rhs + node_count body
  | Tir.ELetRec (fns, body) ->
    1 + List.fold_left (fun a fd -> a + node_count fd.Tir.fn_body) 0 fns + node_count body
  | Tir.ECase (_, branches, default) ->
    1 + List.fold_left (fun a b -> a + node_count b.Tir.br_body) 0 branches
    + Option.fold ~none:0 ~some:node_count default
  | Tir.ESeq (e1, e2) -> 1 + node_count e1 + node_count e2

(** Check if a function name appears in an expression (recursion detection). *)
let rec calls_self name : Tir.expr -> bool = function
  | Tir.EApp (f, _) when f.Tir.v_name = name -> true
  | Tir.ELet (_, rhs, body) -> calls_self name rhs || calls_self name body
  | Tir.ELetRec (fns, body) ->
    List.exists (fun fd -> calls_self name fd.Tir.fn_body) fns || calls_self name body
  | Tir.ECase (_, branches, default) ->
    List.exists (fun b -> calls_self name b.Tir.br_body) branches
    || Option.fold ~none:false ~some:(calls_self name) default
  | Tir.ESeq (e1, e2) -> calls_self name e1 || calls_self name e2
  | _ -> false

(** Alpha-rename: substitute variable names with fresh ones. *)
let gensym =
  let ctr = ref 0 in
  fun prefix -> incr ctr; Printf.sprintf "%s_i%d" prefix !ctr

let alpha_rename (params : Tir.var list) (body : Tir.expr) : (Tir.var list * Tir.expr) =
  let tbl : (string, string) Hashtbl.t = Hashtbl.create 8 in
  let new_params = List.map (fun v ->
    let fresh = gensym v.Tir.v_name in
    Hashtbl.add tbl v.Tir.v_name fresh;
    { v with Tir.v_name = fresh }
  ) params in
  let subst_var v =
    match Hashtbl.find_opt tbl v.Tir.v_name with
    | Some n -> { v with Tir.v_name = n }
    | None   -> v
  in
  let rec subst_atom = function
    | Tir.AVar v -> Tir.AVar (subst_var v)
    | a          -> a
  and subst_expr = function
    | Tir.EAtom a            -> Tir.EAtom (subst_atom a)
    | Tir.EApp (f, args)     -> Tir.EApp (subst_var f, List.map subst_atom args)
    | Tir.ECallPtr (f, args) -> Tir.ECallPtr (subst_atom f, List.map subst_atom args)
    | Tir.ELet (v, rhs, body) ->
      let fresh = gensym v.Tir.v_name in
      Hashtbl.add tbl v.Tir.v_name fresh;
      let v' = { v with Tir.v_name = fresh } in
      Tir.ELet (v', subst_expr rhs, subst_expr body)
    | Tir.ELetRec (fns, body) ->
      Tir.ELetRec (List.map (fun fd ->
        { fd with Tir.fn_body = subst_expr fd.Tir.fn_body }) fns, subst_expr body)
    | Tir.ECase (a, branches, default) ->
      Tir.ECase (subst_atom a,
        List.map (fun b -> { b with Tir.br_body = subst_expr b.Tir.br_body }) branches,
        Option.map subst_expr default)
    | Tir.ETuple atoms       -> Tir.ETuple (List.map subst_atom atoms)
    | Tir.ERecord fields     -> Tir.ERecord (List.map (fun (k, a) -> (k, subst_atom a)) fields)
    | Tir.EField (a, f)      -> Tir.EField (subst_atom a, f)
    | Tir.EUpdate (a, fs)    -> Tir.EUpdate (subst_atom a, List.map (fun (k, v) -> (k, subst_atom v)) fs)
    | Tir.EAlloc (ty, args)  -> Tir.EAlloc (ty, List.map subst_atom args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map subst_atom args)
    | Tir.EFree a            -> Tir.EFree (subst_atom a)
    | Tir.EIncRC a           -> Tir.EIncRC (subst_atom a)
    | Tir.EDecRC a           -> Tir.EDecRC (subst_atom a)
    | Tir.EReuse (a, ty, args) -> Tir.EReuse (subst_atom a, ty, List.map subst_atom args)
    | Tir.ESeq (e1, e2)      -> Tir.ESeq (subst_expr e1, subst_expr e2)
  in
  (new_params, subst_expr body)

(** Build a substitution of param names to argument atoms, wrap in lets. *)
let subst_args (params : Tir.var list) (args : Tir.atom list) (body : Tir.expr) : Tir.expr =
  List.fold_right2 (fun param arg acc ->
    Tir.ELet (param, Tir.EAtom arg, acc)
  ) params args body

let inline_expr ~changed (fn_env : (string, Tir.fn_def) Hashtbl.t) : Tir.expr -> Tir.expr =
  let rec go = function
    | Tir.EApp (f, args) ->
      (match Hashtbl.find_opt fn_env f.Tir.v_name with
       | Some fd ->
         let (new_params, new_body) = alpha_rename fd.Tir.fn_params fd.Tir.fn_body in
         let inlined = subst_args new_params args new_body in
         changed := true;
         inlined
       | None -> Tir.EApp (f, args))
    | Tir.ELet (v, rhs, body) -> Tir.ELet (v, go rhs, go body)
    | Tir.ELetRec (fns, body) ->
      Tir.ELetRec (List.map (fun fd -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go body)
    | Tir.ECase (a, branches, default) ->
      Tir.ECase (a,
        List.map (fun b -> { b with Tir.br_body = go b.Tir.br_body }) branches,
        Option.map go default)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
    | other -> other
  in
  go

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  (* Build env of inline candidates *)
  let fn_env : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd ->
    let is_pure = Purity.is_pure fd.Tir.fn_body in
    let is_small = node_count fd.Tir.fn_body <= inline_size_threshold in
    let is_nonrecursive = not (calls_self fd.Tir.fn_name fd.Tir.fn_body) in
    if is_pure && is_small && is_nonrecursive then
      Hashtbl.add fn_env fd.Tir.fn_name fd
  ) m.Tir.tm_fns;
  { m with Tir.tm_fns = List.map (fun fd ->
      { fd with Tir.fn_body = inline_expr ~changed fn_env fd.Tir.fn_body }
    ) m.Tir.tm_fns }
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "(inline|FAIL)"
```
Expected: all 3 inline tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/inline.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add function inlining pass"
```

---

## Task 5: Dead Code Elimination (`dce.ml`)

**Files:**
- Create: `lib/tir/dce.ml`
- Modify: `lib/tir/dune`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
(* ── Dead code elimination ───────────────────────────────────────── *)

module StringSet = Set.Make(String)

let test_dce_dead_pure_let () =
  (* let x = 5 in 42 → 42, because x is unused and rhs is pure *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5), March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "dead let removed" "EAtom (ALit (LitInt 42))"
    (March_tir.Tir.show_expr (first_body m'))

let test_dce_impure_let_kept () =
  (* let x = println("hi") in 42 → println("hi"); 42 (rhs is impure, must keep) *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
               March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  (* result should be ESeq, not the original ELet, but the print must be present *)
  (match first_body m' with
   | March_tir.Tir.ESeq _ -> ()  (* impure effect sequenced *)
   | March_tir.Tir.ELet _ -> ()  (* or kept as let — both acceptable *)
   | _ -> Alcotest.fail "impure rhs must be preserved")

let test_dce_used_let_kept () =
  (* let x = 5 in x + 1 → unchanged *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5),
               app "+" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "not changed (used)" false !changed

let test_dce_unreachable_top_fn () =
  (* fn unused() = 99 is not reachable from main → removed *)
  let changed = ref false in
  let unused_fn = { March_tir.Tir.fn_name = "unused"; fn_params = [];
                    fn_ret_ty = March_tir.Tir.TInt;
                    fn_body = March_tir.Tir.EAtom (ilit 99) } in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt;
                  fn_body = March_tir.Tir.EAtom (ilit 0) } in
  let m = mk_module [unused_fn; main_fn] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let fn_names = List.map (fun fd -> fd.March_tir.Tir.fn_name) m'.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "unused removed" false (List.mem "unused" fn_names);
  Alcotest.(check bool) "main kept"      true  (List.mem "main" fn_names)
```

Add to test suite:
```ocaml
("dce", [
  Alcotest.test_case "dead_pure_let"       `Quick test_dce_dead_pure_let;
  Alcotest.test_case "impure_let_kept"     `Quick test_dce_impure_let_kept;
  Alcotest.test_case "used_let_kept"       `Quick test_dce_used_let_kept;
  Alcotest.test_case "unreachable_top_fn"  `Quick test_dce_unreachable_top_fn;
]);
```

- [ ] **Step 2: Add `dce` to `lib/tir/dune`**

```
(modules tir pp lower mono defun perceus escape llvm_emit purity fold simplify inline dce)
```

- [ ] **Step 3: Confirm tests fail**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep dce
```

- [ ] **Step 4: Implement `lib/tir/dce.ml`**

```ocaml
(** Dead code elimination pass.
    - Removes pure unused let bindings (converts impure ones to ESeq)
    - Removes top-level functions not reachable from main or pub exports *)

module StringSet = Set.Make (String)

(** Collect all variable names free in an expression. *)
let rec free_vars : Tir.expr -> StringSet.t = function
  | Tir.EAtom (Tir.AVar v)  -> StringSet.singleton v.Tir.v_name
  | Tir.EAtom (Tir.ALit _)  -> StringSet.empty
  | Tir.EApp (f, args)      ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (StringSet.singleton f.Tir.v_name) args
  | Tir.ECallPtr (f, args)  ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (free_atom f) args
  | Tir.ELet (v, rhs, body) ->
    StringSet.union (free_vars rhs) (StringSet.remove v.Tir.v_name (free_vars body))
  | Tir.ELetRec (fns, body) ->
    let names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) fns) in
    let fn_free = List.fold_left (fun s fd ->
        StringSet.union s (StringSet.diff (free_vars fd.Tir.fn_body) names)
      ) StringSet.empty fns in
    StringSet.union fn_free (StringSet.diff (free_vars body) names)
  | Tir.ECase (a, branches, default) ->
    let bf = List.fold_left (fun s b ->
        let bound = StringSet.of_list (List.map (fun v -> v.Tir.v_name) b.Tir.br_vars) in
        StringSet.union s (StringSet.diff (free_vars b.Tir.br_body) bound)
      ) (free_atom a) branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (free_vars d)) default
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a)) StringSet.empty atoms
  | Tir.ERecord fields ->
    List.fold_left (fun s (_, a) -> StringSet.union s (free_atom a)) StringSet.empty fields
  | Tir.EField (a, _)        -> free_atom a
  | Tir.EUpdate (a, fields)  ->
    List.fold_left (fun s (_, v) -> StringSet.union s (free_atom v)) (free_atom a) fields
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a -> free_atom a
  | Tir.EReuse (a, _, args)  ->
    List.fold_left (fun s v -> StringSet.union s (free_atom v)) (free_atom a) args
  | Tir.ESeq (e1, e2)        -> StringSet.union (free_vars e1) (free_vars e2)

and free_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v -> StringSet.singleton v.Tir.v_name
  | Tir.ALit _ -> StringSet.empty

(** Collect all function names called from an expression. *)
let rec called_fns : Tir.expr -> StringSet.t = function
  | Tir.EApp (f, _)         -> StringSet.singleton f.Tir.v_name
  | Tir.ELet (_, rhs, body) -> StringSet.union (called_fns rhs) (called_fns body)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun s fd -> StringSet.union s (called_fns fd.Tir.fn_body))
      (called_fns body) fns
  | Tir.ECase (_, branches, default) ->
    let bf = List.fold_left (fun s b -> StringSet.union s (called_fns b.Tir.br_body))
               StringSet.empty branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (called_fns d)) default
  | Tir.ESeq (e1, e2)       -> StringSet.union (called_fns e1) (called_fns e2)
  | _                        -> StringSet.empty

(** Transitive reachability from entry points. *)
let reachable_fns (m : Tir.tir_module) : StringSet.t =
  let fn_map : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd -> Hashtbl.add fn_map fd.Tir.fn_name fd) m.Tir.tm_fns;
  let visited = ref StringSet.empty in
  let queue = Queue.create () in
  (* Seed with main and pub-exported names (for simplicity, seed with all names
     that appear in main's call graph) *)
  (match List.find_opt (fun fd -> fd.Tir.fn_name = "main") m.Tir.tm_fns with
   | Some main_fn -> Queue.push main_fn.Tir.fn_name queue
   | None -> List.iter (fun fd -> Queue.push fd.Tir.fn_name queue) m.Tir.tm_fns);
  while not (Queue.is_empty queue) do
    let name = Queue.pop queue in
    if not (StringSet.mem name !visited) then begin
      visited := StringSet.add name !visited;
      match Hashtbl.find_opt fn_map name with
      | None -> ()
      | Some fd ->
        StringSet.iter (fun callee -> Queue.push callee queue) (called_fns fd.Tir.fn_body)
    end
  done;
  !visited

let rec dce_expr ~changed : Tir.expr -> Tir.expr = function
  | Tir.ELet (v, rhs, body) ->
    let rhs'  = dce_expr ~changed rhs in
    let body' = dce_expr ~changed body in
    let used  = StringSet.mem v.Tir.v_name (free_vars body') in
    if used then Tir.ELet (v, rhs', body')
    else if Purity.is_pure rhs' then begin
      changed := true; body'
    end else begin
      changed := true; Tir.ESeq (rhs', body')
    end
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = dce_expr ~changed b.Tir.br_body }) branches,
      Option.map (dce_expr ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fd -> { fd with Tir.fn_body = dce_expr ~changed fd.Tir.fn_body }) fns,
                 dce_expr ~changed body)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (dce_expr ~changed e1, dce_expr ~changed e2)
  | other -> other

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  (* Step 1: remove dead let bindings within function bodies *)
  let fns' = List.map (fun fd ->
    { fd with Tir.fn_body = dce_expr ~changed fd.Tir.fn_body }
  ) m.Tir.tm_fns in
  (* Step 2: remove unreachable top-level functions *)
  let m1 = { m with Tir.tm_fns = fns' } in
  let reachable = reachable_fns m1 in
  let fns'' = List.filter (fun fd ->
    if StringSet.mem fd.Tir.fn_name reachable then true
    else begin changed := true; false end
  ) m1.Tir.tm_fns in
  { m1 with Tir.tm_fns = fns'' }
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "(dce|FAIL)"
```
Expected: all 4 DCE tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/dce.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add dead code elimination pass"
```

---

## Task 6: Coordinator (`opt.ml`)

**Files:**
- Create: `lib/tir/opt.ml`
- Modify: `lib/tir/dune`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write failing test**

```ocaml
(* ── Optimizer coordinator ───────────────────────────────────────── *)

let test_opt_fixpoint () =
  (* let x = 1 + 1 in x * 1
     → fold: let x = 2 in x * 1
     → simplify: let x = 2 in x
     → dce: if x is used, it stays; result should be EAtom(AVar x) or EAtom(ALit 2)
     The key test: opt.run reduces it further than a single pass would *)
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "+" [ilit 1; ilit 1],
               app "*" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (* After fold: x=2, x*1. After simplify: x=2, x. After DCE: 2 (if x inlined by further passes)
     At minimum x*1 should be simplified to x *)
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.AVar _) -> () (* x=2; x *)
   | March_tir.Tir.EAtom (March_tir.Tir.ALit _) -> () (* fully reduced *)
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom _) -> () (* let x=2 in x *)
   | e -> Alcotest.failf "expected reduced form, got: %s" (March_tir.Tir.show_expr e))

let test_opt_no_infinite_loop () =
  (* A stable expression should not loop forever *)
  let m = mk_module [mk_fn "main" (March_tir.Tir.EAtom (ilit 42))] in
  let m' = March_tir.Opt.run m in
  Alcotest.(check string) "stable" "EAtom (ALit (LitInt 42))"
    (March_tir.Tir.show_expr (first_body m'))
```

Add to test suite:
```ocaml
("opt", [
  Alcotest.test_case "fixpoint"         `Quick test_opt_fixpoint;
  Alcotest.test_case "no_infinite_loop" `Quick test_opt_no_infinite_loop;
]);
```

- [ ] **Step 2: Add `opt` to `lib/tir/dune`**

```
(modules tir pp lower mono defun perceus escape llvm_emit purity fold simplify inline dce opt)
```

- [ ] **Step 3: Confirm tests fail**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep opt
```

- [ ] **Step 4: Implement `lib/tir/opt.ml`**

```ocaml
(** Optimization coordinator.
    Runs Inline → Fold → Simplify → DCE in a fixed-point loop.
    Terminates when no pass makes a change, or after 5 iterations. *)

let run (m : Tir.tir_module) : Tir.tir_module =
  let passes = [Inline.run; Fold.run; Simplify.run; Dce.run] in
  let changed = ref false in
  let apply p =
    changed := false;
    List.fold_left (fun acc pass -> pass ~changed acc) p passes
  in
  let rec loop p n =
    if n = 0 then p
    else
      let p' = apply p in
      if not !changed then p'  (* use p', not p: p' = p structurally but is the correct binding *)
      else loop p' (n - 1)
  in
  loop m 5
```

- [ ] **Step 5: Run tests**

```
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "(opt|FAIL)"
```
Expected: all tests pass including new opt tests.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/opt.ml lib/tir/dune test/test_march.ml
git commit -m "feat(tir): add optimization coordinator with fixed-point loop"
```

---

## Task 7: Wire Opt into Pipeline (`bin/main.ml`)

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Add `opt_enabled` flag and wire `Opt.run` into pipeline**

In `bin/main.ml`, after line 86 (the existing ref cells), add:

```ocaml
let opt_enabled  = ref true
```

In the `specs` list (line 217), add:
```ocaml
("--no-opt",    Arg.Clear opt_enabled,  " Skip TIR optimization passes");
```

In the `compile` function, after line 153 (`let tir = March_tir.Escape.escape_analysis tir in`), add:

```ocaml
    let tir = if !opt_enabled then March_tir.Opt.run tir else tir in
```

- [ ] **Step 2: Build**

```
/Users/80197052/.opam/march/bin/dune build 2>&1
```
Expected: clean build.

- [ ] **Step 3: Smoke test — `--no-opt` disables optimization**

```bash
# Simple test: both should run without error
echo 'mod Test do fn main() do println("hello") end end' > /tmp/test_opt.march
/Users/80197052/.opam/march/bin/dune exec march -- --emit-llvm /tmp/test_opt.march
/Users/80197052/.opam/march/bin/dune exec march -- --emit-llvm --no-opt /tmp/test_opt.march
echo "both succeeded"
```

- [ ] **Step 4: Run full test suite**

```
/Users/80197052/.opam/march/bin/dune runtest
```
Expected: all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add bin/main.ml
git commit -m "feat(compiler): wire Opt.run into pipeline; add --no-opt flag"
```

---

## Task 8: `--fast-math` in `llvm_emit.ml`

**Files:**
- Modify: `lib/tir/llvm_emit.ml`
- Modify: `bin/main.ml`
- Modify: `test/test_march.ml` (integration test for IR output)

- [ ] **Step 1: Add `str` to `test/dune`**

Edit `test/dune` to add `str` to the libraries list:
```
(test
 (name test_march)
 (libraries march_lexer march_parser march_ast march_desugar march_typecheck march_errors march_eval march_tir march_repl march_debug alcotest str))
```

- [ ] **Step 2: Write a failing test**

```ocaml
(* ── fast-math IR attribute ──────────────────────────────────────── *)

let test_fast_math_emits_fast_attr () =
  (* Build a tiny TIR module with a float add, emit IR with fast_math=true,
     check that "fadd fast" appears in the output *)
  let x = mk_var "x" March_tir.Tir.TFloat in
  let y = mk_var "y" March_tir.Tir.TFloat in
  let fn_var name = mk_var name (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)) in
  let body = March_tir.Tir.EApp (fn_var "+.", [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) in
  let fd = { March_tir.Tir.fn_name = "fadd_test"; fn_params = [x; y];
             fn_ret_ty = March_tir.Tir.TFloat; fn_body = body } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fd]; tm_types = [] } in
  let ir_fast   = March_tir.Llvm_emit.emit_module ~fast_math:true  m in
  let ir_normal = March_tir.Llvm_emit.emit_module ~fast_math:false m in
  Alcotest.(check bool) "fast_math IR contains 'fadd fast'" true
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_fast 0); true with Not_found -> false));
  Alcotest.(check bool) "normal IR does not contain 'fadd fast'" false
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_normal 0); true with Not_found -> false))
```

Add to test suite:
```ocaml
("fast_math", [
  Alcotest.test_case "emits_fast_attr" `Quick test_fast_math_emits_fast_attr;
]);
```

Note: this test uses `Str` — add it to `test/dune` if not already there:
```
(test (name test_march) (libraries ... str))
```

- [ ] **Step 2: Add `fast_math` to `ctx` in `lib/tir/llvm_emit.ml`**

Add field to the `ctx` type after line 36:
```ocaml
  mutable fast_math : bool;
```

Update `make_ctx` to accept a parameter (or add a separate `make_ctx_with_opts`):
```ocaml
let make_ctx ?(fast_math=false) () = {
  buf      = Buffer.create 4096;
  preamble = Buffer.create 1024;
  ctr      = 0; blk = 0; str_ctr = 0;
  ctor_info = Hashtbl.create 64;
  top_fns   = Hashtbl.create 64;
  field_map = Hashtbl.create 16;
  ret_ty   = Tir.TUnit;
  fast_math;
}
```

- [ ] **Step 3: Update `float_arith_op` emission to use `fast` when `ctx.fast_math`**

At the float arithmetic emit site (around line 374), change:
```ocaml
  | Tir.EApp (f, [a; b]) when is_float_arith f.Tir.v_name ->
    let va = emit_atom_val ctx a in
    let vb = emit_atom_val ctx b in
    let r  = fresh ctx "ar" in
    let op = float_arith_op f.Tir.v_name in
    let op_str = if ctx.fast_math then op ^ " fast" else op in
    emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb);
    ("double", r)
```

- [ ] **Step 4: Update `emit_module` signature**

Change:
```ocaml
let emit_module (m : Tir.tir_module) : string =
  let ctx = make_ctx () in
```
To:
```ocaml
let emit_module ?(fast_math=false) (m : Tir.tir_module) : string =
  let ctx = make_ctx ~fast_math () in
```

- [ ] **Step 5: Add `--fast-math` flag to `bin/main.ml`**

Add ref cell:
```ocaml
let fast_math = ref false
```

Add to `specs`:
```ocaml
("--fast-math",  Arg.Set fast_math,  " Emit 'fast' on all FP LLVM instructions");
```

Update the `emit_module` call (line 164):
```ocaml
      let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math tir in
```

- [ ] **Step 6: Build and run tests**

```
/Users/80197052/.opam/march/bin/dune build 2>&1
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep fast_math
```
Expected: `fast_math emits_fast_attr` passes.

- [ ] **Step 7: Manual smoke test**

```bash
cat > /tmp/fp_test.march << 'EOF'
mod Fp do
  fn main() do
    let x = 1.5
    let y = 2.5
    println(float_to_string(x))
  end
end
EOF
/Users/80197052/.opam/march/bin/dune exec march -- --emit-llvm --fast-math /tmp/fp_test.march
grep "fadd fast\|fmul fast\|fsub fast" /tmp/fp_test.ll && echo "fast-math attributes present"
```

- [ ] **Step 8: Commit**

```bash
git add lib/tir/llvm_emit.ml bin/main.ml test/test_march.ml
git commit -m "feat(llvm): add --fast-math flag; emit 'fast' attribute on FP instructions"
```

---

## Task 9: `--opt=N` Flag

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Add `opt_level` ref and flag**

After the existing ref cells, add:
```ocaml
let opt_level = ref (-1)   (* -1 means "not set"; 0..3 are explicit levels *)
```

Add to `specs`:
```ocaml
("--opt",  Arg.Set_int opt_level,  "<N>  Optimization level passed to clang (0-3)");
```

- [ ] **Step 2: Update the clang invocation (line 185)**

Change:
```ocaml
        let cmd = Printf.sprintf "clang %s %s -o %s" runtime ll_file out_bin in
```
To:
```ocaml
        let opt_flag =
          if !opt_level >= 0 && !opt_level <= 3
          then Printf.sprintf " -O%d" !opt_level
          else ""  (* no flag = clang's default -O0 *)
        in
        let cmd = Printf.sprintf "clang%s %s %s -o %s" opt_flag runtime ll_file out_bin in
```

- [ ] **Step 3: Build**

```
/Users/80197052/.opam/march/bin/dune build 2>&1
```
Expected: clean build.

- [ ] **Step 4: Smoke test**

```bash
/Users/80197052/.opam/march/bin/dune exec march -- --compile --opt 2 /tmp/fp_test.march -o /tmp/fp_test
/tmp/fp_test
```
Expected: prints `1.5` (or whatever the test program outputs).

- [ ] **Step 5: Run full test suite**

```
/Users/80197052/.opam/march/bin/dune runtest
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml
git commit -m "feat(compiler): add --opt=N flag to pass -ON to clang"
```

---

## Done

At this point the full feature is implemented:
- `purity.ml`, `fold.ml`, `simplify.ml`, `inline.ml`, `dce.ml`, `opt.ml` — six TIR passes
- `opt.ml` coordinator wired into `bin/main.ml` between Escape and LLVM emit
- `--no-opt` flag to skip TIR passes
- `--fast-math` flag emitting IR-level `fast` attribute on FP ops
- `--opt=N` flag threading `-ON` to clang
- Tests for every pass plus the fast-math IR output

Run the full suite one final time to confirm:
```
/Users/80197052/.opam/march/bin/dune runtest
```
