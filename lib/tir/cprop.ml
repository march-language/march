(** Constant propagation pass.

    Substitutes known-literal variables and variable aliases into their use
    sites, enabling downstream [Fold] passes to evaluate the resulting literal
    expressions.

    Scope:
    - Propagates variables whose RHS is [EAtom (ALit ...)] (literals — P const)
    - Propagates variables whose RHS is [EAtom (AVar y)] (aliases — P12)
    - Tracks [EAlloc(TCon(...))] bindings and reduces [ECase] on known constructors (P11)
    - Tracks [ERecord] and [EUpdate] bindings so that [EField] accesses on
      known-shape records can be folded to the field's atom directly (P13)
    - Does NOT propagate variables bound to complex expressions (no code dup)
    - Stops at any re-binding of the same name within nested scopes
    - RC positions (EFree/EIncRC/EDecRC/EAtomicIncRC/EAtomicDecRC) are never
      substituted: replacing a heap variable's atom there would corrupt RC state

    P11 — Case-of-known-constructor (Beta-ADT reduction):
        let v = Ok(x) in match v do Ok(w) -> body end  →  body[w := x]
    Fires constantly after inlining Option/Result/let? chains. DCE removes the
    dead EAlloc; orphaned RC ops on [v] are cleaned up by DCE.

    P12 — Variable copy propagation:
        let x = y in ... x ...  →  let x = y in ... y ...
    Fires after every inline call; subst_args creates alias chains
    (let param = arg) that DCE then removes once uses are gone.

    Interaction with Fold:
    This pass runs BEFORE [Fold] in the Opt coordinator so that
        let x = 7 in x + 1
    becomes
        let x = 7 in 7 + 1      (CProp literal)
        → 8                      (Fold, after DCE drops dead let x)

    P13 — EField of known record:
        let r = { x = a, y = b } in r.x  →  a
    The [r] binding is retained. For heap-typed fields, Perceus inserts an
    EIncRC dup via [dup_field_results] — the dup fires through the [v_name]
    alias and RC semantics are preserved. Note: for [TRecord]-typed variables,
    [needs_rc(TRecord) = false] so Perceus places no EDecRC/EFree for [r]
    itself; only the individual heap-typed *fields* are RC-managed.
    [EUpdate] is also tracked: merged fields from the base record are inherited
    so that [let r2 = { r with x = c } in r2.y] folds to [b].
    Record aliases ([let r2 = r]) also propagate the field list.

    Sets [~changed] on any substitution. *)

(** A mapping from variable name to the literal it is bound to. *)
type env = (string * March_ast.Ast.literal) list

let env_add name lit (env : env) : env = (name, lit) :: env

let env_find name (env : env) : March_ast.Ast.literal option =
  List.assoc_opt name env

(** A mapping from variable name to its atom alias (P12 copy propagation).
    Used to propagate [let x = y] into use sites so that DCE can drop [x]. *)
type alias_env = (string * Tir.atom) list

let aenv_add name a (aenv : alias_env) : alias_env = (name, a) :: aenv

let aenv_find name (aenv : alias_env) : Tir.atom option =
  List.assoc_opt name aenv

(** A mapping from variable name to the constructor it is bound to (P11).
    Populated for [EAlloc(TCon(tag, _), args)] bindings.  When an
    [ECase(AVar v, branches, _)] is encountered and [v] is in this env, the
    matching branch is substituted inline and the allocation is eliminated. *)
type ctor_env = (string * (string * Tir.atom list)) list

let cenv_add name tag_args (cenv : ctor_env) : ctor_env = (name, tag_args) :: cenv

let cenv_find name (cenv : ctor_env) : (string * Tir.atom list) option =
  List.assoc_opt name cenv

(** Strip the type-name prefix that lower.ml embeds in EAlloc's TCon key
    ("Result.Ok" → "Ok", "Option.Some" → "Some", "Foo" → "Foo").
    [ECase] branch tags are bare constructor names, so we need to match them
    against the short form. *)
let short_ctor_tag name =
  match String.rindex_opt name '.' with
  | Some i -> String.sub name (i + 1) (String.length name - i - 1)
  | None   -> name

(** A mapping from variable name to the record-field list it is bound to.
    Populated for [ERecord], [EUpdate] on a known base, and [EAtom(AVar base)]
    when [base] has a known field list. *)
type field_env = (string * (string * Tir.atom) list) list

let fenv_add name (fields : (string * Tir.atom) list) (fenv : field_env) : field_env =
  (name, fields) :: fenv

