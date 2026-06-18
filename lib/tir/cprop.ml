(** Constant propagation pass.

    Substitutes known-literal variables into their use sites, enabling downstream
    [Fold] passes to evaluate the resulting literal expressions.

    Scope:
    - P12 — Variable copy propagation: propagates [let x = y] (variable alias)
      into use sites, allowing DCE to remove the dead binding. Only propagates
      non-closure aliases ([TFn] and [TVar] typed variables are excluded because
      ECallPtr dispatch in llvm_emit is name-sensitive for closures).
    - Propagates variables whose RHS is [EAtom (ALit ...)] (literals only)
    - Tracks [ERecord] and [EUpdate] bindings so that [EField] accesses on
      known-shape records can be folded to the field's atom directly (P13)
    - Does NOT propagate [ADefRef] references or closure-typed ([TFn]/[TVar])
      aliases — llvm_emit's ECallPtr dispatch special-cases those names via
      [top_fns] membership and [var_slot] lookups
    - Stops at any re-binding of the same name within nested scopes
    - RC positions (EFree/EIncRC/EDecRC/EAtomicIncRC/EAtomicDecRC) are never
      substituted: replacing a heap variable's atom there would corrupt RC state

    Interaction with Fold:
    This pass runs BEFORE [Fold] in the Opt coordinator so that
        let x = 7 in x + 1
    becomes
        let x = 7 in 7 + 1      (CProp literal)
        → 8                      (Fold, after DCE drops dead let x)

    P12 — Variable copy propagation:
        let x = y in x + 1   →   y + 1
    Fires after every inline call ([subst_args] in [inline.ml] produces alias
    chains [let param_i = arg in ...]); lets DCE remove the dead bindings and
    enables Fold to make progress in cascaded inline→fold chains.
    Closure aliases excluded (see above).

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

(** A mapping from variable name to the aliased variable (P12).
    Only populated for non-closure aliases ([TFn]/[TVar] excluded). *)
type avar_env = (string * Tir.var) list

(** True when a type is a closure type.
    After defunctionalization, closures have type [TFn] or [TVar].
    Aliases of closure-typed variables must NOT be propagated: ECallPtr
    dispatch in llvm_emit is name-sensitive (top_fns / var_slot lookups). *)
let is_closure_ty = function
  | Tir.TFn _ | Tir.TVar _ -> true
  | _ -> false

let avar_add name (y : Tir.var) (env : avar_env) : avar_env = (name, y) :: env

let avar_find name (env : avar_env) : Tir.var option =
  List.assoc_opt name env

(** A mapping from variable name to the record-field list it is bound to.
    Populated for [ERecord], [EUpdate] on a known base, and [EAtom(AVar base)]
    when [base] has a known field list. *)
type field_env = (string * (string * Tir.atom) list) list

let fenv_add name (fields : (string * Tir.atom) list) (fenv : field_env) : field_env =
  (name, fields) :: fenv

let fenv_find name (fenv : field_env) : (string * Tir.atom) list option =
  List.assoc_opt name fenv

(** Substitute a variable atom.
    1. If bound to a literal in [env], return the literal.
    2. If bound to another variable in [avar_env] (and [~allow_avar] is true),
       return that variable.
    3. Otherwise return [a] unchanged.
    [~allow_avar:false] is used for positions where name-sensitive dispatch
    could break (ECallPtr function argument). *)
let subst_atom ?(allow_avar = true) ~changed (env : env) (avar : avar_env) (a : Tir.atom)
    : Tir.atom =
  match a with
  | Tir.AVar v ->
    (match env_find v.Tir.v_name env with
     | Some lit -> changed := true; Tir.ALit lit
     | None ->
       if allow_avar then
         match avar_find v.Tir.v_name avar with
         | Some y -> changed := true; Tir.AVar y
         | None   -> a
       else a)
  | Tir.ADefRef _ | Tir.ALit _ -> a

let subst_atoms ~changed env avar atoms =
  List.map (subst_atom ~changed env avar) atoms

let subst_fields ~changed env avar fields =
  List.map (fun (k, a) -> (k, subst_atom ~changed env avar a)) fields

(** Propagate literals, variable aliases, and record-field knowledge.
    [env]  maps variable names to their literal values.
    [avar] maps variable names to their aliased variables (P12).
    [fenv] maps variable names to their known record-field lists (P13).
    New bindings are added as they are encountered; re-bindings shadow earlier ones. *)
let rec cprop_expr ~changed (env : env) (avar : avar_env) (fenv : field_env)
    : Tir.expr -> Tir.expr = function
  | Tir.EAtom a ->
    Tir.EAtom (subst_atom ~changed env avar a)

  | Tir.EApp (f, args) ->
    Tir.EApp (f, subst_atoms ~changed env avar args)

  | Tir.ECallPtr (f, args) ->
    (* The function atom [f] is not substituted with avar_env to avoid
       name-sensitive dispatch breakage in llvm_emit (top_fns / var_slot).
       Literal substitution in [f] is safe and already handled by the
       [~allow_avar:false] path (literals in function position are a type
       error anyway). *)
    Tir.ECallPtr (subst_atom ~allow_avar:false ~changed env avar f,
                  subst_atoms ~changed env avar args)

  | Tir.ELet (v, rhs, body) ->
    let rhs' = cprop_expr ~changed env avar fenv rhs in
    (* Extend literal env when the RHS is a bare literal atom. *)
    let env' = match rhs' with
      | Tir.EAtom (Tir.ALit lit) -> env_add v.Tir.v_name lit env
      | _                        -> env
    in
    (* P12: extend avar_env when RHS is a non-closure variable alias. *)
    let avar' = match rhs' with
      | Tir.EAtom (Tir.AVar y) when not (is_closure_ty y.Tir.v_ty) ->
        avar_add v.Tir.v_name y avar
      | _ -> avar
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
    Tir.ELet (v, rhs', cprop_expr ~changed env' avar' fenv' body)

  | Tir.ELetRec (fns, body) ->
    (* Do not propagate outer literals or aliases into recursive function bodies:
       recursive functions may be called from multiple contexts and the outer
       bindings are not in scope for the callers. *)
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = cprop_expr ~changed [] [] [] fd.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', cprop_expr ~changed env avar fenv body)

  | Tir.ECase (a, branches, default) ->
    let a' = subst_atom ~changed env avar a in
    (* Branch bound variables shadow any outer literal/alias/field binding. *)
    let branches' = List.map (fun b ->
      let bound_names =
        List.fold_left (fun s v -> v.Tir.v_name :: s) [] b.Tir.br_vars in
      let env_branch  = List.filter (fun (n, _) -> not (List.mem n bound_names)) env in
      let avar_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) avar in
      let fenv_branch = List.filter (fun (n, _) -> not (List.mem n bound_names)) fenv in
      { b with Tir.br_body =
          cprop_expr ~changed env_branch avar_branch fenv_branch b.Tir.br_body }
    ) branches in
    let default' = Option.map (cprop_expr ~changed env avar fenv) default in
    Tir.ECase (a', branches', default')

  | Tir.ETuple atoms ->
    Tir.ETuple (subst_atoms ~changed env avar atoms)

  | Tir.ERecord fields ->
    Tir.ERecord (subst_fields ~changed env avar fields)

  (* P13: fold EField on a variable whose record shape is known. *)
  | Tir.EField (Tir.AVar v, k) ->
    (match fenv_find v.Tir.v_name fenv with
     | Some fields ->
       (match List.assoc_opt k fields with
        | Some a -> changed := true; Tir.EAtom a
        | None   -> Tir.EField (subst_atom ~changed env avar (Tir.AVar v), k))
     | None -> Tir.EField (subst_atom ~changed env avar (Tir.AVar v), k))

  | Tir.EField (a, f) ->
    Tir.EField (subst_atom ~changed env avar a, f)

  | Tir.EUpdate (a, fields) ->
    Tir.EUpdate (subst_atom ~changed env avar a, subst_fields ~changed env avar fields)

  | Tir.EAlloc (ty, args) ->
    Tir.EAlloc (ty, subst_atoms ~changed env avar args)

  | Tir.EStackAlloc (ty, args) ->
    Tir.EStackAlloc (ty, subst_atoms ~changed env avar args)

  | Tir.EReuse (token, ty, args) ->
    Tir.EReuse (subst_atom ~changed env avar token, ty, subst_atoms ~changed env avar args)

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
    Tir.ESeq (cprop_expr ~changed env avar fenv e1,
              cprop_expr ~changed env avar fenv e2)

let run_fn ~changed (fd : Tir.fn_def) : Tir.fn_def =
  { fd with Tir.fn_body = cprop_expr ~changed [] [] [] fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
