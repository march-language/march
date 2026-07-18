(** AST → TIR lowering pass.

    Converts desugared [Ast.module_] to [Tir.tir_module] in A-normal form.
    Key transformations:
    - All intermediate results named via [Tir.ELet] using CPS-style let-insertion
    - Blocks → right-nested [ELet] chains
    - Nested patterns → nested [ECase]
    - [EIf] → [ECase] on bool

    ANF conversion uses continuation-passing: [lower_to_atom_k e k] lowers [e]
    and calls [k atom] with the resulting atom. If [e] is not already atomic,
    a fresh [ELet] binding wraps the continuation. This ensures all call
    arguments are atoms without dangling variable references.

    Wave 3 Task 9 (chunk 2) split this file into an orchestrator (this file:
    [lower_module] + the module-decl walkers that assemble a [Tir.tir_module],
    plus [lower_expr]/[lower_to_atom_k]/[lower_atoms_k] — the giant
    mutual-recursive core every other split module calls into) and five
    focused modules:
      - [Lower_state]: the [env] record + the module-level mutable
        tables/refs shared across every split (alias resolution,
        interface-method dispatch, [_fn_param_types], fresh-name counter,
        [nonexhaustive_panic]).
      - [Lower_types]: both AST-ty and typechecker-ty → TIR-ty converters
        ([lower_ty], [convert_ty]) — kept side by side verbatim; see that
        file's module doc for the filed arrow/Nat encoding disagreement.
      - [Lower_match]: the decision-tree matrix compiler, guards, join
        points, and pattern-tag encoding ([compile_matrix], [lower_match],
        [pat_tag_and_subs], …). Mutually recursive with THIS file's
        [lower_expr] (2 call directions, 5 total edges) — broken via a
        forward-ref ([Lower_match.install_lower_expr], wired below) using
        the same idiom this file already used for [_ensure_module_lowered].
      - [Lower_decls]: [lower_fn_def], [lower_type_def], [rename_tir_vars],
        the lazy stdlib-module loader, and the deduped extern-lowering
        helper.
      - [Lower_actor]: [lower_actor] and its glue.
      - [Lower_tests]: DTest/DSetup/DSetupAll/DDescribe collection.
    See each module's doc comment for the detailed moved-verbatim contents
    and (for [Lower_match]) the cycle-breaking rationale. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

(* ── Re-exports: env, fresh-name generation, shared lowering state ──────
   (Wave 3 Task 9 — now defined in [Lower_state]/[Lower_types], re-exported
   here bare so every external caller (bin/main.ml, lib/jit/repl_jit.ml,
   test/, lsp/) keeps referencing [Lower.env] / [Lower.lower_ty] / etc.
   unchanged — same convention Task 7's [Llvm_emit] re-exports used.) *)
type env = Lower_state.env = {
  type_map : (Ast.span, Typecheck.ty) Hashtbl.t option;
  current_module_aliases : (string, string) Hashtbl.t;
}

let empty_env = Lower_state.empty_env
let ty_of_span = Lower_state.ty_of_span
let ty_of_expr = Lower_state.ty_of_expr
let unknown_ty = Lower_types.unknown_ty
let lower_ty = Lower_types.lower_ty
let lower_linearity = Lower_types.lower_linearity
let convert_ty = Lower_types.convert_ty
let reset_counter = Lower_state.reset_counter
let fresh_name = Lower_state.fresh_name
let fresh_var = Lower_state.fresh_var
let nonexhaustive_panic = Lower_state.nonexhaustive_panic
let _fn_param_types = Lower_state._fn_param_types
let _use_aliases = Lower_state._use_aliases
let _protocol_roles = Lower_state._protocol_roles
let _module_aliases = Lower_state._module_aliases
let _module_alias_snapshots = Lower_state._module_alias_snapshots
let _current_module_fns = Lower_state._current_module_fns
let with_current_module_fns = Lower_state.with_current_module_fns
let resolve_use_alias = Lower_state.resolve_use_alias
let _fns_ref = Lower_state._fns_ref
let _types_ref = Lower_state._types_ref
let _lowered_modules = Lower_state._lowered_modules
let _ensure_module_lowered = Lower_state._ensure_module_lowered
let _iface_methods = Lower_state._iface_methods
let _saved_iface_methods = Lower_state._saved_iface_methods
let get_iface_methods = Lower_state.get_iface_methods
let _default_dispatch = Lower_state._default_dispatch
let resolve_iface_method = Lower_state.resolve_iface_method
let _alias_candidates = Lower_state._alias_candidates
let _alias_reported = Lower_state._alias_reported
let note_alias_candidate = Lower_state.note_alias_candidate
let lower_type_def = Lower_decls.lower_type_def
let lower_fn_def = Lower_decls.lower_fn_def
let rename_tir_vars = Lower_decls.rename_tir_vars
let uniquify_fn = Lower_decls.uniquify_fn

(* ── CPS-based ANF lowering ────────────────────────────────────── *)

(** Lower an expression, ensuring the result is an atom.
    [k] is called with the resulting atom, and any necessary [ELet]
    bindings are wrapped around the result of [k].

    This is the core ANF trick: non-atomic expressions get a fresh
    variable name, their lowered form becomes the RHS of an [ELet],
    and the continuation [k] receives the bound variable as an atom. *)
let rec lower_to_atom_k (env : env) (e : Ast.expr) (k : Tir.atom -> Tir.expr) : Tir.expr =
  match e with
  | Ast.ELit (lit, _) -> k (Tir.ALit lit)
  | Ast.EVar { txt = name; span; _ } ->
    let name = resolve_use_alias env name in
    (match String.index_opt name '.' with
     | Some i -> !_ensure_module_lowered env (String.sub name 0 i)
     | None -> ());
    let ty = ty_of_span env span in
    (* Use the parameter's declared type (from _fn_param_types) when available,
       rather than ty_of_span.  The type_map is shared across the whole program
       and ty_of_span may return a stale or spurious type for a parameter
       use-site (e.g. Result(String,String) instead of the concrete storage
       record type, because the mutable typechecker TVar was linked elsewhere).
       _fn_param_types is kept accurate for the current scope by lower_fn_def
       (which sets it to the function's declared params, saved/restored on
       nesting) and the ELam case (which installs the lambda's own params and
       removes enclosing-function entries that the lambda shadows). *)
    let ty = match Hashtbl.find_opt _fn_param_types name with
      | Some param_ty -> param_ty
      | None -> ty
    in
    k (Tir.AVar { v_name = name; v_ty = ty; v_lin = Tir.Unr })
  | Ast.ETuple (es, _) ->
    (* Bind a tuple to a fresh var typed from its ELEMENTS when the tuple's
       own span does not record a tuple type.  Desugar synthesises the
       multi-arg-fn match scrutinee as an [ETuple] sharing the function/match
       span (fn_span); [ty_of_expr] on that tuple therefore returns the MATCH
       RESULT type (the fn's return type), not the tuple type — which then
       reaches codegen as a non-pointer scrutinee destructured as $TupleN and
       ICEs ("constructor pattern $TupleN(...) destructures a non-pointer
       scrutinee").  Each [__argN] element has its own correctly-typed
       synthetic span, so deriving [TTuple] from the per-element types sidesteps
       the collision.  A tuple whose own span correctly records a [TTuple] keeps
       that precise type unchanged. *)
    lower_atoms_k env es (fun atoms ->
      let ty = match ty_of_expr env e with
        | Tir.TTuple _ as t -> t
        | _ -> Tir.TTuple (List.map (ty_of_expr env) es)
      in
      let v = fresh_var ty in
      Tir.ELet (v, Tir.ETuple atoms, k (Tir.AVar v)))
  | _ ->
    let rhs = lower_expr env e in
    let v = fresh_var (ty_of_expr env e) in
    Tir.ELet (v, rhs, k (Tir.AVar v))

(** Lower a list of expressions to atoms using CPS. *)
and lower_atoms_k (env : env) (es : Ast.expr list) (k : Tir.atom list -> Tir.expr) : Tir.expr =
  match es with
  | [] -> k []
  | e :: rest ->
    lower_to_atom_k env e (fun a ->
      lower_atoms_k env rest (fun rest_atoms ->
        k (a :: rest_atoms)))

(** Translate an AST expression to a TIR expression in ANF. *)
and lower_expr (env : env) (e : Ast.expr) : Tir.expr =
  match e with
  (* --- Atoms --- *)
  | Ast.ELit (lit, _) -> Tir.EAtom (Tir.ALit lit)

  | Ast.EVar { txt = name; span; _ } ->
    let name = resolve_use_alias env name in
    (match String.index_opt name '.' with
     | Some i -> !_ensure_module_lowered env (String.sub name 0 i)
     | None -> ());
    let ty = match Hashtbl.find_opt _fn_param_types name with
      | Some param_ty -> param_ty
      | None -> ty_of_span env span
    in
    Tir.EAtom (Tir.AVar { v_name = name; v_ty = ty; v_lin = Tir.Unr })

  (* --- Let bindings --- *)
  | Ast.ELet (b, _) ->
    lower_expr env b.bind_expr

  (* --- Blocks → right-nested ELet --- *)
  | Ast.EBlock ([], _) -> Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
  | Ast.EBlock ([e], _) -> lower_expr env e
  | Ast.EBlock (Ast.ELet (b, _) :: rest, sp) ->
    let rhs = lower_expr env b.bind_expr in
    (* Register the let-bound pattern names in _fn_param_types for the
       duration of lowering the rest of the block.  Without this, a bare
       reference to the bound name (e.g. [html] after [let html = ...]) is
       rewritten through [_use_aliases], turning a local into a global
       function reference (e.g. [html] → [Response.html]).  Save any shadowed
       entries (function parameters or outer let-bindings with the same name)
       and restore them afterwards. *)
    let pat_names = Lower_match.collect_pat_names b.bind_pat in
    let saved_shadowed : (string * Tir.ty) list =
      List.filter_map (fun (name, _) ->
        match Hashtbl.find_opt _fn_param_types name with
        | Some ty -> Some (name, ty)
        | None -> None) pat_names
    in
    List.iter (fun (name, sp) ->
      Hashtbl.replace _fn_param_types name (ty_of_span env sp)) pat_names;
    let body = lower_expr env (Ast.EBlock (rest, sp)) in
    List.iter (fun (name, _) -> Hashtbl.remove _fn_param_types name) pat_names;
    List.iter (fun (name, ty) -> Hashtbl.replace _fn_param_types name ty) saved_shadowed;
    (match b.bind_pat with
     | Ast.PatVar n ->
       let v : Tir.var = {
         v_name = n.txt;
         v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> ty_of_expr env b.bind_expr);
         v_lin = lower_linearity b.bind_lin;
       } in
       Tir.ELet (v, rhs, body)
     | Ast.PatTuple (_, _) ->
       (* let (a, b, ...) = rhs  →  let $p = rhs; let a = $p.$fv0; let b = $p.$fv1; …
          Recover the tuple's element types from the rhs and give each field var
          its concrete type.  Tuple scalar fields are stored low-bit tagged; a
          field var left at TVar makes ELet trust the raw ptr load (no untag), so
          int_to_string(field) prints (n<<1)|1.  The match-pattern path already
          propagates element types from the scrutinee's tuple type — mirror it.

          Sub-patterns may themselves be compound (a NESTED tuple, e.g.
          `let ((a,b),(c,d)) = ...`), so recurse via [bind_subpat] instead of
          only handling a leaf [PatVar] per element.  The prior version matched
          `PatVar` and dropped every other element (`| _ -> inner`), leaving a
          nested tuple's leaf vars unbound — they then resolved to undefined
          global fn references (`call ptr @a()`) and clang rejected the module.
          This mirrors the match path (compile_matrix), which decomposes nested
          tuple patterns field-by-field. *)
       let rhs_tuple_ty = match b.bind_ty with
         | Some t -> lower_ty t
         | None -> ty_of_expr env b.bind_expr in
       (* Recursively bind an irrefutable sub-pattern [pat] over the scrutinee
          atom [scrut] (of type [scrut_ty]), wrapping [inner].  Handles the
          shapes a `let` binding can take: wildcard (skip), var (bind), as-var
          (bind outer name + recurse), and nested tuple (decompose fields). *)
       let rec bind_subpat (scrut : Tir.atom) (scrut_ty : Tir.ty)
           (pat : Ast.pattern) (inner : Tir.expr) : Tir.expr =
         match pat with
         | Ast.PatWild _ -> inner
         | Ast.PatVar n ->
           let fv : Tir.var = { v_name = n.txt; v_ty = scrut_ty; v_lin = Tir.Lin } in
           Tir.ELet (fv, Tir.EAtom scrut, inner)
         | Ast.PatAs (sub, n, _) ->
           let fv : Tir.var = { v_name = n.txt; v_ty = scrut_ty; v_lin = Tir.Lin } in
           Tir.ELet (fv, Tir.EAtom scrut, bind_subpat scrut scrut_ty sub inner)
         | Ast.PatTuple (subs, _) ->
           let elem_tys = match scrut_ty with Tir.TTuple ts -> ts | _ -> [] in
           let elem_ty_at i = match List.nth_opt elem_tys i with
             | Some t -> t
             | None -> unknown_ty in
           (* fold_right so field 0 is the outermost let *)
           List.fold_right (fun (i, sub) acc ->
             match sub with
             | Ast.PatWild _ -> acc  (* wildcard element → no binding *)
             | Ast.PatVar n ->
               (* Bind the field directly, skipping an intermediate copy let —
                  preserves the original RC-friendly single-level shape. *)
               let fv : Tir.var = { v_name = n.txt; v_ty = elem_ty_at i; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, Tir_names.fv_field i), acc)
             | _ ->
               (* Compound element (nested tuple / as-pattern): bind a fresh var
                  to the field, then recurse into it. *)
               let ety = elem_ty_at i in
               let fname = fresh_name "p" in
               let fv : Tir.var = { v_name = fname; v_ty = ety; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, Tir_names.fv_field i),
                 bind_subpat (Tir.AVar fv) ety sub acc)
           ) (List.mapi (fun i p -> (i, p)) subs) inner
         | _ ->
           (* Records / refutable sub-patterns in an irrefutable `let` are not
              decomposed here (unchanged from prior behaviour — a bare `let`
              with such a pattern falls through to the catch-all arm below). *)
           inner
       in
       let tname = fresh_name "p" in
       let tv : Tir.var = { v_name = tname; v_ty = rhs_tuple_ty; v_lin = Tir.Lin } in
       let body_with_fields = bind_subpat (Tir.AVar tv) rhs_tuple_ty b.bind_pat body in
       Tir.ELet (tv, rhs, body_with_fields)
     | _ ->
       let bind_name = fresh_name "p" in
       let v : Tir.var = {
         v_name = bind_name;
         v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> ty_of_expr env b.bind_expr);
         v_lin = lower_linearity b.bind_lin;
       } in
       Tir.ELet (v, rhs, body))
  (* --- ELetFn as block statement → bind function name in rest of block --- *)
  | Ast.EBlock (Ast.ELetFn (name, params, ret_ty_ann, fn_body, _) :: rest, sp) ->
    let fn_name = name.Ast.txt in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> ty_of_span env p.param_name.span);
          v_lin = lower_linearity p.param_lin }
      ) params in
    (* Install fn_name → self_ty so that both recursive self-calls inside the
       body and uses in the block continuation get the correct TFn type.
       Without this, ty_of_span returns TVar("_") for stdlib code that has no
       type_map entry, causing ECallPtr to emit wrong LLVM param types (all ptr
       instead of e.g. i64 for Int params). Save/restore to handle shadowing. *)
    let ret_ty_pre = match ret_ty_ann with Some t -> lower_ty t | None -> unknown_ty in
    let param_tys' = List.map (fun v -> v.Tir.v_ty) params' in
    let self_ty_pre = Tir.TFn (param_tys', ret_ty_pre) in
    let saved_fn = Hashtbl.find_opt _fn_param_types fn_name in
    Hashtbl.replace _fn_param_types fn_name self_ty_pre;
    let fn_body' = lower_expr env fn_body in
    let ret_ty = match ret_ty_ann with Some t -> lower_ty t | None -> ty_of_expr env fn_body in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = fn_body';
      (* Block-statement `fn name(...) do ... end` → same ELetRec([fn], AVar fn)
         lambda-creation shape as ELam; defun's lift_lambda consumes it and
         mints a fresh FnApply fn_def, so FnLambda never reaches borrow/perceus. *)
      fn_kind = Tir.FnLambda;
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (param_tys', ret_ty);
      v_lin = Tir.Unr
    } in
    (* Update with final ret_ty before lowering the continuation *)
    Hashtbl.replace _fn_param_types fn_name fn_var.v_ty;
    let fn_expr = Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var)) in
    let block_body = lower_expr env (Ast.EBlock (rest, sp)) in
    (match saved_fn with
     | Some t -> Hashtbl.replace _fn_param_types fn_name t
     | None -> Hashtbl.remove _fn_param_types fn_name);
    Tir.ELet (fn_var, fn_expr, block_body)
  | Ast.EBlock (e :: rest, sp) ->
    let e' = lower_expr env e in
    let body = lower_expr env (Ast.EBlock (rest, sp)) in
    Tir.ESeq (e', body)

  (* --- If → ECase on bool (CPS for condition) --- *)
  | Ast.EIf (cond, then_e, else_e, _) ->
    lower_to_atom_k env cond (fun cond_atom ->
      let then' = lower_expr env then_e in
      let else' = lower_expr env else_e in
      Tir.ECase (cond_atom,
        [{ br_tag = Tir_names.synthetic_true_tag; br_vars = []; br_body = then' }],
        Some else'))

  (* --- match do cond_arm* end → nested ECase on bools --- *)
  | Ast.ECond (arms, _) ->
    let panic_var : Tir.var = {
      Tir.v_name = "panic"; Tir.v_ty = Tir.TCon ("Never", []); Tir.v_lin = Tir.Unr } in
    let no_match = Tir.EApp (panic_var, [Tir.ALit (Ast.LitString "non-exhaustive match do")]) in
    let rec lower_cond = function
      | [] -> no_match
      | (cond_e, body_e) :: rest ->
        lower_to_atom_k env cond_e (fun cond_atom ->
          let body' = lower_expr env body_e in
          let rest' = lower_cond rest in
          Tir.ECase (cond_atom,
            [{ br_tag = Tir_names.synthetic_true_tag; br_vars = []; br_body = body' }],
            Some rest'))
    in
    lower_cond arms

  (* --- Tuples (CPS for elements) --- *)
  | Ast.ETuple (es, _) ->
    lower_atoms_k env es (fun atoms -> Tir.ETuple atoms)

  (* --- Records (CPS for field values) --- *)
  | Ast.ERecord (fields, _) ->
    let names = List.map (fun (n, _) -> n.Ast.txt) fields in
    let exprs = List.map snd fields in
    lower_atoms_k env exprs (fun atoms ->
      Tir.ERecord (List.combine names atoms))

  | Ast.ERecordUpdate (base, updates, _) ->
    lower_to_atom_k env base (fun base_atom ->
      let names = List.map (fun (n, _) -> n.Ast.txt) updates in
      let exprs = List.map snd updates in
      lower_atoms_k env exprs (fun atoms ->
        Tir.EUpdate (base_atom, List.combine names atoms)))

  | Ast.EField (e, { txt = name; _ }, _) ->
    lower_to_atom_k env e (fun a -> Tir.EField (a, name))

  (* --- Session-typed channel builtins (binary) --- *)
  | Ast.EApp (Ast.EVar { txt = "Chan.new"; _ }, [proto_arg], _) ->
    lower_to_atom_k env proto_arg (fun proto' ->
      let fn_var : Tir.var = {
        v_name = "chan_new"; v_ty = Tir.TFn ([Tir.TString], Tir.TTuple [Tir.TCon ("Chan", []); Tir.TCon ("Chan", [])]);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [proto']))

  | Ast.EApp (Ast.EVar { txt = "Chan.send"; _ }, [ch_arg; val_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      lower_to_atom_k env val_arg (fun val' ->
        let fn_var : Tir.var = {
          v_name = "chan_send"; v_ty = Tir.TFn ([Tir.TCon ("Chan", []); Tir.TPtr Tir.TUnit], Tir.TCon ("Chan", []));
          v_lin = Tir.Unr } in
        Tir.EApp (fn_var, [ch'; val'])))

  | Ast.EApp (Ast.EVar { txt = "Chan.recv"; _ }, [ch_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      let fn_var : Tir.var = {
        v_name = "chan_recv"; v_ty = Tir.TFn ([Tir.TCon ("Chan", [])], Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [ch']))

  | Ast.EApp (Ast.EVar { txt = "Chan.close"; _ }, [ch_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      let fn_var : Tir.var = {
        v_name = "chan_close"; v_ty = Tir.TFn ([Tir.TCon ("Chan", [])], Tir.TUnit);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [ch']))

  | Ast.EApp (Ast.EVar { txt = "Chan.choose"; _ }, [ch_arg; label_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      lower_to_atom_k env label_arg (fun label' ->
        let fn_var : Tir.var = {
          v_name = "chan_choose"; v_ty = Tir.TFn ([Tir.TCon ("Chan", []); Tir.TPtr Tir.TUnit], Tir.TCon ("Chan", []));
          v_lin = Tir.Unr } in
        Tir.EApp (fn_var, [ch'; label'])))

  | Ast.EApp (Ast.EVar { txt = "Chan.offer"; _ }, [ch_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      let fn_var : Tir.var = {
        v_name = "chan_offer"; v_ty = Tir.TFn ([Tir.TCon ("Chan", [])], Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [ch']))

  (* --- Multi-party session type builtins --- *)
  | Ast.EApp (Ast.EVar { txt = "MPST.new"; _ }, [proto_arg], sp) ->
    (* Derive the role count from the result type (TTuple of N TChan endpoints). *)
    let n_roles = match ty_of_span env sp with
      | Tir.TTuple ts -> List.length ts
      | _ -> 3  (* fallback — shouldn't happen for well-typed code *)
    in
    (* Resolve the protocol's sorted role list so the runtime can register
       role_names[] in tuple-position order (name-based routing must line up
       with the endpoint tuple positions).  Empty string ⇒ runtime falls back
       to lazy first-encounter registration. *)
    let proto_name = match proto_arg with
      | Ast.ECon (n, [], _) | Ast.EVar n -> n.txt
      | _ -> ""
    in
    let roles_csv =
      match Hashtbl.find_opt _protocol_roles proto_name with
      | Some roles -> String.concat "," roles
      | None -> ""
    in
    lower_to_atom_k env proto_arg (fun proto' ->
      let n_atom = Tir.ALit (March_ast.Ast.LitInt n_roles) in
      let roles_atom = Tir.ALit (March_ast.Ast.LitString roles_csv) in
      let fn_var : Tir.var = {
        v_name = "mpst_new"; v_ty = Tir.TFn ([Tir.TString; Tir.TInt; Tir.TString], Tir.TPtr Tir.TUnit);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [proto'; n_atom; roles_atom]))

  | Ast.EApp (Ast.EVar { txt = "MPST.send"; _ }, [ch_arg; role_arg; val_arg], _) ->
    (* Lower role name to a string for the runtime's name→index lookup. *)
    let role_name = match role_arg with
      | Ast.ECon (n, [], _) | Ast.EVar n -> n.txt
      | Ast.EAtom (s, [], _) | Ast.ELit (Ast.LitAtom s, _) -> s
      | _ -> "unknown"
    in
    lower_to_atom_k env ch_arg (fun ch' ->
      lower_to_atom_k env val_arg (fun val' ->
        let role_str = Tir.ALit (March_ast.Ast.LitString role_name) in
        let fn_var : Tir.var = {
          v_name = "mpst_send"; v_ty = Tir.TFn ([Tir.TCon ("Chan", []); Tir.TString; Tir.TPtr Tir.TUnit], Tir.TCon ("Chan", []));
          v_lin = Tir.Unr } in
        Tir.EApp (fn_var, [ch'; role_str; val'])))

  | Ast.EApp (Ast.EVar { txt = "MPST.recv"; _ }, [ch_arg; role_arg], _) ->
    let role_name = match role_arg with
      | Ast.ECon (n, [], _) | Ast.EVar n -> n.txt
      | Ast.EAtom (s, [], _) | Ast.ELit (Ast.LitAtom s, _) -> s
      | _ -> "unknown"
    in
    lower_to_atom_k env ch_arg (fun ch' ->
      let role_str = Tir.ALit (March_ast.Ast.LitString role_name) in
      let fn_var : Tir.var = {
        v_name = "mpst_recv"; v_ty = Tir.TFn ([Tir.TCon ("Chan", []); Tir.TString], Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [ch'; role_str]))

  | Ast.EApp (Ast.EVar { txt = "MPST.close"; _ }, [ch_arg], _) ->
    lower_to_atom_k env ch_arg (fun ch' ->
      let fn_var : Tir.var = {
        v_name = "mpst_close"; v_ty = Tir.TFn ([Tir.TCon ("Chan", [])], Tir.TUnit);
        v_lin = Tir.Unr } in
      Tir.EApp (fn_var, [ch']))

  (* --- Function application (CPS: all args must be atoms) --- *)
  | Ast.EApp (f_expr, args, _) ->
    (* Check for default-arg dispatch: if f is a plain EVar that names a
       default-arg function (tracked via [_default_dispatch]), rewrite the
       call to the appropriate arity-mangled version (e.g. greet$1, greet$2). *)
    let resolved_f = match f_expr with
      | Ast.EVar { txt = name; span = fn_span } ->
        let n_args = List.length args in
        (match Hashtbl.find_opt !_default_dispatch name with
         | Some arity_map ->
           (match List.assoc_opt n_args arity_map with
            | Some mangled -> Ast.EVar { txt = mangled; span = fn_span }
            | None -> f_expr)
         | None ->
           (* Check for interface method resolution: redirect to the mangled
              impl function based on the concrete type of the first argument.
              BUT if the current module defines a free function with this exact
              name (e.g. the user wrote `fn show(...)`, colliding with the Show
              interface method), that definition shadows the interface for calls
              in this module — matching the typechecker's overload resolution.
              Without this, `show(someOption)` would dispatch to Show$Option.show
              (String) while typecheck bound it to the user's `show` (Int),
              feeding a String where an Int is expected. *)
           (match args with
            | first_arg :: _
              when not (Hashtbl.mem !_current_module_fns name) ->
              (* `to_string` is a universal formatter that is SEMANTICALLY
                 identical to `show` on any type with a Show impl (verified: the
                 interpreter's `to_string` and `show` produce byte-identical
                 output, and for primitives Show$T.show delegates to the very
                 same *_to_string C helper).  But compiled `to_string` was a
                 codegen builtin that fell through to the generic
                 `march_value_to_string` for non-primitives → `#<tag:N>` garbage.
                 Route it through the Show dispatch so a container/ADT gets its
                 real `Show$T.show`, exactly as `println` already does.  If no
                 Show impl resolves (a Show-less type), fall through to the old
                 `to_string` builtin — no regression. *)
              let dispatch_name = if name = "to_string" then "show" else name in
              (match resolve_iface_method env dispatch_name (Typecheck.span_of_expr first_arg) with
               | Some mangled_name -> Ast.EVar { txt = mangled_name; span = fn_span }
               | None -> f_expr)
            | _ -> f_expr))
      | _ -> f_expr
    in
    lower_to_atom_k env resolved_f (fun f_atom ->
      lower_atoms_k env args (fun arg_atoms ->
        let f_var = match f_atom with
          | Tir.AVar v -> v
          | Tir.ADefRef did ->
            { v_name = did.Tir.did_name; v_ty = unknown_ty; v_lin = Tir.Unr }
          | Tir.ALit _ ->
            { v_name = "<lit>"; v_ty = unknown_ty; v_lin = Tir.Unr }
        in
        (* Special case: own(pid, value) → register_resource + drop closure.
           Transforms own(pid, value : TypeName) into:
             let $own_dropN = fn _ -> Drop$TypeName.drop(value) in
             register_resource(pid, "drop_TypeName", $own_dropN)
           This keeps the Drop impl alive through the mono pass and wires
           the cleanup callback into the actor's kill/crash path. *)
        if f_var.v_name = "own" && List.length arg_atoms = 2 then
          let pid_atom   = List.nth arg_atoms 0 in
          let value_atom = List.nth arg_atoms 1 in
          let value_ty = match value_atom with
            | Tir.AVar v -> v.Tir.v_ty
            | _ -> Tir.TVar "_"
          in
          let type_name = match value_ty with
            | Tir.TCon (n, _) -> n
            | _ -> ""
          in
          if type_name = "" then Tir.EApp (f_var, arg_atoms)
          else
            let drop_fn_name = Printf.sprintf "Drop$%s.drop" type_name in
            let lam_name     = fresh_name "own_drop" in
            let drop_var  = { Tir.v_name = drop_fn_name;
                              v_ty = Tir.TFn ([value_ty], Tir.TUnit);
                              v_lin = Tir.Unr } in
            let dummy_param = { Tir.v_name = "$_"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
            let drop_body   = Tir.EApp (drop_var, [value_atom]) in
            let lam_fn : Tir.fn_def = {
              fn_name   = lam_name;
              fn_params = [dummy_param];
              fn_ret_ty = Tir.TUnit;
              fn_body   = drop_body;
              (* Synthesized `own(...)` drop-callback lambda — same
                 ELetRec([fn], AVar fn) shape defun lifts to FnApply. *)
              fn_kind   = Tir.FnLambda;
            } in
            let lam_ty  = Tir.TFn ([Tir.TUnit], Tir.TUnit) in
            let lam_var = { Tir.v_name = lam_name; v_ty = lam_ty; v_lin = Tir.Unr } in
            (* Bind the closure to a fresh variable so defun can see the
               canonical ELetRec([fn], EAtom(AVar fn)) → closure alloc pattern. *)
            let clo_var = fresh_var lam_ty in
            let name_atom = Tir.ALit (March_ast.Ast.LitString ("drop_" ^ type_name)) in
            let reg_var   = { Tir.v_name = "register_resource";
                              v_ty = Tir.TFn ([Tir.TVar "_"; Tir.TString; lam_ty], Tir.TUnit);
                              v_lin = Tir.Unr } in
            Tir.ELet (clo_var,
              Tir.ELetRec ([lam_fn], Tir.EAtom (Tir.AVar lam_var)),
              Tir.EApp (reg_var, [pid_atom; name_atom; Tir.AVar clo_var]))
        else
          Tir.EApp (f_var, arg_atoms)))

  (* --- Constructor application (CPS for args) --- *)
  (* Embed the parent type name in the TCon key so that different ADTs with
     the same constructor name (e.g. List.Cons vs Tree.Cons) produce distinct
     keys in the emitter's ctor_info table.  The span carries the inferred
     result type from the typechecker; when it is TCon(type_name, _) we use
     "type_name.ctor_name" as the key, otherwise fall back to the bare name. *)
  | Ast.ECon ({ txt = tag; _ }, args, span) ->
    lower_atoms_k env args (fun arg_atoms ->
      (* The reference itself may be module- or type-qualified
         ("AeLib.AeWrap", "Expr.Col"); keep only the final segment so the key
         stays in the "TypeName.CtorName" format ctor_entry resolves against.
         Embedding the raw qualified tag produced keys like
         "AeShape.AeLib.AeWrap" that matched nothing — the allocation then
         silently defaulted to tag 0. *)
      let short_tag = match String.rindex_opt tag '.' with
        | Some i -> String.sub tag (i + 1) (String.length tag - i - 1)
        | None -> tag
      in
      let ctor_key = match ty_of_span env span with
        | Tir.TCon (type_name, _) -> type_name ^ "." ^ short_tag
        | _ -> short_tag
      in
      (* For a NULLARY constructor (e.g. [None]) thread the enclosing type's
         parameters into the EAlloc so codegen can decide the value's
         representation — a niche-shaped type applied to a niche-UNSAFE payload
         (e.g. Option(Option(_))) must box its nullary ctor rather than emit a
         raw-0 niche, to stay consistent with the boxed non-nullary ctor and the
         match's Boxed strategy.  Non-nullary ctors get the payload type from
         their arguments, so this is only needed when there are none. *)
      let ctor_params = match ty_of_span env span, arg_atoms with
        | Tir.TCon (_, params), [] -> params
        | _ -> []
      in
      Tir.EAlloc (Tir.TCon (ctor_key, ctor_params), arg_atoms))

  (* --- Lambda → ELetRec with a single fn_def --- *)
  | Ast.ELam (params, body, lam_span) ->
    let fn_name = fresh_name "lam" in
    (* Extract param types from the lambda's inferred type when no annotation. *)
    let lam_ty = ty_of_span env lam_span in
    let inferred_param_tys = match lam_ty with
      | Tir.TFn (ps, _) -> ps
      | _ -> List.map (fun _ -> unknown_ty) params
    in
    let params' = List.mapi (fun i (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t
                  | None -> List.nth_opt inferred_param_tys i
                            |> Option.value ~default:unknown_ty);
          v_lin = lower_linearity p.param_lin }
      ) params in
    (* Lambda parameters take precedence over any outer function parameters
       with the same name in _fn_param_types.  Without this, a lambda
         fn b -> if b do 1 else 0 end
       defined inside a function that has a parameter named 'b' would have
       its body lowered with the OUTER function's type for 'b', not the
       lambda's own 'b' type (e.g. Bool vs ColumnBuilder).
       We save the displaced entries and restore them after the body. *)
    let saved_lam_params : (string * Tir.ty option) list =
      List.map (fun (v : Tir.var) ->
        (v.v_name, Hashtbl.find_opt _fn_param_types v.v_name)
      ) params'
    in
    List.iter (fun (v : Tir.var) ->
      match v.v_ty with
      | Tir.TVar "_" ->
        (* Unknown lambda param type — remove outer entry so body falls back
           to ty_of_span rather than inheriting a possibly-wrong outer type. *)
        Hashtbl.remove _fn_param_types v.v_name
      | _ ->
        Hashtbl.replace _fn_param_types v.v_name v.v_ty
    ) params';
    let body' = lower_expr env body in
    List.iter (fun (name, saved) ->
      match saved with
      | Some ty -> Hashtbl.replace _fn_param_types name ty
      | None    -> Hashtbl.remove _fn_param_types name
    ) saved_lam_params;
    (* Try to get the return type from the lambda body's span first.
       When that span isn't in the type_map (e.g. desugared lambdas passed to
       builtins), fall back to the lambda's own inferred type (lam_ty) which
       the typechecker does annotate.  Without this fallback a lambda such as
         fn conn -> run_pipeline(conn, plugs)
       would get fn_ret_ty = TVar "_" → void LLVM return → result silently
       dropped → NULL returned to the caller. *)
    let ret_ty =
      let from_body = ty_of_expr env body in
      match from_body with
      | Tir.TVar "_" ->
        (match lam_ty with
         | Tir.TFn (_, r) -> r
         | _ -> from_body)
      | _ -> from_body
    in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = body';
      fn_kind = Tir.FnLambda;  (* `ELam` — anonymous lambda *)
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) params', ret_ty);
      v_lin = Tir.Unr
    } in
    Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var))

  (* --- Match → ECase (CPS for scrutinee) --- *)
  | Ast.EMatch (scrut, branches, _) ->
    lower_to_atom_k env scrut (fun scrut_atom ->
      Lower_match.lower_match env scrut_atom branches)

  (* --- Annotations: lower the inner expr --- *)
  | Ast.EAnnot (e, _, _) -> lower_expr env e

  (* --- Atoms (the :tag syntax) --- *)
  | Ast.EAtom (a, [], _) -> Tir.EAtom (Tir.ALit (Ast.LitAtom a))
  | Ast.EAtom (a, args, _) ->
    lower_atoms_k env args (fun arg_atoms ->
      Tir.EAlloc (Tir.TCon (a, []), arg_atoms))

  (* --- Holes --- *)
  | Ast.EHole (name, _) ->
    let label = match name with Some n -> n.txt | None -> "?" in
    Tir.EAtom (Tir.ALit (Ast.LitAtom ("hole_" ^ label)))

  (* --- Pipe should be desugared already --- *)
  | Ast.EPipe _ -> failwith "TIR lower: EPipe should have been desugared"

  | Ast.EResultRef _ -> failwith "TIR lower: EResultRef is REPL-only and should be substituted before lowering"

  | Ast.EDbg (None, _) ->
    (* dbg() with no argument: compile to unit in compiled mode *)
    Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
  | Ast.EDbg (Some inner, _) ->
    (* dbg(expr): compile to just the expression (strip the debug wrapper) *)
    lower_expr env inner

  (* --- Send/Spawn (CPS for args) --- *)
  | Ast.ESend (cap, msg, _) ->
    lower_to_atom_k env cap (fun cap' ->
      lower_to_atom_k env msg (fun msg' ->
        let send_var : Tir.var = {
          v_name = "send";
          v_ty = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit],
                           Tir.TCon ("Option", [Tir.TUnit]));
          v_lin = Tir.Unr } in
        Tir.EApp (send_var, [cap'; msg'])))

  (* Actor names are upper-case identifiers, parsed as ECon with no args.
     Lower spawn(ActorName) → call to ActorName_spawn() *)
  | Ast.ESpawn (Ast.ECon ({ txt = actor_name; _ }, [], _), _)
  | Ast.ESpawn (Ast.EVar { txt = actor_name; _ }, _) ->
    let spawn_fn : Tir.var = {
      v_name = actor_name ^ Tir_names.actor_spawn_suffix;
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    let march_spawn : Tir.var = {
      v_name = "spawn";
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    let raw_var : Tir.var = {
      v_name = "$raw_actor";
      v_ty = Tir.TPtr Tir.TUnit;
      v_lin = Tir.Unr
    } in
    Tir.ELet (raw_var, Tir.EApp (spawn_fn, []),
              Tir.EApp (march_spawn, [Tir.AVar raw_var]))

  | Ast.ESpawn _ ->
    failwith "TIR lower: ESpawn argument must be a plain actor name"

  (* --- Local named recursive fn → ELetRec with a single fn_def ---
     fn go(params) : ret do body end  is like ELam but the fn knows its own name,
     enabling recursion.  Defun lifts it and computes free-variable captures. *)
  | Ast.ELetFn (name, params, ret_ty_ann, body, _) ->
    let fn_name = name.Ast.txt in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t
                  | None -> ty_of_span env p.param_name.span);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let ret_ty_pre = match ret_ty_ann with Some t -> lower_ty t | None -> unknown_ty in
    let param_tys' = List.map (fun v -> v.Tir.v_ty) params' in
    let saved_fn = Hashtbl.find_opt _fn_param_types fn_name in
    Hashtbl.replace _fn_param_types fn_name (Tir.TFn (param_tys', ret_ty_pre));
    let body' = lower_expr env body in
    (match saved_fn with
     | Some t -> Hashtbl.replace _fn_param_types fn_name t
     | None -> Hashtbl.remove _fn_param_types fn_name);
    let ret_ty = match ret_ty_ann with Some t -> lower_ty t | None -> ty_of_expr env body in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = body';
      fn_kind = Tir.FnLambda;  (* `ELetFn` — named local recursive fn *)
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (param_tys', ret_ty);
      v_lin = Tir.Unr
    } in
    Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar fn_var))

  (* --- let? p = e; cont  →  match e do Ok(p) -> cont | Err($e) -> Err($e) end --- *)
  | Ast.ELetQ (p, result_expr, cont, _) ->
    let dsp = Ast.dummy_span in
    let err_var : Ast.name = { txt = "$letq_err"; span = dsp } in
    let ok_branch : Ast.branch = {
      branch_pat   = Ast.PatCon ({ txt = "Ok";  span = dsp }, [p]);
      branch_guard = None;
      branch_body  = cont;
    } in
    let err_branch : Ast.branch = {
      branch_pat   = Ast.PatCon ({ txt = "Err"; span = dsp }, [Ast.PatVar err_var]);
      branch_guard = None;
      branch_body  = Ast.ECon ({ txt = "Err"; span = dsp }, [Ast.EVar err_var], dsp);
    } in
    lower_expr env (Ast.EMatch (result_expr, [ok_branch; err_branch], dsp))

  (* --- Assert: lower to a runtime panic call on failure (for compiled path) --- *)
  | Ast.EAssert (inner, _) ->
    (* Lower assert to: if inner then () else panic("assertion failed")
       Uses same CPS-based bool dispatch as EIf. *)
    lower_to_atom_k env inner (fun cond_atom ->
      let unit_v = Tir.EAtom (Tir.ALit (Ast.LitAtom "unit")) in
      let panic_var : Tir.var = {
        v_name = "panic";
        v_ty = Tir.TFn ([Tir.TCon ("String", [])], Tir.TCon ("Unit", []));
        v_lin = Tir.Unr
      } in
      let panic_v = Tir.EApp (panic_var, [Tir.ALit (Ast.LitString "assertion failed")]) in
      Tir.ECase (cond_atom,
        [{ br_tag = Tir_names.synthetic_true_tag; br_vars = []; br_body = unit_v }],
        Some panic_v))

  | Ast.ESigil _ ->
    failwith "lower_expr: ESigil should be desugared before lowering"

(** Install this file's [lower_expr] into [Lower_match]'s forward ref.
    Breaks the [lower.ml] <-> [Lower_match] mutual-recursion cycle (see
    [Lower_match]'s module doc): [lower_expr]'s [EBlock]/[ELet] and
    [EMatch] arms above call [Lower_match.collect_pat_names] /
    [Lower_match.lower_match] directly (forward calls, fine at compile
    time since [Lower_match] is an earlier compilation unit); the reverse
    edge ([lower_branch_body_with_pat] and the guarded-match path in
    [lower_match] calling back into THIS [lower_expr]) has to go through
    this ref instead, since [Lower_match] cannot name [Lower.lower_expr]
    directly without creating a real dependency cycle. Set exactly once at
    module-load time — the same idiom as [_ensure_module_lowered] below. *)
let () = Lower_match.install_lower_expr lower_expr

(** Built-in type definitions that must always be present in TIR so that
    their constructors have stable tag assignments in the LLVM emitter.
    These mirror the built-in constructor table in the typechecker. *)
let builtin_type_defs : Tir.type_def list = [
  (* Option a = None | Some(a) — None=tag0, Some=tag1 *)
  Tir.TDVariant ("Option", [("None", []); ("Some", [Tir.TVar "a"])]);
  (* Result a b = Ok(a) | Err(b) — Ok=tag0, Err=tag1 *)
  Tir.TDVariant ("Result", [("Ok", [Tir.TVar "a"]); ("Err", [Tir.TVar "b"])]);
  (* List a = Nil | Cons(a, List(a)) — Nil=tag0, Cons=tag1 *)
  Tir.TDVariant ("List", [("Nil", []); ("Cons", [Tir.TVar "a"; Tir.TCon ("List", [Tir.TVar "a"])])]);
]

(** Lower a module. *)
let lower_module ?type_map ?(stdlib_context : Ast.decl list = []) ?(test_mode=false) ?(hot_reload=false) (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  (* env is constructed fresh here (module-scoped fields only — the
     reset-at-entry set, per the plan's landmine classification): [type_map]
     is set once from the caller's argument and never mutated again this
     call; [current_module_aliases] starts as a fresh empty table exactly
     like the old [_current_module_aliases := Hashtbl.create 16] did. *)
  let env = { type_map; current_module_aliases = Hashtbl.create 16 } in
  _iface_methods := Hashtbl.create 16;
  _use_aliases := Hashtbl.create 16;
  _module_aliases := Hashtbl.create 16;
  _module_alias_snapshots := Hashtbl.create 16;
  Hashtbl.reset _alias_candidates;
  Hashtbl.reset _alias_reported;
  _lowered_modules := Hashtbl.create 8;
  (* Pre-register every top-level DMod name from the combined module.
     This prevents _ensure_module_lowered from re-parsing a stdlib file with a
     relative path (e.g. "stdlib/yaml.march") when the type_map was built from
     the absolute path.  The file-path mismatch causes ty_of_span to return
     TVar "_" for all expressions, producing incorrect code.
     Pre-registering here is safe: every DMod in m.mod_decls will be visited in
     Pass 2, which lowers the functions with the correct type_map. *)
  let rec preregister_mods = function
    | Ast.DMod (nm, _, inner, _) :: rest ->
      Hashtbl.replace !_lowered_modules nm.txt ();
      preregister_mods inner;
      preregister_mods rest
    | _ :: rest -> preregister_mods rest
    | [] -> ()
  in
  preregister_mods m.mod_decls;
  (* Collect protocol → sorted-role-list mappings (mirrors the interpreter's
     [protocol_roles_tbl]) so the [MPST.new] lowering can pass role names to
     the runtime in tuple-position (role-name-sorted) order. *)
  Hashtbl.reset _protocol_roles;
  let rec collect_roles acc = function
    | [] -> acc
    | Ast.ProtoMsg (s, r, _) :: rest -> collect_roles (s.txt :: r.txt :: acc) rest
    | Ast.ProtoLoop steps :: rest -> collect_roles (collect_roles acc steps) rest
    | Ast.ProtoChoice (ch, branches) :: rest ->
      let branch_roles =
        List.concat_map (fun (_, steps) -> collect_roles [] steps) branches in
      collect_roles (ch.txt :: branch_roles @ acc) rest
  in
  let rec register_protocols decls =
    List.iter (fun d -> match d with
      | Ast.DProtocol (name, pdef, _) ->
        let roles = List.sort_uniq String.compare
            (collect_roles [] pdef.Ast.proto_steps) in
        Hashtbl.replace _protocol_roles name.Ast.txt roles
      | Ast.DMod (_, _, inner, _) -> register_protocols inner
      | _ -> ()) decls
  in
  register_protocols m.mod_decls;
  let fns = ref [] in
  let types = ref [] in
  _fns_ref := fns;
  _types_ref := types;
  let top_lets = ref [] in
  let externs = ref [] in
  (* Pre-populate _iface_methods with standard interface builtins:
     Eq, Ord, Show, Hash for Int/Float/String/Bool/Unit.
     These mirror the builtin_impls registered in the typechecker.
     Synthetic TIR functions delegate to the corresponding built-in ops.
     Only injected when a type_map is available (full pipeline mode). *)
  if env.type_map <> None then begin
  let mk_var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr } in
  let call2 op_name x_ty y_ty ret_ty =
    (* fn(x, y) -> op(x, y) *)
    let x = mk_var "x" x_ty and y = mk_var "y" y_ty in
    { Tir.fn_name   = op_name;
      fn_params     = [x; y];
      fn_ret_ty     = ret_ty;
      fn_body       = Tir.EApp (mk_var op_name unknown_ty, [Tir.AVar x; Tir.AVar y]);
      fn_kind       = Tir.FnNormal }
  in
  let call1 op_name x_ty ret_ty =
    (* fn(x) -> op(x) *)
    let x = mk_var "x" x_ty in
    { Tir.fn_name   = op_name;
      fn_params     = [x];
      fn_ret_ty     = ret_ty;
      fn_body       = Tir.EApp (mk_var op_name unknown_ty, [Tir.AVar x]);
      fn_kind       = Tir.FnNormal }
  in
  let reg_method meth_name ty_name mangled_name =
    let existing = match Hashtbl.find_opt !_iface_methods meth_name with
      | Some l -> l | None -> [] in
    Hashtbl.replace !_iface_methods meth_name ((ty_name, mangled_name) :: existing)
  in
  let emit_builtin_fn name params ret_ty body_fn_name body_params =
    let fn : Tir.fn_def = {
      fn_name   = name;
      fn_params = params;
      fn_ret_ty = ret_ty;
      fn_body   = Tir.EApp (mk_var body_fn_name
                               (Tir.TFn (List.map (fun v -> v.Tir.v_ty) body_params, ret_ty)),
                             List.map (fun v -> Tir.AVar v) body_params);
      fn_kind   = Tir.FnNormal;
    } in
    fns := fn :: !fns
  in
  ignore (call2 "" Tir.TInt Tir.TInt Tir.TInt);  (* suppress unused warnings *)
  ignore (call1 "" Tir.TInt Tir.TInt);
  (* Eq implementations: eq(x, y) -> x == y *)
  let eq_types = [("Int", Tir.TInt); ("Float", Tir.TFloat);
                  ("String", Tir.TString); ("Bool", Tir.TBool)] in
  List.iter (fun (ty_name, tir_ty) ->
      let mangled = Printf.sprintf "Eq$%s.eq" ty_name in
      let x = mk_var "x" tir_ty and y = mk_var "y" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x; y]; fn_ret_ty = Tir.TBool;
        fn_body = Tir.EApp (mk_var "==" (Tir.TFn ([tir_ty; tir_ty], Tir.TBool)), [Tir.AVar x; Tir.AVar y]);
        fn_kind = Tir.FnNormal;
      } in
      fns := fn :: !fns;
      reg_method "eq" ty_name mangled
    ) eq_types;
  (* Ord implementations: compare(x, y) — delegate to typed C runtime builtins *)
  let ord_specs = [
    ("Int",    Tir.TInt,    "march_compare_int");
    ("Float",  Tir.TFloat,  "march_compare_float");
    ("String", Tir.TString, "march_compare_string");
  ] in
  List.iter (fun (ty_name, tir_ty, c_fn) ->
      let mangled = Printf.sprintf "Ord$%s.compare" ty_name in
      let x = mk_var "x" tir_ty and y = mk_var "y" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x; y]; fn_ret_ty = Tir.TInt;
        fn_body = Tir.EApp (mk_var c_fn (Tir.TFn ([tir_ty; tir_ty], Tir.TInt)), [Tir.AVar x; Tir.AVar y]);
        fn_kind = Tir.FnNormal;
      } in
      fns := fn :: !fns;
      reg_method "compare" ty_name mangled
    ) ord_specs;
  (* Show implementations: show(x) -> type_specific_to_string(x) *)
  let show_specs = [
    ("Int",    Tir.TInt,    "int_to_string");
    ("Float",  Tir.TFloat,  "float_to_string");
    ("Bool",   Tir.TBool,   "bool_to_string");
    (* Atoms compile to nameless FNV-1a i64 hashes; `atom_to_string` is
       backed by a compile-time-generated hash->name switch that llvm_emit
       emits at end-of-module (see ctx.atom_names / @march_atom_to_string). *)
    ("Atom",   Tir.TCon ("Atom", []), "atom_to_string");
  ] in
  List.iter (fun (ty_name, tir_ty, to_str_fn) ->
      let mangled = Printf.sprintf "Show$%s.show" ty_name in
      emit_builtin_fn mangled [mk_var "x" tir_ty] Tir.TString to_str_fn
        [mk_var "x" tir_ty];
      reg_method "show" ty_name mangled
    ) show_specs;
  (* Show$String.show: identity — the string is already its own representation *)
  let str_x = mk_var "x" Tir.TString in
  let show_str_fn : Tir.fn_def = {
    fn_name = "Show$String.show"; fn_params = [str_x];
    fn_ret_ty = Tir.TString;
    fn_body = Tir.EAtom (Tir.AVar str_x);
    fn_kind = Tir.FnNormal;
  } in
  fns := show_str_fn :: !fns;
  reg_method "show" "String" "Show$String.show";
  (* Show$Unit.show: always returns "()" *)
  let unit_x = mk_var "x" Tir.TUnit in
  let show_unit_fn : Tir.fn_def = {
    fn_name = "Show$Unit.show"; fn_params = [unit_x];
    fn_ret_ty = Tir.TString;
    fn_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitString "()"));
    fn_kind = Tir.FnNormal;
  } in
  fns := show_unit_fn :: !fns;
  reg_method "show" "Unit" "Show$Unit.show";
  (* Hash implementations: hash(x) — delegate to typed C runtime builtins *)
  let hash_specs = [
    ("Int",    Tir.TInt,    "march_hash_int");
    ("Float",  Tir.TFloat,  "march_hash_float");
    ("String", Tir.TString, "march_hash_string");
    ("Bool",   Tir.TBool,   "march_hash_bool");
  ] in
  List.iter (fun (ty_name, tir_ty, c_fn) ->
      let mangled = Printf.sprintf "Hash$%s.hash" ty_name in
      let x = mk_var "x" tir_ty in
      let fn : Tir.fn_def = {
        fn_name = mangled; fn_params = [x]; fn_ret_ty = Tir.TInt;
        fn_body = Tir.EApp (mk_var c_fn (Tir.TFn ([tir_ty], Tir.TInt)), [Tir.AVar x]);
        fn_kind = Tir.FnNormal;
      } in
      fns := fn :: !fns;
      reg_method "hash" ty_name mangled
    ) hash_specs;
  end; (* end of builtin iface injection *)
  (* Pass 1: Collect interface/impl declarations first so that interface
     method resolution is available when lowering function bodies.
     Recursively processes DMod contents so that impls declared inside
     imported modules (which are wrapped in DMod by resolve_imports) are
     also registered. *)
  let rec collect_iface_impls ~lower_bodies ?(mod_prefix = "") decls =
    (* Collect direct function/let names at this module level so that
       rename_tir_vars can qualify references inside impl method bodies.
       For example, inside `mod BigInt do impl Eq(BigInt) do fn eq(a,b) do
       bigint_eq_impl(a,b) end end end`, the impl method body calls
       `bigint_eq_impl` (unqualified), but Pass 2 emits the function as
       `BigInt.bigint_eq_impl`.  Applying rename_tir_vars here fixes the
       mismatch so mono can find the callee in fn_table. *)
    let direct_fn_names =
      if lower_bodies && mod_prefix <> "" then
        List.filter_map (function
          | Ast.DFn (def, _)     -> Some def.fn_name.txt
          | Ast.DLet (_, b, _) ->
            (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
          | _ -> None) decls
      else []
    in
    List.iter (fun d ->
        match d with
        | Ast.DInterface (idef, _) ->
          List.iter (fun (m : Ast.method_decl) ->
              if not (Hashtbl.mem !_iface_methods m.md_name.txt) then
                Hashtbl.replace !_iface_methods m.md_name.txt []
            ) idef.iface_methods
        | Ast.DImpl (idef, _) ->
          let type_name = match idef.impl_ty with
            | Ast.TyCon ({ txt = name; _ }, _) -> name
            (* Tuples dispatch by ARITY ("$Tuple2", "$Tuple3", …) so a distinct
               `impl Show((a,b))` vs `impl Show((a,b,c))` each resolve to their
               own method — arity-agnostic "$Tuple" collapsed them onto one slot.
               Mirrors the arity-keyed tuple pattern tags (`Tir_names.tuple_tag`)
               and the matching lookup in [Lower_state.resolve_iface_method]. *)
            | Ast.TyTuple tys -> Printf.sprintf "$Tuple%d" (List.length tys)
            | Ast.TyRecord _ -> "$Record"
            | _ -> "$Unknown"
          in
          List.iter (fun ((mname : Ast.name), (mdef : Ast.fn_def)) ->
              let mangled = Printf.sprintf "%s$%s.%s"
                idef.impl_iface.txt type_name mname.txt in
              let qualified_key = idef.impl_iface.txt ^ "." ^ mname.txt in
              (* Only lower the function body once per mangled name
                 (avoids double-lowering when DMod recursion re-encounters a
                 top-level impl that was already processed). *)
              let already = match Hashtbl.find_opt !_iface_methods qualified_key with
                | Some l -> List.mem_assoc type_name l
                | None   -> false
              in
              if not already then begin
                (* When lower_bodies is true, lower the impl method and emit
                   a TIR function.  When false (stdlib_context), only register
                   the dispatch entry — the function is already precompiled. *)
                ignore mdef;
                if lower_bodies then begin
                  let fn = Lower_decls.lower_fn_def env mdef in
                  (* If this impl is inside a module, qualify any references to
                     module-local functions (e.g. bigint_eq_impl → BigInt.bigint_eq_impl)
                     so that mono can find them in fn_table (which uses the
                     prefixed names from lower_stdlib_mod_decls). *)
                  let fn = if mod_prefix <> "" && direct_fn_names <> [] then
                    Lower_decls.rename_tir_vars mod_prefix direct_fn_names fn
                  else fn in
                  fns := { fn with fn_name = mangled } :: !fns
                end;
                let existing = match Hashtbl.find_opt !_iface_methods mname.txt with
                  | Some l -> l | None -> [] in
                Hashtbl.replace !_iface_methods mname.txt
                  ((type_name, mangled) :: existing);
                (* Also register under fully-qualified key "Interface.method" so that
                   polymorphic call sites using qualified names can be resolved
                   post-monomorphization. *)
                let existing2 = match Hashtbl.find_opt !_iface_methods qualified_key with
                  | Some l -> l | None -> [] in
                Hashtbl.replace !_iface_methods qualified_key
                  ((type_name, mangled) :: existing2)
              end
            ) idef.impl_methods
        | Ast.DMod (sub_name, _, inner_decls, _) ->
          (* Recurse, tracking the module prefix so that impl method bodies
             that call module-private functions are renamed correctly. *)
          collect_iface_impls ~lower_bodies
            ~mod_prefix:(mod_prefix ^ sub_name.txt ^ ".")
            inner_decls
        | _ -> ()
      ) decls
  in
  (* Stdlib context: only register dispatch table entries, don't lower bodies
     (they're already in the precompiled .so) *)
  if stdlib_context <> [] then
    collect_iface_impls ~lower_bodies:false stdlib_context;
  collect_iface_impls ~lower_bodies:true m.mod_decls;
  let all_context_decls = stdlib_context @ m.mod_decls in
  (* Build default-arg dispatch table from mangled DFn names (foo$N pattern).
     These are generated by desugar's expand_defaults_decl.
     Maps base_name -> [(arity, mangled_name)] so that call sites can be
     rewritten: EApp(EVar "greet", [x]) → EApp(EVar "greet$1", [x]). *)
  let default_dispatch = Hashtbl.create 8 in
  (* Walk into DMods and register module-QUALIFIED keys so that any
     arity-mangled foo$N declarations nested inside modules dispatch
     correctly at qualified call sites (Mod.foo → Mod.foo$N).  NOTE: as of
     today desugar only expands default-args to $N decls for top-level fns;
     module-nested default-arg fns go through a separate tuple-switch
     dispatcher in native codegen which MISCOMPILES non-pointer args (see
     test/native/default_args_nested repro: an explicitly passed Bool true
     arrives as false).  That bug is in the dispatcher lowering, not here. *)
  let rec build_default_dispatch prefix decls =
    List.iter (fun d ->
        match d with
        | Ast.DFn (def, _) ->
          let name = def.fn_name.txt in
          (match Tir_names.parse_default_arg name with
           | Some (base, _arity) ->
                let n_params = match def.fn_clauses with
                  | [] -> 0
                  | c :: _ -> List.length c.fc_params
                in
                let key = prefix ^ base in
                let mangled = prefix ^ name in
                let existing = try Hashtbl.find default_dispatch key with Not_found -> [] in
                Hashtbl.replace default_dispatch key ((n_params, mangled) :: existing)
           | None -> ())
        | Ast.DMod (mname, _, inner_decls, _) ->
          build_default_dispatch (prefix ^ mname.Ast.txt ^ ".") inner_decls
        | _ -> ()
      ) decls
  in
  build_default_dispatch "" all_context_decls;
  _default_dispatch := default_dispatch;
  (* Pre-pass: Lower top-level DFn declarations from stdlib_context so that
     monomorphization can specialize them at user call sites.  These are
     prelude functions (e.g. println, map) that live at global scope — they
     have no module prefix and are therefore not discoverable by the lazy
     _ensure_module_lowered mechanism, which only fires for qualified names.
     DMod / DImpl entries from stdlib_context are handled lazily (DMod) or
     via collect_iface_impls (DImpl) and must NOT be re-lowered here. *)
  if stdlib_context <> [] then
    List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        if not (Hashtbl.mem !_default_dispatch def.fn_name.txt) then begin
          let fn = Lower_decls.lower_fn_def env def in   (* evaluate before reading !fns *)
          fns := fn :: !fns
        end
      | _ -> ()
    ) stdlib_context;
  (* Make the entry module's own top-level function names the "current module"
     scope for Pass 2, mirroring what lower_mod_decls does for nested modules.
     This lets a bare call in the entry module resolve to the module's own
     function (e.g. a user `fn show` shadowing the Show interface method) rather
     than being redirected to an interface impl — matching the typechecker.
     Nested DMod lowering saves/restores this via with_current_module_fns. *)
  let entry_fn_names =
    List.filter_map (function
      | Ast.DFn (def, _) -> Some def.fn_name.txt
      | _ -> None) m.mod_decls
  in
  (let t = Hashtbl.create (List.length entry_fn_names) in
   List.iter (fun n -> Hashtbl.replace t n ()) entry_fn_names;
   _current_module_fns := t);
  (* Pass 2: Lower all other declarations. *)
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        (* Skip dispatcher DFns (original-named wrappers for default-arg functions).
           The mangled versions (foo$N) are the real implementations used by TIR.
           Dispatchers are only needed by the interpreter for VMultiarity dispatch. *)
        if not (Hashtbl.mem !_default_dispatch def.fn_name.txt) then begin
          let fn = Lower_decls.lower_fn_def env def in   (* evaluate before reading !fns *)
          fns := fn :: !fns
        end
      | Ast.DType (_, name, params, td, _)
      | Ast.DAlwaysLinearType (_, name, params, td, _) ->
        (match Lower_decls.lower_type_def name params td with
         | Some td' -> types := td' :: !types
         | None -> ())
      | Ast.DLet (_, b, _) ->
        let rhs = lower_expr env b.bind_expr in
        (match b.bind_pat with
         | Ast.PatVar n ->
           let v : Tir.var = {
             v_name = n.txt;
             v_ty = (match b.bind_ty with Some t -> lower_ty t
                     | None -> ty_of_expr env b.bind_expr);
             v_lin = lower_linearity b.bind_lin;
           } in
           top_lets := (v, rhs) :: !top_lets
         | _ -> ())
      | Ast.DActor (_, name, actor_def, _) ->
        let (new_types, new_fns) = Lower_actor.lower_actor env ~hot_reload name.txt actor_def in
        types := List.rev_append new_types !types;
        fns   := List.rev_append new_fns   !fns
      | Ast.DMod (mod_name, _, inner_decls, _) ->
        (* Register this module as already lowered BEFORE processing its declarations.
           Without this, _ensure_module_lowered fires later when a function body
           references e.g. "Map.insert" — it re-parses the stdlib file from disk
           WITHOUT the type_map, producing all-TVar-"_" signatures that overwrite
           the correctly-typed versions (added here) in fn_table via Hashtbl.replace
           last-write-wins.  Mono then sees only unknown types and cannot specialize
           iface dispatch (e.g. hash → march_hash_string/int/…), leaving a bare
           @hash extern that the linker cannot resolve. *)
        Hashtbl.replace !_lowered_modules mod_name.txt ();
        let rec lower_mod_decls (env : env) prefix decls =
          let direct_fn_names = List.filter_map (function
              | Ast.DFn (def, _) -> Some def.fn_name.txt
              | Ast.DLet (_, b, _) ->
                (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
              | _ -> None) decls in
          (* Scope the per-module import-alias table: inherit the enclosing
             module's aliases (via a fresh copy in [mod_env]) so this
             module's own imports (registered into [mod_env.current_module_aliases]
             below) do not leak into the CALLER's [env] value once this
             function returns — [env] itself is never mutated, so "restore"
             is automatic (the caller's own binding is untouched), the exact
             behavior the old code's [Fun.protect]-guarded [:=]/restore dance
             produced. *)
          let mod_env = { env with
            current_module_aliases = Hashtbl.copy env.current_module_aliases } in
          with_current_module_fns direct_fn_names (fun () ->
          List.iter (fun d ->
              match d with
              | Ast.DFn (def, _) ->
                let fn = Lower_decls.lower_fn_def mod_env def in
                let fn = Lower_decls.rename_tir_vars prefix direct_fn_names fn in
                fns := { fn with fn_name = prefix ^ fn.fn_name } :: !fns
              | Ast.DType (_, tname, params, td, _)
              | Ast.DAlwaysLinearType (_, tname, params, td, _) ->
                let qtname = { tname with txt = prefix ^ tname.txt } in
                (match Lower_decls.lower_type_def qtname params td with
                 | Some td' -> types := td' :: !types
                 | None -> ())
              | Ast.DMod (sub_name, _, sub_decls, _) ->
                lower_mod_decls mod_env (prefix ^ sub_name.txt ^ ".") sub_decls
              | Ast.DLet (_, b, _) ->
                (* Module-level let bindings are compiled as zero-arg functions
                   so they can be referenced by qualified name after
                   rename_tir_vars renames the short name to prefix^name. *)
                let rhs = lower_expr mod_env b.bind_expr in
                (match b.bind_pat with
                 | Ast.PatVar n ->
                   let fn : Tir.fn_def = {
                     fn_name   = prefix ^ n.txt;
                     fn_params = [];
                     fn_ret_ty = (match b.bind_ty with Some t -> lower_ty t
                                  | None -> ty_of_expr mod_env b.bind_expr);
                     fn_body   = rhs;
                     fn_kind   = Tir.FnNormal;  (* module-level `let` as zero-arg fn *)
                   } in
                   fns := fn :: !fns
                 | _ -> ())
              | Ast.DUse (ud, _) ->
                (* Handle [import X] inside a module body.  Functions from
                   imported modules are stored under the current context prefix
                   (e.g. "import Query" inside "mod Migration do" → fns are
                   named "Migration.Query.*").  Build aliases mapping the short
                   name (e.g. "simple_query") to the context-qualified name
                   (e.g. "Migration.Query.simple_query") so that calls to the
                   unqualified name are resolved correctly.

                   IMPORTANT: a sibling fn in the current module shadows an
                   imported name of the same kind.  Without this guard, a
                   module like [Controller] with [import ErrorView] followed
                   by [fn render] would have its own [render] calls rewritten
                   to [Controller.ErrorView.render].  [direct_fn_names] is
                   the list of sibling fn short-names collected upfront. *)
                let import_prefix =
                  String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) ^ "."
                in
                let ctx_prefix = prefix ^ import_prefix in
                let all_fn_names =
                  List.map (fun (fn : Tir.fn_def) -> fn.fn_name) !fns
                in
                let register_aliases p =
                  List.iter (fun fn_name ->
                    let plen = String.length p in
                    if String.length fn_name > plen
                       && String.sub fn_name 0 plen = p
                    then begin
                      let short = String.sub fn_name plen
                                    (String.length fn_name - plen) in
                      (* Skip if a sibling fn in the current module has the
                         same short name — sibling fns shadow imports. *)
                      if not (List.mem short direct_fn_names) then begin
                        note_alias_candidate short fn_name;
                        if not (Hashtbl.mem !_use_aliases short) then
                          Hashtbl.replace !_use_aliases short fn_name;
                        (* Also record in the CURRENT module's own alias table so
                           this import wins over a global alias another module
                           registered for the same short name.  First local
                           registration wins (mirrors the global first-wins). *)
                        if not (Hashtbl.mem mod_env.current_module_aliases short) then
                          Hashtbl.replace mod_env.current_module_aliases short fn_name
                      end
                    end
                  ) all_fn_names
                in
                (* Prefer context-qualified name (e.g. "Migration.Query.f");
                   fall back to bare module name (e.g. "Query.f") for
                   imports of top-level non-prefixed modules. *)
                register_aliases ctx_prefix;
                register_aliases import_prefix
              | Ast.DAlias (ad, _) ->
                (* `alias Long.Path as Short` INSIDE a module body.  The
                   top-level DAlias handler (which builds exact !fns-scanned
                   entries) is only reached for aliases at the entry file's
                   top level; an alias in an auto-discovered/stdlib module
                   body arrives here instead and was previously dropped by the
                   [_ -> ()] catch-all, so `Short.member` never resolved to
                   `Long.Path.member` and codegen emitted an undefined
                   `_Short.member` symbol.  Register the order-independent
                   prefix mapping (first-wins) — [resolve_use_alias]'s prefix
                   fallback then rewrites references without needing the target
                   sibling to have been lowered yet. *)
                let full_path =
                  String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) in
                let short = ad.alias_name.Ast.txt in
                if not (Hashtbl.mem !_module_aliases short) then
                  Hashtbl.replace !_module_aliases short full_path
              | Ast.DActor (_, name, actor_def, _) ->
                (* Actors defined inside a module block need the same spawn/handler
                   glue as top-level actors.  The spawn symbol uses the actor's
                   short name (e.g. "Pool_spawn"), not the module-qualified name,
                   because spawn(Pool) at the call site emits _Pool_spawn.
                   Handler bodies reference the module's private helpers by short
                   name; rename_tir_vars rewrites them to their qualified names so
                   the linker can resolve them (e.g. close_all → Pool.close_all). *)
                let (new_types, new_fns) = Lower_actor.lower_actor mod_env ~hot_reload name.txt actor_def in
                let renamed_fns = List.map (Lower_decls.rename_tir_vars prefix direct_fn_names) new_fns in
                types := List.rev_append new_types !types;
                fns   := List.rev_append renamed_fns !fns
              | Ast.DExtern (edef, _) ->
                (* Verified byte-identical (module leading whitespace) to the
                   top-level DExtern arm below — both now share
                   [Lower_decls.lower_extern_fns] rather than duplicating the
                   extern-lowering logic. *)
                externs := List.rev_append (Lower_decls.lower_extern_fns edef edef.ext_fns) !externs
              | _ -> ()
            ) decls);
          (* Save this module's aliases so the later test/setup lowering pass
             (collect_tests) can re-load them for DTest bodies. *)
          Hashtbl.replace !_module_alias_snapshots prefix
            (Hashtbl.copy mod_env.current_module_aliases)
        in
        lower_mod_decls env (mod_name.txt ^ ".") inner_decls
      | Ast.DExtern (edef, _) ->
        (* Verified byte-identical to the nested [lower_mod_decls] DExtern
           arm above (module leading whitespace) — dedup per Task 9's
           boundary. *)
        externs := List.rev_append (Lower_decls.lower_extern_fns edef edef.ext_fns) !externs
      | Ast.DInterface _ | Ast.DImpl _ -> ()  (* handled in pass 1 *)
      | Ast.DProtocol _ | Ast.DSig _
      | Ast.DNeeds _ | Ast.DProofCap _ | Ast.DApp _ | Ast.DDeriving _ | Ast.DSatisfy _
      | Ast.DTest _ | Ast.DSetup _ | Ast.DSetupAll _ -> ()
      | Ast.DTransitions _ -> ()
      | Ast.DUse (ud, _) ->
        (* Build use-import aliases: map unqualified names to qualified names.
           The qualified fn_defs are already in [fns] from DMod processing above.

           Each alias is registered into BOTH the program-global [_use_aliases]
           table AND this (entry) module's own [env.current_module_aliases] —
           mirroring the nested-module DUse handler (register_aliases above).
           The per-module table is what [resolve_use_alias] consults for
           MODULE-QUALIFIED (dotted) references: after the global fallback was
           restricted to unqualified names (to stop one module's bulk import
           hijacking another's qualified call), a bulk `import Foo` at the entry
           file's top level followed by the partial-qualified `Sub.fn(...)` form
           must still resolve to `Foo.Sub.fn` via THIS module's own table, or it
           would emit an undefined `_Sub.fn` symbol. *)
        let prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) ^ "." in
        let all_fn_names = List.map (fun (fn : Tir.fn_def) -> fn.fn_name) !fns in
        let register short fn_name =
          note_alias_candidate short fn_name;
          Hashtbl.replace !_use_aliases short fn_name;
          if not (Hashtbl.mem env.current_module_aliases short) then
            Hashtbl.replace env.current_module_aliases short fn_name
        in
        (match ud.use_sel with
         | Ast.UseSingle -> ()
         | Ast.UseAll ->
           (* Find all functions with the matching prefix *)
           List.iter (fun fn_name ->
               let plen = String.length prefix in
               if String.length fn_name > plen
                  && String.sub fn_name 0 plen = prefix
               then begin
                 let short = String.sub fn_name plen (String.length fn_name - plen) in
                 register short fn_name
               end
             ) all_fn_names
         | Ast.UseNames names ->
           List.iter (fun (n : Ast.name) ->
               let qualified = prefix ^ n.txt in
               if List.mem qualified all_fn_names then
                 register n.txt qualified
             ) names
         | Ast.UseExcept excluded ->
           let excl_set = List.map (fun (n : Ast.name) -> n.txt) excluded in
           List.iter (fun fn_name ->
               let plen = String.length prefix in
               if String.length fn_name > plen
                  && String.sub fn_name 0 plen = prefix
               then begin
                 let short = String.sub fn_name plen (String.length fn_name - plen) in
                 if not (List.mem short excl_set) then
                   register short fn_name
               end
             ) all_fn_names)
      | Ast.DAlias (ad, _) ->
        (* alias Long.Name, as: Short — map Short.f → Long.Name.f *)
        let orig_prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) ^ "." in
        let short_name = ad.alias_name.Ast.txt in
        let short_prefix = short_name ^ "." in
        let all_fn_names = List.map (fun (fn : Tir.fn_def) -> fn.fn_name) !fns in
        List.iter (fun fn_name ->
            let plen = String.length orig_prefix in
            if String.length fn_name > plen
               && String.sub fn_name 0 plen = orig_prefix
            then begin
              let rest = String.sub fn_name plen (String.length fn_name - plen) in
              Hashtbl.replace !_use_aliases (short_prefix ^ rest) fn_name
            end
          ) all_fn_names;
        (* Also register the order-independent prefix mapping so a reference
           whose target fn was not yet in [!fns] when this ran still resolves
           (see [resolve_use_alias]'s [_module_aliases] fallback).  The exact
           entries above still win when present; this only backstops. *)
        (let full_path =
           String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) in
         if not (Hashtbl.mem !_module_aliases short_name) then
           Hashtbl.replace !_module_aliases short_name full_path)
      | Ast.DDescribe _ | Ast.DOpts _ -> ()
    ) m.mod_decls;
  (* --- Test mode: collect DTest/DSetup/DSetupAll/DDescribe blocks and lower
     them to TIR functions so they can be compiled into a test-runner binary.
     [Lower_tests.run] appends to [fns]/[test_pairs] exactly as the inline
     closures used to (see that module's doc for the closure→parameter
     extraction rationale). *)
  let test_pairs = ref [] in   (* (fn_name, display_name) in declaration order *)
  if test_mode then
    Lower_tests.run env fns test_pairs m.mod_decls;
  (* Inject top-level let bindings into function bodies that reference them.
     We scan each fn_body for direct variable references to decide which
     top_lets to inject.  This avoids duplicate alloca names in mutco
     combined functions (which merge multiple fn_defs into one LLVM function). *)
  let rec fn_body_uses name (e : Tir.expr) =
    match e with
    | Tir.EAtom a -> atom_uses name a
    | Tir.EApp (f, args) ->
      f.Tir.v_name = name || List.exists (atom_uses name) args
    | Tir.ECallPtr (a, args) ->
      atom_uses name a || List.exists (atom_uses name) args
    | Tir.ELet (v, rhs, body) ->
      fn_body_uses name rhs ||
      (if v.Tir.v_name = name then false else fn_body_uses name body)
    | Tir.ELetRec (fns, body) ->
      List.exists (fun fn -> fn_body_uses name fn.Tir.fn_body) fns ||
      fn_body_uses name body
    | Tir.ECase (scrut, arms, def) ->
      atom_uses name scrut ||
      List.exists (fun br -> fn_body_uses name br.Tir.br_body) arms ||
      (match def with Some e -> fn_body_uses name e | None -> false)
    | Tir.ETuple atoms -> List.exists (atom_uses name) atoms
    | Tir.ERecord fields -> List.exists (fun (_, a) -> atom_uses name a) fields
    | Tir.EField (a, _) -> atom_uses name a
    | Tir.EUpdate (a, fields) ->
      atom_uses name a || List.exists (fun (_, a) -> atom_uses name a) fields
    | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
      List.exists (atom_uses name) atoms
    | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
    | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> atom_uses name a
    | Tir.EReuse (a, _, atoms) ->
      atom_uses name a || List.exists (atom_uses name) atoms
    | Tir.ESeq (e1, e2) -> fn_body_uses name e1 || fn_body_uses name e2
  and atom_uses name a =
    match a with Tir.AVar v -> v.Tir.v_name = name | _ -> false
  in
  let all_fns = List.rev !fns in
  let all_fns =
    match List.rev !top_lets with
    | [] -> all_fns
    | lets ->
      List.map (fun (fn : Tir.fn_def) ->
          let is_main = fn.fn_name = "main" ||
            (String.length fn.fn_name > 5 &&
             String.sub fn.fn_name (String.length fn.fn_name - 5) 5 = ".main") in
          let needed = List.filter (fun (v, _) ->
              is_main || fn_body_uses v.Tir.v_name fn.fn_body
            ) lets in
          match needed with
          | [] -> fn
          | _ ->
            let body = List.fold_right (fun (v, rhs) body ->
                Tir.ELet (v, rhs, body)) needed fn.fn_body in
            { fn with fn_body = body }
        ) all_fns
  in
  (* Alpha-rename any shadowed local binder to a fresh unique name so that
     every name-based downstream pass (cprop/fold/inline/dce and the JS
     [const] emitter) is immune to variable capture across shadowing.  A
     non-shadowing binder keeps its source name, so only genuinely-shadowing
     functions change shape.  See [Lower_decls.uniquify_fn]. *)
  let all_fns = List.map uniquify_fn all_fns in
  let result : Tir.tir_module = { tm_name = m.mod_name.txt;
    tm_fns = all_fns;
    tm_types = builtin_type_defs @ List.rev !types;
    tm_externs = List.rev !externs;
    tm_exports = [];
    tm_tests = List.rev !test_pairs;
    tm_io_fns = [] } in
  (* [env]'s [type_map] and [current_module_aliases] fields are local
     bindings, not refs — they are simply dropped when [lower_module]
     returns, with no explicit reset needed (was [_type_map_ref := None];
     [_current_module_aliases := Hashtbl.create 0]). *)
  (* Save a snapshot before clearing so the mono pass can use it. *)
  _saved_iface_methods := Hashtbl.copy !_iface_methods;
  _iface_methods := Hashtbl.create 0;
  _use_aliases := Hashtbl.create 0;
  _module_aliases := Hashtbl.create 0;
  result
