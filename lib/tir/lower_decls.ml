(** Declaration lowering: function/type defs, TIR variable renaming, extern
    declarations, and the lazy stdlib-module loader (Wave 3 Task 9: split
    out of [Lower]).

    Moved verbatim from lower.ml's "Declaration lowering" and "Qualified
    module lowering" sections. All functions here call [Lower_match]'s
    [lower_expr] wrapper (itself forwarding to lower.ml's [lower_expr] via
    the forward ref installed by [Lower_match.install_lower_expr]) strictly
    ONE WAY — nothing in lower.ml's [lower_expr] calls back into this
    module, so unlike [lower_match.ml] this file needs no forward-ref
    wiring of its own. *)

module Ast = March_ast.Ast

(* ── TIR renaming ───────────────────────────────────────────────── *)

(** Rename [AVar] atoms whose [v_name] appears in [names] by prefixing with
    [prefix].  Used when lowering [DMod] inner functions to rewrite unqualified
    intra-module call sites (e.g. [from_string] → [IOList.from_string]).

    Scope-aware: a local binder with the same name as a module function
    (a fn parameter, [ELet]/[ELetRec] binding, or [ECase] branch variable)
    shadows it — references to the shadowed name are left untouched within
    the binder's scope.  Without this, e.g. a parameter named [fields] in a
    module that also defines [fn fields(...)] had its body references
    rewritten to the qualified global, which the emitter then compiled as a
    zero-arg module-constant call ([call ptr @Mod.fields()]). *)
