(** The [--check-migration] tool: verify actor `migrate_state` soundness.

    Lifted verbatim out of [bin/main.ml] (Target A, task A3 of
    [specs/plans/2026-08-27-remaining-decomposition-targets.md]).  This is a
    standalone actor-schema diffing tool that merely happened to be reachable
    through [compile]'s arm cascade: it shares nothing with the compile
    pipeline but the parsed AST, and both of its exits leave the process.

    Its inputs are the three --check-migration flags (from [Flags]) plus the
    source text and the desugared module, which are [run]'s two parameters.

    The body keeps [compile]'s original indentation: OCaml is insensitive to
    it, and re-indenting would forfeit the byte-for-byte motion proof. *)

open Flags

(* ------------------------------------------------------------------ *)
(* Gap #3: --check-migration helpers                                   *)
(* ------------------------------------------------------------------ *)

let parse_pred (src : string) : March_ast.Ast.expr option =
  let lb = Lexing.from_string src in
  match March_parser.Parse.expr_of_lexbuf lb with
  | e -> Some e
  | exception _ -> None

(* Convert a schema type string back to an AST type.
   Inverse of the ty_to_schema_str function that writes .schemas.json. *)
let rec schema_str_to_ty (s : string) : March_ast.Ast.ty =
  let module A = March_ast.Ast in
  let sp = A.dummy_span in
  let con name args = A.TyCon ({ A.txt = name; A.span = sp }, args) in
  match s with
  | "Int"    -> con "Int"    []
  | "Bool"   -> con "Bool"   []
  | "String" -> con "String" []
  | "Float"  -> con "Float"  []
  | _ when String.length s > 5 && String.sub s 0 5 = "List(" ->
    let inner = String.sub s 5 (String.length s - 6) in
    con "List" [schema_str_to_ty inner]
  | other -> con other []

(* Synthesise a fake DType for the prior-version state shape (called RawRecord)
   from the field list in the prior .schemas.json.  This lets register_types_for_check
   see the selectors so check_post can reflect old.field projections in inv_old. *)
let make_rawrecord_decl (prior_fields : March_forge.Schema_diff.field list) : March_ast.Ast.decl =
  let module A = March_ast.Ast in
  let sp = A.dummy_span in
  let ast_fields = List.map (fun (f : March_forge.Schema_diff.field) ->
      { A.fld_name = { A.txt = f.March_forge.Schema_diff.name; A.span = sp };
        A.fld_ty   = schema_str_to_ty f.March_forge.Schema_diff.ty;
        A.fld_lin  = A.Unrestricted })
    prior_fields
  in
  A.DType (A.Public, { A.txt = "RawRecord"; A.span = sp },
           [], A.TDRecord ast_fields, sp)

(* Synthesise a DType named "State" from the NEW actor schema fields so
   register_types_for_check can build SMT selectors for the return type. *)
let make_newstate_decl (new_fields : March_forge.Schema_diff.field list) : March_ast.Ast.decl =
  let module A = March_ast.Ast in
  let sp = A.dummy_span in
  let ast_fields = List.map (fun (f : March_forge.Schema_diff.field) ->
      { A.fld_name = { A.txt = f.March_forge.Schema_diff.name; A.span = sp };
        A.fld_ty   = schema_str_to_ty f.March_forge.Schema_diff.ty;
        A.fld_lin  = A.Unrestricted })
    new_fields
  in
  A.DType (A.Public, { A.txt = "State"; A.span = sp },
           [], A.TDRecord ast_fields, sp)

(* Search the desugared AST for the migration fn for a named actor.
   Convention (from TIR/llvm_emit): user writes `fn {actor_lower}_migrate_state`
   as a top-level DFn; TIR picks it up by suffix and exports @__migrate_<Actor>.
   We match any DFn whose name ends with "_migrate_state" and whose last
   dotted component before the suffix equals lowercase(actor) — see
   [March_tir.Tir_names.is_migrate_fn_for]. *)
let find_migrate_fn (actor : string) (decls : March_ast.Ast.decl list)
    : March_ast.Ast.fn_def option =
  let module A = March_ast.Ast in
  let rec walk = function
    | [] -> None
    | d :: rest ->
      let found = match d with
        | A.DFn (fd, _) when
            March_tir.Tir_names.is_migrate_fn_for ~actor fd.A.fn_name.A.txt ->
          Some fd
        | A.DMod (_, _, inner, _) -> walk inner
        | _ -> None
      in
      (match found with Some _ -> found | None -> walk rest)
  in
  walk decls

(* Rewrite bare field-name EVar references to EField projections so smt_of
   can emit SMT selectors.  @invariant predicates use bare names — e.g.
   `count >= 0` has EVar "count", not EField(EVar "s", "count").
   We also handle the case where the user wrote `state.count` — an existing
   EField whose receiver is renamed to the canonical binder. *)
let qualify_bare_field_refs
    (binder : string) (field_names : string list)
    (e : March_ast.Ast.expr) : March_ast.Ast.expr =
  let module A = March_ast.Ast in
  let rec go e = match e with
    | A.EVar v when List.mem v.A.txt field_names ->
      A.EField (A.EVar { v with A.txt = binder }, v, v.A.span)
    | A.EField (A.EVar v, f, sp) ->
      A.EField (A.EVar { v with A.txt = binder }, f, sp)
    | A.EField (base, f, sp) -> A.EField (go base, f, sp)
    | A.EApp (f, args, sp)  -> A.EApp (go f, List.map go args, sp)
    | other -> other
  in go e

(* Patch a migrate_state fn_def with refined param/return types for the VC.
   - First param gets type  { s : RawRecord | inv_old(s) }
   - Return type becomes    { v : State      | inv_new(v) }
   prior_field_names and new_field_names are used to rewrite bare field-name
   EVar refs to EField projections before SMT reflection. *)
let patch_migrate_fn (fd : March_ast.Ast.fn_def)
    ~(inv_old : March_ast.Ast.expr) ~(inv_new : March_ast.Ast.expr)
    ~(state_name : string)
    ~(prior_field_names : string list)
    ~(new_field_names   : string list) : March_ast.Ast.fn_def =
  let module A = March_ast.Ast in
  let sp = fd.A.fn_name.A.span in
  let rawrec_ty = A.TyCon ({ A.txt = "RawRecord"; A.span = sp }, []) in
  let state_ty  = A.TyCon ({ A.txt = state_name;  A.span = sp }, []) in
  let mk_binder name = Some { A.txt = name; A.span = sp } in
  let inv_old = qualify_bare_field_refs "s" prior_field_names inv_old in
  let inv_new = qualify_bare_field_refs "v" new_field_names   inv_new in
  let patch_clause (c : A.fn_clause) =
    let params = match c.A.fc_params with
      | [] -> []
      | fp :: rest ->
        (match fp with
         | A.FPNamed p | A.FPDefault (p, _) ->
           let refined = A.TyRefine (rawrec_ty, mk_binder "s", inv_old) in
           let p' = { p with A.param_ty = Some refined } in
           (match fp with
            | A.FPNamed _ -> A.FPNamed p'
            | A.FPDefault (_, def) -> A.FPDefault (p', def)
            | A.FPPat _ -> fp)
           :: rest
         | A.FPPat _ -> fp :: rest)
    in
    { c with A.fc_params = params }
  in
  let ret_ty = A.TyRefine (state_ty, mk_binder "v", inv_new) in
  { fd with
    A.fn_clauses = List.map patch_clause fd.A.fn_clauses;
    A.fn_ret_ty  = Some ret_ty }

(* ------------------------------------------------------------------ *)
(* The deploy gate's laws (specs/todos/2026-11-04-hcr-refinement-     *)
(* strengthening-unchecked.md, design §3.3)                            *)
(* ------------------------------------------------------------------ *)

(* What one law came to.  Only [Proved] passes on its own; [Unproved] and
   [Unchecked] pass when the law is named in --accept-unproved; [Refuted]
   never does. *)
type verdict =
  | Proved of string            (* how: "proved", "unchanged" *)
  | Refuted
  | Unproved of string          (* the implication that was not shown *)
  | Unchecked of string         (* why it could not be checked *)

let conj (ps : March_ast.Ast.expr list) : March_ast.Ast.expr option =
  let module A = March_ast.Ast in
  match ps with
  | [] -> None
  | p :: rest ->
    Some (List.fold_left (fun acc q ->
        A.EApp (A.EVar { A.txt = "&&"; A.span = A.dummy_span }, [ acc; q ], A.dummy_span))
        p rest)

(* An actor's state contract: its @invariant and its fields' refinements,
   all predicates over the bare field names.  [Error] when a predicate does
   not parse back. *)
let state_contract (s : March_forge.Schema_diff.actor_schema)
    : (string list * March_ast.Ast.expr list, string) result =
  let module Sd = March_forge.Schema_diff in
  let texts =
    Option.to_list s.Sd.invariant
    @ List.filter_map (fun (f : Sd.field) -> f.Sd.refine) s.Sd.state_fields in
  let parsed = List.map (fun t -> (t, parse_pred t)) texts in
  match List.find_opt (fun (_, p) -> p = None) parsed with
  | Some (t, _) -> Error (Printf.sprintf "the predicate `%s` does not parse" t)
  | None -> Ok (List.sort_uniq compare texts, List.filter_map snd parsed)

(* Rename the free variable [x] to [y]: the grammar the schema writer emits
   (variables, fields, applications, literals). *)
let rec rename_var x y (e : March_ast.Ast.expr) : March_ast.Ast.expr =
  let module A = March_ast.Ast in
  match e with
  | A.EVar v when v.A.txt = x -> A.EVar { v with A.txt = y }
  | A.EField (b, f, sp) -> A.EField (rename_var x y b, f, sp)
  | A.EApp (f, args, sp) -> A.EApp (f, List.map (rename_var x y) args, sp)
  | other -> other

(* [fn <name>(f1 : T1, ..., fn : Tn, w : {Int | old}) : {r : Int | new} do w end]:
   the identity migration a deploy without a migrate_state performs, stated
   over the fields as scalars.  The field-set record form is ambiguous to
   the checker here: a synthesised literal has no typechecker type, and the
   actor's own state sort has the same field set as [State]. *)
let identity_contract_fn (name : string) (fields : March_forge.Schema_diff.field list)
    (old_c : March_ast.Ast.expr) (new_c : March_ast.Ast.expr) : March_ast.Ast.fn_def =
  let module A = March_ast.Ast in
  let module Sd = March_forge.Schema_diff in
  let sp = A.dummy_span in
  let n s = { A.txt = s; A.span = sp } in
  let int_ty = A.TyCon (n "Int", []) in
  let w = "hcr$old" in
  let params =
    List.map (fun (f : Sd.field) ->
        A.FPNamed { A.param_name = n f.Sd.name; param_ty = Some (schema_str_to_ty f.Sd.ty);
                    param_lin = A.Unrestricted }) fields
    @ [ A.FPNamed { A.param_name = n w;
                    param_ty = Some (A.TyRefine (int_ty, Some (n "_"), old_c));
                    param_lin = A.Unrestricted } ] in
  { A.fn_name = n name; fn_vis = A.Public; fn_doc = None; fn_attrs = [];
    fn_ret_ty = Some (A.TyRefine (int_ty, Some (n "hcr$r"), new_c));
    fn_clauses =
      [ { A.fc_params = params; fc_guard = None; fc_body = A.EVar (n w);
          fc_span = sp; fc_params_span = sp } ];
    fn_bounds = []; fn_attr_args = []; fn_needs = None }

(* [fn <name>(p0 : {T0 | old0}, ...) : {Ti | new_i} do p_i end]: handler
   parameter [i]'s new refinement must follow from the running version's
   refinements, because a queued message, or one an old-epoch sender builds,
   was only ever checked against those. *)
let param_variance_fn (name : string) (tys : string list)
    (old_r : March_ast.Ast.expr option list) (i : int) (new_r : March_ast.Ast.expr)
    : March_ast.Ast.fn_def =
  let module A = March_ast.Ast in
  let sp = A.dummy_span in
  let n s = { A.txt = s; A.span = sp } in
  let pn j = Printf.sprintf "p%d" j in
  let params = List.mapi (fun j t ->
      let base = schema_str_to_ty t in
      let ty = match List.nth_opt old_r j with
        | Some (Some r) -> A.TyRefine (base, Some (n "_"), rename_var (pn j) "_" r)
        | _ -> base in
      A.FPNamed { A.param_name = n (pn j); param_ty = Some ty; param_lin = A.Unrestricted })
      tys in
  { A.fn_name = n name; fn_vis = A.Public; fn_doc = None; fn_attrs = [];
    fn_ret_ty = Some (A.TyRefine (schema_str_to_ty (List.nth tys i), Some (n "v"),
                                  rename_var (pn i) "v" new_r));
    fn_clauses =
      [ { A.fc_params = params; fc_guard = None; fc_body = A.EVar (n (pn i));
          fc_span = sp; fc_params_span = sp } ];
    fn_bounds = []; fn_attr_args = []; fn_needs = None }

let run ~(src : string) ~(desugared : March_ast.Ast.module_) : unit =
    if !prior_schema_path = "" || !new_schema_path = "" then begin
      Printf.eprintf "error: --check-migration requires --prior-schema and --new-schema\n";
      exit 2
    end;
    let module A  = March_ast.Ast in
    let module Rc = March_refinecheck.Refine_check in
    let module Sd = March_forge.Schema_diff in

    let prior_schemas = Sd.parse_schemas_file !prior_schema_path in
    let new_schemas   = Sd.parse_schemas_file !new_schema_path   in
    let root = Sys.getcwd () in
    let results : (string * verdict) list ref = ref [] in
    let diags = ref [] in
    let note law v = results := (law, v) :: !results in

    (* One synthesised function's postcondition, in its own error context so
       a counterexample is told apart from an undecided query. *)
    let verify ~(shows : string) (fd : A.fn_def) : verdict =
      let ctx = March_errors.Errors.create () in
      let proved = Rc.check_fn_post_verdict ~root ctx fd in
      diags := !diags @ March_errors.Errors.sorted ctx;
      if March_errors.Errors.has_errors ctx then Refuted
      else if proved then Proved "proved" else Unproved shows
    in

    List.iter (fun (actor_name, (new_s : Sd.actor_schema)) ->
      match List.assoc_opt actor_name prior_schemas with
      | None -> ()   (* a new actor: no live state, no queued messages *)
      | Some (old_s : Sd.actor_schema) ->
        let state_law = actor_name ^ ".state" in
        let new_has_refines =
          List.exists (fun (f : Sd.field) -> f.Sd.refine <> None) new_s.Sd.state_fields
          || List.exists (fun (h : Sd.ctor) -> List.exists Option.is_some h.Sd.refines)
               (Option.value ~default:[] new_s.Sd.handlers) in
        if new_s.Sd.unsupported || old_s.Sd.unsupported then
          note actor_name
            (Unchecked "a refinement or @invariant of this actor could not be recorded in its schema")
        else if new_has_refines && not old_s.Sd.contracts then
          note actor_name
            (Unchecked "the running version's schema predates refinement recording, so \
                        what it guaranteed is unknown")
        else begin
          (* ── The state: old contract ⇒ new contract ── *)
          (match state_contract old_s, state_contract new_s with
           | Error why, _ | _, Error why -> note state_law (Unchecked why)
           | Ok (old_t, old_ps), Ok (new_t, new_ps) ->
             if new_ps = [] then ()
             else if old_t = new_t
                     && old_s.Sd.state_fields = new_s.Sd.state_fields then
               note state_law (Proved "unchanged")
             else begin
               let prior_fields = old_s.Sd.state_fields in
               let new_fields = new_s.Sd.state_fields in
               let same_shape =
                 List.map (fun (f : Sd.field) -> (f.Sd.name, f.Sd.ty)) prior_fields
                 = List.map (fun (f : Sd.field) -> (f.Sd.name, f.Sd.ty)) new_fields in
               let inv_old = Option.value (conj old_ps)
                   ~default:(A.ELit (A.LitBool true, A.dummy_span)) in
               let inv_new = Option.get (conj new_ps) in
               let shows = Printf.sprintf "%s implies %s"
                   (match old_t with [] -> "true" | ts -> String.concat " && " ts)
                   (String.concat " && " new_t) in
               match find_migrate_fn actor_name desugared.A.mod_decls with
               | Some fd ->
                 (* Register both RawRecord (prior shape) and State (new shape) so
                    refine_check can build SMT selectors for both param and return
                    field projections.  Actors use inline state, not DType, so
                    these declarations must be synthesised here. *)
                 let extra_decls = [make_rawrecord_decl prior_fields] in
                 Rc.register_adt_names extra_decls;
                 Rc.register_field_sorts extra_decls;
                 let patched = patch_migrate_fn fd ~inv_old ~inv_new
                     ~state_name:actor_name
                     ~prior_field_names:(List.map (fun (f : Sd.field) -> f.Sd.name) prior_fields)
                     ~new_field_names:(List.map (fun (f : Sd.field) -> f.Sd.name) new_fields) in
                 note state_law (verify ~shows patched)
               | None when same_shape ->
                 note state_law
                   (verify ~shows
                      (identity_contract_fn
                         (String.lowercase_ascii actor_name ^ "_hcr_identity")
                         new_fields inv_old inv_new))
               | None -> ()   (* the compat gate answers a shape change *)
             end);
          (* ── Handler parameters: old refinement ⇒ new refinement ── *)
          match old_s.Sd.handlers, new_s.Sd.handlers with
          | Some old_h, Some new_h ->
            let changed = Sd.messages_changed ~old_h ~new_h in
            List.iter (fun (h : Sd.ctor) ->
                if List.exists Option.is_some h.Sd.refines then begin
                  let law = actor_name ^ "." ^ h.Sd.cname in
                  if changed then begin
                    (* Every old-format message is converted by migrate_msg (or
                       dropped without one); nothing reaches this handler
                       unconverted. *)
                    if new_s.Sd.migrate_msg_from <> None then
                      note law (Unchecked "migrate_msg's results are not yet checked \
                                           against the new handler's refinements")
                  end else
                    match List.find_opt (fun (o : Sd.ctor) -> o.Sd.cname = h.Sd.cname) old_h with
                    | None -> ()   (* a new handler: no message was built for it *)
                    | Some o ->
                      let parse_all rs = List.map (Option.map parse_pred) rs in
                      let old_r = parse_all o.Sd.refines and new_r = parse_all h.Sd.refines in
                      if List.exists (function Some None -> true | _ -> false) (old_r @ new_r)
                      then note law (Unchecked "a handler refinement does not parse")
                      else
                        let old_r = List.map Option.join old_r in
                        let old_text i = Option.join (List.nth_opt o.Sd.refines i) in
                        List.iteri (fun i r ->
                            match Option.join r with
                            | None -> ()   (* unrefined: nothing is assumed of it *)
                            | Some _ when old_text i = List.nth h.Sd.refines i ->
                              note law (Proved "unchanged")
                            | Some p ->
                              let fd = param_variance_fn
                                  (Printf.sprintf "%s_hcr_%s_p%d"
                                     (String.lowercase_ascii actor_name) h.Sd.cname i)
                                  h.Sd.params old_r i p in
                              let shows = Printf.sprintf "parameter %d: %s implies %s" i
                                  (Option.value (old_text i) ~default:"true")
                                  (Option.value (List.nth h.Sd.refines i) ~default:"true") in
                              note law (verify ~shows fd))
                          new_r
                end)
              new_h
          | _ -> ()
        end
    ) new_schemas;

    (* One line per law, then the diagnostics behind any that failed. *)
    let accepted law =
      let actor = match String.index_opt law '.' with
        | Some i -> String.sub law 0 i | None -> law in
      let rest = if String.length law > String.length actor
        then String.sub law (String.length actor + 1)
            (String.length law - String.length actor - 1) else "" in
      (* Named on this command line, or built into the new image with
         --accept-unproved, which is the override the server audits. *)
      List.mem law !accept_unproved || List.mem actor !accept_unproved
      || (match List.assoc_opt actor new_schemas with
          | Some (s : Sd.actor_schema) -> List.mem "*" s.accepted || List.mem rest s.accepted
          | None -> false) in
    let failed = ref false in
    let worst = Hashtbl.create 8 in
    List.iter (fun (law, v) ->
        (* A law checked more than once (one handler, several parameters)
           reports its weakest result. *)
        let rank = function Refuted -> 3 | Unchecked _ -> 2 | Unproved _ -> 1 | Proved _ -> 0 in
        match Hashtbl.find_opt worst law with
        | Some w when rank w >= rank v -> ()
        | _ -> Hashtbl.replace worst law v)
      (List.rev !results);
    let laws = List.sort_uniq compare (List.map fst !results) in
    List.iter (fun law ->
        let v = Hashtbl.find worst law in
        let line = match v with
          | Proved how -> Printf.sprintf "%s: %s" law how
          | Refuted -> failed := true; Printf.sprintf "%s: REFUSED, a counterexample exists" law
          | Unproved shows when accepted law ->
            Printf.sprintf "%s: not proved that %s; accepted by --accept-unproved" law shows
          | Unproved shows -> failed := true;
            Printf.sprintf "%s: REFUSED, not proved that %s (the running version's \
                            contract must imply the new one; pass --accept-unproved %s \
                            to deploy anyway)" law shows law
          | Unchecked why when accepted law ->
            Printf.sprintf "%s: not checked (%s), accepted by --accept-unproved" law why
          | Unchecked why -> failed := true;
            Printf.sprintf "%s: REFUSED, not checked: %s (pass --accept-unproved %s to deploy anyway)"
              law why law
        in
        Printf.eprintf "migration: %s\n" line)
      laws;
    if !failed then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
          Printf.eprintf "%s\n\n" (March_errors.Errors.render_diagnostic ~src d))
        !diags;
      exit 1
    end else
      exit 0
