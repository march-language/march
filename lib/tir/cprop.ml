(** Constant propagation pass.

    Substitutes variables bound directly to literals into their use sites,
    enabling downstream [Fold] passes to evaluate the resulting literal
    expressions.

    Scope:
    - Only propagates variables whose RHS is a bare [EAtom (ALit ...)]
    - Does NOT propagate variables bound to complex expressions (would duplicate work)
    - Stops at any re-binding of the same name within nested scopes

    Interaction with Fold:
    This pass runs BEFORE [Fold] in the Opt coordinator so that
        let x = 7 in x + 1
    becomes
        let x = 7 in 7 + 1      (CProp)
        → 8                      (Fold, after DCE drops dead let x)

    Sets [~changed] on any substitution. *)

(** A mapping from variable name to the literal it is bound to. *)
type env = (string * March_ast.Ast.literal) list

let env_add name lit (env : env) : env = (name, lit) :: env

let env_find name (env : env) : March_ast.Ast.literal option =
  List.assoc_opt name env

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

(** Propagate literals through an expression.
    [env] maps variable names to their literal values.
    New literal bindings are added to [env] as they are encountered.
    Any re-binding of a name shadows the previous entry. *)
let rec cprop_expr ~changed (env : env) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a ->
    Tir.EAtom (subst_atom ~changed env a)

  | Tir.EApp (f, args) ->
    Tir.EApp (f, subst_atoms ~changed env args)

  | Tir.ECallPtr (f, args) ->
    Tir.ECallPtr (subst_atom ~changed env f, subst_atoms ~changed env args)

  | Tir.ELet (v, rhs, body) ->
    let rhs' = cprop_expr ~changed env rhs in
    (* If the rhs is now (or was already) a bare literal, extend the env *)
    let env' = match rhs' with
      | Tir.EAtom (Tir.ALit lit) -> env_add v.Tir.v_name lit env
      | _                        -> env
    in
    Tir.ELet (v, rhs', cprop_expr ~changed env' body)

  | Tir.ELetRec (fns, body) ->
    (* Do not propagate outer literals into recursive function bodies:
       recursive functions may be called from multiple contexts and the
       outer binding is not in scope for the callers.
       We still recurse into fn bodies with an empty env for their local lets. *)
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = cprop_expr ~changed [] fd.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', cprop_expr ~changed env body)

  | Tir.ECase (a, branches, default) ->
    let a' = subst_atom ~changed env a in
    (* Branch bound variables shadow any outer literal binding for the same name.
       Drop any env entry that conflicts with a branch-bound variable. *)
    let branches' = List.map (fun b ->
      let bound_names =
        List.fold_left (fun s v -> v.Tir.v_name :: s) [] b.Tir.br_vars in
      let env_branch =
        List.filter (fun (name, _) -> not (List.mem name bound_names)) env in
      { b with Tir.br_body = cprop_expr ~changed env_branch b.Tir.br_body }
    ) branches in
    let default' = Option.map (cprop_expr ~changed env) default in
    Tir.ECase (a', branches', default')

  | Tir.ETuple atoms ->
    Tir.ETuple (subst_atoms ~changed env atoms)

  | Tir.ERecord fields ->
    Tir.ERecord (subst_fields ~changed env fields)

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

  | Tir.EFree a        -> Tir.EFree (subst_atom ~changed env a)
  | Tir.EIncRC a       -> Tir.EIncRC (subst_atom ~changed env a)
  | Tir.EDecRC a       -> Tir.EDecRC (subst_atom ~changed env a)
  | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (subst_atom ~changed env a)
  | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (subst_atom ~changed env a)

  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (cprop_expr ~changed env e1, cprop_expr ~changed env e2)

let run_fn ~changed (fd : Tir.fn_def) : Tir.fn_def =
  (* Seed env with any literal parameter defaults — in practice March parameters
     are never literal-bound at the TIR level, so the env starts empty. *)
  { fd with Tir.fn_body = cprop_expr ~changed [] fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
