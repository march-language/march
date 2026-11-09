(** The last deployed build's actor contracts, as hypotheses for this build's
    hot-reload migrations (lemmas design §3.4, H1/H2; phase A).

    A `<actor>_migrate_state` runs on a state the DEPLOYED build kept, and a
    `<actor>_migrate_msg` on a message the deployed build accepted.  Whatever
    that build's contract guaranteed of them is therefore a fact about the
    migration's input, even where the migration's own parameter type does not
    say it (`old : { count : Int }` written for a deployed
    `count : {Int | _ >= 0}`).  Without it, a correct migration fails to prove
    and the counterexample search ([Witness.confirm_migration]) produces an
    input the runtime can never hand over.

    The driver fills [baseline] from the deployed `.schemas.json` (forge keeps
    it as `.march/<name>_hot.so.schemas.json.prev`); empty means "no deploy
    known", and every migration is checked against its declared parameter type
    alone, as before.

    Two uses:
    - [strengthen] adds each deployed state field refinement (and each
      @invariant conjunct that mentions one field) to the matching field of a
      migrate_state's anonymous-record parameter, where gap G5's lifting makes
      it an SMT hypothesis and [Witness.satisfies] an admissibility check.  A
      field the user already refined is left as written; a named-record
      parameter is not rewritten.
    - [handler_refines] gives the deployed handler refinements for a message
      constructor, which [Witness.confirm_migration] requires of a generated
      old message.  These are not SMT hypotheses: the match binder of
      `V1.Bump(n)` gets none (residual). *)

module A = March_ast.Ast

type actor = {
  field_names : string list;  (** every state field of the deployed build *)
  fields : (string * A.expr) list;
      (** field name -> deployed predicate over the bare field names *)
  handlers : (string * A.expr option list) list;
      (** message constructor -> per-parameter predicate over `p0`, `p1`, … *)
}

let baseline : (string * actor) list ref = ref []

(** The `<actor>_migrate_state` functions the compiler derived
    (Desugar_migrate_derive, M11), with where each state field is declared.
    A counterexample to one is reported at the field, in words that say the
    user did not write the function.  Filled by the driver. *)
let derived : (string * (string * A.span) list) list ref = ref []

let ends_with ~suffix s =
  let n = String.length s and k = String.length suffix in
  n > k && String.sub s (n - k) k = suffix

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

(* The deployed actor a migration belongs to: the baseline entry whose
   lowercased name is the function's prefix (`tally_migrate_state` →
   `Tally`), the convention [Tir_names.is_migrate_fn_for] states. *)
let actor_of_migration (fn_name : string) : actor option =
  let strip sfx =
    if ends_with ~suffix:sfx fn_name then
      Some (String.sub fn_name 0 (String.length fn_name - String.length sfx))
    else None
  in
  match strip "_migrate_state", strip "_migrate_msg" with
  | Some p, _ | None, Some p ->
    let p = last_segment p in
    List.find_map
      (fun (name, a) ->
        if String.lowercase_ascii (last_segment name) = p then Some a else None)
      !baseline
  | None, None -> None

(* The variables an expression mentions (heads of applications excluded). *)
let rec vars acc (e : A.expr) =
  match e with
  | A.EVar { A.txt; _ } -> txt :: acc
  | A.EApp (A.EVar _, xs, _) -> List.fold_left vars acc xs
  | A.EApp (f, xs, _) -> List.fold_left vars (vars acc f) xs
  | A.EField (r, _, _) -> vars acc r
  | A.ECon (_, xs, _) | A.ETuple (xs, _) -> List.fold_left vars acc xs
  | _ -> acc

let rec conjuncts (e : A.expr) =
  match e with
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> conjuncts a @ conjuncts b
  | e -> [ e ]

let conj = function
  | [] -> None
  | p :: ps ->
    Some
      (List.fold_left
         (fun acc q -> A.EApp (A.EVar { A.txt = "&&"; A.span = A.dummy_span }, [ acc; q ], A.dummy_span))
         p ps)

(* The deployed facts about each field, each one a predicate over that field's
   bare name and nothing else. *)
let field_facts (a : actor) : (string * A.expr) list =
  let names = a.field_names in
  let single p =
    match List.sort_uniq compare (List.filter (fun v -> List.mem v names) (vars [] p)) with
    | [ f ] -> Some (f, p)
    | _ -> None
  in
  let facts = List.concat_map (fun (_, p) -> List.filter_map single (conjuncts p)) a.fields in
  List.filter_map
    (fun f ->
      match List.filter_map (fun (g, p) -> if g = f then Some p else None) facts with
      | [] -> None
      | ps -> Option.map (fun p -> (f, p)) (conj ps))
    names

let strengthen_fn (fd : A.fn_def) : A.fn_def =
  if not (ends_with ~suffix:"_migrate_state" fd.A.fn_name.A.txt) then fd
  else
    match actor_of_migration fd.A.fn_name.A.txt with
    | None -> fd
    | Some a ->
      let facts = field_facts a in
      if facts = [] then fd
      else
        let field_ty (f : A.name) (t : A.ty) =
          match t, List.assoc_opt f.A.txt facts with
          | A.TyRefine _, _ | _, None -> t
          | t, Some p -> A.TyRefine (t, Some { A.txt = f.A.txt; A.span = A.dummy_span }, p)
        in
        let param = function
          | A.FPNamed ({ A.param_ty = Some (A.TyRecord fs); _ } as p) ->
            A.FPNamed
              { p with A.param_ty = Some (A.TyRecord (List.map (fun (f, t) -> (f, field_ty f t)) fs)) }
          | fp -> fp
        in
        { fd with
          A.fn_clauses =
            List.map (fun c -> { c with A.fc_params = List.map param c.A.fc_params }) fd.A.fn_clauses }

let strengthen (m : A.module_) : A.module_ =
  if !baseline = [] then m
  else
    let rec decls ds =
      List.map
        (function
          | A.DFn (fd, sp) -> A.DFn (strengthen_fn fd, sp)
          | A.DMod (n, v, inner, sp) -> A.DMod (n, v, decls inner, sp)
          | d -> d)
        ds
    in
    { m with A.mod_decls = decls m.A.mod_decls }

(* The deployed refinements of message constructor [ctor] of the actor
   [fn_name] migrates, if the baseline records it. *)
let handler_refines ~(fn_name : string) ~(ctor : string) : A.expr option list option =
  match actor_of_migration fn_name with
  | None -> None
  | Some a -> List.assoc_opt (last_segment ctor) a.handlers