let rename_tir_vars (prefix : string) (names : string list) (fn : Tir.fn_def) : Tir.fn_def =
  let module SSet = Set.Make (String) in
  let rename_var bound (v : Tir.var) : Tir.var =
    if List.mem v.Tir.v_name names && not (SSet.mem v.Tir.v_name bound)
    then { v with Tir.v_name = prefix ^ v.Tir.v_name }
    else v
  in
  let rename_atom bound = function
    | Tir.AVar v -> Tir.AVar (rename_var bound v)
    | a -> a
  in
  let add_params bound (params : Tir.var list) =
    List.fold_left (fun acc (p : Tir.var) -> SSet.add p.Tir.v_name acc) bound params
  in
  let rec rename_expr bound = function
    | Tir.EAtom a        -> Tir.EAtom (rename_atom bound a)
    | Tir.EApp (v, args) -> Tir.EApp (rename_var bound v, List.map (rename_atom bound) args)
    | Tir.ECallPtr (f, args) -> Tir.ECallPtr (rename_atom bound f, List.map (rename_atom bound) args)
    | Tir.ELet (v, e1, e2) ->
      Tir.ELet (v, rename_expr bound e1, rename_expr (SSet.add v.Tir.v_name bound) e2)
    | Tir.ELetRec (fns, body) ->
      let bound' = List.fold_left (fun acc (f : Tir.fn_def) ->
          SSet.add f.Tir.fn_name acc) bound fns in
      Tir.ELetRec (List.map (rename_fn bound') fns, rename_expr bound' body)
    | Tir.ECase (scrut, branches, def) ->
      Tir.ECase (rename_atom bound scrut,
                 List.map (fun br ->
                     let bound' = add_params bound br.Tir.br_vars in
                     { br with Tir.br_body = rename_expr bound' br.Tir.br_body }) branches,
                 Option.map (rename_expr bound) def)
    | Tir.ETuple atoms   -> Tir.ETuple (List.map (rename_atom bound) atoms)
    | Tir.ERecord fields -> Tir.ERecord (List.map (fun (k, a) -> (k, rename_atom bound a)) fields)
    | Tir.EField (a, f)  -> Tir.EField (rename_atom bound a, f)
    | Tir.EUpdate (a, fields) ->
      Tir.EUpdate (rename_atom bound a, List.map (fun (k, v) -> (k, rename_atom bound v)) fields)
    | Tir.EAlloc (ty, args)      -> Tir.EAlloc (ty, List.map (rename_atom bound) args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map (rename_atom bound) args)
    | Tir.EFree a   -> Tir.EFree (rename_atom bound a)
    | Tir.EIncRC a       -> Tir.EIncRC (rename_atom bound a)
    | Tir.EDecRC a       -> Tir.EDecRC (rename_atom bound a)
    | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (rename_atom bound a)
    | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (rename_atom bound a)
    | Tir.EReuse (a, ty, args) -> Tir.EReuse (rename_atom bound a, ty, List.map (rename_atom bound) args)
    | Tir.EAllocHole (ty, args, hole) ->
      Tir.EAllocHole (ty, List.map (rename_atom bound) args, hole)
    | Tir.ESetField (o, i, v) ->
      Tir.ESetField (rename_atom bound o, i, rename_atom bound v)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (rename_expr bound e1, rename_expr bound e2)
  and rename_fn bound (f : Tir.fn_def) : Tir.fn_def =
    let bound' = add_params bound f.Tir.fn_params in
    { f with Tir.fn_body = rename_expr bound' f.Tir.fn_body }
  in
  rename_fn SSet.empty fn

(* ── Shadow uniquification (alpha-rename of shadowed local binders) ── *)

(** Make every local binder name within a function UNIQUE by alpha-renaming
    any binder that SHADOWS a name already in scope to a fresh name
    ([orig ^ "$sh" ^ N]).  References within the shadowed binder's scope are
    rewritten to match.

    Why this is necessary — the lowering CPS builds a block like
    [let x = 10 ; let x = x + 5 ; int_to_string(x)] into a right-nested chain
    of [ELet]s that reuse the SOURCE name verbatim:
        let x : Int = 10 in
        let x : Int = +(x, 5) in
        int_to_string(x)
    The tree is structurally correct (proper lexical nesting), and the native
    codegen ([llvm_emit]) copes because it renames colliding alloca slots.
    But every NAME-BASED TIR pass is vulnerable to capture: copy-propagation
    ([cprop]/[fold]) records [x -> 10] from the OUTER binding and substitutes
    it into [int_to_string(x)] — whose [x] semantically refers to the INNER
    binding — folding the program to [int_to_string(10)] (prints 10, not 15).
    The [--target js] backend independently emits nested [const x = (… x …)]
    blocks that hit the temporal-dead-zone (TDZ) on the self-reference.

    Making binder names unique at the end of lowering fixes the whole class at
    once (cprop, fold, inline, dce, and the JS [const] emitter) and aligns the
    compiled backends with the interpreter's lexical scoping.

    Minimal by design: a binder that does NOT shadow keeps its original name,
    so non-shadowing code (the overwhelming majority) is byte-for-byte
    unchanged and only genuinely-shadowing programs shift in TIR snapshots. *)
let uniquify_fn (fn : Tir.fn_def) : Tir.fn_def =
  let module SMap = Map.Make (String) in
  let counter = ref 0 in
  let fresh (base : string) : string =
    incr counter; Printf.sprintf "%s$sh%d" base !counter in
  (* env maps a source name to the unique TIR name currently in scope. *)
  let resolve env name = match SMap.find_opt name env with Some n -> n | None -> name in
  let rename_var env (v : Tir.var) : Tir.var = { v with Tir.v_name = resolve env v.Tir.v_name } in
  let rename_atom env = function
    | Tir.AVar v -> Tir.AVar (rename_var env v)
    | a -> a in
  (* Introduce a binder: if its name is already bound in [env] it shadows, so
     give it a fresh unique name; otherwise keep it.  Returns the (possibly
     renamed) var and the extended env for the binder's scope. *)
  let intro env (v : Tir.var) : Tir.var * 'a =
    if SMap.mem v.Tir.v_name env then
      let nn = fresh v.Tir.v_name in
      ({ v with Tir.v_name = nn }, SMap.add v.Tir.v_name nn env)
    else
      (v, SMap.add v.Tir.v_name v.Tir.v_name env) in
  let intro_all env (vs : Tir.var list) : Tir.var list * 'a =
    let env', vs' =
      List.fold_left (fun (env, acc) v ->
          let v', env' = intro env v in (env', v' :: acc)) (env, []) vs in
    (List.rev vs', env') in
  let rec go env = function
    | Tir.EAtom a        -> Tir.EAtom (rename_atom env a)
    | Tir.EApp (v, args) -> Tir.EApp (rename_var env v, List.map (rename_atom env) args)
    | Tir.ECallPtr (f, args) -> Tir.ECallPtr (rename_atom env f, List.map (rename_atom env) args)
    | Tir.ELet (v, e1, e2) ->
      (* e1 is in the OUTER scope; the binder is visible only in e2. *)
      let e1' = go env e1 in
      let v', env' = intro env v in
      Tir.ELet (v', e1', go env' e2)
    | Tir.ELetRec (fns, body) ->
      (* Function names are mutually visible in all bodies and the continuation. *)
      let env', fns_named =
        List.fold_left (fun (env, acc) (f : Tir.fn_def) ->
            if SMap.mem f.Tir.fn_name env then
              let nn = fresh f.Tir.fn_name in
              (SMap.add f.Tir.fn_name nn env, { f with Tir.fn_name = nn } :: acc)
            else
              (SMap.add f.Tir.fn_name f.Tir.fn_name env, f :: acc)) (env, []) fns in
      let fns' = List.map (go_fn env') (List.rev fns_named) in
      Tir.ELetRec (fns', go env' body)
    | Tir.ECase (scrut, branches, def) ->
      Tir.ECase (rename_atom env scrut,
                 List.map (fun (br : Tir.branch) ->
                     let vars', env' = intro_all env br.Tir.br_vars in
                     { br with Tir.br_vars = vars'; Tir.br_body = go env' br.Tir.br_body })
                   branches,
                 Option.map (go env) def)
    | Tir.ETuple atoms   -> Tir.ETuple (List.map (rename_atom env) atoms)
    | Tir.ERecord fields -> Tir.ERecord (List.map (fun (k, a) -> (k, rename_atom env a)) fields)
    | Tir.EField (a, f)  -> Tir.EField (rename_atom env a, f)
    | Tir.EUpdate (a, fields) ->
      Tir.EUpdate (rename_atom env a, List.map (fun (k, v) -> (k, rename_atom env v)) fields)
    | Tir.EAlloc (ty, args)      -> Tir.EAlloc (ty, List.map (rename_atom env) args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map (rename_atom env) args)
    | Tir.EFree a        -> Tir.EFree (rename_atom env a)
    | Tir.EIncRC a       -> Tir.EIncRC (rename_atom env a)
    | Tir.EDecRC a       -> Tir.EDecRC (rename_atom env a)
    | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (rename_atom env a)
    | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (rename_atom env a)
    | Tir.EReuse (a, ty, args) -> Tir.EReuse (rename_atom env a, ty, List.map (rename_atom env) args)
    | Tir.EAllocHole (ty, args, hole) ->
      Tir.EAllocHole (ty, List.map (rename_atom env) args, hole)
    | Tir.ESetField (o, i, v) ->
      Tir.ESetField (rename_atom env o, i, rename_atom env v)
    | Tir.ESeq (e1, e2)  -> Tir.ESeq (go env e1, go env e2)
  and go_fn env (f : Tir.fn_def) : Tir.fn_def =
    let params', env' = intro_all env f.Tir.fn_params in
    { f with Tir.fn_params = params'; Tir.fn_body = go env' f.Tir.fn_body } in
  go_fn SMap.empty fn

(* ── Declaration lowering ───────────────────────────────────────── *)

(** Lower a single function definition (post-desugaring: exactly 1 clause). *)
let lower_fn_def (env : Lower_state.env) (def : Ast.fn_def) : Tir.fn_def =
  let clause = match def.fn_clauses with
    | [c] -> c
    | _ -> failwith (Printf.sprintf "TIR lower: fn %s has %d clauses (expected 1 after desugaring)"
                       def.fn_name.txt (List.length def.fn_clauses))
  in
  (* For polymorphic fn_defs, prefer the typechecker's inferred type over the
     surface annotation.  The typechecker has already unified the source-level
     named type variable (e.g. `a` in `fn nth(xs: List(a), n: Int) : a`) with
     the unbound unification variable used in the body's typed expressions.
     Using `lower_ty` on the annotation would emit `TVar "a"`, but the body
     uses `TVar "_<id>"`.  Monomorphization's subst keys off the param TVar,
     so the two names must match — otherwise the body's TVars never get
     substituted and recursive calls fall back to a polymorphic specialization
     named e.g. `List.nth$List_V__1771$Int`, causing runtime infinite recursion.
     Only when the typechecker has no record for this span (placeholder
     [TVar "_"]) do we fall back to the source annotation. *)
  let ty_from_tc_or_ann (tc_ty : Tir.ty) (ann : Ast.ty option) : Tir.ty =
    match tc_ty, ann with
    | Tir.TVar "_", Some t -> Lower_types.lower_ty t
    | Tir.TVar "_", None -> tc_ty
    | _ -> tc_ty
  in
  let params = List.map (fun fp ->
      match fp with
      | Ast.FPNamed p ->
        let ty = ty_from_tc_or_ann (Lower_state.ty_of_span env p.param_name.span) p.param_ty in
        { Tir.v_name = p.param_name.txt;
          v_ty = ty;
          v_lin = Lower_types.lower_linearity p.param_lin }
      | Ast.FPPat (Ast.PatVar n) ->
        { Tir.v_name = n.txt; v_ty = Lower_state.ty_of_span env n.span; v_lin = Tir.Unr }
      | _ -> failwith "TIR lower: unexpected pattern param after desugaring"
    ) clause.fc_params in
  let ret_ty =
    (* Same rationale as params: prefer the typechecker's inferred return type,
       falling back to the source annotation only when the typechecker has no
       record for the body span. *)
    let tc_ret = Lower_state.ty_of_expr env clause.fc_body in
    ty_from_tc_or_ann tc_ret def.fn_ret_ty
  in
  (* Populate the parameter type scope so that body variable references can
     fall back to the declared parameter type when ty_of_span gives TError.
     Save/restore to handle nested lower_fn_def calls (impl methods, etc.). *)
  let saved_scope = Hashtbl.copy Lower_state._fn_param_types in
  Hashtbl.clear Lower_state._fn_param_types;
  List.iter (fun v -> Hashtbl.replace Lower_state._fn_param_types v.Tir.v_name v.Tir.v_ty) params;
  let body = Lower_match.lower_expr env clause.fc_body in
  Hashtbl.clear Lower_state._fn_param_types;
  Hashtbl.iter (fun k v -> Hashtbl.replace Lower_state._fn_param_types k v) saved_scope;
  { fn_name = def.fn_name.txt; fn_params = params; fn_ret_ty = ret_ty; fn_body = body;
    fn_kind = Tir.FnNormal }  (* parsed user/stdlib/impl-method fn *)

(** Lower a type definition. *)
let lower_type_def (name : Ast.name) (_params : Ast.name list) (td : Ast.type_def) : Tir.type_def option =
  match td with
  | Ast.TDVariant variants ->
    let ctors = List.map (fun (v : Ast.variant) ->
        (v.var_name.txt, List.map Lower_types.lower_ty v.var_args)
      ) variants in
    Some (Tir.TDVariant (name.txt, ctors))
  | Ast.TDRecord fields ->
    let fs = List.map (fun (f : Ast.field) ->
        (f.fld_name.txt, Lower_types.lower_ty f.fld_ty)
      ) fields in
    Some (Tir.TDRecord (name.txt, fs))
  | Ast.TDAlias _ -> None

(** Lower a single [DExtern] declaration's function list to [Tir.extern_decl]
    entries.  Factored out because lower.ml's [lower_module] previously had
    TWO verbatim-identical copies of this block (one in the top-level Pass 2
    walker, one in the nested [lower_mod_decls] walker) — verified
    byte-identical (module leading whitespace, which differed only because
    one copy sat one indentation level deeper inside a nested [match]) before
    deduping into this single shared helper. Both call sites now call this
    function and [@ externs :=] the result themselves. *)
let lower_extern_fns (edef : Ast.extern_def) (ext_fns : Ast.extern_fn list) : Tir.extern_decl list =
  List.map (fun (ef : Ast.extern_fn) ->
      let params = List.map (fun (_, t) -> Lower_types.lower_ty t) ef.ef_params in
      let ret = Lower_types.lower_ty ef.ef_ret_ty in
      let c_name = match ef.ef_symbol with
        | Some s -> s
        | None   -> edef.Ast.ext_lib_name ^ "_" ^ ef.ef_name.txt in
      let js_sym = match ef.ef_symbol with
        | Some s -> s
        | None   -> ef.ef_name.txt in
      { Tir.ed_march_name = ef.ef_name.txt;
        ed_c_name = c_name;
        ed_lib_name = edef.Ast.ext_lib_name;
        ed_js_sym = js_sym;
        ed_params = params;
        ed_consumed = ef.ef_param_consumed;
        ed_blocking = ef.ef_blocking;
        ed_raises = ef.ef_raises;
        ed_ret = ret }
    ) ext_fns

(* ── Qualified module lowering (implementation) ───────────────── *)

(** Lower all declarations from a stdlib module's body, adding functions
    and types to the current module-level accumulator refs. *)
let rec lower_stdlib_mod_decls (env : Lower_state.env) prefix decls =
  let direct_fn_names = List.filter_map (function
      | Ast.DFn (def, _) -> Some def.fn_name.txt
      | Ast.DLet (_, b, _) ->
        (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
      | _ -> None) decls in
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        let fn = lower_fn_def env def in
        let fn = rename_tir_vars prefix direct_fn_names fn in
        !Lower_state._fns_ref := { fn with fn_name = prefix ^ fn.fn_name } :: !(!Lower_state._fns_ref)
      | Ast.DType (_, tname, params, td, _)
      | Ast.DAlwaysLinearType (_, tname, params, td, _) ->
        let qtname = { tname with txt = prefix ^ tname.txt } in
        (match lower_type_def qtname params td with
         | Some td' -> !Lower_state._types_ref := td' :: !(!Lower_state._types_ref)
         | None -> ())
      | Ast.DMod (sub_name, _, sub_decls, _) ->
        lower_stdlib_mod_decls env (prefix ^ sub_name.txt ^ ".") sub_decls
      | Ast.DLet (_, b, _) ->
        (* Module-level let bindings are compiled as zero-arg functions so they
           can be referenced by qualified name (e.g. Crypto.pw_dklen). *)
        (match b.bind_pat with
         | Ast.PatVar n ->
           let rhs = Lower_match.lower_expr env b.bind_expr in
           let fn : Tir.fn_def = {
             fn_name   = prefix ^ n.txt;
             fn_params = [];
             fn_ret_ty = (match b.bind_ty with Some t -> Lower_types.lower_ty t
                          | None -> Lower_state.ty_of_expr env b.bind_expr);
             fn_body   = rhs;
             fn_kind   = Tir.FnNormal;  (* module-level `let` as zero-arg fn *)
           } in
           !Lower_state._fns_ref := fn :: !(!Lower_state._fns_ref)
         | _ -> ())
      | _ -> ()
    ) decls

let () = Lower_state._ensure_module_lowered := (fun env mod_name ->
  if not (Hashtbl.mem !Lower_state._lowered_modules mod_name) then begin
    Hashtbl.replace !Lower_state._lowered_modules mod_name ();
    match March_modules.Module_registry.find_stdlib_file mod_name with
    | None -> ()
    | Some path ->
      (try
         let ic = open_in_bin path in
         let n = in_channel_length ic in
         let b = Bytes.create n in
         really_input ic b 0 n;
         close_in ic;
         let src = Bytes.to_string b in
         let lexbuf = Lexing.from_string src in
         lexbuf.Lexing.lex_curr_p <-
           { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
         let ast = March_parser.Parser.module_
                     (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
         let ast = March_desugar.Desugar.desugar_module ast in
         lower_stdlib_mod_decls env (mod_name ^ ".") ast.mod_decls
       with _ -> ())
  end)
