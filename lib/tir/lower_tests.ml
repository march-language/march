(** Test-mode declaration collection: DTest/DSetup/DSetupAll/DDescribe →
    TIR test-runner functions (Wave 3 Task 9: split out of [Lower]).

    Moved verbatim from lower.ml's "Test mode" section inside [lower_module].
    That section was originally a set of closures defined INLINE in
    [lower_module], capturing [lower_module]'s own local accumulator refs
    ([fns], [test_pairs]) and its [env]/[m] parameters directly. To move it
    out as a standalone top-level function without duplicating any logic,
    those captures become explicit parameters: [run] below takes the [fns]
    and [test_pairs] refs (so callers see the same accumulation lower.ml's
    orchestrator already performs on them) plus [rename_tir_vars] (from
    [Lower_decls], to match [lower_module]'s `qualify_locals` helper) and
    [with_current_module_fns] (from [Lower_state]). This is a calling-
    convention change only (closure-capture → explicit argument) — every
    expression inside is copied verbatim; no lowering decision changed.

    Includes Wave 3 Task 8's observability comments on the [DMod] case
    (module-alias re-loading for test bodies), which move here unchanged. *)

module Ast = March_ast.Ast

(** Collect and lower every [DTest]/[DSetup]/[DSetupAll]/[DDescribe] block
    reachable from [decls], appending the resulting TIR functions to [fns]
    and (name, display_name) pairs to [test_pairs] — the exact accumulation
    [lower_module] performed when this code lived inline. [env] is the
    top-level lowering env (post Pass-2, i.e. after [lower_mod_decls] has
    already unwound [env.current_module_aliases] back to the entry module's
    own value — see the [DMod] case below for why test bodies must re-load
    per-module aliases from [Lower_state._module_alias_snapshots] rather
    than trusting the live [env]). *)
let run
    (env : Lower_state.env)
    (fns : Tir.fn_def list ref)
    (test_pairs : (string * string) list ref)
    (decls : Ast.decl list)
  : unit =
  let test_counter = ref 0 in
  (* Qualify references to module-local fns/lets inside a lowered test or
     setup body.  Test blocks written inside `mod X do ... end` call the
     module's own (often private) helpers UNQUALIFIED, but those helpers
     are emitted as "X.helper" — without the rename the test fn links
     against an undefined bare symbol.  Same treatment as impl-method
     bodies in collect_iface_impls. *)
  let qualify_locals mod_prefix direct_fn_names fn =
    if mod_prefix <> "" && direct_fn_names <> [] then
      Lower_decls.rename_tir_vars mod_prefix direct_fn_names fn
    else fn
  in
  let direct_names_of decls =
    List.filter_map (function
      | Ast.DFn (def, _) -> Some def.fn_name.txt
      | Ast.DLet (_, b, _) ->
        (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
      | _ -> None) decls
  in
  (* Lower a test-body expression to a zero-arg TIR function. *)
  let lower_test_body test_env ~mod_prefix ~direct_fn_names display_name body =
    let fn_name = Tir_names.test_fn_name !test_counter in
    incr test_counter;
    (* Register the enclosing module's own function names as current-module
       locals while lowering the test body, so [resolve_use_alias] does NOT
       rewrite a reference to a local function (e.g. a test-file-local
       [fn list_len(lst)]) into an import alias of the same bare name (e.g. the
       2-arg stdlib [Bytes.list_len]).  Without this the local def is shadowed
       by the import BEFORE [qualify_locals] can prefix it, producing a call to
       the wrong-arity stdlib function (arg dropped → uninitialized param). *)
    let body' = Lower_state.with_current_module_fns direct_fn_names
        (fun () -> Lower_match.lower_expr test_env body) in
    let fn : Tir.fn_def = {
      fn_name;
      fn_params = [];
      fn_ret_ty = Tir.TCon ("Unit", []);
      fn_body   = body';
      (* `__march_test_N__` runner wrapper: an ordinary zero-arg top-level
         fn from every RC/codegen consumer's perspective (dce.ml's root-set
         detection and llvm_emit's --test driver key off Tir_names.test_fn_name
         directly, not fn_kind), so FnNormal is honest here. *)
      fn_kind   = Tir.FnNormal;
    } in
    let fn = qualify_locals mod_prefix direct_fn_names fn in
    fns := fn :: !fns;
    test_pairs := (fn_name, display_name) :: !test_pairs
  in
  (* Recursive collector: descends into DDescribe and DMod blocks.
     [prefix] builds the human-readable display name; [mod_prefix] /
     [direct_fn_names] track the enclosing module for symbol renaming.
     [test_env] carries the CURRENT module's [current_module_aliases] —
     re-loaded per [DMod] descent from [_module_alias_snapshots] below,
     since this whole pass runs after [env]'s own module-alias scoping
     (in [lower_mod_decls] above) has already unwound. *)
  let rec collect_tests test_env prefix ~mod_prefix ~direct_fn_names decls =
    List.iter (fun d ->
      match d with
      | Ast.DTest (tdef, _) ->
        let display = if prefix = "" then tdef.Ast.test_name
                      else prefix ^ " " ^ tdef.Ast.test_name in
        lower_test_body test_env ~mod_prefix ~direct_fn_names display tdef.Ast.test_body
      | Ast.DDescribe (label, inner, _) ->
        let new_prefix = if prefix = "" then label else prefix ^ " " ^ label in
        collect_tests test_env new_prefix ~mod_prefix ~direct_fn_names inner
      | Ast.DSetup (body, _) ->
        (* Per-test setup: lower to __march_setup__ (overwritten by last decl) *)
        let body' = Lower_state.with_current_module_fns direct_fn_names
            (fun () -> Lower_match.lower_expr test_env body) in
        let fn : Tir.fn_def = {
          fn_name   = Tir_names.setup_fn_name;
          fn_params = [];
          fn_ret_ty = Tir.TCon ("Unit", []);
          fn_body   = body';
          fn_kind   = Tir.FnNormal;  (* `__march_setup__` — see test-runner comment above *)
        } in
        fns := qualify_locals mod_prefix direct_fn_names fn :: !fns
      | Ast.DSetupAll (body, _) ->
        let body' = Lower_state.with_current_module_fns direct_fn_names
            (fun () -> Lower_match.lower_expr test_env body) in
        let fn : Tir.fn_def = {
          fn_name   = Tir_names.setup_all_fn_name;
          fn_params = [];
          fn_ret_ty = Tir.TCon ("Unit", []);
          fn_body   = body';
          fn_kind   = Tir.FnNormal;  (* `__march_setup_all__` — see test-runner comment above *)
        } in
        fns := qualify_locals mod_prefix direct_fn_names fn :: !fns
      | Ast.DMod (mname, _, inner_decls, _) ->
        let new_mod_prefix = mod_prefix ^ mname.txt ^ "." in
        (* Re-load this module's import aliases (saved during lower_mod_decls)
           so the test bodies inside resolve unqualified names via the module's
           own imports — e.g. `close` → Connection.close, not the global
           Db.close. A fresh [env] value (not a mutation of [test_env]), so
           sibling [DMod]s at this level are unaffected — matching the old
           code's save/restore around [_current_module_aliases] on the
           normal path. NOTE the old dance here was NOT [Fun.protect]-
           guarded (unlike lower_mod_decls'): a throw escaping this
           recursion used to leave the ref dirty, which the env version
           does not reproduce — an UNOBSERVABLE difference (see the
           [env.current_module_aliases] field doc for the full trace:
           no reader outside [lower_module]'s dynamic extent, and the
           next call's entry preamble reset the ref before any read). *)
        let inner_env =
          let base = match Hashtbl.find_opt !Lower_state._module_alias_snapshots new_mod_prefix with
            | Some snap -> { test_env with Lower_state.current_module_aliases = snap }
            | None -> test_env
          in
          (* Also update [mod_prefix] so a colliding-type constructor built
             inside a test/setup body nested in this module gets the same
             collision-conditional qualification [lower_mod_decls]'s normal
             (non-test) path gives it — see [env.mod_prefix]'s field doc
             (Task 3, docs/superpowers/plans/2026-07-21-ctor-module-identity.md). *)
          { base with Lower_state.mod_prefix = new_mod_prefix }
        in
        collect_tests inner_env prefix
          ~mod_prefix:new_mod_prefix
          ~direct_fn_names:(direct_names_of inner_decls)
          inner_decls
      | _ -> ()
    ) decls
  in
  collect_tests env "" ~mod_prefix:"" ~direct_fn_names:(direct_names_of decls) decls