let fenv_find name (fenv : field_env) : (string * Tir.atom) list option =
  List.assoc_opt name fenv

(** Substitute a variable atom if it is bound to a literal in [env] or an
    alias in [aenv] (P12 copy propagation). Literal substitution takes priority. *)
let subst_atom ~changed (env : env) (aenv : alias_env) (a : Tir.atom) : Tir.atom =
  match a with
  | Tir.AVar v ->
    (match env_find v.Tir.v_name env with
     | Some lit -> changed := true; Tir.ALit lit
     | None ->
       match aenv_find v.Tir.v_name aenv with
       | Some alias -> changed := true; alias
       | None       -> a)
  | Tir.ADefRef _ | Tir.ALit _ -> a

let subst_atoms ~changed env aenv atoms =
  List.map (subst_atom ~changed env aenv) atoms

let subst_fields ~changed env aenv fields =
  List.map (fun (k, a) -> (k, subst_atom ~changed env aenv a)) fields

(** Propagate literals, variable aliases, constructor bindings, and record-field
    knowledge through an expression.
    [env]  maps variable names to their literal values.
    [aenv] maps variable names to their atom aliases (P12 copy propagation).
    [cenv] maps variable names to their known constructor (P11 Beta-ADT).
    [fenv] maps variable names to their known record-field lists (P13).
    New bindings are added as they are encountered; re-bindings shadow earlier ones. *)
