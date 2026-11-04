(* Field refinements of an anonymous-record parameter (gap G5 of
   specs/2026-11-04-lemmas-hcr-actors-choreography-design.md).

   `fn f(old : { count : {Int | _ >= 0} })` declared a contract the checker
   never used: an anonymous record has no SMT sort, so `old.count` was
   unreflectable, the refinement sat "below the outermost position"
   (--refine-audit), and neither the callee assumed it nor a caller was
   obliged.  A named record with a refinement on the whole parameter,
   `fn f(old : {OldT | _.count >= 0})`, already works both ways.  So this
   rewrites the first into the second, before anything reads a signature:

   - each such record shape becomes a synthetic record type of the same
     fields with their top-level refinements removed ([synthetic_prefix] ^
     a counter), prepended to the module's declarations;
   - the parameter's type becomes that type refined by the conjunction of
     the field predicates, each over `_.field` (the binder and the field's
     own name both denote it, as [Refine_scope.field_facts] reads them).

   The synthetic types never enter the record-literal shape table when a
   declared type has the same field set ([Refine_scope.collect_ctor_sigs]),
   so a literal that was typed before is typed the same way.  A parameter
   whose record has no refined field, or a refinement below a field's top
   level, is left alone. *)

module A = March_ast.Ast

let synthetic_prefix = "AnonRecord__"

let is_synthetic (name : string) : bool =
  String.length name > String.length synthetic_prefix
  && String.sub name 0 (String.length synthetic_prefix) = synthetic_prefix

let rec strip_linear (t : A.ty) : A.ty =
  match t with A.TyLinear (_, t) -> strip_linear t | t -> t

(* The plain field types and the field predicates over `_`, when at least one
   field is refined at its top level. *)
let split_fields ~(span : A.span) (fs : (A.name * A.ty) list)
  : ((A.name * A.ty) list * A.expr list) option =
  let under = A.EVar { A.txt = "_"; A.span = span } in
  let proj (f : string) = A.EField (under, { A.txt = f; A.span = span }, span) in
  let field_env = List.map (fun ((n : A.name), _) -> (n.A.txt, proj n.A.txt)) fs in
  let plain, preds =
    List.fold_right
      (fun ((n : A.name), t) (plain, preds) ->
        match strip_linear t with
        | A.TyRefine (base, b, pred) ->
          let env = match b with
            | Some { A.txt = "_"; _ } | None -> field_env
            | Some b -> (b.A.txt, proj n.A.txt) :: field_env in
          (* `_` inside the field's predicate is the field itself. *)
          let env = ("_", proj n.A.txt) :: env in
          ((n, base) :: plain, Refine_encode.subst_params env pred :: preds)
        | _ -> ((n, t) :: plain, preds))
      fs ([], [])
  in
  if preds = [] then None else Some (plain, preds)

let conj ~(span : A.span) (ps : A.expr list) : A.expr =
  match ps with
  | [] -> A.ELit (A.LitBool true, span)
  | p :: rest ->
    List.fold_left (fun acc q -> A.EApp (A.EVar { A.txt = "&&"; A.span = span }, [ acc; q ], span)) p rest

let lift (m : A.module_) : A.module_ =
  let synth : (string * (string * A.decl)) list ref = ref [] in   (* shape key -> name, decl *)
  let type_for ~(span : A.span) (plain : (A.name * A.ty) list) : string =
    let key = String.concat ";" (List.map (fun ((n : A.name), t) -> n.A.txt ^ ":" ^ A.show_ty t) plain) in
    match List.assoc_opt key !synth with
    | Some (name, _) -> name
    | None ->
      let name = Printf.sprintf "%s%d" synthetic_prefix (List.length !synth) in
      let fields = List.map (fun (n, t) -> { A.fld_name = n; fld_ty = t; fld_lin = A.Unrestricted }) plain in
      let decl = A.DType (A.Private, { A.txt = name; A.span = span }, [], A.TDRecord fields, span) in
      synth := (key, (name, decl)) :: !synth;
      name
  in
  let lift_ty ~(span : A.span) (t : A.ty) : A.ty option =
    match strip_linear t with
    | A.TyRecord fs ->
      (match split_fields ~span fs with
       | None -> None
       | Some (plain, preds) ->
         let name = type_for ~span plain in
         Some (A.TyRefine (A.TyCon ({ A.txt = name; A.span = span }, []),
                           Some { A.txt = "_"; A.span = span }, conj ~span preds)))
    | _ -> None
  in
  let lift_param (fp : A.fn_param) : A.fn_param =
    match fp with
    | A.FPNamed ({ A.param_ty = Some t; _ } as p) ->
      (match lift_ty ~span:p.A.param_name.A.span t with
       | Some t' -> A.FPNamed { p with A.param_ty = Some t' }
       | None -> fp)
    | A.FPDefault (({ A.param_ty = Some t; _ } as p), d) ->
      (match lift_ty ~span:p.A.param_name.A.span t with
       | Some t' -> A.FPDefault ({ p with A.param_ty = Some t' }, d)
       | None -> fp)
    | _ -> fp
  in
  let rec decls (ds : A.decl list) : A.decl list =
    List.map
      (fun (d : A.decl) ->
        match d with
        | A.DFn (fd, sp) ->
          let clauses = List.map (fun (c : A.fn_clause) ->
              let ps = List.map lift_param c.A.fc_params in
              if List.for_all2 ( == ) ps c.A.fc_params then c else { c with A.fc_params = ps })
              fd.A.fn_clauses in
          if List.for_all2 ( == ) clauses fd.A.fn_clauses then d
          else A.DFn ({ fd with A.fn_clauses = clauses }, sp)
        | A.DMod (n, v, inner, sp) ->
          let inner' = decls inner in
          if List.for_all2 ( == ) inner' inner then d else A.DMod (n, v, inner', sp)
        | d -> d)
      ds
  in
  let ds = decls m.A.mod_decls in
  if !synth = [] then m
  else { m with A.mod_decls = List.rev_map (fun (_, (_, d)) -> d) !synth @ ds }
