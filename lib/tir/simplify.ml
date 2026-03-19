(** Algebraic simplification pass.
    Peephole rewrites on expression shape.
    All results remain in ANF; new operations are bound to fresh lets.
    Sets [~changed] on any rewrite. *)

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

  (* 0 / x → 0 (atoms are always pure) *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt 0); _x]) when f.Tir.v_name = "/" ->
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
