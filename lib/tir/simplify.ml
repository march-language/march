(** Algebraic simplification pass.
    Peephole rewrites on expression shape.
    All results remain in ANF; new operations are bound to fresh lets.
    Sets [~changed] on any rewrite. *)

(** True when [ty] is guaranteed to contain no float values.
    Conservative: [TCon] and [TVar] return false because the type definition
    may include float fields that are not visible at this point in the pipeline.
    Used to guard [x == x → true] / [x != x → false]: IEEE 754 mandates
    [NaN ≠ NaN], so those rewrites are unsound for any type containing a float. *)
let rec is_float_free = function
  | Tir.TInt | Tir.TBool | Tir.TString | Tir.TUnit -> true
  | Tir.TFloat                                       -> false
  | Tir.TTuple ts   -> List.for_all is_float_free ts
  | Tir.TRecord fds -> List.for_all (fun (_, t) -> is_float_free t) fds
  | Tir.TPtr _      -> true
  | Tir.TFn _       -> true   (* functions are never compared with == *)
  | Tir.TCon _      -> false  (* conservative: definition may contain float fields *)
  | Tir.TVar _      -> false  (* conservative: unknown *)

let gensym =
  let ctr = ref 0 in
  fun prefix ->
    incr ctr;
    Printf.sprintf "%s_s%d" prefix !ctr

let mk_var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr }

(** Wrap a new EApp in a fresh let binding (ANF-safe strength reduction). *)
let let_wrap ty op args =
  let name = gensym "sr" in
  let var = mk_var name ty in
  let op_var = mk_var op (Tir.TFn ([], ty)) in
  let rhs = Tir.EApp (op_var, args) in
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

  (* x - x → 0 (integer only, v_name equality; not float due to NaN) *)
  | Tir.EApp (f, [Tir.AVar a; Tir.AVar b])
    when f.Tir.v_name = "-" && a.Tir.v_name = b.Tir.v_name ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* Strength reduction: x * 2 → let t = x + x in t (integer only)
     MUST come before x * 0 and x * 1 so 2 is not matched by those. *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 2)]) when f.Tir.v_name = "*" ->
    changed := true; let_wrap Tir.TInt "+" [x; x]
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 2); x]) when f.Tir.v_name = "*" ->
    changed := true; let_wrap Tir.TInt "+" [x; x]

  (* x * 1 | 1 * x → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 1)]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 1); x]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom x

  (* x * 0 | 0 * x → 0 (atoms are always pure in ANF) *)
  | Tir.EApp (f, [_x; Tir.ALit (March_ast.Ast.LitInt 0)]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); _x]) when f.Tir.v_name = "*" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* x / 1 → x *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitInt 1)]) when f.Tir.v_name = "/" ->
    changed := true; Tir.EAtom x

  (* 0 / x → 0 only when x is a known non-zero literal *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); Tir.ALit (March_ast.Ast.LitInt d)])
    when f.Tir.v_name = "/" && d <> 0 ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 0))

  (* Float identities (IEEE 754 safe; no x -. x rule due to NaN) *)
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

  (* Boolean identities — x is always an atom (ANF), so no side effects dropped *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool true)]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); x]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool false)]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); x]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom x

  (* P15 — Boolean short-circuit absorber laws:
     x && false = false, false && x = false (x already bound, no side effects in ANF)
     x || true  = true,  true  || x = true  *)
  | Tir.EApp (f, [_x; Tir.ALit (March_ast.Ast.LitBool false)]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool false))
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); _x]) when f.Tir.v_name = "&&" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool false))
  | Tir.EApp (f, [_x; Tir.ALit (March_ast.Ast.LitBool true)]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool true))
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); _x]) when f.Tir.v_name = "||" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool true))

  (* P15 — not with known argument: not true = false, not false = true *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool b)]) when f.Tir.v_name = "not" ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool (not b)))

  (* String identities x ++ "" → x and "" ++ x → x are DELIBERATELY NOT folded
     here.  This Simplify pass runs *after* Perceus (see the pipeline in
     bin/main.ml: Perceus then Opt.run).  Perceus treats `"" ++ x` as a concat
     that allocates a fresh owned string distinct from `x`, and emits a separate
     dec_rc for each.  Folding the concat down to the bare atom `x` aliases the
     two together while leaving both dec_rc operations in place — two decrements
     on one object → RC underflow / double-free.  Eliminating an RC-tracked
     allocation is unsound once RC ops have been inserted; the saved allocation
     (one empty-string concat copy) is not worth the miscompile.  If this fold is
     ever wanted, it must run in a pre-Perceus simplification pass instead. *)

  (* Boolean conditional identities arising from guard desugaring / inlining *)

  (* if x then true else false → x *)
  | Tir.ECase (a,
      [{ Tir.br_tag = "True"; br_vars = []; br_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool true)) }],
      Some (Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool false)))) ->
    changed := true; Tir.EAtom a

  (* if x then false else true → not x *)
  | Tir.ECase (a,
      [{ Tir.br_tag = "True"; br_vars = []; br_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool false)) }],
      Some (Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool true)))) ->
    changed := true;
    Tir.EApp (mk_var "not" (Tir.TFn ([Tir.TBool], Tir.TBool)), [a])

  (* x == x → true  (only for float-free types; IEEE 754 NaN ≠ NaN) *)
  | Tir.EApp (f, [Tir.AVar v1; Tir.AVar v2])
    when f.Tir.v_name = "=="
      && v1.Tir.v_name = v2.Tir.v_name
      && is_float_free v1.Tir.v_ty ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool true))

  (* x != x → false  (only for float-free types) *)
  | Tir.EApp (f, [Tir.AVar v1; Tir.AVar v2])
    when f.Tir.v_name = "!="
      && v1.Tir.v_name = v2.Tir.v_name
      && is_float_free v1.Tir.v_ty ->
    changed := true; Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool false))

  (* Recurse *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, simplify_expr ~changed rhs, simplify_expr ~changed body)
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = simplify_expr ~changed b.Tir.br_body }) branches,
      Option.map (simplify_expr ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (
      List.map (fun fd -> { fd with Tir.fn_body = simplify_expr ~changed fd.Tir.fn_body }) fns,
      simplify_expr ~changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (simplify_expr ~changed e1, simplify_expr ~changed e2)
  | other -> other

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (fun fd ->
      { fd with Tir.fn_body = simplify_expr ~changed fd.Tir.fn_body }
    ) m.Tir.tm_fns }
