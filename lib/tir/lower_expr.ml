(** The CPS/ANF lowering core — [lower_to_atom_k], [lower_expr], [lower_atoms_k].

    One [let rec … and] group: the mutually-recursive heart of AST → TIR
    lowering that every other [Lower_*] module calls into.  Moved VERBATIM out
    of [Lower] (finding 3 of
    [specs/2026-08-25-file-decomposition-analysis.md]); [Lower] re-exports the
    three names, so no call site changed.

    ── Why the [Lower_match] hook lives at the BOTTOM of this file ──────────

    [Lower_match] is mutually recursive with [lower_expr] (2 call directions,
    5 edges) and the cycle is broken by a forward ref, installed once at
    module-load time by the [let () = Lower_match.install_lower_expr] at the
    end of this file.  That hook MOVED WITH THE BAND and must stay here: it
    has to run after [lower_expr] is defined, and it cannot live in [Lower]
    any more, because [Lower] no longer defines [lower_expr] — it only
    aliases it.  Leaving the hook behind builds, but installs the alias
    before/independently of this module's initialisation, which is exactly
    the kind of init-order bug an oracle cannot see.

    The alias block below is a verbatim copy of the one in [lower.ml]: 16
    one-line re-exports of [Lower_state] / [Lower_types] / [Lower_decls]
    values the band uses.  No logic is duplicated. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

type env = Lower_state.env = {
  type_map : (Ast.span, Typecheck.ty) Hashtbl.t option;
  current_module_aliases : (string, string) Hashtbl.t;
  mod_prefix : string;
  collision_set : (string, string list) Hashtbl.t;
}

let ty_of_span = Lower_state.ty_of_span
let ty_of_expr = Lower_state.ty_of_expr
let unknown_ty = Lower_types.unknown_ty
let lower_ty = Lower_types.lower_ty
let lower_linearity = Lower_types.lower_linearity
let fresh_name = Lower_state.fresh_name
let fresh_var = Lower_state.fresh_var
let _fn_param_types = Lower_state._fn_param_types
let _use_aliases = Lower_state._use_aliases
let _protocol_roles = Lower_state._protocol_roles
let _current_module_fns = Lower_state._current_module_fns
let resolve_use_alias = Lower_state.resolve_use_alias
let _ensure_module_lowered = Lower_state._ensure_module_lowered
let _default_dispatch = Lower_state._default_dispatch
let resolve_iface_method = Lower_state.resolve_iface_method
let lower_fn_def = Lower_decls.lower_fn_def

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
    (match rhs with
     (* Already a VARIABLE atom — pass it straight through instead of binding
        it to a fresh temp.  `let v = EAtom (AVar x) in k (AVar v)` and
        `k (AVar x)` are equivalent in ANF, but they are NOT equivalent to
        Perceus: the let-bound alias looks like a second owned reference to the
        same value, so RC insertion brackets it with an inc_rc/dec_rc pair that
        buys nothing.  This arm is reached when a lowering rule collapses an
        expression to one of its operands — e.g. the `Show$String.show`
        identity elision above, which every `"${s}"` interpolation of a String
        goes through.

        Restricted to [AVar] on purpose.  A LITERAL atom carries no type of its
        own, so the fresh binder's [ty_of_expr] ascription is load-bearing for
        it: passing a bare `ALit (LitAtom …)` through drops that type and
        `println(:x)` / `show(:x)` fall back to the untyped path and print `()`
        instead of `:x`. *)
     | Tir.EAtom (Tir.AVar _ as a) -> k a
     | _ ->
       (* Prefer the type the LOWERING computed over the one the source span
          records.  For a lambda, [lower_expr] returns
          [ELetRec ([fn], EAtom (AVar fn_var))] and builds [fn_var.v_ty] as
          [TFn (param_tys, ret_ty)] from the fn_def it just constructed — that
          is authoritative by construction.  [ty_of_expr env e] consults the
          shared type_map by span, which for a ZERO-ARG lambda hands back the
          RETURN type instead of `() -> ret`, so the temp holding the closure
          is typed as whatever the thunk computes.  Codegen then loads the
          captured closure with the return type's LLVM representation:
          `Task.async(fn () -> 1.5)` typed the captured `f : () -> Float` as
          `Float`, emitted `load double` for a closure pointer and
          `inttoptr i64 %d` on a `double`, and clang rejected the module
          ('%ldN' defined with type 'double' but expected 'i64').  An Int thunk
          is mistyped identically and merely survives because i64 and ptr share
          a register — so this is a latent miscompile for every zero-arg
          lambda, not only the Float one that made it visible.
          See specs/progress/2026-08-21-float-returning-task-compiled.md. *)
       let ty = match rhs with
         | Tir.ELetRec ([_], Tir.EAtom (Tir.AVar fv)) -> fv.Tir.v_ty
         | _ -> ty_of_expr env e
       in
       let v = fresh_var ty in
       Tir.ELet (v, rhs, k (Tir.AVar v)))

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
     | Ast.PatTuple (_, _) | Ast.PatRecord (_, _) ->
       (* This arm now also carries the record case (`let { x, y } = r`) via
          bind_subpat's PatRecord case below; the local names ($p, rhs_tuple_ty)
          stay tuple-flavored to keep the diff small, but the logic is generic
          over any irrefutable compound pattern.
          let (a, b, ...) = rhs  →  let $p = rhs; let a = $p.$fv0; let b = $p.$fv1; …
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
         | Ast.PatRecord (fs, _) ->
           (* let { x: a, y: b } = r  →  let a = r.x; let b = r.y; …
              Mirrors the PatTuple arm above: each field gets its concrete
              type so scalar fields are loaded with the right tagging, and
              compound sub-patterns recurse through a fresh intermediate. *)
           let field_ty name =
             match scrut_ty with
             | Tir.TRecord fts ->
               (match List.assoc_opt name fts with
                | Some t -> t
                | None -> unknown_ty)
             | _ -> unknown_ty
           in
           List.fold_right (fun ((n : Ast.name), sub) acc ->
             let fname_txt = n.Ast.txt in
             match sub with
             | Ast.PatWild _ -> acc   (* wildcard field → no binding *)
             | Ast.PatVar vn ->
               let fty =
                 match field_ty fname_txt with
                 | t when t = unknown_ty -> ty_of_span env vn.Ast.span
                 | t -> t
               in
               let fv : Tir.var =
                 { v_name = vn.Ast.txt; v_ty = fty; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, fname_txt), acc)
             | _ ->
               let fty = field_ty fname_txt in
               let tmp = fresh_name "p" in
               let fv : Tir.var =
                 { v_name = tmp; v_ty = fty; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, fname_txt),
                 bind_subpat (Tir.AVar fv) fty sub acc)
           ) fs inner
         | _ ->
           (* Refutable sub-patterns in an irrefutable `let` are still not
              decomposed here — such a `let` is a type error upstream. *)
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
    (* The params shadow import aliases inside the body.  Registering only
       [fn_name] above left them unbound as far as [resolve_use_alias] is
       concerned, so a param whose name matched an imported fn — depot's
       `fn go(i, acc)` against stdlib's [Logger.i], reached by any file with
       `import Logger` — lowered to that fn's address instead of the
       parameter. *)
    let fn_body' =
      Lower_state.with_scope_locals
        (List.map (fun (v : Tir.var) -> v.Tir.v_name) params')
        (fun () -> lower_expr env fn_body)
    in
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
    (* `Show$String.show` is the synthesized IDENTITY on String (emitted by
       [emit_builtin_impls] below: `fn x -> x`, because a string already IS
       its own representation).  Emitting the call and letting a later pass
       remove it is NOT free: Perceus runs first, sees a real owned-argument
       call, and brackets it with an inc_rc/dec_rc pair; the opt loop that
       inlines the identity away runs afterwards and leaves the pair behind.
       Every string interpolation lowers `"${s}"` to `to_string(s)`, which
       dispatches here, so that leftover atomic pair was charged to every
       interpolated String operand in every March program.  Elide the call at
       the source instead — then Perceus never sees a call to bracket. *)
    begin match resolved_f, args with
    | Ast.EVar { txt = "Show$String.show"; _ }, [ arg ] -> lower_expr env arg
    | _ ->
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
    end

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
      (* Collision-conditional module qualification (Task 3 of
         docs/superpowers/plans/2026-07-21-ctor-module-identity.md): a
         same-short-name type declared by >= 2 modules stays a BARE
         [TCon(type_name, _)] in the static [Tir.ty] (the whole plan's
         "TCon stays bare" invariant — see [Collision_set]'s module doc),
         so bare `type_name ^ "." ^ short_tag` collapses two different
         modules' identically-named constructors (e.g. both declaring a
         nullary `Shared`) onto ONE ctor_info key at codegen time —
         whichever [TDVariant] registers last silently wins for BOTH
         constructions. Qualifying by [env.mod_prefix] (the LEXICAL
         enclosing module of THIS construction) produces the same
         qualified key [build_ctor_info] (llvm_toplevel.ml) already
         computes from [tm_types]' module-qualified type names — so the
         two agree without a second collision-set computation. Gated on
         membership in the NARROW [Lower_state.shared_ctor_collision_tbl]
         (Task 5.5 — public, impl-bearing collisions only), NOT the broad
         [Collision_set.is_colliding]: a stdlib structural-interop [ptype]
         (e.g. two [ptype Seq(a) = Seq(a)] declarations relied on for a
         cross-module hand-off) collides by [Collision_set]'s measure but must
         NOT be qualified — its construction and consuming pattern must both
         stay bare so they agree via [ctor_entry]'s suffix resolver. A
         non-colliding (or non-public / impl-less colliding) type's key is
         unconditionally the old bare form, so ordinary programs are
         byte-identical. The [env.mod_prefix <> ""] half of the gate stays. *)
      let ctor_key = match ty_of_span env span with
        | Tir.TCon (type_name, _) ->
          (match Lower_state.reserved_monitor_ctor_key
                   ~module_prefix:env.mod_prefix ~source_tag:tag
                   ~type_name:(Some type_name) ~ctor_name:short_tag with
           | Some key -> key
           | None ->
             (* Qualifier-carrying construction of a narrow-collision ctor:
                the pattern-side counterpart (lower_match.ml's qualified-tag
                branch) re-expands a written module qualifier (`Ast.Asc`)
                into the 3-segment "Mod.Type.Ctor" key when
                [shared_ctor_collision_type] resolves it.  Without the same
                re-expansion here, the construction keyed bare
                ("SortDir.Asc") while the pattern keyed qualified
                ("Ast.SortDir.Asc"); codegen's [ctor_entry] suffix scan then
                resolved the bare construction against whichever colliding
                type registered first (stdlib DataFrame.SortDir.Asc, tag
                33554493) while the match switch tested the pattern's tag
                (Ast.SortDir.Asc, 33554516) — every qualified construction
                of a collision ctor failed open to the match's default arm
                at runtime (depot ORDER BY/GROUP BY, 2026-08-20). *)
             let qualified_collision_key =
               match String.rindex_opt tag '.' with
               | None -> None
               | Some i ->
                 let qual = String.sub tag 0 (i + 1) in
                 (match Lower_state.shared_ctor_collision_type qual short_tag with
                  | Some _ -> Some (qual ^ type_name ^ "." ^ short_tag)
                  | None -> None)
             in
             (match qualified_collision_key with
              | Some key -> key
              | None ->
                if env.mod_prefix <> ""
                   && Lower_state.shared_ctor_collision_type env.mod_prefix short_tag <> None
                then env.mod_prefix ^ type_name ^ "." ^ short_tag
                else type_name ^ "." ^ short_tag))
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
    (* Every param also shadows import aliases for the body, whether or not it
       carried a usable type above: the [TVar "_"] arm removes the name from
       _fn_param_types, which would otherwise let [resolve_use_alias] rewrite a
       reference to it into some imported module's same-named fn. *)
    let body' =
      Lower_state.with_scope_locals
        (List.map (fun (v : Tir.var) -> v.Tir.v_name) params')
        (fun () -> lower_expr env body)
    in
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
    (* The params shadow import aliases inside the body.  Unlike [ELam] above
       this path never registered them anywhere, so a param whose name matched
       an imported fn (depot's `fn go(i, acc)` vs stdlib's [Logger.i]) was
       resolved to that fn's address instead of the parameter. *)
    let body' =
      Lower_state.with_scope_locals
        (List.map (fun (v : Tir.var) -> v.Tir.v_name) params')
        (fun () -> lower_expr env body)
    in
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

  (* --- let* p = e; cont  →  M.flat_map(e, fn $tmp -> match $tmp do p -> cont end end)
     where M is e's head type constructor (Option, Result, a user type, ...).
     Unlike ELetQ (hardwired to Result's two ctors, so it can build the
     exhaustive match directly), ELetStar has no fixed shape to match on --
     it must go through the SAME `M.flat_map` call an ordinary qualified
     call would make, so this constructs that call and re-enters
     [lower_expr] on it, exactly as ELetQ re-enters on its synthesized
     EMatch above. `M` is resolved from [result_expr]'s type, already
     pinned by typecheck (which validated `M.flat_map` exists and has the
     right shape) and available here via [ty_of_expr]/[env.type_map]. *)
  | Ast.ELetStar (p, result_expr, cont, sp) ->
    let dsp = Ast.dummy_span in
    let head_name = match ty_of_expr env result_expr with
      | Tir.TCon (name, _) -> name
      | _ ->
        failwith (Printf.sprintf
          "lower_expr: let* at %s:%d could not determine its right-hand \
           side's type constructor (should have been caught by typecheck)"
          sp.Ast.file sp.Ast.start_line)
    in
    let tmp : Ast.name = { txt = "$letstar_tmp"; span = dsp } in
    let match_branch : Ast.branch = {
      branch_pat   = p;
      branch_guard = None;
      branch_body  = cont;
    } in
    let callback = Ast.ELam (
        [ { Ast.param_name = tmp; param_ty = None; param_lin = Ast.Unrestricted } ],
        Ast.EMatch (Ast.EVar tmp, [match_branch], dsp),
        dsp)
    in
    let flat_map_call =
      Ast.EApp (
        Ast.EVar { txt = head_name ^ ".flat_map"; span = dsp },
        [ result_expr; callback ],
        dsp)
    in
    lower_expr env flat_map_call

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
