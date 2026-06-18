(** Constant propagation pass.

    Substitutes known-literal variables into their use sites, enabling downstream
    [Fold] passes to evaluate the resulting literal expressions.

    Scope:
    - Propagates variables whose RHS is [EAtom (ALit ...)] (literals only)
    - Tracks [ERecord] and [EUpdate] bindings so that [EField] accesses on
      known-shape records can be folded to the field's atom directly (P13)
    - Does NOT propagate variables bound to complex expressions (no code dup)
    - Does NOT propagate [AVar] variable aliases in the main env — doing so
      risks substituting closure struct names with function references in
      positions where LLVM emit special-cases the variable name (ECallPtr
      dispatch reads the var name for var_slot / top_fn membership checks).
    - Stops at any re-binding of the same name within nested scopes
    - RC positions (EFree/EIncRC/EDecRC/EAtomicIncRC/EAtomicDecRC) are never
      substituted: replacing a heap variable's atom there would corrupt RC state

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

(** A mapping from variable name to the record-field list it is bound to.
    Populated for [ERecord], [EUpdate] on a known base, and [EAtom(AVar base)]
    when [base] has a known field list. *)
type field_env = (string * (string * Tir.atom) list) list

let fenv_add name (fields : (string * Tir.atom) list) (fenv : field_env) : field_env =
  (name, fields) :: fenv

let fenv_find name (fenv : field_env) : (string * Tir.atom) list option =
  List.assoc_opt name fenv

(** Substitute a variable atom if it is bound to a literal in [env]. *)
let subst_atom ~changed (env : env) (a : Tir.atom) : Tir.atom =
  match a with
  | Tir.AVar v ->
    (match env_find v.Tir.v_name env with
     | Some lit -> changed := true; Tir.ALit lit
     | None     -> a)
  | Tir.ADefRef _ | Tir.ALit _ -> a

let subst_atoms ~changed env atoms =
  List.map (subst_atom ~changed env) atoms

let subst_fields ~changed env fields =
  List.map (fun (k, a) -> (k, subst_atom ~changed env a)) fields

(** Propagate literals and record-field knowledge through an expression.
    [env]  maps variable names to their literal values.
    [fenv] maps variable names to their known record-field lists (P13).
    New bindings are added as they are encountered; re-bindings shadow earlier ones. *)
let rec cprop_expr ~changed (env : env) (fenv : field_env) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a ->
    Tir.EAtom (subst_atom ~changed env a)

  | Tir.EApp (f, args) ->
    Tir.EApp (f, subst_atoms ~changed env args)

  | Tir.ECallPtr (f, args) ->
    Tir.ECallPtr (subst_atom ~changed env f, subst_atoms ~changed env args)

  | Tir.ELet (v, rhs, body) ->
    let rhs' = cprop_expr ~changed env fenv rhs in
    (* Extend literal env when the RHS is a bare literal atom. *)
    let env' = match rhs' with
      | Tir.EAtom (Tir.ALit lit) -> env_add v.Tir.v_name lit env
      | _                        -> env
    in
    (* Extend field env for ERecord, EUpdate, and EAtom(AVar) record aliases. *)
    let fenv' = match rhs' with
      | Tir.ERecord fields ->
        (* [rhs'] is already fully substituted by the ERecord arm below, so
           [fields] here is post-substitution — store directly. *)
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
    Tir.ELet (v, rhs', cprop_expr ~changed env' fenv' body)

  | Tir.ELetRec (fns, body) ->
    (* Do not propagate outer literals into recursive function bodies:
       recursive functions may be called from multiple contexts and the
       outer binding is not in scope for the callers.
       Recurse into fn bodies with empty envs for their local lets. *)
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = cprop_expr ~changed [] [] fd.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', cprop_expr ~changed env fenv body)

  | Tir.ECase (a, branches, default) ->
    let a' = subst_atom ~changed env a in
    (* Branch bound variables shadow any outer literal/field binding. *)
    let branches' = List.map (fun b ->
      let bound_names =
        List.fold_left (fun s v -> v.Tir.v_name :: s) [] b.Tir.br_vars in
      let env_branch  = List.filter (fun (n, _) -> not (List.mem n bound_names)) env in
      let fenv_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) fenv in
      { b with Tir.br_body = cprop_expr ~changed env_branch fenv_branch b.Tir.br_body }
    ) branches in
    let default' = Option.map (cprop_expr ~changed env fenv) default in
    Tir.ECase (a', branches', default')

  | Tir.ETuple atoms ->
    Tir.ETuple (subst_atoms ~changed env atoms)

  | Tir.ERecord fields ->
    Tir.ERecord (subst_fields ~changed env fields)

  (* P13: fold EField on a variable whose record shape is known. *)
  | Tir.EField (Tir.AVar v, k) ->
    (match fenv_find v.Tir.v_name fenv with
     | Some fields ->
       (match List.assoc_opt k fields with
        | Some a -> changed := true; Tir.EAtom a
        | None   -> Tir.EField (subst_atom ~changed env (Tir.AVar v), k))
     | None -> Tir.EField (subst_atom ~changed env (Tir.AVar v), k))

  | Tir.EField (a, f) ->
    Tir.EField (subst_atom ~changed env a, f)

  | Tir.EUpdate (a, fields) ->
    Tir.EUpdate (subst_atom ~changed env a, subst_fields ~changed env fields)

  | Tir.EAlloc (ty, args) ->
    Tir.EAlloc (ty, subst_atoms ~changed env args)

  | Tir.EStackAlloc (ty, args) ->
    Tir.EStackAlloc (ty, subst_atoms ~changed env args)

  | Tir.EReuse (token, ty, args) ->
    Tir.EReuse (subst_atom ~changed env token, ty, subst_atoms ~changed env args)

  (* RC operations must NOT have their argument substituted.  For literals:
     replacing a heap var with a literal in EDecRC would free a non-heap value.
     Replacing with a variable alias could also cause double-decrement of the
     aliased value's reference count when Perceus placed RC ops for both names. *)
  | Tir.EFree a        -> Tir.EFree a
  | Tir.EIncRC a       -> Tir.EIncRC a
  | Tir.EDecRC a       -> Tir.EDecRC a
  | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC a
  | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC a

  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (cprop_expr ~changed env fenv e1, cprop_expr ~changed env fenv e2)

let run_fn ~changed (fd : Tir.fn_def) : Tir.fn_def =
  { fd with Tir.fn_body = cprop_expr ~changed [] [] fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
