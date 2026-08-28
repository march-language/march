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
  mod_prefix : string;
  collision_set : (string, string list) Hashtbl.t;
}

let empty_env = Lower_state.empty_env
let ty_of_expr = Lower_state.ty_of_expr
let unknown_ty = Lower_types.unknown_ty
let lower_ty = Lower_types.lower_ty
let lower_linearity = Lower_types.lower_linearity
let convert_ty = Lower_types.convert_ty
let reset_counter = Lower_state.reset_counter
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
let _alias_candidates = Lower_state._alias_candidates
let _alias_reported = Lower_state._alias_reported
let note_alias_candidate = Lower_state.note_alias_candidate
let lower_type_def = Lower_decls.lower_type_def
let lower_fn_def = Lower_decls.lower_fn_def
let rename_tir_vars = Lower_decls.rename_tir_vars
let uniquify_fn = Lower_decls.uniquify_fn

(* ── CPS-based ANF lowering (moved to [Lower_expr]) ───────────────────────
   The mutual-recursive core [lower_to_atom_k]/[lower_expr]/[lower_atoms_k]
   moved VERBATIM into [Lower_expr], together with the
   [Lower_match.install_lower_expr] forward-ref hook that breaks the
   Lower_expr <-> Lower_match cycle (the hook must run after lower_expr is
   defined, so it belongs with the band, not here).  Re-exported so every
   caller — this file's [lower_module], the other Lower_* modules, and
   lower.mli — is unchanged. *)
let lower_expr = Lower_expr.lower_expr

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

(** Pre-Pass-1 AST walker that reproduces the SET of TIR type NAMES Pass 2
    will eventually populate into [tm_types], computed BEFORE
    [collect_iface_impls] (Pass 1) runs — the [types] ref Pass 2 fills is
    still empty at that point.  Feeding these names to [Collision_set.compute]
    up front lets [collect_iface_impls] qualify a colliding-type impl's mangled
    symbol; the whole point is that this EARLY set agrees with the LATER
    [Collision_set.compute tm_types] (Task 1/2's driver), so a type is never
    globally-tagged/forced-Boxed by the late set while its impl symbols stay
    un-qualified by the early set (a first-wins collapse → silent miscompile).

    Only the type NAME matters to [Collision_set] (it ignores ctors and the
    variant/record distinction), so an empty-ctor placeholder stands in for
    each declared type.

    [~prefix] mirrors Pass 2's nested-module qualification (prefix ^ tname.txt,
    with "sub_name.txt ^ \".\"" appended at each [DMod] level — see the [DType]
    arms under [DMod] in [lower_module]).  Actor-generated types are the
    EXCEPTION: Pass 2 emits <Name>_Msg/_Actor/_State BARE — neither the
    top-level nor the nested [DActor] arm applies the module prefix to
    [Lower_actor.lower_actor]'s returned [types] (only to its [fns]).  So the
    [DActor] arm here inserts BARE names regardless of [~prefix], matching the
    real emission; without it the early set could miss an
    actor-type-name/user-type-name collision (e.g. bare [Foo_Msg] from
    [actor Foo] vs a user type [A.Foo_Msg]) that the late [tm_types] set
    catches. *)
let rec collect_type_names ~prefix acc decls =
  List.fold_left (fun acc d -> match d with
      | Ast.DType (_, name, _, _, _)
      | Ast.DAlwaysLinearType (_, name, _, _, _) ->
        Tir.TDVariant (prefix ^ name.txt, []) :: acc
      | Ast.DActor (_, name, _, _) ->
        (* BARE, ignoring ~prefix — see doc comment above. *)
        Tir.TDVariant (name.txt ^ Tir_names.actor_msg_suffix, [])
        :: Tir.TDVariant (name.txt ^ Tir_names.actor_struct_suffix, [])
        :: Tir.TDVariant (name.txt ^ Tir_names.actor_state_suffix, [])
        :: acc
      | Ast.DMod (sub_name, _, inner_decls, _) ->
        collect_type_names ~prefix:(prefix ^ sub_name.txt ^ ".") acc inner_decls
      | _ -> acc
    ) acc decls

