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
  match March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lb with
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
    let mig_errctx    = March_errors.Errors.create () in
    let any_error     = ref false in

    List.iter (fun (actor_name, new_schema) ->
      match new_schema.Sd.invariant with
      | None -> ()   (* actor has no @invariant — nothing to verify *)
      | Some inv_new_str ->
        let inv_old_str = match List.assoc_opt actor_name prior_schemas with
          | Some s -> Option.value s.Sd.invariant ~default:"true"
          | None   -> "true"
        in
        let inv_old_opt = parse_pred inv_old_str in
        let inv_new_opt = parse_pred inv_new_str in
        (match inv_old_opt, inv_new_opt with
        | None, _ | _, None -> ()   (* unparseable predicate: conservatively accept *)
        | Some inv_old, Some inv_new ->
          let prior_fields = match List.assoc_opt actor_name prior_schemas with
            | Some s -> s.Sd.state_fields | None -> [] in
          let new_fields = new_schema.Sd.state_fields in
          (* Register both RawRecord (prior shape) and State (new shape) so
             refine_check can build SMT selectors for both param and return
             field projections.  Actors use inline state, not DType, so
             these declarations must be synthesised here.
             register_adt_names / register_field_sorts ADD to the tables already
             populated by the earlier check_module call; that is exactly what we
             want — the synthesised types are simply two extra ADTs. *)
          let extra_decls =
            [make_rawrecord_decl prior_fields; make_newstate_decl new_fields] in
          Rc.register_adt_names extra_decls;
          Rc.register_field_sorts extra_decls;
          (match find_migrate_fn actor_name desugared.A.mod_decls with
          | None -> ()   (* no migrate_state for this actor — nothing to verify *)
          | Some fd ->
            let prior_field_names =
              List.map (fun (f : Sd.field) -> f.Sd.name) prior_fields in
            let new_field_names =
              List.map (fun (f : Sd.field) -> f.Sd.name) new_fields in
            let patched = patch_migrate_fn fd ~inv_old ~inv_new
                            ~state_name:"State"
                            ~prior_field_names ~new_field_names in
            Rc.check_fn_post ~root:(Sys.getcwd ()) mig_errctx patched;
            if March_errors.Errors.has_errors mig_errctx then
              any_error := true))
    ) new_schemas;

    if !any_error then begin
      let diags = March_errors.Errors.sorted mig_errctx in
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
          Printf.eprintf "%s\n\n"
            (March_errors.Errors.render_diagnostic ~src d))
        diags;
      exit 1
    end else
      exit 0