let rec cprop_expr ~changed (env : env) (aenv : alias_env) (cenv : ctor_env) (fenv : field_env) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a ->
    Tir.EAtom (subst_atom ~changed env aenv a)

  | Tir.EApp (f, args) ->
    Tir.EApp (f, subst_atoms ~changed env aenv args)

  | Tir.ECallPtr (f, args) ->
    Tir.ECallPtr (subst_atom ~changed env aenv f, subst_atoms ~changed env aenv args)

  | Tir.ELet (v, rhs, body) ->
    let rhs' = cprop_expr ~changed env aenv cenv fenv rhs in
    (* Extend literal env when the RHS is a bare literal atom. *)
    let env' = match rhs' with
      | Tir.EAtom (Tir.ALit lit) -> env_add v.Tir.v_name lit env
      | _                        -> env
    in
    (* P12: extend alias env when the RHS is a variable atom.
       ONLY when the binding and the source have the SAME type.  A
       type-changing alias — e.g. [let go : (List(Int),Int)->Int = $clo]
       where [$clo : Ptr(Unit)] is the erased closure parameter of an apply
       function — must NOT be propagated.  Downstream codegen selects an
       indirect-call ABI from the callee atom's static type: calling through
       the typed [go] uses the concrete signature (e.g. [(ptr,ptr,i64)]),
       but calling through [$clo : Ptr(Unit)] falls back to the generic
       all-boxed apply ABI [(ptr,ptr,ptr)], tag-encoding scalar arguments
       that the callee then reads as raw i64 — a silent miscompile
       (List.length of a 3-element list returning 21).  Copy propagation is
       only sound when the copy is type-preserving. *)
    let aenv' = match rhs' with
      | Tir.EAtom (Tir.AVar y) when v.Tir.v_ty = y.Tir.v_ty ->
        aenv_add v.Tir.v_name (Tir.AVar y) aenv
      | _                      -> aenv
    in
    (* P11: track constructor bindings for Beta-ADT reduction.
       lower.ml embeds the parent type in TCon ("Result.Ok"), but br_tag is the
       bare name ("Ok"), so strip the prefix via [short_ctor_tag]. *)
    let cenv' = match rhs' with
      | Tir.EAlloc (Tir.TCon (tag, _), args) ->
        cenv_add v.Tir.v_name (short_ctor_tag tag, args) cenv
      | _ -> cenv
    in
    (* Extend field env for ERecord, EUpdate, and EAtom(AVar) record aliases. *)
    let fenv' = match rhs' with
      | Tir.ERecord fields ->
        fenv_add v.Tir.v_name fields fenv
      | Tir.EAtom (Tir.AVar base) ->
        (* Record alias: let r2 = r. If r has a known field list, copy it. *)
        (match fenv_find base.Tir.v_name fenv with
         | Some fields -> fenv_add v.Tir.v_name fields fenv
         | None        -> fenv)
      | Tir.EUpdate (Tir.AVar base, new_fields) ->
        (* Merge: new_fields override the base record's known fields. *)
        (match fenv_find base.Tir.v_name fenv with
         | Some base_fields ->
           let new_keys = List.map fst new_fields in
           let merged =
             List.filter (fun (k, _) -> not (List.mem k new_keys)) base_fields
             @ new_fields
           in
           fenv_add v.Tir.v_name merged fenv
         | None -> fenv)
      | _ -> fenv
    in
    Tir.ELet (v, rhs', cprop_expr ~changed env' aenv' cenv' fenv' body)

  | Tir.ELetRec (fns, body) ->
    (* Do not propagate outer literals/aliases/constructors into recursive bodies. *)
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = cprop_expr ~changed [] [] [] [] fd.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', cprop_expr ~changed env aenv cenv fenv body)

  | Tir.ECase (a, branches, default) ->
    let a' = subst_atom ~changed env aenv a in
    (* P11: case-of-known-constructor — if scrutinee is a known EAlloc, reduce to
       the matching branch body with br_vars substituted by the constructor args. *)
    let try_beta_adt () =
      match a' with
      | Tir.AVar v ->
        (match cenv_find v.Tir.v_name cenv with
         | Some (ctor_tag, ctor_args) ->
           (match List.find_opt (fun b -> b.Tir.br_tag = ctor_tag) branches with
            | Some b when List.length b.Tir.br_vars = List.length ctor_args ->
              (* Extend aenv with br_vars → ctor_args so the body sees them as aliases. *)
              let aenv_branch =
                List.fold_left2 (fun acc bv arg -> aenv_add bv.Tir.v_name arg acc)
                  aenv b.Tir.br_vars ctor_args
              in
              changed := true;
              Some (cprop_expr ~changed env aenv_branch cenv fenv b.Tir.br_body)
            | _ -> None)
         | None -> None)
      | _ -> None
    in
    (match try_beta_adt () with
     | Some body -> body
     | None ->
       (* Branch bound variables shadow any outer literal/alias/constructor/field binding. *)
       let branches' = List.map (fun b ->
         let bound_names =
           List.fold_left (fun s v -> v.Tir.v_name :: s) [] b.Tir.br_vars in
         let env_branch  = List.filter (fun (n, _) -> not (List.mem n bound_names)) env in
         let aenv_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) aenv in
         let cenv_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) cenv in
         let fenv_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) fenv in
         { b with Tir.br_body = cprop_expr ~changed env_branch aenv_branch cenv_branch fenv_branch b.Tir.br_body }
       ) branches in
       let default' = Option.map (cprop_expr ~changed env aenv cenv fenv) default in
       Tir.ECase (a', branches', default'))

  | Tir.ETuple atoms ->
    Tir.ETuple (subst_atoms ~changed env aenv atoms)

  | Tir.ERecord fields ->
    Tir.ERecord (subst_fields ~changed env aenv fields)

  (* P13: fold EField on a variable whose record shape is known. *)
  | Tir.EField (Tir.AVar v, k) ->
    (match fenv_find v.Tir.v_name fenv with
     | Some fields ->
       (match List.assoc_opt k fields with
        | Some a -> changed := true; Tir.EAtom a
        | None   -> Tir.EField (subst_atom ~changed env aenv (Tir.AVar v), k))
     | None -> Tir.EField (subst_atom ~changed env aenv (Tir.AVar v), k))

  | Tir.EField (a, f) ->
    Tir.EField (subst_atom ~changed env aenv a, f)

  | Tir.EUpdate (a, fields) ->
    Tir.EUpdate (subst_atom ~changed env aenv a, subst_fields ~changed env aenv fields)

  | Tir.EAlloc (ty, args) ->
    Tir.EAlloc (ty, subst_atoms ~changed env aenv args)

  | Tir.EStackAlloc (ty, args) ->
    Tir.EStackAlloc (ty, subst_atoms ~changed env aenv args)

  | Tir.EReuse (token, ty, args) ->
    Tir.EReuse (subst_atom ~changed env aenv token, ty, subst_atoms ~changed env aenv args)

  (* RC operations must NOT have their argument substituted.  Replacing a heap
     var with a literal or alias there would corrupt RC state. *)
  | Tir.EFree a        -> Tir.EFree a
  | Tir.EIncRC a       -> Tir.EIncRC a
  | Tir.EDecRC a       -> Tir.EDecRC a
  | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC a
  | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC a

  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (cprop_expr ~changed env aenv cenv fenv e1, cprop_expr ~changed env aenv cenv fenv e2)

let run_fn ~changed (fd : Tir.fn_def) : Tir.fn_def =
  { fd with Tir.fn_body = cprop_expr ~changed [] [] [] [] fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