(** Lower a module. *)
let lower_module ?type_map ?(stdlib_context : Ast.decl list = []) ?(test_mode=false) ?(hot_reload=false) (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  (* Collision-conditional qualification (Task 3 of specs/plans/2026-07-20-
     fqn-impl-dispatch-identity.md, impl symbols; extended by Task 3 of
     docs/superpowers/plans/2026-07-21-ctor-module-identity.md to ECon
     construction below) needs the collision set BEFORE [collect_iface_impls]
     (Pass 1) and BEFORE any function body is lowered (Pass 1's stdlib_context
     bodies, Pass 2's user bodies) — but the [types] ref Pass 2 fills is still
     empty at this point. [collect_type_names] (top-level, above) walks the
     AST directly, producing the SAME set of qualified/bare TIR type names
     Pass 2 will eventually put into [tm_types] (including actor-generated
     types) — see its doc comment. Computed here (before [env] itself, so it
     can be folded directly into [env.collision_set] below) rather than at its
     old post-[env] location, so [ECon] lowering deep inside [lower_expr]
     (which only ever sees [env], not [lower_module]'s local lets) can reach
     it too. *)
  (* [builtin_type_defs] is prepended so this EARLY set actually agrees with
     the LATER [Collision_set.compute tm_types] as the comment above claims:
     [tm_types] is [builtin_type_defs @ ...] (below), but [collect_type_names]
     only walks parsed AST decls — Option/Result/List are never AST nodes (no
     [stdlib/option.march]-style [DType] backs them), so without this they were
     invisible here while still being real, globally-tagged collision members
     at the late/tag-assignment site. A user type bare-named "Result" (etc.)
     then silently aliased the builtin's OWN ctor_info entry at construction
     (P0: builtin-ctor-collision-gap, 2026-07-22). *)
  let collision_set =
    Collision_set.compute
      (builtin_type_defs @
       collect_type_names ~prefix:"" (collect_type_names ~prefix:"" [] stdlib_context) m.mod_decls)
  in
  (* Task 5.5 (docs/superpowers/plans/2026-07-21-ctor-module-identity.md,
     inserted fix): the NARROWER shared-ctor table that gates ONLY Tasks 3/4's
     [ECon]/[br_tag] qualification (public + impl-bearing collisions), leaving
     the broad [collision_set] above untouched for Task 1/2 and the earlier
     plan's impl-symbol qualification. Computed from the SAME raw AST decls that
     feed [collect_type_names]/[collision_set] (stdlib_context then m.mod_decls,
     both at the top-level prefix), so the two stay in agreement about which
     modules are in scope. See [Lower_state.compute_shared_ctor_collisions]. *)
  Lower_state.compute_shared_ctor_collisions (stdlib_context @ m.mod_decls);
  (* env is constructed fresh here (module-scoped fields only — the
     reset-at-entry set, per the plan's landmine classification): [type_map]
     is set once from the caller's argument and never mutated again this
     call; [current_module_aliases] starts as a fresh empty table exactly
     like the old [_current_module_aliases := Hashtbl.create 16] did;
     [mod_prefix] starts bare ("" — no module scope entered yet, updated by
     [lower_mod_decls]'s [mod_env] at each [DMod] descent); [collision_set]
     is the module-scoped constant computed just above. *)
  let env = { type_map; current_module_aliases = Hashtbl.create 16;
              mod_prefix = ""; collision_set } in
  _iface_methods := Hashtbl.create 16;
  _use_aliases := Hashtbl.create 16;
  _module_aliases := Hashtbl.create 16;
  _module_alias_snapshots := Hashtbl.create 16;
  Hashtbl.reset _alias_candidates;
  Hashtbl.reset _alias_reported;
  Handler_owner.reset ();
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
    | Ast.ProtoStop _ :: rest -> collect_roles acc rest
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
  (* Show$String.show: a DYNAMIC identity.  A string is already its own
     representation, so on a genuine String [march_value_to_string] returns it
     verbatim (+1) — observationally the same as the `fn x -> x` this used to be.
     The reason it can no longer be a static identity is that [Tir.TString] is
     also what [Mono.default_residual_tvars] assigns to a DANGLING type variable,
     and that assumption ("no concrete value ever flows through it") is false at
     an erased runtime boundary: `record_get(r, "y")` has type Option('a) with
     nothing to pin 'a, so `println` specializes to Show$Option.show$Option_String
     and the static identity handed a tagged Int / boxed Float straight to
     march_string_concat3 as a march_string* — SIGSEGV, and the residual left
     open by PR #315 (specs/progress/2026-08-20-record-put-get-float-niche-
     segfault.md).  march_value_to_string classifies the uniform representation
     at runtime, which is the only thing that CAN be right here: the compiler
     provably does not know the type.

     Cost: the common `"${s}"` interpolation never reaches this body — lower.ml
     elides `Show$String.show` at the source when the argument is concretely a
     String (see the elision a few hundred lines below, and its note on the
     Perceus inc/dec pair that motivated it).  What reaches here is the
     mono-resolved generic-container path (Show$List/Show$Option/string_join
     elements), which already pays a call and an allocation per element. *)
  let str_x = mk_var "x" Tir.TString in
  let show_str_fn : Tir.fn_def = {
    fn_name = "Show$String.show"; fn_params = [str_x];
    fn_ret_ty = Tir.TString;
    fn_body = Tir.EApp (mk_var "march_value_to_string"
                          (Tir.TFn ([Tir.TString], Tir.TString)),
                        [Tir.AVar str_x]);
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
  (* Collision-conditional impl-symbol qualification (Task 3 of
     specs/plans/2026-07-20-fqn-impl-dispatch-identity.md) needs the collision
     set BEFORE [collect_iface_impls] (Pass 1, directly below) runs, but the
     [types] ref above is populated only by Pass 2 — so we can't reuse it.
     Now computed up front (before [env] itself) and folded into
     [env.collision_set] so [ECon] lowering (in [lower_expr], which only
     sees [env]) can reach the SAME set too — see [env.collision_set]'s
     field doc in [Lower_state] for the full rationale. Re-bound to a bare
     local here purely so the rest of this Pass-1 closure (written before
     that move) keeps referencing the short name [collision_set] unchanged. *)
  let collision_set = env.collision_set in
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
          (* Collision-conditional: a colliding short type name gets a symbol
             qualified by THIS impl's declaring module (mod_prefix, already
             threaded for rename_tir_vars) so two same-short-name impls of a
             GENERAL interface no longer mangle onto one symbol (last-write-wins
             miscompile — see accept/t89's doc comment). Single-declaration
             types are untouched: mangled/qualified_key/dispatch-table entries
             stay byte-identical. Not gated on interface name: Eq/Ord/Show/Hash
             impls for colliding types (accept/t88) are unaffected either way
             because those dispatch natively through ctor-qualified structural
             functions (ensure_adt_eq_fn &c.), never consulting this mangled
             symbol table — qualifying their entries too is harmless. *)
          let declaring_qualified_type_name =
            if mod_prefix <> "" && Collision_set.is_colliding collision_set type_name then
              (* mod_prefix already ends in "." (see the DMod recursion below) *)
              String.sub mod_prefix 0 (String.length mod_prefix - 1) ^ "." ^ type_name
            else type_name
          in
          (* [_iface_methods] keys plain method-dispatch rows (below) by the
             BARE method name only (never by interface), so two UNRELATED
             interfaces that happen to declare a same-named method (e.g. a
             user `interface MyEq do fn eq: a -> a -> Bool end` alongside the
             builtin `Eq`, both with a method literally named "eq") share one
             dispatch bucket. A compositional impl body (`impl MyEq(Wrap(a))
             when MyEq(a)`'s `eq` calling `eq(x, y)` on the unwrapped element)
             then resolves against BOTH interfaces' "Int" rows and mono's
             collision-dispatch machinery — built for the unrelated case of
             one interface's impl colliding across two same-short-name types —
             mistakes the two DIFFERENT interfaces' impls for competing rows
             of ONE ambiguous type, and either binds the wrong body (silently
             re-entering this impl's own `eq`, an infinite/wrong-answer
             mis-dispatch) or, when a row has no ADT constructor tags to
             switch on (a bare `Int`), fails outright with "has no
             runtime-tag rows". Below, self-referencing bare calls inside a
             GENERAL (non-builtin-named) interface's own impl bodies are
             qualified to "Iface.method" — the qualified key [collect_iface_impls]
             already registers per impl (see [qualified_key] below) — so the
             call resolves only against THIS interface's own rows. Builtin
             Show/Eq/Ord/Hash impls are excluded: their primitive-type rows
             (Eq$Int.eq &c., a few lines above) are registered under the bare
             name only, so qualifying would leave e.g. `Eq(List(a))`'s
             recursive `eq` on an Int element unresolved. *)
          let is_builtin_dispatched_iface =
            match idef.impl_iface.txt with
            | "Show" | "Eq" | "Ord" | "Hash" -> true
            | _ -> false
          in
          let iface_self_call_names =
            if is_builtin_dispatched_iface then []
            else List.map (fun ((m : Ast.name), _) -> m.txt) idef.impl_methods
          in
          List.iter (fun ((mname : Ast.name), (mdef : Ast.fn_def)) ->
              let mangled = Printf.sprintf "%s$%s.%s"
                idef.impl_iface.txt declaring_qualified_type_name mname.txt in
              let qualified_key = idef.impl_iface.txt ^ "." ^ mname.txt in
              (* Only lower the function body once per mangled name
                 (avoids double-lowering when DMod recursion re-encounters a
                 top-level impl that was already processed).  Keyed on the
                 (possibly module-qualified) MANGLED name rather than the bare
                 type_name: a colliding bare type_name now legitimately maps to
                 MULTIPLE (type_name, mangled) pairs (one per declaring
                 module's impl) under the same qualified_key, so guarding on
                 type_name alone would wrongly treat the second impl as
                 already-registered (the exact first-wins bug this task
                 fixes). For a non-colliding type, declaring_qualified_type_name
                 = type_name always, so mangled is identical across
                 re-encounters and this check behaves exactly as before. *)
              let already = match Hashtbl.find_opt !_iface_methods qualified_key with
                | Some l -> List.mem_assoc mangled (List.map (fun (a, b) -> (b, a)) l)
                | None   -> false
              in
              if not already then begin
                (* When lower_bodies is true, lower the impl method and emit
                   a TIR function.  When false (stdlib_context), only register
                   the dispatch entry — the function is already precompiled. *)
                ignore mdef;
                if lower_bodies then begin
                  (* [env] is closed over from [lower_module]'s top level and
                     never carries THIS impl's declaring-module prefix on its
                     own — [mod_prefix] above (the recursion parameter) was,
                     pre-fix, only used for the mangled SYMBOL name and
                     [rename_tir_vars] a few lines below, never folded into
                     the [env] that [lower_fn_def] threads down into
                     [lower_expr]'s [ECon] gate. Without [mod_env], a bare
                     colliding-type constructor written directly inside an
                     impl method's OWN body (e.g. `fn again(_self) do Shared
                     end`) would lower with [env.mod_prefix = ""], so the
                     collision-conditional qualification in [lower_expr]
                     never fires and the ctor key stays bare — reproducing
                     the same double-collision bug this task exists to fix,
                     just for THIS construction site instead of a
                     module-level `fn mk()`. [mod_env] mirrors
                     [lower_mod_decls]'s own [mod_env] (Pass 2, below) using
                     the SAME [mod_prefix] value already used for [mangled]
                     a few lines above — no new prefix computation. *)
                  let mod_env = { env with mod_prefix } in
                  let fn = Lower_decls.lower_fn_def mod_env mdef in
                  (* If this impl is inside a module, qualify any references to
                     module-local functions (e.g. bigint_eq_impl → BigInt.bigint_eq_impl)
                     so that mono can find them in fn_table (which uses the
                     prefixed names from lower_stdlib_mod_decls). *)
                  let fn = if mod_prefix <> "" && direct_fn_names <> [] then
                    Lower_decls.rename_tir_vars mod_prefix direct_fn_names fn
                  else fn in
                  let fn = if iface_self_call_names <> [] then
                    Lower_decls.rename_tir_vars (idef.impl_iface.txt ^ ".")
                      iface_self_call_names fn
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
             produced.

             [mod_prefix] is set to THIS module's own accumulated [prefix]
             (e.g. "DcA." at the first level, "A.B." if doubly-nested) —
             the same value [prefix] already carries for the
             [rename_tir_vars]/qualified-fn-name uses below, now also
             reachable from [ECon] lowering deep inside [lower_fn_def]'s
             call into [lower_expr] (Task 3 of
             docs/superpowers/plans/2026-07-21-ctor-module-identity.md). *)
          let mod_env = { env with
            current_module_aliases = Hashtbl.copy env.current_module_aliases;
            mod_prefix = prefix } in
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
                (* The synthesized fn names above are BARE by contract (the
                   spawn symbol and the HCR manifest both assert the short
                   spelling), so the name cannot say which module declared the
                   actor.  Record ownership out-of-band for capability
                   attribution — without this, a handler's IO was charged to
                   the ENTRY module and this module's own `needs` could not
                   satisfy the ceiling.  [prefix] carries a trailing dot. *)
                let owner = String.sub prefix 0 (max 0 (String.length prefix - 1)) in
                List.iter
                  (fun (fd : Tir.fn_def) ->
                     Handler_owner.register ~fn_name:fd.Tir.fn_name ~owner)
                  renamed_fns;
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
    | Tir.EAllocHole (tok, _, atoms, _) ->
      (match tok with Some a -> atom_uses name a | None -> false)
      || List.exists (atom_uses name) atoms
    | Tir.ESetField (o, _, v) -> atom_uses name o || atom_uses name v
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
