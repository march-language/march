(** Proof-backed rewrites (specs/todos/2026-11-02-lemma-uses-beyond-refinement.md
    idea 5): a code action that rewrites an expression by a lemma's
    equation, offered only when the lemma is admitted.

    A lemma `fn name(params) : {Unit | lhs == rhs}` of the open file whose
    theorem is an equation is a rewrite rule `lhs -> rhs`: its parameters are
    the rule's variables, every other name must match as written.  At the
    cursor, the smallest expression [lhs] matches is replaced by [rhs] with
    each variable's matched source text substituted.  The action names the
    lemma, and is offered only when the last refinement check reported the
    lemma admitted ([Refine_diag.lemma_admitted]), so the rewrite keeps the
    program's meaning.  Only the left-to-right direction is offered: a bare
    variable on the right (`rev(rev(xs)) == xs`) would match everything. *)

open Analysis_util
module Ast = March_ast.Ast

type law = { l_name : string; l_params : string list; l_lhs : Ast.expr; l_rhs : Ast.expr }

let rec laws_of (ds : Ast.decl list) : law list =
  List.concat_map
    (function
      | Ast.DFn (fd, _) when List.mem "lemma" fd.Ast.fn_attrs -> (
        match fd.Ast.fn_ret_ty, fd.Ast.fn_clauses with
        | Some (Ast.TyRefine (_, _, Ast.EApp (Ast.EVar { Ast.txt = "=="; _ }, [ l; r ], _))), [ c ] ->
          let params =
            List.filter_map
              (function Ast.FPNamed p | Ast.FPDefault (p, _) -> Some p.Ast.param_name.Ast.txt | Ast.FPPat _ -> None)
              c.Ast.fc_params
          in
          [ { l_name = fd.Ast.fn_name.Ast.txt; l_params = params; l_lhs = l; l_rhs = r } ]
        | _ -> [])
      | Ast.DMod (_, _, inner, _) -> laws_of inner
      | _ -> [])
    ds

let last_segment s = match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s

(* Two callee or constructor spellings name the same thing: equal, or one
   qualifies the other (`List.reverse` against `reverse`). *)
let same_name a b = a = b || String.ends_with ~suffix:("." ^ b) a || String.ends_with ~suffix:("." ^ a) b

let head_name src (e : Ast.expr) =
  match e with
  | Ast.EVar n -> Some n.Ast.txt
  | Ast.EField _ -> Some (slice_span src (span_of_expr e))
  | _ -> None

(* [Some bindings] when [e] is an instance of [pat], each rule variable bound
   to the subexpression it matched (a repeated variable must match the same
   source text). *)
let rec matches src (vars : string list) env (pat : Ast.expr) (e : Ast.expr) =
  match pat, e with
  | Ast.EVar v, _ when List.mem v.Ast.txt vars -> (
    match List.assoc_opt v.Ast.txt env with
    | None -> Some ((v.Ast.txt, e) :: env)
    | Some e0 ->
      if slice_span src (span_of_expr e0) = slice_span src (span_of_expr e) then Some env else None)
  | Ast.EVar v, Ast.EVar w -> if same_name v.Ast.txt w.Ast.txt then Some env else None
  | Ast.ELit (l1, _), Ast.ELit (l2, _) -> if l1 = l2 then Some env else None
  | Ast.ECon (c1, a1, _), Ast.ECon (c2, a2, _) ->
    if same_name c1.Ast.txt c2.Ast.txt && List.length a1 = List.length a2 then args src vars env a1 a2 else None
  | Ast.EApp (f1, a1, _), Ast.EApp (f2, a2, _) -> (
    match head_name src f1, head_name src f2 with
    | Some n1, Some n2 when same_name n1 n2 && List.length a1 = List.length a2 -> args src vars env a1 a2
    | _ -> None)
  | _ -> None

and args src vars env a1 a2 =
  List.fold_left2 (fun acc p x -> Option.bind acc (fun env -> matches src vars env p x)) (Some env) a1 a2

let is_operator_app = function
  | Ast.EApp (Ast.EVar { Ast.txt; _ }, _, _) -> is_march_operator txt
  | _ -> false

(* [rhs] as source text, each rule variable replaced by its match. *)
let instantiate src (vars : string list) env (rhs : Ast.expr) : string option =
  let rs, re = span_byte_bounds src (span_of_expr rhs) in
  if not (rs >= 0 && re > rs && re <= String.length src) then None
  else
    let holes = ref [] in
    iter_expr
      (function
        | Ast.EVar v as x when List.mem v.Ast.txt vars -> holes := (span_byte_bounds src (span_of_expr x), v.Ast.txt) :: !holes
        | _ -> ())
      rhs;
    let holes = List.sort_uniq compare !holes in
    if List.exists (fun (_, v) -> not (List.mem_assoc v env)) holes then None
    else
      let b = Buffer.create 64 in
      let pos =
        List.fold_left
          (fun pos ((s, e), v) ->
            Buffer.add_string b (String.sub src pos (s - pos));
            let m = List.assoc v env in
            let t = slice_span src (span_of_expr m) in
            Buffer.add_string b (if is_operator_app m then "(" ^ t ^ ")" else t);
            e)
          rs holes
      in
      Buffer.add_string b (String.sub src pos (re - pos));
      let t = Buffer.contents b in
      Some (if is_operator_app rhs then "(" ^ t ^ ")" else t)

(** The rewrite actions at the cursor: one per admitted lemma whose left side
    matches the smallest expression it can, at the cursor.  [admitted] is
    [Refine_diag.lemma_admitted]. *)
let actions (a : t) ~line ~character ~(admitted : string -> bool option) :
    Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let src = a.src in
  let laws = List.filter (fun l -> admitted l.l_name = Some true) (laws_of a.decls) in
  if laws = [] then []
  else
    List.filter_map
      (fun law ->
        let pred e = matches src law.l_params [] law.l_lhs e <> None in
        match smallest_expr_at a ~line ~character ~pred with
        | None -> None
        | Some e -> (
          let sp = span_of_expr e in
          (* Not the lemma's own theorem or body. *)
          if sp = span_of_expr law.l_lhs then None
          else
            match Option.bind (matches src law.l_params [] law.l_lhs e) (fun env -> instantiate src law.l_params env law.l_rhs) with
            | None -> None
            | Some text ->
              let range =
                Range.create
                  ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:sp.Ast.start_col)
                  ~end_:(Position.create ~line:(sp.Ast.end_line - 1) ~character:sp.Ast.end_col)
              in
              let edit = TextEdit.create ~range ~newText:text in
              let uri = DocumentUri.of_path a.filename in
              Some
                (CodeAction.create
                   ~title:(Printf.sprintf "Rewrite to `%s` (by the proved lemma `%s`)" text law.l_name)
                   ~kind:CodeActionKind.RefactorRewrite
                   ~edit:(WorkspaceEdit.create ~changes:[ (uri, [ edit ]) ] ())
                   ())))
      laws
