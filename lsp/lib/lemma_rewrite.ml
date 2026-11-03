(** Proof-backed rewrites (specs/todos/2026-11-02-lemma-uses-beyond-refinement.md
    idea 5): a code action that rewrites an expression by a lemma's
    equation, offered only when the lemma is admitted.

    A lemma `fn name(params) : {Unit | lhs == rhs}` is a rewrite rule
    `lhs -> rhs`: its parameters are the rule's variables, every other name
    must match as written.  At the cursor, the smallest expression [lhs]
    matches is replaced by [rhs] with each variable's matched source text
    substituted.  Rules come from:
    - the open file, and the user files it imports: admitted when the last
      refinement check said so ([Refine_diag.lemma_admitted]);
    - the stdlib: admitted when `stdlib/lemmas.verified` (the stdlib lemma
      manifest) lists it.
    A rule from another module has that module's functions in [rhs]
    qualified (`List.append(..)`), since the open file may not import them.
    Only the left-to-right direction is offered: a bare variable on the right
    (`rev(rev(xs)) == xs`) would match everything. *)

open Analysis_util
module Ast = March_ast.Ast

type law = {
  l_name : string;
  l_params : string list;
  l_lhs : Ast.expr;
  l_rhs : Ast.expr;
  l_src : string;  (** the source text of the lemma's file *)
  l_module : string option;  (** the module to qualify [rhs]'s functions with *)
  l_fns : string list;  (** the functions that module defines *)
  l_qname : string;  (** `Mod.name`, for the stdlib manifest *)
}

let file_text : (string, string) Hashtbl.t = Hashtbl.create 8

let read_file (f : string) : string =
  match Hashtbl.find_opt file_text f with
  | Some t -> t
  | None ->
    let t = try In_channel.with_open_bin f In_channel.input_all with Sys_error _ -> "" in
    Hashtbl.replace file_text f t;
    t

let rec laws_of ~(src : string option) ~(prefix : string) (ds : Ast.decl list) : law list =
  let fns = List.filter_map (function Ast.DFn (fd, _) -> Some fd.Ast.fn_name.Ast.txt | _ -> None) ds in
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
          let text = match src with Some s -> s | None -> read_file fd.Ast.fn_name.Ast.span.Ast.file in
          let m = if prefix = "" then None else Some (String.sub prefix 0 (String.length prefix - 1)) in
          [ { l_name = fd.Ast.fn_name.Ast.txt; l_params = params; l_lhs = l; l_rhs = r; l_src = text;
              l_module = (match src with Some _ -> None | None -> m); l_fns = fns;
              l_qname = prefix ^ fd.Ast.fn_name.Ast.txt } ]
        | _ -> [])
      | Ast.DMod (n, _, inner, _) -> laws_of ~src ~prefix:(prefix ^ n.Ast.txt ^ ".") inner
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

(* [Some bindings] when [e] (in [src]) is an instance of [pat] (in
   [psrc]), each rule variable bound to the subexpression it matched (a
   repeated variable must match the same source text). *)
let rec matches ~psrc ~src (vars : string list) env (pat : Ast.expr) (e : Ast.expr) =
  match pat, e with
  | Ast.EVar v, _ when List.mem v.Ast.txt vars -> (
    match List.assoc_opt v.Ast.txt env with
    | None -> Some ((v.Ast.txt, e) :: env)
    | Some e0 ->
      if slice_span src (span_of_expr e0) = slice_span src (span_of_expr e) then Some env else None)
  | Ast.EVar v, Ast.EVar w -> if same_name v.Ast.txt w.Ast.txt then Some env else None
  | Ast.ELit (l1, _), Ast.ELit (l2, _) -> if l1 = l2 then Some env else None
  | Ast.ECon (c1, a1, _), Ast.ECon (c2, a2, _) ->
    if same_name c1.Ast.txt c2.Ast.txt && List.length a1 = List.length a2 then args ~psrc ~src vars env a1 a2
    else None
  | Ast.EApp (f1, a1, _), Ast.EApp (f2, a2, _) -> (
    match head_name psrc f1, head_name src f2 with
    | Some n1, Some n2 when same_name n1 n2 && List.length a1 = List.length a2 -> args ~psrc ~src vars env a1 a2
    | _ -> None)
  | _ -> None

and args ~psrc ~src vars env a1 a2 =
  List.fold_left2 (fun acc p x -> Option.bind acc (fun env -> matches ~psrc ~src vars env p x)) (Some env) a1 a2

let is_operator_app = function
  | Ast.EApp (Ast.EVar { Ast.txt; _ }, _, _) -> is_march_operator txt
  | _ -> false

(* [law]'s [rhs] as source text: each rule variable replaced by its match
   (text of the open file [src]), and, for a rule from another module, each
   of that module's functions qualified with it. *)
let instantiate ~src (law : law) env : string option =
  let psrc = law.l_src in
  let rs, re = span_byte_bounds psrc (span_of_expr law.l_rhs) in
  if not (rs >= 0 && re > rs && re <= String.length psrc) then None
  else
    let holes = ref [] in
    iter_expr
      (function
        | Ast.EVar v as x when List.mem v.Ast.txt law.l_params ->
          holes := (span_byte_bounds psrc (span_of_expr x), `Var v.Ast.txt) :: !holes
        | Ast.EApp ((Ast.EVar v as h), _, _) when law.l_module <> None && List.mem v.Ast.txt law.l_fns ->
          holes := (span_byte_bounds psrc (span_of_expr h), `Qualify v.Ast.txt) :: !holes
        | _ -> ())
      law.l_rhs;
    let holes = List.sort_uniq compare !holes in
    if List.exists (function (_, `Var v) -> not (List.mem_assoc v env) | _ -> false) holes then None
    else
      let b = Buffer.create 64 in
      let pos =
        List.fold_left
          (fun pos ((s, e), h) ->
            Buffer.add_string b (String.sub psrc pos (s - pos));
            (match h with
             | `Var v ->
               let m = List.assoc v env in
               let t = slice_span src (span_of_expr m) in
               Buffer.add_string b (if is_operator_app m then "(" ^ t ^ ")" else t)
             | `Qualify f -> Buffer.add_string b (Option.get law.l_module ^ "." ^ f));
            e)
          rs holes
      in
      Buffer.add_string b (String.sub psrc pos (re - pos));
      let t = Buffer.contents b in
      Some (if is_operator_app law.l_rhs then "(" ^ t ^ ")" else t)

(* The stdlib lemma manifest: the qualified names it lists are admitted. *)
let stdlib_manifest : (string, unit) Hashtbl.t option ref = ref None

let stdlib_admitted (qname : string) : bool =
  let tbl =
    match !stdlib_manifest with
    | Some t -> t
    | None ->
      let t = Hashtbl.create 32 in
      (match (!Stdlib_cache.stdlib_dir) () with
       | Some dir ->
         let text =
           try In_channel.with_open_bin (Filename.concat dir "lemmas.verified") In_channel.input_all
           with Sys_error _ -> ""
         in
         String.split_on_char '\n' text
         |> List.iter (fun l ->
                if l <> "" && l.[0] <> '#' then
                  match String.split_on_char '\t' l with n :: _ -> Hashtbl.replace t n () | [] -> ())
       | None -> ());
      stdlib_manifest := Some t;
      t
  in
  Hashtbl.mem tbl qname

(** Every rule [a] can use: the open file's, its imported user files', and
    the stdlib's, each with whether it is admitted. *)
let rules (a : t) ~(admitted : string -> bool option) ~(stdlib : Ast.decl list) : law list =
  let own = laws_of ~src:(Some a.src) ~prefix:"" a.decls in
  let imported =
    laws_of ~src:None ~prefix:""
      (List.filter
         (function
           | Ast.DMod (_, _, _, sp) | Ast.DFn (_, sp) -> sp.Ast.file <> a.filename
           | _ -> false)
         a.depot_source_decls)
  in
  let std = laws_of ~src:None ~prefix:"" stdlib in
  List.filter (fun l -> admitted l.l_name = Some true) (own @ imported)
  @ List.filter (fun l -> stdlib_admitted l.l_qname) std

(** The rewrite actions at the cursor: one per admitted rule whose left side
    matches the smallest expression it can, at the cursor.  [admitted] is
    [Refine_diag.lemma_admitted]; [stdlib] the stdlib's declarations. *)
let actions ?(stdlib = []) (a : t) ~line ~character ~(admitted : string -> bool option) :
    Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let src = a.src in
  let laws = rules a ~admitted ~stdlib in
  if laws = [] then []
  else
    List.filter_map
      (fun law ->
        let m e = matches ~psrc:law.l_src ~src law.l_params [] law.l_lhs e in
        match smallest_expr_at a ~line ~character ~pred:(fun e -> m e <> None) with
        | None -> None
        | Some e -> (
          let sp = span_of_expr e in
          (* Not the lemma's own theorem. *)
          if law.l_src == src && sp = span_of_expr law.l_lhs then None
          else
            match Option.bind (m e) (instantiate ~src law) with
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
                   ~title:
                     (Printf.sprintf "Rewrite to `%s` (by the proved lemma `%s`)" text
                        (if law.l_module = None then law.l_name else law.l_qname))
                   ~kind:CodeActionKind.RefactorRewrite
                   ~edit:(WorkspaceEdit.create ~changes:[ (uri, [ edit ]) ] ())
                   ())))
      laws
