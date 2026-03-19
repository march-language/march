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

  (* false && <literal rhs> -> false (only safe for literal atoms, not vars) *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); Tir.ALit _ as rhs])
    when f.Tir.v_name = "&&"
      && Purity.is_pure (Tir.EAtom rhs) ->
    changed := true; mk_bool false

  (* true || <literal rhs> -> true (only safe for literal atoms, not vars) *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); Tir.ALit _ as rhs])
    when f.Tir.v_name = "||"
      && Purity.is_pure (Tir.EAtom rhs) ->
    changed := true; mk_bool true

  (* if true -> then branch; if false -> else branch *)
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
