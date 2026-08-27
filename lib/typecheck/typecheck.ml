(** March type checker — bidirectional Hindley-Milner with provenance.

    Architecture — what is still in this file:
      §3  Linearity tracking
      §4  Pattern inference
      §5  Expression checking (bidirectional: infer / check)
      §6  Declaration checking
      §7  Top-level declaration dispatch and import warnings
      §8  Module entry point

    §1 (unification) and §2 (surface-type → internal-type conversion) left
    this file for [Typecheck_unify] on 2026-08-27.  The surviving sections
    keep their original numbers rather than closing the gap, so that the §
    references in commit messages, specs and code comments keep resolving.

    …and what now lives beside it, each re-entering this module through an
    [include] at the position its band used to occupy (see Phase 6 of
    specs/plans/2026-08-19-compiler-file-decomposition.md):
      [Typecheck_types]       the type language ([reason], [ty], [session_ty],
                              [scheme]), [repr] / [occurs], the printers, the
                              Elm-style message renderer, and the two pure AST
                              walkers [span_of_expr] and [free_vars_expr]
      [Typecheck_env]         [env] and everything that enters or leaves it:
                              [make_env], the [lookup_*] / [resolve_*] /
                              [suggest_*] family, the [bind_*] binders,
                              [generalize] and [instantiate]
      [Typecheck_builtins]    the type constants, [builtin_cap_table], the
                              standard interfaces, [builtin_bindings] and
                              [base_env]
      [Typecheck_exhaustive]  pattern exhaustiveness and redundancy
      [Typecheck_caps]        the capability / [needs] checker
      [Typecheck_tailcall]    tail-call enforcement
      [Typecheck_unify]       §1 unification and §2 surface-type conversion:
                              [unify], [report_mismatch], [surface_ty],
                              [expand_record], [instantiate_ctor], and both
                              of this library's top-level hook installations
      [Typecheck_session]     session-type projection and duality
      [Typecheck_reorder]     declaration dependency ordering
      [Typecheck_modcaps]     the module-level [cap] checkers (no_panic, pure,
                              no_extern, deterministic) and the panic-surface
                              tables

    The inference chain ([infer_expr] … [bind_lam_param]) and its consumers
    ([check_decl], [check_module_core]) deliberately stay: they are 18 and 2
    mutually recursive definitions that thread and mutate [env], and splitting
    them would trade locality for a callback record.

    Key design choices:
    - Bidirectional: [infer_expr] synthesises a type; [check_expr] verifies
      against a known expected type.  Annotations and fn return types drive
      the "checking" direction; everything else is inferred.
    - Provenance: every [unify] call carries a [reason] that explains *why*
      the expected type was expected.  Errors say "I expected X because Y".
    - Error recovery: unification failures record a diagnostic and return;
      the [TError] sentinel unifies with anything so checking continues.
    - Linearity: linear/affine vars are tracked via mutable [bool ref]
      "used" flags in the environment. *)

(* =================================================================
   The type language, its printer and the message renderer — now
   lib/typecheck/typecheck_types.ml.  The environment follows it in
   lib/typecheck/typecheck_env.ml.

   [include], not [open]: only [include] re-exports these names as part of
   [Typecheck]'s own surface, and consumers reach them through [let open] and
   through aliases (Tc., TC., T.) that no grep can see.  The include also
   carries the [Ast] / [Err] / [StringSet] module aliases this file used to
   declare here, and — load-bearing — it ALIASES the mutable cells rather than
   copying them, which is what keeps [bin/main.ml]'s marshalling of
   [_counter] / [_record_names] pointing at the cells the checker mutates.
   ================================================================= *)
include Typecheck_types

(* =================================================================
   Type environment, generalization and instantiation — now
   lib/typecheck/typecheck_env.ml.  [include] for the same reason as
   [Typecheck_types] above.
   ================================================================= *)
include Typecheck_env
(* =================================================================
   Built-in types, capability tables, standard interfaces and the base
   environment — now lib/typecheck/typecheck_builtins.ml.  [include] for the
   same reason as the two modules above; [base_env] in particular is declared
   in typecheck.mli and has 33 external call sites, so the build says so
   immediately if the include fails to supply it.
   ================================================================= *)
include Typecheck_builtins
(* =================================================================
   §1  Unification and §2 surface-type → internal-type conversion — now
   lib/typecheck/typecheck_unify.ml.  [include], not [open], for the same
   reason as the modules above.  The band carries BOTH of this library's
   top-level effects (the [inject_iface_exports_ref] and [expand_record_ref]
   hook installations); typecheck_unify.ml's header records why moving them
   cannot reorder anything observable.
   ================================================================= *)
include Typecheck_unify

(* =================================================================
   §3  Linearity tracking
   ================================================================= *)

(** Record a use of variable [name].  Errors if a linear var is used
    more than once. *)
(* Linear-field sentinels are tracked under the internal name
   "varname#fieldname" (see bind_linear_field_sentinels).  Diagnostics must
   not leak that internal spelling (slice-7 finding L5) — render it as the
   user-facing field-access form instead. *)
let lin_display_name n =
  match String.index_opt n '#' with
  | Some i ->
    Printf.sprintf "%s.%s"
      (String.sub n 0 i) (String.sub n (i + 1) (String.length n - i - 1))
  | None -> n

let record_use name span env =
  (* Mark any import entry that matches this name as used.
     [import_tracker] can hold one entry per use/import/alias declaration
     across the WHOLE combined program (stdlib + every file pulled in via
     MARCH_LIB_PATH auto-discovery) and [record_use] runs once per EVar in
     that same combined program, so a linear scan here is O(var-refs *
     imports) -- quadratic in project size and the dominant cost on any
     multi-hundred-file project (confirmed via `sample` showing
     List.mem/compare_val as the hot path during `march check`).  Use the
     Hashtbl-backed [import_idx] instead: an exact-name lookup for the
     common (unqualified) case, plus a prefix-root lookup only when [name]
     is qualified (contains a '.').  Both indices were populated from the
     exact same names/prefixes each entry's [ie_matches] closure compares
     against, so this is behavior-preserving, just no longer O(n) per call. *)
  (* [ie_used_names] is recorded alongside [ie_used] at both index hits: the
     index that matched already tells us exactly WHICH imported name this
     reference resolved to, which is the demand side of demand-driven
     capability propagation (see [ie_used_names]).  The exact index records the
     bare name; the prefix index records the FULL dotted name, since that is
     what identifies the member under a qualified `M.foo` reference. *)
  (match Hashtbl.find_opt env.import_idx.ie_exact_index name with
   | None -> ()
   | Some entries ->
     List.iter (fun ie ->
         ie.ie_used := true;
         Hashtbl.replace ie.ie_used_names name ()) entries);
  (match String.index_opt name '.' with
   | None -> ()
   | Some dot ->
     let prefix_root = String.sub name 0 dot in
     match Hashtbl.find_opt env.import_idx.ie_prefix_index prefix_root with
     | None -> ()
     | Some entries ->
       List.iter (fun ie ->
           if ie.ie_matches name then begin
             ie.ie_used := true;
             Hashtbl.replace ie.ie_used_names name ()
           end) entries);
  match List.find_opt (fun e -> e.le_name = name) env.lin with
  | None -> ()   (* unrestricted — no tracking needed *)
  | Some le ->
    (* A double-use is a relationship between two sites. Point at the earlier
       one as well: without it the reader knows only that the value was already
       gone, not what took it — which on a long function is the whole search. *)
    let consumed_label () =
      match !(le.le_first_use) with
      | None -> []
      | Some first ->
        [{ Err.lbl_span = first;
           Err.lbl_message =
             Printf.sprintf "`%s` was already consumed here"
               (lin_display_name name) }]
    in
    (match le.le_lin with
     | Ast.Linear when !(le.le_used) ->
       Err.report env.errors
         { Err.severity = Err.Error; span;
           message = Printf.sprintf
             "The linear value `%s` is used more than once here.\n\
              Linear values must be consumed exactly once — they cannot \
              be copied or ignored." (lin_display_name name);
           labels = consumed_label (); notes = []; code = None; fix = None }
     | Ast.Affine when !(le.le_used) ->
       Err.report env.errors
         { Err.severity = Err.Error; span;
           message = Printf.sprintf
             "The affine value `%s` is used more than once here.\n\
              Affine values may be used at most once." (lin_display_name name);
           labels = consumed_label (); notes = []; code = None; fix = None }
     | (Ast.Linear | Ast.Affine) ->
       le.le_used := true;
       if !(le.le_first_use) = None then le.le_first_use := Some span
     | Ast.Unrestricted -> ())

(** [bind_vars_with_linearity bindings env] is like [bind_vars] except it
    checks the repr'd type of each binding after unification: if the type
    has resolved to a [TLin] wrapper, the variable is registered as a
    linear/affine binding (tracked in [env.lin]) rather than an ordinary one.
    Use this wherever pattern-bound variables inherit linearity from the
    scrutinee, e.g. in match arms. *)
let bind_vars_with_linearity (bindings : (string * scheme) list) env =
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           bind_linear name lin inner acc_env
         | t' ->
           let env1 = bind_var name (Mono t') acc_env in
           bind_linear_field_sentinels name t' env1)
      | _ -> bind_var name sch acc_env
    ) env bindings

(** [bind_pattern_bindings scrut_expr bindings env] adds [bindings] to [env].
    Linearity is propagated in two ways:
    1. If a binding's type (after unification) is [TLin], it is registered as
       linear (catches cases where the type annotation carries linearity).
    2. If [scrut_expr] is a linear/affine variable, ALL top-level bindings
       inherit that linearity — this covers the common pattern of matching
       a linearly-typed variable bound with the [linear x: T] syntax, where
       the internal type is plain [T] without a [TLin] wrapper. *)
let bind_pattern_bindings scrut_expr (bindings : (string * scheme) list) env =
  (* Check whether the scrutinee is itself a tracked linear variable. *)
  let inherited_lin =
    match scrut_expr with
    | Ast.EVar sname ->
      (match List.find_opt (fun le -> le.le_name = sname.txt) env.lin with
       | Some le when le.le_lin <> Ast.Unrestricted -> Some le.le_lin
       | _ -> None)
    | _ -> None
  in
  (* A binding whose resolved type names an `always_linear type` must be
     tracked as Linear even when it carries no [TLin] wrapper and the
     scrutinee isn't itself a pre-tracked linear variable to inherit from —
     e.g. `let? sock = connect(addr)` or `with Ok(sock) <- connect(addr)`
     bind `sock` straight from a fresh call's result type, with no prior
     linear tracking to propagate. Mirrors the auto-promotion that [ELet]'s
     `auto_lin` and [bind_lam_param]'s `effective_lin` already perform for
     plain lets and function params — without it, `sock` is bound as an
     ordinary variable and its uses are never checked for double-consumption. *)
  let always_linear_of t =
    match repr t with
    | TCon (name, _) when List.mem name env.always_linear_types -> Some Ast.Linear
    | _ -> None
  in
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           (* Binding type carries TLin — use that linearity. *)
           bind_linear name lin inner acc_env
         | t' ->
           (match inherited_lin with
            | Some lin ->
              (* Scrutinee was linear: the bound variable inherits its linearity. *)
              bind_linear name lin t' acc_env
            | None ->
              (match always_linear_of t' with
               | Some lin -> bind_linear name lin t' acc_env
               | None ->
                 let env1 = bind_var name (Mono t') acc_env in
                 bind_linear_field_sentinels name t' env1)))
      | Poly (_, _, t) ->
        (match always_linear_of t with
         | Some lin -> bind_linear name lin t acc_env
         | None ->
           (* Generalised binding: bind normally but also add field sentinels for
              any linear fields in the underlying type. *)
           let env1 = bind_var name sch acc_env in
           bind_linear_field_sentinels name (repr t) env1)
    ) env bindings

(** After a scope closes, check that every in-scope linear var was used. *)
let check_linear_all_consumed env ~scope_span in_scope_names =
  List.iter (fun le ->
      if List.mem le.le_name in_scope_names
      && le.le_lin = Ast.Linear
      && not !(le.le_used) then
        Err.error env.errors ~span:scope_span
          (Printf.sprintf
             "The linear value `%s` was never used.\n\
              Linear values must be consumed exactly once — did you \
              mean to pass it somewhere?" (lin_display_name le.le_name))
    ) env.lin

(* =================================================================
   §4  Pattern inference
   ================================================================= *)

(** Infer the type that a pattern *expects*, and return the list of
    (name, scheme) bindings it introduces.

    We don't yet resolve constructor types through a type registry —
    ADT patterns produce fresh type variables.  That will be fixed
    when [DType] declarations populate the type registry. *)
let rec infer_pattern ?expected env (pat : Ast.pattern)
    : (string * scheme) list * ty =
  match pat with
  | Ast.PatWild sp ->
    let t = fresh_var env.level in
    (* Record in type_map so lower_match.ml's pattern-matrix compiler can look
       up the resolved (possibly-still-polymorphic) type via ty_of_span for
       constructor-field sub-patterns it discards — e.g. `Cons(_, t) -> ...`.
       Without this, a discarded field's synthetic TIR var never resolves to
       a concrete type through monomorphization (unlike a NAMED field, which
       gets fixed up the same way) and Perceus conservatively treats it as
       RC-managed, corrupting compiled programs when the concrete type is
       actually an unboxed scalar (e.g. Float) — see lower_match.ml. *)
    Hashtbl.replace env.type_map sp t;
    [], t

  | Ast.PatVar name ->
    let t = fresh_var env.level in
    (* Record in type_map so lower.ml can look up the resolved type via ty_of_span.
       Unification happens after infer_pattern returns; repr t follows the link. *)
    Hashtbl.replace env.type_map name.span t;
    [(name.txt, Mono t)], t

  | Ast.PatLit (lit, _) ->
    [], ty_of_lit lit

  | Ast.PatTuple (ps, _) ->
    (* Thread per-element expected types so a nested record pattern inside a
       tuple pattern — which is what desugar builds for multi-param fns —
       still gets an expected type to open its field list against. *)
    let elem_expected =
      match expected with
      | Some t -> (match repr t with TTuple ts -> ts | _ -> [])
      | None -> []
    in
    let bs_tys =
      List.mapi (fun i p ->
        match List.nth_opt elem_expected i with
        | Some et -> infer_pattern ~expected:et env p
        | None    -> infer_pattern env p) ps
    in
    let bindings = List.concat_map fst bs_tys in
    let tys      = List.map snd bs_tys in
    bindings, TTuple tys

  | Ast.PatCon (name, ps) ->
    (* When the bare constructor name is ambiguous and the scrutinee type is
       known (threaded in from [infer_match] / nested constructor arguments),
       prefer the candidate whose parent type matches, instead of relying on
       [lookup_ctor]'s order-dependent "most recently registered wins". *)
    (let ci_opt =
       (* Resolution precedence for a bare (unqualified) pattern constructor:
          1. A KNOWN scrutinee type that UNIQUELY identifies the constructor
             wins first — matching a value of an imported type
             `N.Remote = Reg(String)` via bare `Reg(s)` must resolve to
             `N.Remote`'s ctor even when the current module locally defines a
             same-named `Reg` on a different type (Finding-1).
          2. Otherwise same-module precedence: a module's own constructor
             outranks a same-named sibling's.  This is what wins when the
             expected type name is itself shared by several candidates (two
             sibling `Registry` types) so step 1 is ambiguous.
          3. Then the order-dependent expected-type head (legacy behaviour for
             a genuinely ambiguous cross-module name with no same-module match).
          4. Then the raw head / qualified resolution. *)
       let expected_tn =
         if String.contains name.txt '.' then None
         else match expected with
           | Some t -> (match repr t with TCon (tn, _) -> Some tn | _ -> None)
           | None -> None
       in
       let by_expected_unique = match expected_tn with
         | Some tn -> lookup_ctor_in_type_unique name.txt tn env
         | None -> None
       in
       match by_expected_unique with
       | Some _ as r -> r
       | None ->
       match lookup_ctor_same_module name.txt env with
       | Some _ as r -> r
       | None ->
       let by_expected = match expected_tn with
         | Some tn -> lookup_ctor_in_type name.txt tn env
         | None -> None
       in
       match by_expected with
       | Some _ as r -> r
       | None ->
         match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
     in
     match ci_opt with
     | None ->
       let candidates = suggest_ctors name.txt env in
       let hint =
         if candidates = [] then
           qualified_error_msg name.txt env
         else
           let lines = List.map (fun (k, ty) ->
               Printf.sprintf "  • `%s` — from type `%s`" k ty
             ) candidates in
           "Did you mean one of:\n" ^ String.concat "\n" lines
       in
       Err.error env.errors ~span:name.span
         (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
            name.txt hint);
       let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
       bindings, TError
     | Some ci ->
       (* A bare, unqualified reference whose candidates span more than one
          DECLARING MODULE (not just more than one bare type name — two
          candidates from the SAME module sharing a ctor name across
          unrelated types is the pre-existing, harmless case below) is
          genuinely ambiguous when the current module owns none of them.

          BUT a KNOWN scrutinee/expected type that UNIQUELY identifies the
          constructor is not ambiguous at all — step 1 of the resolution
          precedence above already picked the right candidate by type. The
          diagnostic must mirror that: matching a value of type `Defs.Thing`
          via bare `Bar(_)` is unambiguous even when stdlib's `Plot.SeriesKind`
          also declares a `Bar`, so gate the whole ambiguity report on the
          expected type NOT having resolved it (same `lookup_ctor_in_type_unique`
          predicate `by_expected_unique` uses). *)
       let resolved_by_expected_unique =
         (not (String.contains name.txt '.'))
         && (match expected with
             | Some t ->
               (match repr t with
                | TCon (tn, _) -> lookup_ctor_in_type_unique name.txt tn env <> None
                | _ -> false)
             | None -> false)
       in
       (if not (String.contains name.txt '.')
           && not resolved_by_expected_unique then begin
         let candidates = all_ctor_candidates_named name.txt env in
         let distinct_modules = List.sort_uniq compare (List.map snd candidates) in
         let local_owns_one =
           List.exists
             (fun (_, m) ->
                m = env.current_module
                || List.exists (same_package_namespace m)
                     (local_module_paths env))
             candidates in
         if List.length distinct_modules > 1 && not local_owns_one then begin
           let lines = List.map (fun (t, m) ->
               Printf.sprintf "  • `%s.%s` — from type `%s` in module `%s`"
                 m name.txt t m) candidates in
           Err.error env.errors ~span:name.span
             (Printf.sprintf
                "Constructor `%s` is ambiguous between multiple modules:\n%s\n\
                 Use a qualified form to disambiguate."
                name.txt (String.concat "\n" lines))
         end else begin
           let all_types = all_ctors_named name.txt env in
           if List.length all_types > 1 then
             Err.hint env.errors ~span:name.span
               (Printf.sprintf
                  "Constructor `%s` is defined by multiple types (%s). \
                   Use a qualified form to disambiguate, e.g. `%s.%s`."
                  name.txt
                  (String.concat ", " all_types)
                  (List.hd all_types)
                  name.txt)
         end
       end);
       let arg_tys, result_ty = instantiate_ctor env ci in
       (* Record in type_map so lower_match.ml's pattern-matrix compiler can look
          up the resolved type via ty_of_span for a NESTED constructor
          sub-pattern (e.g. `Cons(Row(fp), rest)`'s `Row(fp)`) — without this the
          destructured field var stays TVar "_" forever, and if the ctor's short
          name collides with another type's ctor (Collision_set), codegen's
          ambiguous by-arity ctor_entry fallback can pick the WRONG type's tag. *)
       Hashtbl.replace env.type_map name.span result_ty;
       (* Resolve the constructor's own type against the expected type BEFORE
          walking its arguments.  [instantiate_ctor] hands back fresh vars for
          the parent type's parameters, so `Some`'s argument is still an
          unbound var here and is only linked to the scrutinee's payload by the
          caller's unify, AFTER the arguments have been inferred.  A sub-pattern
          that needs a CONCRETE expected type — a record pattern, which uses it
          to open its field list — would see that bare var and fall back to
          closed synthesis, so `Some({ status: s })` against
          `Option({status, body})` failed while the full
          `Some({ status: s, body: b })` happened to unify anyway.  Binding the
          parameter first makes [arg_tys] repr to real types. *)
       (match expected with
        | Some exp_ty ->
          unify env ~span:name.span
            ~reason:(Some (RBuiltin
              (Printf.sprintf "I'm checking the pattern for constructor `%s`."
                 name.txt)))
            result_ty exp_ty
        | None -> ());
       let n_expected = List.length arg_tys in
       let n_got      = List.length ps in
       if n_expected <> n_got then begin
         Err.error env.errors ~span:name.span
           (Printf.sprintf
              "Constructor `%s` expects %d argument(s) in a pattern but I got %d."
              name.txt n_expected n_got);
         let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
         bindings, TError
       end else begin
         let all_bindings = ref [] in
         List.iter2 (fun pat arg_ty ->
             let bindings, pat_ty = infer_pattern ~expected:arg_ty env pat in
             all_bindings := bindings @ !all_bindings;
             unify env ~span:name.span
               ~reason:(Some (RBuiltin
                 (Printf.sprintf "I'm checking the pattern for constructor `%s`."
                    name.txt)))
               pat_ty arg_ty
           ) ps arg_tys;
         !all_bindings, result_ty
       end)

  | Ast.PatAtom (_, ps, _) ->
    let bs_tys   = List.map (infer_pattern env) ps in
    let bindings  = List.concat_map fst bs_tys in
    bindings, t_atom

  | Ast.PatRecord (flds, sp) ->
    (* Record patterns have OPEN field lists: `{ x }` matches any record with
       at least an `x`.  Since [unify] requires exact field-set equality
       (no width subtyping, no row variables), we cannot synthesize the
       pattern's type from the mentioned fields and unify — that rejects every
       partial pattern.  Drive the sub-patterns from the EXPECTED type
       instead, and return the expected type unchanged so the caller's unify
       is a no-op.

       With no expected type available (an unannotated scrutinee whose type is
       still a fresh var), fall back to the old closed-record synthesis: it is
       the only thing that can constrain the scrutinee at all, and it matches
       the pre-existing behaviour for full destructures. *)
    let expected_rec =
      match expected with
      | Some t -> expand_record env (repr t)
      | None -> None
    in
    (match expected_rec with
     | Some (TRecord expected_flds) ->
       let bindings = ref [] in
       List.iter (fun ((name : Ast.name), pat) ->
         match List.assoc_opt name.Ast.txt expected_flds with
         | Some fty ->
           let bs, pty = infer_pattern ~expected:fty env pat in
           unify env ~span:name.Ast.span ~reason:(Some (RMatchArm sp)) fty pty;
           bindings := bs @ !bindings
         | None ->
           Err.report env.errors
             { Err.severity = Error; span = name.Ast.span;
               message =
                 Printf.sprintf "This record has no field `%s`." name.Ast.txt;
               labels = [];
               notes  =
                 [Printf.sprintf "Available fields: %s"
                    (String.concat ", " (List.map fst expected_flds))];
               code = Some "unknown_record_field";
               fix  = None }
       ) flds;
       (* Record the PATTERN's own type under its span.  lower_match's
          [expand_record_column] emits [EField] on the column's scrutinee, and
          llvm_emit can only compute a static GEP when that scrutinee's TIR
          type is the record's — otherwise it falls back to the by-name
          dynamic accessor and decodes the result with the FIELD's type, which
          dereferences an inline unboxed Float as a pointer (SIGSEGV).  A
          NESTED record column (a record inside a constructor payload) has a
          synthetic sub-var deliberately left at the lowering placeholder, so
          this span is the only place the record type can be recovered from. *)
       Hashtbl.replace env.type_map sp (TRecord expected_flds);
       !bindings, TRecord expected_flds
     | _ ->
       let bindings = ref [] in
       let fld_tys = List.map (fun ((name : Ast.name), pat) ->
           let bs, t = infer_pattern env pat in
           bindings := bs @ !bindings;
           (name.Ast.txt, t)
         ) flds
       in
       let sorted =
         List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
       (* Same reason as the expected-driven branch above. *)
       Hashtbl.replace env.type_map sp (TRecord sorted);
       !bindings, TRecord sorted)

  | Ast.PatOr (alts, sp) ->
    (* Every alternative must have the same type, AND must bind the same names
       at the same types.  Lowering splits the row into one per alternative but
       shares a single lowered body, reached through a join point whose
       parameters are the arm's binders ([pat_binder_vars] in lower_match.ml) —
       so a name only some alternatives supply would be unbound on the paths
       that don't, and a name supplied at two different types has no single
       parameter type.  Both are rejected here rather than miscompiled.

       [span_of_pat] isn't defined until later in this file (it's used by
       exhaustiveness checking, which runs after inference), so diagnostics
       point at the whole or-pattern's span [sp] rather than at the specific
       offending alternative. *)
    let results = List.map (fun p -> infer_pattern ?expected env p) alts in
    (match results with
     | [] -> [], fresh_var env.level
     | (_, t0) :: rest ->
       List.iter (fun (_, t) ->
         unify env ~span:sp ~reason:(Some (RMatchArm sp)) t0 t) rest;
       let bs0 = match results with (bs, _) :: _ -> bs | [] -> [] in
       let ty_of_scheme = function Mono t -> t | Poly (_, _, t) -> t in
       let names bs = List.sort_uniq String.compare (List.map fst bs) in
       let n0 = names bs0 in
       let report_names_differ missing extra =
         let describe label ns =
           Printf.sprintf "%s: %s" label
             (String.concat ", " (List.map (fun n -> "`" ^ n ^ "`") ns))
         in
         let detail =
           String.concat "; "
             ((if missing = [] then []
               else [describe "bound by an earlier alternative only" missing])
              @ (if extra = [] then []
                 else [describe "bound by a later alternative only" extra]))
         in
         Err.report env.errors
           { Err.severity = Error; span = sp;
             message = "Or-pattern alternatives must bind the same variables.";
             labels = [];
             notes  =
               [detail;
                "Every alternative of `p1 | p2` shares one arm body, so a name \
                 bound by only some alternatives would be undefined when the \
                 others match.";
                "Bind the same names in every alternative, split this into \
                 separate arms, or match the common shape and test the \
                 difference in a `when` guard."];
             code = Some "or_pattern_binding";
             fix  = None }
       in
       List.iter (fun (bs, _) ->
         let ni = names bs in
         if ni <> n0 then
           report_names_differ
             (List.filter (fun n -> not (List.mem n ni)) n0)
             (List.filter (fun n -> not (List.mem n n0)) ni)
         else
           (* Same names: each must carry the same type in every alternative,
              since the join point gives it exactly one parameter. *)
           List.iter (fun (n, sch) ->
             match List.assoc_opt n bs0 with
             | Some sch0 ->
               unify env ~span:sp
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf
                      "`%s` is bound by more than one alternative of this \
                       or-pattern, so every alternative must bind it at the \
                       same type." n)))
                 (ty_of_scheme sch0) (ty_of_scheme sch)
             | None -> ()) bs
       ) rest;
       bs0, t0)

  | Ast.PatAs (inner, name, _) ->
    (* Thread [expected] into the aliased pattern, exactly as [PatTuple] and
       constructor arguments do.  Dropping it sent a record pattern under an
       alias (`{ code: 404 } as w`) down the CLOSED-synthesis branch, so `w`
       got the narrow `{ code : Int }` instead of the scrutinee's own type —
       two misleading errors (`expected { code : Int } but got
       { code : Int, msg : String }` and `this record does not have a field
       called msg`), neither pointing at the real cause. *)
    let bindings, t = infer_pattern ?expected env inner in
    Hashtbl.replace env.type_map name.span t;
    (name.txt, Mono t) :: bindings, t

and ty_of_lit = function
  | Ast.LitInt    _ -> t_int
  | Ast.LitFloat  _ -> t_float
  | Ast.LitBool   _ -> t_bool
  | Ast.LitString _ -> t_string
  | Ast.LitAtom   _ -> t_atom

(* =================================================================
   §5  Expression checking — bidirectional
   ================================================================= *)

(* =================================================================
   Pattern exhaustiveness checking — now
   lib/typecheck/typecheck_exhaustive.ml.  [include] for the same reason as
   the modules above.
   ================================================================= *)
include Typecheck_exhaustive

(** [infer_expr env e] synthesises the type of [e], accumulating any
    errors into [env.errors]. *)
let rec infer_expr env (e : Ast.expr) : ty =
  let result =
    match e with
    (* ── Literals ─────────────────────────────────────────────────── *)
    | Ast.ELit (lit, _) ->
      ty_of_lit lit

    (* ── Variables ────────────────────────────────────────────────── *)
    | Ast.EVar name ->
      record_use name.txt name.span env;
      (* R2: the root capability is granted at the boundary, not taken.  The
         name stays BOUND (so this reports a capability error rather than
         "I cannot find `root_cap`", and so the inferred type below stays
         [Cap(IO)] and no cascade of unification failures follows a single
         mistake) — only naming it is refused. *)
      if name.txt = "root_cap" && not env.root_cap_allowed then
        Err.error env.errors ~span:name.span
          (render_parts [
            MPCode "root_cap";
            MPText " cannot be referenced — the root capability is granted to ";
            MPCode "main"; MPText ", not taken.";
            MPBreak;
            MPText "help: declare "; MPCode "fn main(cap : Cap(IO))";
            MPText " and pass the capability down to whatever needs it, narrowing with ";
            MPCode "cap_narrow"; MPText " along the way." ]);
      (match lookup_var name.txt env with
       | Some sch ->
         (if StrMap.mem name.txt env.local_fns && !(env.current_decl) <> "" then
            env.refs := { callee = qualify_ref_name env.current_module name.txt;
                          caller = !(env.current_decl);
                          ref_kind = `Call;
                          ref_file = name.span.Ast.file;
                          ref_line = name.span.Ast.start_line } :: !(env.refs)
          else if String.contains name.txt '.' && StrMap.mem name.txt env.qual_fn_names
                  && !(env.current_decl) <> "" then
            (* Already-qualified "Mod.name" resolved directly out of env.vars —
               this is how same-compilation cross-module DMod exports work (see
               the [Ast.DMod] branch of [check_decl], which binds "Mod.member"
               straight into the outer env.vars rather than routing through
               [resolve_qualified_var]/[Module_registry]). The [qual_fn_names]
               membership check excludes a qualified reference to a public
               top-level [DLet] constant/value — [DMod]'s export step binds
               those into [env.vars] the exact same way it binds a [DFn], so a
               bare dotted-name check alone cannot tell them apart; only
               [qual_fn_names] (populated exclusively from [DFn]s, see its doc
               comment) can. *)
            env.refs := { callee = name.txt;
                          caller = !(env.current_decl);
                          ref_kind = `Call;
                          ref_file = name.span.Ast.file;
                          ref_line = name.span.Ast.start_line } :: !(env.refs));
         instantiate ~use_span:name.span env.level env sch
       | None     ->
         (* Try qualified module resolution: "Mod.func" *)
         match resolve_qualified_var name.txt env with
         | env', Some sch ->
           (* [env'] is the env AFTER [load_module_into_env] merged the
              resolved module's exports — [qual_fn_names] is only populated
              there for the ExFn case, so this correctly excludes a qualified
              reference to a registry-loaded module's public [DLet]
              value/constant (ExValue). See [qual_fn_names]'s doc comment. *)
           (if StrMap.mem name.txt env'.qual_fn_names && !(env.current_decl) <> "" then
              env.refs := { callee = name.txt;
                            caller = !(env.current_decl);
                            ref_kind = `Call;
                            ref_file = name.span.Ast.file;
                            ref_line = name.span.Ast.start_line } :: !(env.refs));
           instantiate ~use_span:name.span env.level env sch
         | _ when is_confirmed_private_qualified name.txt env ->
           (* A confirmed privacy violation (`Mod.priv_fn`) must be reported
              as such — falling through to the dot-suffix fallback below would
              let it silently resolve to an unrelated global of the same bare
              name (e.g. `Auth.hash` matching the builtin `hash` from the
              `Hash` interface), bypassing the visibility check entirely. *)
           Err.error env.errors ~span:name.span (qualified_error_msg name.txt env);
           TError
         | _ when (match split_qualified name.txt with
                   | Some (mod_name, _) -> March_modules.Module_registry.ensure_loaded mod_name <> None
                   | None -> false) ->
           (* The qualifier's first component IS a genuinely known module (a
              real, loaded stdlib module — [ensure_loaded] succeeded) and
              [resolve_qualified_var] just confirmed it does not export this
              member. That is decisive: fall straight through to the
              dot-suffix fallback below would let e.g. `String.length` (no
              such export; the real API is `byte_size`/`codepoint_count`)
              silently resolve to the unrelated `List.length` bare binding,
              producing a baffling `expected List(u2) but got String` instead
              of "Module `String` does not export `length`". The dot-suffix
              fallback exists for a DIFFERENT case — multi-component paths
              like "Conduit.Storage.workflow_load" whose first component
              ("Conduit") is a local/app module never registered in
              [Module_registry] (only the REPL calls [register]; compiled
              builds only lazily populate the registry with real stdlib
              modules) — so this guard cannot misfire on that case. *)
           Err.error env.errors ~span:name.span (qualified_error_msg name.txt env);
           TError
         | _ ->
           (* Final fallback: for multi-component names like "Conduit.Storage.workflow_load",
              interface methods are registered without the outer module prefix
              (e.g. as "Storage.workflow_load"). Try progressively stripping
              leading dot-separated components. *)
           let rec try_suffix n =
             match String.index_opt n '.' with
             | None -> None
             | Some i ->
               let rest = String.sub n (i + 1) (String.length n - i - 1) in
               (match lookup_var rest env with
                | Some sch -> Some sch
                | None -> try_suffix rest)
           in
           (match try_suffix name.txt with
            | Some sch -> instantiate ~use_span:name.span env.level env sch
            | None ->
              let msg =
                if String.contains name.txt '.' then
                  qualified_error_msg name.txt env
                else begin
                  let base = Printf.sprintf "I cannot find `%s`." name.txt in
                  match suggest_var_in_scope name.txt env with
                  | Some s -> base ^ Printf.sprintf " Did you mean `%s`?" s
                  | None   -> base
                end
              in
              Err.error env.errors ~span:name.span msg;
              TError))

    (* ── Type annotations ─────────────────────────────────────────── *)
    | Ast.EAnnot (e, ann, sp) ->
      let tvars = ref [] in
      let expected = surface_ty env ~tvars ann in
      check_expr env e expected ~reason:(Some (RAnnotation sp));
      expected

    (* ── Typed holes ──────────────────────────────────────────────── *)
    | Ast.EHole (name, sp) ->
      let t = fresh_var env.level in
      let label = match name with Some n -> "?" ^ n.txt | None -> "?" in
      Err.report env.errors
        { Err.severity = Hint; span = sp;
          message = Printf.sprintf "Typed hole %s has type `%s`" label (pp_ty t);
          labels  = [];
          notes   = [ "Fill this hole with an expression of the type shown above." ];
          code    = None; fix = None };
      t

    (* ── Function application ─────────────────────────────────────── *)
    (* ── Session channel operations (special casing for session type advancement) ── *)

    (* Normalize Mod.method(args) → EVar("Mod.method")(args) so that Chan.send etc.
       work whether written as `Chan.send(ch, v)` (field access) or `Chan.send(ch, v)`. *)
    | Ast.EApp (Ast.EField (Ast.ECon ({txt = mod_name; _}, [], _),
                             {txt = meth; _}, _),
                args, sp) ->
      let norm = Ast.EApp (Ast.EVar {txt = mod_name ^ "." ^ meth;
                                     span = Ast.dummy_span}, args, sp) in
      infer_expr env norm

    (* Chan.new(proto_name_string_or_atom) →
         (linear Chan(RoleA, Proto), linear Chan(RoleB, Proto))
       The protocol name is the sole argument; we look it up to generate typed endpoints. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.new"; _ }, [proto_expr], sp) ->
      let proto_name = match proto_expr with
        | Ast.ELit (LitString s, _) | Ast.ELit (LitAtom s, _) -> Some s
        | Ast.EVar n -> Some n.txt
        | Ast.ECon (n, [], _) -> Some n.txt   (* bare Protocol name: Chan.new(MyProto) *)
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "Chan.new: argument must be a protocol name (string, atom, or bare name).";
         TError
       | Some pname ->
         (match StrMap.find_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "Chan.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            (match pi.pi_projections with
             | [(_, sty_a); (_, sty_b)] ->
               (* Return (linear Chan(A, Proto), linear Chan(B, Proto)) *)
               let ty_a = TLin (Ast.Linear, TChan (ref sty_a)) in
               let ty_b = TLin (Ast.Linear, TChan (ref sty_b)) in
               TTuple [ty_a; ty_b]
             | [_] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has only one role." pname);
               TError
             | [] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has no roles." pname);
               TError
             | projs ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "Chan.new: protocol `%s` has %d roles but Chan.new needs \
                     exactly 2. Use MPST.new for multi-party protocols."
                    pname (List.length projs));
               TError)))

    (* Chan.send(ch, value) → linear Chan at continuation session state.
       Pre-condition: ch must be at SSend(T, S). Post: ch is consumed; returns Chan at S. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.send"; _ }, [ch_expr; val_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.send" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SSend (payload_ty, cont) ->
            check_expr env val_expr payload_ty
              ~reason:(Some (RBuiltin "Payload type of Chan.send"));
            TLin (Ast.Linear, TChan (ref cont))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.send: channel is at `%s` but I expected `Send(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.send: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.recv(ch) → (value, linear Chan at continuation).
       Pre-condition: ch must be at SRecv(T, S). Post: ch consumed; returns (T, Chan at S). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.recv"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.recv" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SRecv (payload_ty, cont) ->
            TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))]
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.recv: channel is at `%s` but I expected `Recv(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.recv: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.close(ch) → Unit.
       Pre-condition: ch must be at SEnd. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.close"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.close" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.close: channel is at `%s` but I expected `End`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.close: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.choose(ch, :label) → linear Chan at chosen branch continuation.
       Pre-condition: ch must be at SChoose(branches). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.choose"; _ }, [ch_expr; label_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      let label_str = match label_expr with
        | Ast.EAtom (s, [], _) -> Some s
        | Ast.ELit (LitAtom s, _) -> Some s
        | _ -> None
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.choose" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SChoose branches ->
            (match label_str with
             | None ->
               Err.error env.errors ~span:sp
                 "Chan.choose: label must be an atom literal (e.g. :ok).";
               TError
             | Some lbl ->
               (match List.assoc_opt lbl branches with
                | Some cont -> TLin (Ast.Linear, TChan (ref cont))
                | None ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Chan.choose: label `:%s` is not a valid branch of this protocol." lbl);
                  TError))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.choose: channel is at `%s` but I expected `Choose{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.choose: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.offer(ch) → (Atom, linear Chan at some continuation).
       Pre-condition: ch must be at SOffer(branches).
       Returns (label_atom, new_chan) where new_chan is at the continuation
       for whichever branch the other side chose.  The exact continuation is
       not known statically without dependent types, so we return the first
       branch's continuation type as a conservative approximation that still
       lets users write match expressions over the returned atom. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.offer"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.offer" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SOffer branches ->
            (match branches with
             | (_, sty) :: _ ->
               (* Hand back a channel at the FIRST branch's continuation as the
                  default (keeps the previously-accepted programs that offer then
                  drive without matching the label — the approximation is exact
                  when the peer chose the first branch).  But ALSO register this
                  fresh session ref against the full branch map so that a later
                  `match <label>` can refine it PER ARM to the branch actually
                  taken (F5 path-dependent refinement). *)
               let cont_ref = ref sty in
               env.offer_conts := (cont_ref, branches) :: !(env.offer_conts);
               (* If the branches continue differently, the first-branch type is
                  a GUESS — mark the ref as needing a `match`-driven refinement
                  before any operation may use it. *)
               (match branches with
                | (_, first) :: rest
                  when not (List.for_all (fun (_, s) -> session_ty_exact_equal s first) rest) ->
                  env.offer_unrefined := cont_ref :: !(env.offer_unrefined)
                | _ -> ());
               TTuple [t_atom; TLin (Ast.Linear, TChan cont_ref)]
             | [] ->
               TTuple [t_atom; TError])
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.offer: channel is at `%s` but I expected `Offer{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.offer: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* ── MPST multi-party session operations ─────────────────────────
       These mirror Chan.* but work with multi-party protocols (N>2 roles).
       MPST.new(Proto)            → (ep_r1, ep_r2, ..., ep_rN) sorted by role name
       MPST.send(ep, :Role, val)  → new_ep  (must be at SMSend(Role, T, S))
       MPST.recv(ep, :Role)       → (val, new_ep) (must be at SMRecv(Role, T, S))
       MPST.close(ep)             → ()  (must be at SEnd)
    ──────────────────────────────────────────────────────────────────── *)

    | Ast.EApp (Ast.EVar { txt = "MPST.new"; _ }, [proto_expr], sp) ->
      (* Look up the protocol and return a tuple of one TChan per role. *)
      let proto_name = match proto_expr with
        | Ast.ELit (Ast.LitString s, _) -> Some s
        | Ast.EAtom (s, [], _)           -> Some s
        | Ast.ECon (n, [], _)            -> Some n.txt
        | Ast.EVar n                     -> Some n.txt
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "MPST.new: argument must be a protocol name.";
         TError
       | Some pname ->
         (match StrMap.find_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "MPST.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            let n = List.length pi.pi_projections in
            if n < 3 then begin
              Err.error env.errors ~span:sp
                (Printf.sprintf
                   "MPST.new: protocol `%s` has %d role(s) but MPST.new \
                    requires at least 3. Use Chan.new for binary protocols."
                   pname n);
              TError
            end else
              (* Return tuple of TChan endpoints, sorted by role (same as projections order) *)
              TTuple (List.map (fun (_, s_ty) ->
                  TLin (Ast.Linear, TChan (ref s_ty))
                ) pi.pi_projections)))

    | Ast.EApp (Ast.EVar { txt = "MPST.send"; _ }, [ch_expr; role_expr; val_expr], sp) ->
      (* MPST.send(ch, Server, value) — ch must be at SMSend(Server, T, S).
         The role can be written as a bare uppercase name (ECon) or atom (:server). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMSend (target_role, payload_ty, cont) ->
            (* Verify the role argument matches *)
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.send: second argument must be a role name (e.g. Server).";
               TError
             | Some ar when ar <> target_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.send: channel expects to send to `%s` but you said `%s`."
                    target_role ar);
               TError
             | _ ->
               check_expr env val_expr payload_ty
                 ~reason:(Some (RBuiltin "Payload type of MPST.send"));
               TLin (Ast.Linear, TChan (ref cont)))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.send: channel is at `%s` but I expected `MSend(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.send: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.recv"; _ }, [ch_expr; role_expr], sp) ->
      (* MPST.recv(ch, Source) — ch must be at SMRecv(Source, T, S).
         The role can be written as a bare uppercase name or atom.
         Returns (value, new_chan). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMRecv (source_role, payload_ty, cont) ->
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.recv: second argument must be a role name (e.g. Client).";
               TError
             | Some ar when ar <> source_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.recv: channel expects to receive from `%s` but you said `%s`."
                    source_role ar);
               TError
             | _ ->
               TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))])
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.recv: channel is at `%s` but I expected `MRecv(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.recv: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.close"; _ }, [ch_expr], sp) ->
      (* MPST.close(ch) — ch must be at SEnd. *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.close: channel is at `%s` but the session must be complete \
                  (End) before closing."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.close: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Any other `MPST.*` / `Chan.*` spelling reaching this point either (a) is
       one of the six real `Chan.*` ops called with the wrong shape (the
       arity-specific arms above only match the CORRECT arg count, so falling
       through to here with one of these six exact names, still bound to the
       compiler's OWN untouched placeholder, means the call is malformed) or
       (b) does not resolve as an ordinary bound name at all (a misspelling,
       an unimplemented `MPST.choose`/`MPST.offer`, etc). Both are treated as
       a session-op diagnostic rather than a library-lookup failure — falling
       through to the generic qualified-name path would otherwise produce a
       misleading "Unknown module `MPST`".

       The distinction between "still the compiler's placeholder" and "a user
       module shadowed this name" is made STRUCTURALLY, not by a hand-kept
       name list: `builtin_bindings` (the table a few hundred lines above
       that seeds `Chan.new`/`send`/`recv`/`close`/`choose`/`offer` into
       `base_env` as generic curried placeholders — see the comment there,
       "these entries just put the names in scope; the real typing is done in
       the Chan.* EApp branches") is evaluated exactly once at program
       startup, so each entry's `scheme` is a single fixed heap object. A
       fresh top-level `env` starts with that EXACT object bound under each
       name (`bind_vars` calls `StrMap.add`, which stores the value, not a
       copy). If a user later writes `mod Chan do fn recv(a, b) do ... end
       end`, module-export folding REBINDS "Chan.recv" in `env.vars` to a
       brand-new scheme built while typechecking that function — a different
       heap object. So `sch == placeholder_sch` (physical equality) is true
       iff the name was never shadowed: exactly the "still a bare, unshadowed
       compiler builtin, and we already fell through its arity-specific arm"
       case this branch needs to catch, with no risk of a false positive on a
       real user binding and no separate list to keep in sync with the table.
       MPST has no placeholder table entries at all, so `MPST.*` names always
       take the `None`-from-`lookup_var` branch below (mirroring the two
       resolution steps the ordinary `EVar` fallthrough, above, tries first)
       — a genuinely-defined `MPST.helper` (a user module actually named
       `MPST`) is left alone and reaches that path unharmed; only names that
       would ALSO fail there get the session-op message. *)
    | Ast.EApp (Ast.EVar ({ txt = op; _ } as n), _, sp)
      when ((String.length op > 5 && String.sub op 0 5 = "MPST.")
         || (String.length op > 5 && String.sub op 0 5 = "Chan."))
        && (match lookup_var op env with
            | None -> (match resolve_qualified_var op env with (_, Some _) -> false | (_, None) -> true)
            | Some sch ->
              (match List.assoc_opt op builtin_bindings with
               | Some placeholder_sch -> sch == placeholder_sch
               | None -> false)) ->
      Err.error env.errors ~span:sp
        (Printf.sprintf
           "`%s` is not a session-channel operation I know, or it was called \
            with the wrong number of arguments.\n\
            Binary channels: Chan.new/send/recv/close/choose/offer. \
            Multi-party: MPST.new/send/recv/close — multi-party `choose`/`offer` \
            are not implemented yet."
           n.txt);
      TError

    (* Restrict cap_narrow (Part 1): its result must never be a nominal proof
       cap. cap_narrow is the ONLY polymorphic cap producer, so closing this
       closes the proof-cap forge in every expression position (inline arg,
       let-binding, return, and laundered through a polymorphic function).
       IO-lattice narrowing (Cap(IO) -> Cap(IO.Network)) is unaffected because IO
       caps are not in env.proof_caps; proof-cap minting goes through `mint_cap`
       (gated).

       WHY A CALL-SITE / POST-CHECKING SWEEP IS INSUFFICIENT: at this point the
       result var `a` in `Cap(a)` is NOT yet pinned — `infer_app` only pins the
       ARGUMENT against `Cap(IO)`; `a` is pinned by LATER unification.  A recorded
       side-table read after checking catches the directly-pinned positions
       (R1/R7), but when the value is laundered through a polymorphic user
       function (`consume(id(cap_narrow(cap)))`) the recorded node stays unbound
       forever — indistinguishable from legitimate laundered IO narrowing.

       THE FIX (two complementary, both here):
       - VALUE RESTRICTION [demote_to_monomorphic]: a cap_narrow application is
         expansive, so its result must never let-generalize.  Demoting the result
         var to level 0 keeps `let x = cap_narrow(cap)` monomorphic so its single
         use pins the one var.
       - USE-SITE HOOK [tag_cap_producer_result] + the [unify] proof-cap-forge
         arm: tag the inner cap var `a`; the instant `a` (or any var it later
         links to) is unified with a nominal proof cap, [unify] rejects it —
         position- and flow-independent, and it fires ONLY for proof caps so
         IO narrowing (including through a polymorphic fn) is never touched. *)
    | Ast.EApp (Ast.EVar { txt = "cap_narrow"; _ } as fv, [arg], sp) ->
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      demote_to_monomorphic rty;
      tag_cap_producer_result env rty sp;
      (* R4a: record the INSTANTIATED arrow so the sweep can read BOTH the
         source and the target once unification has pinned them. *)
      env.cap_narrow_sites := (sp, f_ty) :: !(env.cap_narrow_sites);
      rty

    (* mint_cap (Part 2): the GATED proof-cap mint.  Same Cap(IO) -> Cap(a)
       inference as cap_narrow; the gate — target must be a proof cap whose
       declaring module is the enclosing module, and the enclosing fn must be
       public — is enforced by the post-checking sweep because (like cap_narrow)
       the result var is not pinned until the surrounding unification runs.  We
       capture the enclosing fn/module CONTEXT here (env.cur_fn_public,
       env.current_module — lambdas inherit the enclosing fn's public-ness) since
       that context is unavailable at sweep time. *)
    | Ast.EApp (Ast.EVar { txt = "mint_cap"; _ } as fv, [arg], sp) ->
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      (* Same value restriction as cap_narrow: a mint_cap application is
         expansive and must not let-generalize, so the gate sweep sees the
         concrete pinned cap rather than an unbound quantified var. *)
      demote_to_monomorphic rty;
      env.mint_cap_sites :=
        (sp, rty, env.cur_fn_public, env.current_module) :: !(env.mint_cap_sites);
      rty

    (* Capability unforgeability (R3): record the three unconstrained JSON
       builtins for the post-checking sweep.  [f_ty] is the FRESHLY
       INSTANTIATED [a -> b]; [infer_app] unifies [a] with the argument and
       [b] with the result in place, so the arrow recorded here reads back
       solved at sweep time.  No [demote_to_monomorphic] here — see
       [check_json_cap_sites] for why an unsolved var is handled by the sweep
       rather than forced at the call site. *)
    | Ast.EApp ((Ast.EVar { txt = ("to_json" | "from_json" | "from_json_events"); _ }) as fv,
                [arg], sp) ->
      let jname = (match fv with Ast.EVar n -> n.txt | _ -> assert false) in
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      (* Value restriction, for exactly the reason spelled out at
         [demote_to_monomorphic]: without it, [let x = from_json(s)]
         generalizes [x] to [∀b. b], every use instantiates a FRESH var pinned
         to that use's type, and the single node recorded here stays an
         unbound quantified var forever.  The sweep then reads [TVar], reports
         nothing, and the forge is reopened in precisely the let-flow position
         reject/t143 exercises.
         Consequence, and it is a real one: a single [from_json] application
         can no longer be used at two DIFFERENT result types. Decoding one
         string as two unrelated types is already meaningless at run time —
         [from_json] dispatches on a single determinable target type — so this
         costs nothing that worked. *)
      demote_to_monomorphic f_ty;
      env.json_cap_sites := (sp, f_ty, jname) :: !(env.json_cap_sites);
      rty

    (* Value restriction for [record_get], for the same reason as [from_json]
       above and for one more that is specific to it: the RUNTIME
       REPRESENTATION of the result is chosen once, at this call site.
       [march_record_get] takes an [expected_kind] that codegen derives from
       the result's static type — [Option(Float)] asks for a BOXED [Some] cell
       (kind 'f'), an unresolved [Option('_)] asks for the erased NICHE
       encoding (kind 'g', payload verbatim).  A [record_get] APPLICATION is
       expansive, so if [let d = record_get(r, "z")] generalizes [d] to
       [∀b. Option(b)], every USE instantiates a fresh [b] and the binding's
       own type — the one codegen reads — stays unbound forever.  The call site
       then emits kind 'g' while [d == Some(0.5)] builds a boxed
       [Option(Float)] on the other side, and the two encodings compare
       unequal: [d == Some(0.5)] answered [false] compiled and [true]
       interpreted.
       Demoting the payload var to level 0 lets the use site's type flow back
       to the binding, so the call site emits the kind the consumer decodes.
       Consequence, and it is a real one: a single [record_get] application can
       no longer be used at two DIFFERENT payload types.  That was never
       meaningful — one stored field has one representation, and reading it as
       both [Option(Float)] and [Option(String)] type-checked only because the
       erasure hid the contradiction. *)
    | Ast.EApp (Ast.EVar { txt = "record_get"; _ } as fv, ([_; _] as args), sp) ->
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty args 0 in
      demote_to_monomorphic rty;
      rty

    | Ast.EApp (f, args, sp) ->
      (* Default-arg call resolution.  [expand_defaults_decl] emits a default-arg
         fn as mangled `foo$R`..`foo$N` decls (one per supplied arity) with NO
         bare `foo` decl; the interpreter (VMultiarity) and TIR
         (_default_dispatch) reconstruct the base-name dispatch downstream, but
         the typechecker runs BETWEEN desugar and both consumers and binds only
         the mangled names — so a source-level call `foo(args)` to a default-arg
         fn otherwise fails with "I cannot find `foo`".  Redirect a call of an
         UNBOUND bare/qualified name to its `name$<n_args>` arity variant when
         that variant is in scope (the codegen/eval paths lower the ORIGINAL
         `foo(args)` independently, so this rewrite is typing-only). *)
      let f =
        match f with
        | Ast.EVar name when lookup_var name.txt env = None ->
          let mangled = Printf.sprintf "%s$%d" name.txt (List.length args) in
          (match lookup_var mangled env with
           | Some _ -> Ast.EVar { name with txt = mangled }
           | None -> f)
        | _ -> f
      in
      let f_ty = infer_expr env f in
      (* Reject wrong-arity calls of known (module-defined) functions.  March
         has no partial application: under-application panics at runtime (and
         the compiler miscompiles it into a body call with a garbage arg), and
         curried-style over-application of a function-returning function also
         panics.  infer_app, being curried, silently accepts these.  We only
         flag a direct call of a name in [fn_arities] whose actual callee type
         is at least as deep as its declared arity — so a local binding that
         shadows the name (different shape) is never falsely rejected. *)
      let arity_error =
        match f with
        | Ast.EVar name ->
          (match StrMap.find_opt name.txt env.fn_arities with
           | Some (arity, def_span) ->
             let n_args = List.length args in
             let rec count_arrows t =
               match repr t with TArrow (_, r) -> 1 + count_arrows r | _ -> 0 in
             if n_args <> arity && count_arrows f_ty >= arity then Some (name, arity, n_args, def_span)
             else None
           | None -> None)
        | _ -> None
      in
      (* Reject a zero-arg call of a plain, non-function VALUE — e.g.
         `root_cap()`, or `let x = 5; x()`, or `let zf = answer; zf()`
         aliasing a genuine zero-arg fn.  infer_app's `| [], t -> t` base
         case exists so a zero-param user `fn` (whose type collapses to its
         bare return type — see the [pmap_threshold] comment) can still be
         invoked as `f()`; without this check it also silently accepts
         calling any non-function value with `()`, since a plain value and a
         "disguised" zero-arg function are indistinguishable by type alone
         once no arguments remain to unify against.

         Two cases:
          - a hardcoded denylist of builtin ambient values ([root_cap]);
          - the general case: a name in [env.plain_let_names] — i.e. one
            most recently bound by a simple `let name = expr` (see the
            [Ast.ELet] case of [infer_block]) — whose resolved type is a
            *concrete* non-arrow (excluding [TVar], which means "not yet
            known" — e.g. mid-inference of a self-recursive call — and
            [TError], already reported elsewhere).  Deliberately does NOT
            use "not in [env.fn_arities]" as the discriminator: that field
            is cleared by [bind_var] on ANY rebinding of the same name
            (correct for its own arity-check purpose — see its comment —
            but a bulk `import Mod` rebinds every imported name via
            [bind_var] too), so at multi-file program scale one importing
            module's `import Shared` would wipe [fn_arities]'s "helper" entry
            for every OTHER module checked afterward in the same threaded
            env, and a plain, unaliased `helper()` call would be misflagged.
            [plain_let_names] avoids that: it is only ever ADDED to at one
            site, so it can't be emptied by an unrelated binding elsewhere. *)
      let noncallable_error =
        match f, args with
        | Ast.EVar name, [] when StringSet.mem name.txt noncallable_builtin_values ->
          Some name
        | Ast.EVar name, [] when StringSet.mem name.txt env.plain_let_names ->
          (match repr f_ty with
           | TArrow _ | TVar _ | TError -> None
           | _ -> Some name)
        | _ -> None
      in
      (match arity_error, noncallable_error with
       | Some (name, arity, n_args, def_span), _ ->
         List.iter (fun a -> ignore (infer_expr env a)) args;
         Err.report env.errors
           { Err.severity = Err.Error; span = sp;
             message = Printf.sprintf
               "Function `%s` expects %d argument%s, but got %d.\n\
                March has no partial application — a call must supply all arguments."
               name.txt arity (if arity = 1 then "" else "s") n_args;
             labels = [{ Err.lbl_span = def_span;
                         Err.lbl_message = Printf.sprintf "defined here with %d parameter%s"
                           arity (if arity = 1 then "" else "s") }];
             notes = []; code = None; fix = None };
         (* Return the declared return type so downstream inference stays sane. *)
         let rec peel n t =
           if n <= 0 then t
           else match repr t with TArrow (_, r) -> peel (n - 1) r | other -> other in
         peel arity f_ty
       | None, Some name ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "`%s` is not a function — it has type `%s`.\n\
               Remove the `()` and use `%s` directly."
              name.txt (pp_ty (repr f_ty)) name.txt);
         TError
       | None, None ->
         let res = infer_app env sp f_ty args 0 in
         (* If [f] is a cap-narrow-factory fn (its body launders a cap_narrow
            result — recorded in check_fn), taint the call's result so the unify
            hook fires when it is later bound to a proof cap.  This closes the
            cross-module factory route (`consume(mk(cap))`) whose prebound scheme
            hides the per-var taint from the hook. *)
         (match f with
          | Ast.EVar name when Hashtbl.mem env.cap_narrow_factory_fns name.txt ->
            tag_cap_producer_result env res sp
          | _ -> ());
         res)

    (* ── Constructor application ──────────────────────────────────── *)
    | Ast.ECon (name, args, sp) ->
      (let ci_opt = match lookup_ctor_same_module name.txt env with
         | Some _ as r -> r
         | None ->
         match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           (* Try qualified module resolution: "Mod.Ctor" *)
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
       in
       (match ci_opt with
        | Some ci when !(env.current_decl) <> "" ->
          env.refs := { callee = qualify_ref_name ci.ci_module
                          (if String.contains name.txt '.'
                           then (let i = String.rindex name.txt '.' in
                                 String.sub name.txt (i + 1) (String.length name.txt - i - 1))
                           else name.txt);
                        caller = !(env.current_decl);
                        ref_kind = `Ctor;
                        ref_file = sp.Ast.file;
                        ref_line = sp.Ast.start_line } :: !(env.refs)
        | Some _ | None -> ());
       match ci_opt with
       | None ->
         let candidates = suggest_ctors name.txt env in
         let hint =
           if candidates = [] then
             qualified_error_msg name.txt env
           else
             let lines = List.map (fun (k, ty) ->
                 Printf.sprintf "  • `%s` — from type `%s`" k ty
               ) candidates in
             "Did you mean one of:\n" ^ String.concat "\n" lines
         in
         Err.error env.errors ~span:name.span
           (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
              name.txt hint);
         List.iter (fun a -> ignore (infer_expr env a)) args;
         TError
       | Some ci ->
         (* A bare, unqualified reference whose candidates span more than one
            DECLARING MODULE (not just more than one bare type name — two
            candidates from the SAME module sharing a ctor name across
            unrelated types is the pre-existing, harmless case below) is
            genuinely ambiguous when the current module owns none of them. *)
         (if not (String.contains name.txt '.') then begin
           let candidates = all_ctor_candidates_named name.txt env in
           let distinct_modules = List.sort_uniq compare (List.map snd candidates) in
           let local_owns_one =
             List.exists
               (fun (_, m) ->
                  m = env.current_module
                  || List.exists (same_package_namespace m)
                       (local_module_paths env))
               candidates in
           if List.length distinct_modules > 1 && not local_owns_one then begin
             let lines = List.map (fun (t, m) ->
                 Printf.sprintf "  • `%s.%s` — from type `%s` in module `%s`"
                   m name.txt t m) candidates in
             Err.error env.errors ~span:name.span
               (Printf.sprintf
                  "Constructor `%s` is ambiguous between multiple modules:\n%s\n\
                   Use a qualified form to disambiguate."
                  name.txt (String.concat "\n" lines))
           end else begin
             let all_types = all_ctors_named name.txt env in
             if List.length all_types > 1 then
               Err.hint env.errors ~span:name.span
                 (Printf.sprintf
                    "Constructor `%s` is defined by multiple types (%s). \
                     Use a qualified form to disambiguate, e.g. `%s.%s`."
                    name.txt
                    (String.concat ", " all_types)
                    (List.hd all_types)
                    name.txt)
           end
         end);
         let arg_tys, result_ty = instantiate_ctor env ci in
         let n_expected = List.length arg_tys in
         let n_got      = List.length args in
         if n_expected <> n_got then begin
           Err.error env.errors ~span:sp
             (Printf.sprintf
                "Constructor `%s` expects %d argument(s) but I got %d."
                name.txt n_expected n_got);
           List.iter (fun a -> ignore (infer_expr env a)) args;
           TError
         end else begin
           List.iter2 (fun arg arg_ty ->
               check_expr env arg arg_ty
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "Argument to constructor `%s`." name.txt)))
             ) args arg_tys;
           (* Message-payload sendability. The overall constructor RESULT
              type (e.g. TCon("Worker_Msg", [])) can never carry this
              information -- actor message sum types are registered with
              ci_params = [] (see ci_is_actor_msg's doc comment), so their
              type never varies with payload. The instantiated ARGUMENT
              types (arg_tys, already solved by the check_expr loop above)
              are the only place a RingBuf/NativeIntArr/NativeFloatArr
              hidden in a message payload is actually visible. Runs once,
              here, at message-construction time -- covers every current
              and future way to move the resulting value (send,
              send_checked, Actor.cast, Actor.call, or just storing it in a
              variable first), not just the builtin used at THIS callsite. *)
           if ci.ci_is_actor_msg then
             List.iter (check_sendable env.errors sp) arg_tys;
           result_ty
         end)

    (* ── Lambdas ──────────────────────────────────────────────────── *)
    | Ast.ELam (params, body, lsp) ->
      (* Snapshot which outer linear vars are unused before entering the lambda.
         Any that become used during body checking were captured by the closure.
         Capturing a linear value in a closure is unsound because the closure
         could be called multiple times, violating the exactly-once guarantee. *)
      let outer_lin_snapshot =
        List.map (fun le -> (le.le_name, !(le.le_used))) env.lin
      in
      let param_tys, env' = bind_lam_params env params in
      let body_ty = infer_expr env' body in
      (* Detect captures: outer linear vars that were unused before but used now. *)
      List.iter (fun le ->
          let was_used_before =
            match List.assoc_opt le.le_name outer_lin_snapshot with
            | Some b -> b
            | None   -> true  (* not in snapshot = lambda's own param, skip *)
          in
          if not was_used_before && !(le.le_used)
          && le.le_lin <> Ast.Unrestricted then
            Err.error env.errors ~span:lsp
              (Printf.sprintf
                 "The linear value `%s` cannot be captured by a closure.\n\
                  A closure may be called multiple times, which would violate \
                  the exactly-once guarantee.\n\
                  Pass `%s` as a parameter to the closure instead."
                 le.le_name le.le_name)
        ) env.lin;
      List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty

    (* ── do/end block ─────────────────────────────────────────────── *)
    | Ast.EBlock (exprs, _) ->
      infer_block env exprs

    (* ── let binding (block-scoped) ───────────────────────────────── *)
    | Ast.ELet (b, sp) ->
      (* When ELet appears as the last expression in a block it's a
         programmer error, but we give it type Unit and move on.  Still honour
         a type annotation on the binding (`let x : T = e`) so the RHS is
         checked against it, mirroring the normal infer_block ELet arm. *)
      let rhs_ty = infer_let_annotated env sp b.bind_ty b.bind_expr in
      let bindings, pat_ty = infer_pattern ~expected:rhs_ty env b.bind_pat in
      let reason = Some (RLetBind sp) in
      unify env ~span:sp ~reason rhs_ty pat_ty;
      (* Record variable name type for hover even in tail position *)
      (match b.bind_pat with
       | Ast.PatVar name -> Hashtbl.replace env.type_map name.span (repr rhs_ty)
       | _ -> ());
      ignore bindings;
      t_unit

    (* ── match ────────────────────────────────────────────────────── *)
    | Ast.EMatch (scrut, branches, sp) ->
      let scrut_ty = infer_expr env scrut in
      infer_match env sp scrut scrut_ty branches

    (* ── Tuples ───────────────────────────────────────────────────── *)
    | Ast.ETuple ([], _)  -> t_unit
    | Ast.ETuple (es, _)  -> TTuple (List.map (infer_expr env) es)

    (* ── Record literals ──────────────────────────────────────────── *)
    | Ast.ERecord (flds, _) ->
      let fld_tys = List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) flds in
      TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys)

    (* ── Record update: { base with f = e, … } ───────────────────── *)
    | Ast.ERecordUpdate (base, updates, sp) ->
      let base_ty   = infer_expr env base in
      let update_tys =
        List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) updates
      in
      (match expand_record env (repr base_ty) with
       | Some (TRecord all_flds) ->
         List.iter (fun (fname, uty) ->
             match List.assoc_opt fname all_flds with
             | Some fty ->
               unify env ~span:sp
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "field `%s` must keep its original type" fname)))
                 fty uty
             | None ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "This record does not have a field called `%s`.\n\
                     The fields I know about are: %s"
                    fname
                    (String.concat ", " (List.map fst all_flds)))
           ) update_tys;
         base_ty
       | _ ->
       (match repr base_ty with
       | TVar _ ->
         (* Base type not yet known — build a partial record constraint *)
         let partial =
           TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b)
                      update_tys) in
         unify env ~span:sp base_ty partial;
         base_ty
       | other ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "I can only use `{ … with … }` on a record, but this \
               expression has type `%s`." (pp_ty other));
         TError))

    (* ── Field access: e.name ─────────────────────────────────────── *)
    | Ast.EField (e, name, sp) ->
      (* Module member access: if e is a module path (ECon or chained EField),
         try looking up "A.B.name" in env.vars before falling back to record field. *)
      let rec module_path = function
        | Ast.ECon (n, [], _) -> Some n.txt
        | Ast.EField (e2, f, _) ->
          (match module_path e2 with
           | Some prefix -> Some (prefix ^ "." ^ f.txt)
           | None -> None)
        | _ -> None
      in
      let mod_access =
        match module_path e with
        | Some prefix ->
          let qualified = prefix ^ "." ^ name.txt in
          (match lookup_var qualified env with
           | Some sch -> Some (instantiate ~use_span:sp env.level env sch)
           | None ->
             (* For multi-component paths like Conduit.Storage.workflow_load,
                the interface method may be registered as just "Storage.workflow_load"
                (interface-qualified) without the outer module prefix.
                Try progressively stripping leading path components. *)
             let member = name.txt in
             let rec try_suffix p =
               match String.index_opt p '.' with
               | None -> None
               | Some i ->
                 let rest = String.sub p (i + 1) (String.length p - i - 1) in
                 let candidate = rest ^ "." ^ member in
                 (match lookup_var candidate env with
                  | Some sch -> Some (instantiate ~use_span:sp env.level env sch)
                  | None -> try_suffix rest)
             in
             try_suffix prefix)
        | None -> None
      in
      (match mod_access with
       | Some ty -> ty
       | None ->
      let e_ty = infer_expr env e in
      (match expand_record env (repr e_ty) with
       | Some (TRecord flds) ->
         (match List.assoc_opt name.txt flds with
          | Some t ->
            (* If the field type is linear/affine, accessing it consumes the
               field.  When the record is held in a named variable, a second
               access on the same variable is caught by [record_use].
               For non-variable expressions we emit a diagnostic here. *)
            (match repr t with
             | TLin (lin, _) when lin <> Ast.Unrestricted ->
               (match e with
                | Ast.EVar vname ->
                  (* Record is held in a named variable: check per-field sentinel.
                     Sentinel "varname#fieldname" was registered by bind_lam_param /
                     bind_pattern_bindings when the variable was bound.  If it
                     exists, record_use will catch a second access; if it doesn't
                     (e.g., variable is outer-scope), fall back to checking the
                     whole-record linear entry via record_use on the variable itself. *)
                  let sentinel = vname.txt ^ "#" ^ name.txt in
                  if List.exists (fun le -> le.le_name = sentinel) env.lin then
                    record_use sentinel sp env
                  else begin
                    (* Sentinel not present — warn that we can't track this field. *)
                    ignore lin;
                    Err.warning env.errors ~span:sp
                      (Printf.sprintf
                         "Field `%s` has a linear type but linearity tracking \
                          is not available for `%s` at this binding site.\n\
                          Ensure `%s` is a locally-bound variable."
                         name.txt vname.txt vname.txt)
                  end
                | _ ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Field `%s` has a linear type; accessing it through \
                        a complex expression loses linearity tracking.\n\
                        Bind the record to a variable first."
                       name.txt))
             | _ -> ());
            t
          | None   ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "This record does not have a field called `%s`.\n\
                  The fields I see are: %s"
                 name.txt
                 (String.concat ", " (List.map fst flds)));
            TError)
       | _ ->
         (match repr e_ty with
          | TVar _ ->
            (* Field-access on an unknown record type — return a fresh var for now.
               A row-polymorphism extension would constrain this properly. *)
            fresh_var env.level
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "I cannot access field `%s` because this expression has \
                  type `%s`, which is not a record." name.txt (pp_ty other));
            TError))
      (* close the None branch of mod_access match *)
      )

    (* ── if/do/else/end ───────────────────────────────────────────── *)
    | Ast.EIf (cond, then_, else_, _sp) ->
      (* The condition runs on BOTH paths, so it is checked before the
         mutual-exclusion snapshot below: a linear value consumed here is
         still consumed inside either branch. *)
      check_expr env cond t_bool
        ~reason:(Some (RBuiltin "The condition of an if expression must be Bool."));
      (* The two branches are mutually exclusive, so each may consume the same
         outer linear value once — the same rule match arms get. *)
      let r_then = ref TError and r_else = ref TError in
      iter_paths_linear env
        [ (fun () -> r_then := infer_expr env then_);
          (fun () -> r_else := infer_expr env else_) ];
      let t_then = !r_then in
      let t_else = !r_else in
      (* Point primary error at the else branch; label points at then branch
         (the source of the expected type), making both branches visible. *)
      let then_sp = span_of_expr then_ in
      let else_sp = span_of_expr else_ in
      unify env ~span:else_sp
        ~reason:(Some (RBecause (RMatchArm then_sp,
          "Both branches of an if expression must return the same type.")))
        t_else t_then;
      t_then

    (* ── match do cond_arm* end ───────────────────────────────────── *)
    | Ast.ECond (arms, sp) ->
      (match arms with
       | [] ->
         Err.error env.errors ~span:sp
           "A `match do` expression needs at least one arm.";
         TError
       | (first_cond, first_body) :: rest ->
         (* Only the BODIES are mutually exclusive here, so this cannot use
            [iter_paths_linear] wholesale. The conditions are evaluated in
            order until one holds, so a later condition genuinely co-occurs
            with every earlier one on the fall-through path and they must
            share linear-use state. A body, by contrast, runs only when its
            own condition was the first true one — at which point no later
            condition is ever evaluated — so each body is its own path,
            starting from the state its own condition left behind.

            Hence: check conditions against the shared state, run each body
            rolled back, and apply the union of what the bodies consumed
            once at the end. *)
         let body_acc =
           List.map (fun le -> (le, ref false, ref (None : Ast.span option)))
             env.lin
         in
         let run_body body_e =
           let saved =
             List.map (fun le -> (le, !(le.le_used), !(le.le_first_use)))
               env.lin
           in
           let ty = infer_expr env body_e in
           List.iter (fun (le, acc, acc_span) ->
               if !(le.le_used) then begin
                 acc := true;
                 if !acc_span = None then acc_span := !(le.le_first_use)
               end) body_acc;
           List.iter (fun (le, was, was_span) ->
               le.le_used := was; le.le_first_use := was_span) saved;
           ty
         in
         check_expr env first_cond t_bool
           ~reason:(Some (RBuiltin "Each condition in `match do` must be Bool."));
         let result_ty = run_body first_body in
         List.iter (fun (cond_e, body_e) ->
             check_expr env cond_e t_bool
               ~reason:(Some (RBuiltin "Each condition in `match do` must be Bool."));
             let arm_ty = run_body body_e in
             unify env ~span:sp ~reason:(Some (RMatchArm sp)) result_ty arm_ty
           ) rest;
         List.iter (fun (le, acc, acc_span) ->
             if !acc && not !(le.le_used) then begin
               le.le_used := true;
               if !(le.le_first_use) = None then le.le_first_use := !acc_span
             end) body_acc;
         result_ty)

    (* ── Pipes / Sigils — must be desugared before reaching us ───── *)
    | Ast.EPipe _ ->
      failwith
        "March type checker: encountered EPipe — \
         the desugaring pass must run before type checking."

    | Ast.ESigil _ ->
      failwith
        "March type checker: encountered ESigil — \
         the desugaring pass must run before type checking."

    (* ── Atoms ────────────────────────────────────────────────────── *)
    | Ast.EAtom (_, args, _) ->
      List.iter (fun a -> ignore (infer_expr env a)) args;
      t_atom

    (* ── Actor messaging ──────────────────────────────────────────── *)
    | Ast.ESend (cap, msg, _sp) ->
      ignore (infer_expr env cap);
      (* Message-payload sendability (RingBuf/NativeIntArr/NativeFloatArr)
         is checked once, at message-CONSTRUCTION time, in the ECon arm
         (guarded by ci_is_actor_msg) -- not here. The overall type of `msg`
         (a bare TCon("<Actor>_Msg", []), since actor message sum types are
         registered with ci_params = []) never varies with payload and so
         could never see a mutable-buffer type nested in it; checking it
         here was a no-op regardless of what check_sendable's argument was. *)
      let _msg_ty = infer_expr env msg in
      (* send() returns Option(Unit): Some(()) when the message was enqueued,
         None when the target actor is dead/unknown (fire-and-forget drop).
         This is the ACTUAL contract of both backends — the interpreter's ESend
         only ever produces `Some(VUnit)` / `None` (sends are async; the
         handler result never flows back), and the compiled runtime's
         march_send returns the equivalent boxed Option(Unit).  The previous
         `fresh_var` typing ("returns the handler's result — unconstrained")
         was stale AND actively harmful compiled: the erased Option('a) at a
         `match send(...)` scrutinee made emit_case's abstract-arg niche
         recovery guess the NICHE decode for march_send's BOXED values, so
         `send(dead_pid, M)` decoded as Some while the interpreter said None. *)
      TCon ("Option", [t_unit])

    | Ast.ESpawn (actor, _) ->
      ignore (infer_expr env actor);
      (* Both backends dispatch `spawn` by the actor's *name*, resolved at
         compile time (it selects a statically generated `<Actor>_spawn`
         function).  There is no runtime actor-descriptor value, so the argument
         must be a plain actor name — not a computed expression.  The TIR
         lowering assumes exactly this shape (`ECon(_, [], _)` / `EVar`); reject
         anything else here with a clean diagnostic rather than letting a
         well-typed program reach the internal `failwith` in lowering. *)
      (match actor with
       | Ast.ECon (_, [], _) | Ast.EVar _ -> ()
       | _ ->
         Err.error env.errors ~span:(span_of_expr actor)
           "`spawn` needs a plain actor name written directly, like \
            `spawn(Counter)`.\n\
            A computed actor expression (from an `if`, `match`, or function \
            call) isn't supported: March resolves which actor to spawn at \
            compile time from its name.");
      (* Return Pid[state] rather than Pid[fresh]: [DActor] binds the actor
         NAME to `Pid[state_ty]` in [env.vars], but the nullary-constructor
         registration (needed so `spawn(Counter)` parses/checks as a name)
         shadows that binding at every ECon occurrence — so the state type
         never reached an observable Pid and every spawn site got an
         unconstrained variable that unified opportunistically (finding 18,
         core-march-types.md §2.6.3).  Reach the vars binding directly by
         name here.  Unknown names (error recovery) keep the fresh var. *)
      let actor_name = match actor with
        | Ast.ECon (n, [], _) -> Some n.txt
        | Ast.EVar n          -> Some n.txt
        | _ -> None in
      (match actor_name with
       | Some n ->
         (match StrMap.find_opt n env.vars with
          | Some sch ->
            (match instantiate env.level env sch with
             | TCon ("Pid", _) as pid_ty -> pid_ty
             | _ -> TCon ("Pid", [fresh_var env.level]))
          | None -> TCon ("Pid", [fresh_var env.level]))
       | None -> TCon ("Pid", [fresh_var env.level]))

    (* ── REPL result reference ─────────────────────────────────────── *)
    | Ast.EResultRef _ ->
      (* Return a fresh unification variable — EResultRef is substituted
         by the REPL loop before typechecking, so this is a fallback. *)
      fresh_var env.level

    (* ── Debugger breakpoint / value trace ────────────────────────── *)
    | Ast.EDbg (None, _) -> t_unit
    | Ast.EDbg (Some inner, _) -> infer_expr env inner

    (* ── Test assertion ─────────────────────────────────────────────── *)
    | Ast.EAssert (inner, sp) ->
      (* The inner expression must be Bool. Assert evaluates to Unit. *)
      check_expr env inner t_bool ~reason:(Some (RBuiltin "assert expects a Bool expression"));
      Hashtbl.replace env.type_map sp t_unit;
      t_unit

    (* ── Local recursive named function (block-scoped) ─────────────── *)
    | Ast.ELetFn (name, params, ret_ann, body, sp) ->
      (* Typecheck the local fn and return the type of its closure.
         When appearing as a standalone expression (last in block), return
         the function type; the binding is only in effect for block context. *)
      let fn_ty = fresh_var env.level in
      let env_with_self = bind_var name.txt (Mono fn_ty) env in
      let param_tys, env_inner = bind_lam_params env_with_self params in
      let body_ty = infer_block env_inner [body] in
      let ret_ty  = match ret_ann with
        | None -> body_ty
        | Some ann ->
          let tvars = ref [] in
          let expected = surface_ty env ~tvars ann in
          unify env ~span:sp ~reason:None body_ty expected;
          expected
      in
      let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
      unify env ~span:sp ~reason:None fn_ty arrow_ty;
      arrow_ty

    | Ast.ELetQ (p, result_expr, body, sp) ->
      (* let? p = result_expr; body
         - result_expr  : Result(t_ok, t_err)
         - p            : t_ok  (binds on Ok branch)
         - body         : Result(t_r, t_err)  (continuation)
         Returns Result(t_r, t_err), propagating Err upward automatically. *)
      (match body with
       | Ast.EBlock ([], _) ->
         Err.error env.errors ~span:sp
           "`let?` cannot be the last expression in a block.\n\
            Add a Result-producing expression after it — for example:\n\
            \n\
            \    let? x = might_fail()\n\
            \    Ok(x + 1)";
         TError
       | _ ->
         let result_ty = infer_expr env result_expr in
         let t_ok  = fresh_var env.level in
         let t_err = fresh_var env.level in
         unify env ~span:sp
           ~reason:(Some (RBuiltin
             "The right-hand side of `let?` must be a Result value."))
           result_ty (t_result t_ok t_err);
         (* [t_ok] is no longer a bare fresh var — the unify above bound it to
            the RHS's Ok payload — so it is a usable expected type here, and a
            record pattern needs it to open its field list. *)
         let bindings, pat_ty = infer_pattern ~expected:t_ok env p in
         unify env ~span:sp
           ~reason:(Some (RLetBind sp))
           t_ok pat_ty;
         let env' = bind_pattern_bindings result_expr bindings env in
         let body_ty = infer_expr env' body in
         let t_r = fresh_var env.level in
         unify env ~span:sp
           ~reason:(Some (RBuiltin
             "The code after `let?` must produce a Result with the same error type."))
           body_ty (t_result t_r t_err);
         body_ty)

    | Ast.ELetStar (p, result_expr, body, sp) ->
      (* let* p = result_expr; body
         Generalizes let?: `M` is whatever type constructor result_expr's
         type turns out to be (Option, Result, List, a user type, ...),
         resolved by convention -- M's `flat_map` lives in the module of
         the SAME name as M (Option.flat_map, Result.flat_map, ...). March
         has no Bind/Monad interface (interfaces take exactly one type
         parameter; Self is never applied to an argument), so this cannot
         be ordinary constrained polymorphism -- the dispatch happens HERE,
         by inferred type, at typecheck time. See
         specs/lang/let-star-generalized-bind.md and
         specs/plans/2026-08-09-parsing-and-string-search.md §4.3.
         TIR lowering (lib/tir/lower.ml) expands this into an ordinary call
         `M.flat_map(result_expr, fn p -> body end)` once types are fixed;
         this case only needs to CHECK that shape is consistent. *)
      (match body with
       | Ast.EBlock ([], _) ->
         Err.error env.errors ~span:sp
           "`let*` cannot be the last expression in a block.\n\
            Add an expression of the same type as the right-hand side \
            after it — for example, if the right-hand side is an \
            `Option`:\n\
            \n\
            \    let* x = might_be_none()\n\
            \    Some(x + 1)";
         TError
       | _ ->
         let result_ty = infer_expr env result_expr in
         (match repr result_ty with
          | TCon (head_name, _) ->
            let flat_map_name = head_name ^ ".flat_map" in
            (* Look in the CURRENT SCOPE first, and only then fall back to
               loading a stdlib module off disk.  [resolve_qualified_var] can
               only find a module that has a FILE whose snake_case name
               matches it ([Module_registry.ensure_loaded]) — true of
               Option/Result/List, false of every user-defined type, whether
               declared in this file or imported.  Those are already bound in
               [env.vars] under their qualified name, so consulting the env
               first is what makes `let*`'s documented extension point ("define
               `flat_map` in a module named `M`") actually work for user types.
               Resolving env-first also matches how an ordinary hand-written
               `Box.flat_map(...)` call already resolves, so `let*` can never
               disagree with the equivalent explicit call.  Regression witness:
               specs/lang/types/accept/t184_letstar_user_defined_type.march. *)
            let env', scheme_opt =
              match lookup_var flat_map_name env with
              | Some s -> env, Some s
              | None   -> resolve_qualified_var flat_map_name env
            in
            (match scheme_opt with
             | None ->
               Err.error env'.errors ~span:sp
                 (Printf.sprintf
                    "`let*` needs `%s`, but it doesn't exist.\n\
                     Define `flat_map(x : %s(a), f : a -> %s(b)) : %s(b)` \
                     in a module named `%s` to make `let*` work with `%s`."
                    flat_map_name head_name head_name head_name
                    head_name head_name);
               TError
             | Some scheme ->
               let flat_map_ty = instantiate env'.level env' scheme in
               (match repr flat_map_ty with
                | TArrow (m_arg, TArrow (TArrow (a_ty, m_b1), m_b2)) ->
                  unify env' ~span:sp
                    ~reason:(Some (RBuiltin
                      (Printf.sprintf
                         "The right-hand side of `let*` must match `%s`'s \
                          own type." flat_map_name)))
                    result_ty m_arg;
                  unify env' ~span:sp ~reason:(Some (RLetBind sp)) m_b1 m_b2;
                  let bindings, pat_ty = infer_pattern ~expected:a_ty env' p in
                  unify env' ~span:sp ~reason:(Some (RLetBind sp)) a_ty pat_ty;
                  let env'' = bind_pattern_bindings result_expr bindings env' in
                  let body_ty = infer_expr env'' body in
                  unify env'' ~span:sp
                    ~reason:(Some (RBuiltin
                      (Printf.sprintf
                         "The code after `let*` must also produce `%s`."
                         head_name)))
                    body_ty m_b2;
                  body_ty
                | _ ->
                  Err.error env'.errors ~span:sp
                    (Printf.sprintf
                       "`%s` doesn't have the shape `let*` needs: \
                        `%s(a) -> (a -> %s(b)) -> %s(b)`."
                       flat_map_name head_name head_name head_name);
                  TError))
          | _ ->
            Err.error env.errors ~span:sp
              "`let*`'s right-hand side must have a concrete type (e.g. \
               `Option(a)`, `Result(a, e)`) so `let*` can find its \
               `flat_map` — its type could not be determined here.";
            TError))
  in
  Hashtbl.replace env.type_map (span_of_expr e) (repr result);
  result

(** [check_expr env e expected ~reason] verifies [e] has type [expected].
    Uses the "checking" direction for lambdas (peels off arrows) and for
    match expressions (checks each arm against [expected]).  Falls back
    to infer + unify for everything else. *)
and check_expr env (e : Ast.expr) (expected : ty) ~reason =
  let sp = span_of_expr e in
  Hashtbl.replace env.type_map sp (repr expected);
  match e, repr expected with

  (* Lambda in check mode: peel arrow types one-by-one *)
  | Ast.ELam (params, body, lsp), _ ->
    let rec peel ps ty env =
      match ps, repr ty with
      | [], TArrow (param_ty, ret_ty)
        when (match repr param_ty with TTuple [] -> true | _ -> false) ->
        (* A 0-arg lambda `fn -> body` (or the equivalent `fn () -> body`,
           which parses identically to [ELam ([], ...)]) checked against a
           declared `Unit -> T` is accepted as a unit-consuming thunk: there is
           no surface parameter to bind (the unit domain is implicit), so we
           simply check the body against the arrow's result type.  This lets
           `fn -> body` satisfy a `Unit -> Unit` callback param — the natural
           spelling — without forcing the `fn _ -> body` (1-arg discard) idiom.
           The symmetric call side (`cb()`) is handled in [infer_app]. *)
        check_expr env body ret_ty ~reason
      | [], body_ty ->
        check_expr env body body_ty ~reason
      | p :: rest, TArrow (arg_ty, ret_ty) ->
        let env' = bind_lam_param env lsp p (Some arg_ty) in
        peel rest ret_ty env'
      | _, _ ->
        let inferred = infer_expr env (Ast.ELam (params, body, lsp)) in
        unify env ~span:lsp ~reason inferred expected
    in
    peel params expected env

  (* Match in check mode: check each arm against expected *)
  | Ast.EMatch (scrut, branches, msp), _ ->
    let scrut_ty = infer_expr env scrut in
    iter_arms_linear env branches (fun (br : Ast.branch) ->
        let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
        unify env ~span:msp ~reason:(Some (RMatchArm msp)) scrut_ty pat_ty;
        (* Propagate linearity from scrutinee to pattern-bound variables. *)
        let env' = bind_pattern_bindings scrut bindings env in
        (match br.branch_guard with
         | Some g ->
           check_expr env' g t_bool
             ~reason:(Some (RBuiltin "Match guards must be Bool."))
         | None -> ());
        with_offer_refinement env scrut br (fun () ->
          check_expr env' br.branch_body expected ~reason)
      );
    if not (check_offer_label_exhaustiveness env msp scrut branches) then
      check_exhaustiveness env msp scrut_ty branches;
    check_redundant_arms env scrut_ty branches

  (* Constructor in check mode: when the bare constructor name is ambiguous
     across types, use the expected type to pick the candidate whose parent
     type matches — mirroring the pattern path ([infer_pattern]'s by_expected
     logic). Without this, the catch-all below would route through [infer_expr],
     whose [lookup_ctor] makes a registration-order-dependent pick; if it
     guesses the wrong type the result fails to unify. Resolving by expected
     type also lets nested constructors disambiguate recursively (the args are
     checked against the chosen constructor's field types). *)
  | Ast.ECon (name, args, sp), exp_ty
    when (not (String.contains name.txt '.'))
         && (match exp_ty with TCon _ -> true | _ -> false)
         && List.length (all_ctors_named name.txt env) > 1 ->
    (match (match exp_ty with
            | TCon (tn, _) -> lookup_ctor_in_type name.txt tn env
            | _ -> None) with
     | Some ci ->
       let arg_tys, result_ty = instantiate_ctor env ci in
       let n_expected = List.length arg_tys in
       let n_got      = List.length args in
       if n_expected <> n_got then begin
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Constructor `%s` expects %d argument(s) but I got %d."
              name.txt n_expected n_got);
         List.iter (fun a -> ignore (infer_expr env a)) args
       end else begin
         List.iter2 (fun arg arg_ty ->
             check_expr env arg arg_ty
               ~reason:(Some (RBuiltin
                 (Printf.sprintf "Argument to constructor `%s`." name.txt)))
           ) args arg_tys;
         unify env ~span:sp ~reason result_ty expected
       end
     | None ->
       (* Expected type doesn't name a type defining this constructor —
          fall back to inference so the normal mismatch error is produced. *)
       let inferred = infer_expr env e in
       unify env ~span:sp ~reason inferred expected)

  (* All other expressions: infer then unify *)
  | _ ->
    let inferred = infer_expr env e in
    unify env ~span:sp ~reason inferred expected

(** Thread function application through argument list, tracking arg index. *)
and infer_app env span f_ty args idx =
  match args, repr f_ty with
  | [], t ->
    (* A call written with empty parens — `f()`, i.e. zero surface arguments
       at [idx = 0] — against a `Unit -> T` value applies the implicit unit
       argument and yields `T`.  This mirrors March's 0-arg convention: a
       0-arg function is typed as its return type, and a 0-arg lambda
       `fn -> body` checks against `Unit -> T` (see the [ELam] arm in
       [check_expr]).  The [idx = 0] guard keeps a partial application that
       merely leaves a trailing `Unit -> T` (e.g. `g(x)` with
       `g : Int -> Unit -> T`) returning the arrow — only the literal
       empty-parens call form applies the implicit unit. *)
    (match idx, t with
     | 0, TArrow (param_ty, ret_ty)
       when (match repr param_ty with TTuple [] -> true | _ -> false) ->
       ret_ty
     | _ -> t)
  | arg :: rest, TArrow (param_ty, ret_ty) ->
    check_expr env arg param_ty
      ~reason:(Some (RFnArg (span, idx)));
    (* Proof-cap forge taint: if this argument laundered a [cap_narrow] result
       (its type — now unified with [param_ty] — carries a tagged cap-producer
       var), taint [ret_ty].  This closes the launder-through-a-polymorphic-fn
       routes (e.g. [consume(id(cap_narrow(cap)))]) where the fn's return
       decouples from its param and would otherwise slip past the direct unify
       hook: the tainted result is then rejected when it is bound to a proof cap.
       Only proof caps are ever rejected downstream, so IO narrowing through the
       same fn is unaffected. *)
    if ty_has_tagged_cap_producer env param_ty then
      tag_cap_producer_result env ret_ty span;
    infer_app env span ret_ty rest (idx + 1)
  | arg :: rest, TVar _ ->
    (* f_ty not yet known — constrain it *)
    let arg_ty = infer_expr env arg in
    let ret_ty = fresh_var env.level in
    unify env ~span
      ~reason:(Some (RBuiltin "A value being applied like a function must have a function type."))
      f_ty (TArrow (arg_ty, ret_ty));
    (* Proof-cap forge taint (same as the TArrow branch): a laundered cap_narrow
       argument taints the call's result so the unify hook still fires downstream. *)
    if ty_has_tagged_cap_producer env arg_ty then
      tag_cap_producer_result env ret_ty span;
    infer_app env span ret_ty rest (idx + 1)
  | _, TError ->
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError
  | _, other ->
    Err.error env.errors ~span
      (Printf.sprintf
         "This is not a function — it has type `%s`.\n\
          I cannot apply it to arguments." (pp_ty other));
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError

(** Extract the branch label an atom arm selects (nullary `:L`), if any. *)
and offer_arm_label (br : Ast.branch) =
  match br.branch_pat with
  | Ast.PatAtom (l, [], _)          -> Some l
  | Ast.PatLit (Ast.LitAtom l, _)   -> Some l
  | _                               -> None

(** Exhaustiveness for a `match` whose scrutinee is an OFFER LABEL variable.
    The label's universe is the protocol's branch set — closed — not the open
    `Atom` universe the generic checker assumes.  Returns [true] when this
    specialised check ran (so the caller skips the generic one). *)
and check_offer_label_exhaustiveness env span scrut (branches : Ast.branch list) =
  match scrut with
  | Ast.EVar name ->
    (match List.assoc_opt name.txt env.offer_labels with
     | None -> false
     | Some (_r, proto_branches) ->
       let has_catch_all =
         List.exists (fun (br : Ast.branch) ->
             match br.branch_pat with
             | Ast.PatWild _ | Ast.PatVar _ -> br.branch_guard = None
             | _ -> false) branches
       in
       let handled =
         List.filter_map (fun (br : Ast.branch) ->
             if br.branch_guard = None then offer_arm_label br else None) branches
       in
       let missing =
         List.filter (fun (lbl, _) -> not (List.mem lbl handled)) proto_branches
       in
       (* An arm naming a label the protocol does not offer can never be taken —
          almost always a typo (`:okk` for `:ok`).  A warning, not an error: a
          redundant arm is dead code, not a soundness problem. *)
       List.iter (fun (br : Ast.branch) ->
           match offer_arm_label br with
           | Some lbl when not (List.mem_assoc lbl proto_branches) ->
             Err.warning env.errors ~span
               (Printf.sprintf
                  "This `match` has an arm for `:%s`, which is not one of the \
                   protocol's `offer` branches — it can never be taken.\n\
                   The branches are: %s."
                  lbl
                  (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) proto_branches)))
           | _ -> ()) branches;
       (if not has_catch_all && missing <> [] then
          Err.error env.errors ~span
            (Printf.sprintf
               "This `match` doesn't handle every branch the peer can choose — \
                missing: %s.\n\
                The protocol's `offer` branches are: %s."
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) missing))
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) proto_branches))));
       true)
  | _ -> false

(** Run [f] with the offer channel's session ref transiently refined to the
    branch [br] selects (F5).  When [scrut] is an offer label variable (linked
    in [env.offer_labels]) and [br]'s pattern names a known branch label, point
    the shared session ref at that branch's continuation for the duration of
    [f], then restore it — so the channel bound alongside the label types at the
    branch the peer ACTUALLY chose inside each arm, not always the first. *)
and with_offer_refinement env scrut (br : Ast.branch) (f : unit -> unit) =
  let applied =
    match scrut with
    | Ast.EVar name ->
      (match List.assoc_opt name.txt env.offer_labels, offer_arm_label br with
       | Some (r, branches), Some lbl ->
         (match List.assoc_opt lbl branches with
          | Some cont -> let saved = !r in r := cont; Some (r, saved)
          | None -> None)
       | _ -> None)
    | _ -> None
  in
  match applied with
  | Some (r, saved) ->
    (* Snapshot-and-restore the WHOLE list rather than re-adding [r] on the way
       out: safe because [Chan.offer] only ever PREPENDS, so anything registered
       while [f] runs is a strictly newer, unrelated ref whose own scope ended
       with [f] — restoring the snapshot cannot resurrect a stale mark or drop a
       live one for a ref still reachable after this arm. *)
    let saved_unrefined = !(env.offer_unrefined) in
    env.offer_unrefined := List.filter (fun r' -> not (r' == r)) saved_unrefined;
    Fun.protect
      ~finally:(fun () -> r := saved; env.offer_unrefined := saved_unrefined)
      f
  | None ->
    (* No refinement applied.  If the scrutinee IS an offer label but this arm
       names no branch (a `_`/variable catch-all), the user demonstrably DID
       write a `match` — record that so any unrefined-channel diagnostic raised
       inside the arm explains why the catch-all does not count (F7). *)
    let is_offer_catchall =
      match scrut with
      | Ast.EVar name ->
        List.mem_assoc name.txt env.offer_labels
        && (match br.branch_pat with
            | Ast.PatWild _ | Ast.PatVar _ -> true
            | _ -> false)
      | _ -> false
    in
    if is_offer_catchall then begin
      incr offer_catchall_depth;
      Fun.protect ~finally:(fun () -> decr offer_catchall_depth) f
    end else f ()

(** Check each match arm as a mutually-exclusive path with respect to
    linear-value use.  Because at most one arm runs on any execution path, a
    linear value bound OUTSIDE the match may be consumed once in EACH arm
    without violating "use exactly once".  Snapshot the outer linear-use flags,
    reset them before every arm, and union afterwards (a var used in any arm is
    marked consumed) — eliminating the spurious "used more than once" a shared
    mutable flag would otherwise raise across arms, while still catching a
    genuine double-use WITHIN a single arm. *)
and iter_arms_linear env (branches : Ast.branch list) (f : Ast.branch -> unit) : unit =
  iter_paths_linear env (List.map (fun br () -> f br) branches)

(** The mutual-exclusion discipline itself, over an arbitrary list of paths.
    Every branching construct in the language shares it — [EMatch] arms via
    [iter_arms_linear], the two branches of an [EIf], and the bodies of an
    [ECond] — because "at most one of these runs" is the only property it
    needs.  Each path is run with the linear-use flags reset to their state
    on entry, and the union of what the paths consumed is applied once at the
    end.

    What this deliberately does NOT cover is code that runs on EVERY path: an
    [EIf]'s condition, or an [ECond]'s conditions, must be checked OUTSIDE the
    paths (before the relevant snapshot is taken), so that a value consumed
    there is still seen as consumed inside each branch.  Resetting around the
    condition too would turn a genuine double-use into an accepted program —
    the one way this helper can be misused. *)
and iter_paths_linear env (paths : (unit -> unit) list) : unit =
  (* For each outer linear entry track (entry, pre-branch flag, union accumulator). *)
  (* [le_first_use] is saved and restored alongside [le_used]. If it were not,
     the first path to consume a value would leave its span behind, and a genuine
     double-use in a LATER path would point at a line in a sibling path that never
     ran on the same execution — a confidently wrong "already consumed here". *)
  let snapshot =
    List.map (fun le ->
        (le, !(le.le_used), ref !(le.le_used),
             !(le.le_first_use), ref !(le.le_first_use)))
      env.lin
  in
  List.iter (fun run_path ->
      (* Reset each entry to its pre-branch state so this path starts fresh. *)
      List.iter (fun (le, was, _acc, was_span, _acc_span) ->
          le.le_used := was; le.le_first_use := was_span) snapshot;
      run_path ();
      (* Fold whatever this path consumed into the union accumulator. *)
      List.iter (fun (le, _was, acc, _was_span, acc_span) ->
          if !(le.le_used) then begin
            acc := true;
            if !acc_span = None then acc_span := !(le.le_first_use)
          end) snapshot
    ) paths;
  (* Final: consumed iff consumed before the branch OR on some path. *)
  List.iter (fun (le, _was, acc, _was_span, acc_span) ->
      le.le_used := !acc; le.le_first_use := !acc_span) snapshot

(** Infer the result type of a match expression. *)
and infer_match env span scrut scrut_ty branches =
  let result_ty = fresh_var env.level in
  iter_arms_linear env branches (fun (br : Ast.branch) ->
      let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
      unify env ~span ~reason:(Some (RMatchArm span)) scrut_ty pat_ty;
      (* Propagate linearity from scrutinee to pattern-bound variables. *)
      let env' = bind_pattern_bindings scrut bindings env in
      (match br.branch_guard with
       | Some g ->
         check_expr env' g t_bool
           ~reason:(Some (RBuiltin "Match guards must be Bool."))
       | None -> ());
      with_offer_refinement env scrut br (fun () ->
        check_expr env' br.branch_body result_ty
          ~reason:(Some (RMatchArm span)))
    );
  if not (check_offer_label_exhaustiveness env span scrut branches) then
    check_exhaustiveness env span scrut_ty branches;
  check_redundant_arms env scrut_ty branches;
  result_ty

(** Whether every diagnostic in [scratch] stems from a data constructor used
    in type position — a phantom/typestate tag like `Handle(Open)`, where
    `Open` is a constructor of some ADT rather than a type name, which
    [surface_ty] legitimately cannot resolve (it emits [qualified_error_msg]'s
    unqualified-name form, "I cannot find `Open`.", for the ctor name).
    Recognised by checking that the unresolved name IS a known constructor
    ([env.ctors]) — genuinely bogus names (typo'd/renamed types, unknown
    modules) are never registered there, so this returns [false] for those
    and the caller must surface the error instead of discarding it. *)
and annotation_errors_are_phantom_tags_only env (scratch : March_errors.Errors.ctx) =
  let prefix = "I cannot find `" in
  let plen = String.length prefix in
  List.for_all (fun (d : March_errors.Errors.diagnostic) ->
    let msg = d.March_errors.Errors.message in
    String.length msg >= plen + 2
    && String.sub msg 0 plen = prefix
    && String.sub msg (String.length msg - 2) 2 = "`."
    && StrMap.mem (String.sub msg plen (String.length msg - plen - 2)) env.ctors
  ) scratch.March_errors.Errors.diagnostics

(** Compute the type of a `let`-binding RHS, honouring an optional type
    annotation (`let x : T = e`, finding 16).  When [bind_ty] is present the
    annotation becomes a CHECKING context for the RHS (via [check_expr]) — a
    mismatch like `let x : Int = "foo"` is rejected, while a polymorphic RHS
    bound at a more specific instance (`let f : (Int) -> Int = fn x -> x`)
    still typechecks.

    The annotation is resolved into a scratch error context first.  If
    [surface_ty] fails ONLY because of a phantom/typestate tag used in type
    position (`let h : Handle(Open) = …`), we discard the scratch errors and
    fall back to plain inference — the pre-finding-16 behaviour for
    annotations the type grammar can't express.  But if any failure is a
    genuinely unresolvable name (unknown module, typo'd/renamed type — see
    the `RRB`/`Vec(Int) = "not a vec"` soundness hole), the annotation is
    real and broken: surface the scratch diagnostics as real errors instead
    of silently ignoring the annotation. *)
and infer_let_annotated env sp bind_ty bind_expr =
  match bind_ty with
  | None -> infer_expr env bind_expr
  | Some ann ->
    let scratch = March_errors.Errors.create () in
    let tvars = ref [] in
    let ann_ty = surface_ty { env with errors = scratch } ~tvars ann in
    if March_errors.Errors.has_errors scratch then begin
      if not (annotation_errors_are_phantom_tags_only env scratch) then
        List.iter (fun (d : March_errors.Errors.diagnostic) ->
          March_errors.Errors.error env.errors ~span:d.March_errors.Errors.span
            d.March_errors.Errors.message
        ) scratch.March_errors.Errors.diagnostics;
      (* Annotation not (fully) expressible as a resolvable type — infer from
         the RHS alone; any genuine error was already surfaced above. *)
      infer_expr env bind_expr
    end else begin
      check_expr env bind_expr ann_ty ~reason:(Some (RAnnotation sp));
      ann_ty
    end

(** Infer types of all expressions in a block, threading [ELet] bindings. *)
and infer_block env exprs =
  match exprs with
  | [] -> t_unit
  | [ e ] -> infer_expr env e
  | Ast.ELet (b, sp) :: rest ->
    (* Use enter_level so the RHS is checked at a fresh level.  This ensures
       that `occurs` lowers any TVars that escape into outer-scope types (e.g.
       the return type of a curried application f(acc) where f is a parameter)
       before generalize is called.  Without the level bump, those intermediate
       TVars share the function-body level and get incorrectly quantified, causing
       `let f1 = f(acc); f1(k)` to instantiate a fresh TVar for f1 rather than
       unifying the original t_r1 that links f's curried return chain. *)
    let env_rhs = enter_level env in
    (* If the binding carries a type annotation (`let x : T = e`), CHECK the
       RHS against the annotated type rather than inferring it bare.  Using
       check_expr (not just a post-hoc unify) gives a legitimately polymorphic
       RHS a checking context, so `let f : (Int) -> Int = fn x -> x` still
       works while `let x : Int = "foo"` is rejected.  The annotated type then
       becomes the binding's type, so the pattern unifies against it. *)
    let rhs_ty = infer_let_annotated env_rhs sp b.bind_ty b.bind_expr in
    (* Drive the pattern from the RHS type, exactly as the match path drives
       arms from the scrutinee type.  A record pattern needs this to know the
       record's full field list — without it, it synthesizes a CLOSED record
       from just the fields it names and `let { code: c } = p` fails to unify
       against a wider `p`.  The [unify] below is then a no-op for records and
       unchanged for every other pattern shape. *)
    let bindings, pat_ty = infer_pattern ~expected:rhs_ty env_rhs b.bind_pat in
    unify env_rhs ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    (* Record the binding type in type_map so LSP hover over `let x = …` shows
       the RHS type rather than the enclosing block's return type. *)
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    (match b.bind_pat with
     | Ast.PatVar name -> Hashtbl.replace env.type_map name.span (repr rhs_ty)
     | _ -> ());
    (* Generalise the binding if it's a simple variable — let-polymorphism.
       Use env.level (not env.level - 1) as the generalization threshold: only
       TVars created inside env_rhs (level env.level+1) that did NOT escape into
       outer types via occurs-check lowering are quantified.  Lambda-bound TVars
       created at env_rhs.level stay at that level (no outer reference lowers
       them) and are correctly quantified; function-call result TVars that are
       linked to outer-scope TVars get lowered to env.level and are not
       quantified. *)
    (* Vault handles are the ML [ref []] case: `let t = Vault.new("t")` is an
       application, and generalizing its element type would let each use pick a
       different one.  Skipped when the binding is annotated — writing the type
       out is the explicit opt-out.  See [demote_vault_handle_vars]. *)
    if b.bind_ty = None then demote_vault_handle_vars rhs_ty;
    let gen_binding bnd = match bnd with
      | (name, Mono t) -> (name, generalize env.level t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_binding bindings
      | _            -> bindings
    in
    (* Propagate linearity: if bind_lin is Linear/Affine (written as
       `linear let x = ...` or `affine let x = ...`), override the
       normal binding and register the variable as linear/affine.
       If bind_lin is Unrestricted but the RHS type is an always-linear type
       constructor, auto-promote the binding to Linear.
       Otherwise, propagate linearity from the RHS expression type. *)
    let auto_lin =
      match b.bind_lin with
      | Ast.Unrestricted ->
        let rty = repr rhs_ty in
        (match rty with
         (* L8: a `linear`/`affine` RHS type — e.g. a call to
            `fn mk() : linear Res` — propagates its linearity to the plain
            `let h = mk()` binding, so the return-position qualifier is not
            merely decorative.  EXCLUDE channels: a `TLin`-wrapped `TChan`
            (session endpoint) has its own tracking (offer_conts / affine param
            / End-drop create-and-drop leniency) and was Unrestricted here
            before — promoting it to strict-linear would regress that. *)
         | TLin (lin, inner) when lin <> Ast.Unrestricted
             && (match repr inner with TChan _ -> false | _ -> true) -> lin
         | TCon (name, _) ->
           if resolves_always_linear name env then Ast.Linear else Ast.Unrestricted
         | _ -> Ast.Unrestricted)
      | lin -> lin
    in
    let env' = match auto_lin with
      | Ast.Unrestricted ->
        bind_pattern_bindings b.bind_expr bindings' env
      | lin ->
        (* For linear/affine bindings, extract the underlying type from Poly schemes
           too — phantom type params cause gen_binding to generalize, but the binding
           is still a single concrete value that must be consumed exactly once. *)
        List.fold_left (fun acc_env (bname, sch) ->
            let t = match sch with
              | Mono t | Poly (_, _, t) -> t
            in
            bind_linear bname lin t acc_env
          ) env bindings'
    in
    (* Mark a simple, unrestricted `let name = expr` binding as a genuine
       plain VALUE (see [plain_let_names]) — this is the ONLY site that adds
       to it, so it's a precise, narrow, positively-identified signal (as
       opposed to [fn_arities]'s broader "not a known function" absence,
       which the [Ast.EApp] handler's zero-arg noncallable check used to
       lean on for this and proved unsafe: a bulk `import Mod` re-binds
       every imported name via [bind_var] too, which — by design (see the
       comment above [bind_var]) — clears any [fn_arities] entry for that
       name as part of ordinary shadow discipline, so a large multi-file
       program whose modules cross-import a same-module zero-arg fn made
       EVERY later reference to it look "not a known function").  Only a
       true `let x = e` (single-variable pattern, non-linear) is marked —
       destructuring patterns, lambda/fn params, and match arms are left
       alone (narrower scope, no false positives there either way).

       Critically, ALSO exclude an RHS that is itself a lambda literal
       (`Ast.ELam`, i.e. `let g = fn ... -> body`).  A ZERO-param lambda
       checked under plain inference (no expected-type context — see the
       [Ast.ELam] arm of [infer_expr]) collapses to its body's result type
       exactly like a top-level zero-arg `fn`, via the identical
       [List.fold_right ... [] body_ty = body_ty] convention — it only
       gets a real `Unit -> T` [TArrow] when CHECKED against one (the
       [Ast.ELam] arm of [check_expr]).  So `let g = fn -> println("b")`
       then `g()` (test/native/unit_callback_zero_arg.march) is completely
       legitimate, ordinary code whose RHS produces the very same
       "collapsed non-arrow type" shape as the bug this check targets —
       type alone truly cannot tell them apart here, but the AST shape of
       the RHS can: a fresh lambda LITERAL is never a "disguised alias of
       something else", it always means exactly what it says. *)
    let env' =
      match b.bind_pat, auto_lin, b.bind_expr with
      | Ast.PatVar _, Ast.Unrestricted, Ast.ELam _ ->
        env'
      | Ast.PatVar name, Ast.Unrestricted, _ ->
        { env' with plain_let_names = StringSet.add name.txt env'.plain_let_names }
      | _ -> env'
    in
    (* F5 path-dependent OFFER refinement: if this let destructures a
       `Chan.offer` result — a 2-tuple whose 2nd component is a channel whose
       session ref was registered in [offer_conts] — link the label variable
       (1st tuple component) to that channel's ref + branch map, so a later
       `match <label>` can refine the channel per arm.  Detected purely from
       the (repr'd) RHS type + the tuple-of-vars pattern shape, so it fires for
       both the `Chan.offer(x)` and `Mod.offer`-normalized call spellings. *)
    let env' =
      match b.bind_pat, repr rhs_ty with
      | Ast.PatTuple ([Ast.PatVar lbl; Ast.PatVar _chan], _),
        TTuple [_; chan_ty] ->
        (match repr chan_ty with
         | TLin (_, TChan r) | TChan r ->
           (match List.find_opt (fun (r', _) -> r' == r) !(env.offer_conts) with
            | Some (r', branches) ->
              { env' with offer_labels = (lbl.txt, (r', branches)) :: env'.offer_labels }
            | None -> env')
         | _ -> env')
      | _ -> env'
    in
    let result_ty = infer_block env' rest in
    (* After the rest of the block has run, verify that any linear let
       bindings introduced here were consumed (used exactly once). *)
    (match auto_lin with
     | Ast.Unrestricted -> ()
     | _lin ->
       let linear_names = List.map fst bindings' in
       check_linear_all_consumed env' ~scope_span:sp linear_names);
    (* Session-specific must-close accounting (F7 hole a): a channel binding
       whose session state is `End` MUST be closed — dropping it leaks the
       endpoint.  This is NARROWER than full linear consumption on purpose: a
       freshly-created channel still at a Send/Recv/Choose/Offer state that is
       never driven stays legal (the accept corpus deliberately creates-and-
       drops such endpoints, e.g. t42/t44), matching the documented scope
       (mid-protocol drop is the out-of-scope F6, only `End`-drop is caught).
       A channel that reaches `End` and IS passed to `Chan.close` counts as
       used (its EVar fires [record_use]); only a dropped `End` channel — never
       referenced after the binding — is flagged. *)
    List.iter (fun (n, sch) ->
        let bty = match sch with Mono t -> t | Poly (_, _, t) -> t in
        let at_end = match repr bty with
          | TLin (_, TChan r) | TChan r ->
            (match unfold_srec !r with SEnd -> true | _ -> false)
          | _ -> false
        in
        if at_end then
          match List.find_opt (fun le -> le.le_name = n) env'.lin with
          | Some le when not !(le.le_used) ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Session channel `%s` reached `End` but was never closed.\n\
                  A channel at `End` must be passed to `Chan.close` — dropping \
                  it leaks the endpoint." n)
          | _ -> ()
      ) bindings';
    result_ty
  (* Local named recursive function: fn go(params) : ret_ty do body end *)
  | Ast.ELetFn (name, params, ret_ann, body, sp) :: rest ->
    (* Introduce a fresh type for the function, check recursively *)
    let fn_ty = fresh_var env.level in
    let env_with_self = bind_var name.txt (Mono fn_ty) env in
    let param_tys, env_inner = bind_lam_params env_with_self params in
    (* Record each param's inferred type in the type_map at its name span.
       check_fn does this for top-level DFn params (line ~3706), but ELetFn
       goes through bind_lam_params which uses dummy_span and skips this.
       Without it, lower.ml's ty_of_span(p.param_name.span) returns TVar "_"
       for every ELetFn param, collapsing all params to a single unknown type
       that breaks monomorphization of inner functions (e.g. Map.from_list's
       inner `go` getting TVar "_" instead of TVar "_17776" / "_17775"). *)
    List.iter2 (fun (p : Ast.param) pty ->
        Hashtbl.replace env.type_map p.param_name.span (repr pty)
      ) params param_tys;
    let body_ty = infer_block env_inner [body] in
    (* Track whether the return-annotation unify (below) already reported a
       mismatch, so the later self-type/arrow-type reconciliation does not
       rediscover and DOUBLE-REPORT the identical conflict once it flows
       through the self-reference `fn_ty` (finding 13).  We compare the
       diagnostic count before/after rather than a boolean, so a genuinely
       distinct error from the self-reference (which grows the count on the
       arrow unify but NOT here) is still surfaced. *)
    let errs_before_ret = List.length env.errors.March_errors.Errors.diagnostics in
    let ret_ty  = match ret_ann with
      | None ->
        (* Same Vault return-position value restriction as the top-level `fn`
           path — a local `fn t() do Vault.open("x") end` is a handle factory
           too.  See [demote_vault_handle_vars]. *)
        demote_vault_handle_vars body_ty; body_ty
      | Some ann ->
        let tvars = ref [] in
        let expected = surface_ty env ~tvars ann in
        unify env ~span:sp ~reason:None body_ty expected;
        expected
    in
    let ret_annot_reported =
      List.length env.errors.March_errors.Errors.diagnostics > errs_before_ret
    in
    let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
    if ret_annot_reported then
      (* The return-annotation unify already reported this mismatch; run the
         arrow reconciliation for its type-linking side effects only, routing
         any (duplicate) report to a scratch context that we discard. *)
      unify { env with errors = March_errors.Errors.create () }
        ~span:sp ~reason:None fn_ty arrow_ty
    else
      unify env ~span:sp ~reason:None fn_ty arrow_ty;
    let gen_ty = generalize (env.level - 1) arrow_ty in
    let env' = bind_var name.txt gen_ty env in
    (* Register this local fn's arity in [fn_arities] (mirrors the top-level
       `DFn` registration — see the [env_rec] comment above [check_fn]) so
       the [arity_error] wrong-arg-count check in [Ast.EApp]'s handler also
       covers direct calls of a local `fn ... end` binding, not just a
       top-level `fn` decl — e.g. `fn helper(a, b) do ... end; helper(1)`
       inside a block now reports the same "expects 2 arguments" diagnostic
       a top-level `helper` would.  (This is NOT needed for the zero-arg
       "calling a non-function value" check just above — that one uses
       [plain_let_names], which a local `fn ... end` binding never enters,
       so `helper()`/a sibling local fn calling `helper()` already
       typechecks regardless of this registration.)  [bind_var] just above
       already cleared any stale entry under this name (shadow semantics),
       so this is a plain (re-)add, not a merge. *)
    let env' =
      { env' with fn_arities =
          StrMap.add name.txt (List.length params, name.span) env'.fn_arities } in
    infer_block env' rest
  | e :: rest ->
    ignore (infer_expr env e);
    infer_block env rest

(** Bind lambda parameters into the environment, returning (types, env). *)
and bind_lam_params env params =
  List.fold_right
    (fun p (tys, env) ->
       let t = fresh_var env.level in
       let env' = bind_lam_param env Ast.dummy_span p (Some t) in
       (t :: tys, env'))
    params ([], env)

and bind_lam_param env _sp (p : Ast.param) ann_ty =
  let t = match p.param_ty, ann_ty with
    | Some ann, expected ->
      let tvars = ref [] in
      let ann_t = surface_ty env ~tvars ann in
      (* RECONCILE the annotation with the type the caller expects this
         parameter to have (F5 residual, 2026-07-27).  [bind_lam_params] mints a
         fresh var per parameter, builds the lambda's ARROW type from those vars
         and passes each one here; [check_expr]'s lambda-peel passes the arrow
         component of the expected type.  Before this unify, an ANNOTATED
         parameter simply ignored that type: the body was checked against the
         annotation while the arrow — and therefore every call site — kept the
         unrelated variable.  So a lambda (or a named `fn` nested in a function
         body, which routes here too) had its parameter annotations checked
         against NOTHING, and an argument flowing into an annotated parameter
         reached neither the [Chan.*] operation arms nor [unify]'s `TChan`
         laundering guard — letting an unrefined `Chan.offer` continuation be
         washed clean by `fn (c : Chan(R, P)) -> ...`.  The top-level [check_fn]
         `FPNamed` loop never had this gap, which is why only the inner forms
         leaked. *)
      (match expected with
       | Some t0 ->
         unify env ~span:p.param_name.Ast.span
           ~reason:(Some (RAnnotation p.param_name.Ast.span)) t0 ann_t
       | None -> ());
      ann_t
    | None, Some t -> t
    | None, None   -> fresh_var env.level
  in
  let effective_lin = match p.param_lin with
    | Ast.Unrestricted ->
      (match repr t with
       | TCon (name, _) when resolves_always_linear name env -> Ast.Linear
       (* A parameter whose resolved type is a linear/affine wrapper — e.g. a
          session channel `ch : Chan(Client, Echo)` resolving to
          `TLin(Linear, TChan …)` — is tracked as AFFINE so a re-read of the
          endpoint is caught (F7 hole b) while a never-driven endpoint stays
          legal (create-and-drop leniency; see the matching note in [check_fn]'s
          parameter loop).  The old code only recognized `always_linear` [TCon]s
          here, so such a parameter slipped past the use-tracker entirely; a
          let-bound channel was already tracked via [bind_pattern_bindings]. *)
       | TLin (lin, _) when lin <> Ast.Unrestricted -> Ast.Affine
       | _ -> Ast.Unrestricted)
    | lin -> lin
  in
  (* Track the linear parameter at its INNER (unwrapped) type, matching how
     [bind_pattern_bindings] registers linear let-bindings. *)
  let bind_ty = match repr t with TLin (_, inner) -> inner | _ -> t in
  match effective_lin with
  | Ast.Unrestricted ->
    let env1 = bind_var p.param_name.txt (Mono t) env in
    bind_linear_field_sentinels p.param_name.txt t env1
  | lin -> bind_linear p.param_name.txt lin bind_ty env

(* =================================================================
   §6  Declaration checking
   ================================================================= *)

(** Emit unused-variable warnings for fn params not referenced in the body.
    The wildcard [_] and names starting with [_] are silently ignored. *)
let warn_unused_params env (params : Ast.fn_param list) (body : Ast.expr) _fn_span =
  let used = free_vars_expr [] body in
  (* A capability value is a runtime-erased grant token: it is normal, and
     often correct, for it never to be mentioned in the body. Warning on it
     made the right code noisy and pushed users to spell every grant `_cap`.

     Deliberately NOT [Cap_surface_ty.caps_in_ty], which recurses into ANY
     type structure and returns non-empty as soon as a [Cap(...)] appears
     ANYWHERE inside it — so `List(Cap(IO.Console))`, `(Int, Cap(IO.Console))`,
     and `Cap(IO.Console) -> ()` all satisfied it, exempting a genuinely dead
     list/tuple/closure parameter from the warning it should still get: the
     "never referenced, and that's fine" rationale only holds for a value
     that *is* a capability, not one that merely contains one. This checks
     the DIRECT form only — the same recognition [caps_in_ty] itself uses at
     its own top match arm (`cap_surface_ty.ml`'s `TyCon (con, [arg]) when
     con.txt = "Cap"`) — so `fn main(cap : Cap(IO.Console))` and every plain
     `Cap(X)` parameter stay exempt, while a capability merely nested inside
     a container or arrow type does not. *)
  let is_cap_ty = function
    | Some (Ast.TyCon (con, [_])) -> con.txt = "Cap"
    | Some _ | None -> false
  in
  let check_name name span =
    if name <> "_" && not (String.length name > 0 && name.[0] = '_')
       && not (List.mem name used) then
      Err.warning_with_code_and_fix env.errors ~span ~code:"unused_binding"
        ~fix:(Err.FReplace { span; text = "_" ^ name })
        (Printf.sprintf "Unused variable `%s`.\n\
                         Use `_` to mark intentionally unused params." name)
  in
  List.iter (fun fp ->
    match fp with
    | Ast.FPNamed p ->
      if not (is_cap_ty p.param_ty) then check_name p.param_name.txt p.param_name.span
    | Ast.FPPat (Ast.PatVar n) -> check_name n.txt n.span
    | Ast.FPPat _ -> ()
    | Ast.FPDefault (p, _) ->
      if not (is_cap_ty p.param_ty) then check_name p.param_name.txt p.param_name.span
  ) params

(** Check a function definition.

    Strategy:
    1. Enter a fresh generalization level.
    2. Add a monomorphic self-reference (allows recursion).
    3. Bind each parameter into the env.
    4. Infer/check the body.
    5. Leave level and generalize the function type.
    6. Return the scheme so the caller can update the env. *)
let check_fn env (def : Ast.fn_def) fn_span : scheme =
  (* [current_decl] is a single shared ref, not a stack — save/restore around
     the whole body so it never leaks into whatever gets checked next once
     this fn's body is done (nested fns, a later top-level decl, etc.). This
     mirrors [with_no_caller]'s save/restore pattern but restores the PREVIOUS
     caller rather than blanking to "", since [check_fn] can itself be nested
     (a closure body containing a locally-defined named fn). *)
  let saved_caller = !(env.current_decl) in
  env.current_decl := qualify_ref_name env.current_module def.fn_name.txt;
  Fun.protect ~finally:(fun () -> env.current_decl := saved_caller) (fun () ->
  let env'    = enter_level env in
  (* Captured BEFORE the self-bind below (which unconditionally clears any
     [local_fns] entry for this name, per [bind_var]'s shadowing discipline)
     so we know whether to restore it afterward — this fn is only a genuine
     top-level Call-recording target if it already was one; an impl method
     (checked via [check_fn] too, but never registered in [local_fns] to
     begin with) must not spuriously become one. *)
  let was_local_fn = StrMap.mem def.fn_name.txt env'.local_fns in
  (* Self-reference for recursion — a fresh var that will get unified
     with the actual type as the body is checked.
     For default-arg wrappers (multiple DFn with the same name), the full-arity
     version is processed first.  When a wrapper is checked, the function name
     is already bound to a concrete type in the environment.  In that case we
     reuse the existing binding so the wrapper body can call the full function
     at a different arity without a self-type conflict. *)
  let self_ty, env_rec, placeholder =
    match StrMap.find_opt def.fn_name.txt env'.vars with
    | Some (Mono (TVar _ as pv)) ->
      (* Pass-1 forward-reference placeholder.  It is a bare [Mono (TVar _)]:
         either still Unbound, or already Linked because an EARLIER caller in
         this module unified its use site against it.  Either way it is the
         placeholder (a genuine concrete binding — e.g. a default-arg wrapper's
         full-arity sibling — is always [Mono (TArrow ..)] or [Poly _], never a
         bare [Mono (TVar _)]).  Use a fresh self-ref for recursion and keep a
         handle on the placeholder so we can reconcile it with the inferred type
         after generalization (see below). *)
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt (Mono sv) env', Some pv)
    | Some existing_sch ->
      (* Already concretely typed (e.g. full-arity default-arg fn) — keep it
         so the wrapper body resolves calls at the full arity correctly.
         Still create a self_ty for the unify at the end of check_fn. *)
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt existing_sch env', None)
    | None ->
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt (Mono sv) env', None)
  in
  (* The self-bind above cleared any fn_arities/local_fns entry for this name
     (shadow semantics — correct when a NESTED fn shadows a top-level fn of
     different arity).  Re-register the CURRENT def's own arity so recursive
     calls in the body are still arity-checked, against the right arity
     either way — and re-register [local_fns] so a recursive call to this
     same top-level fn is still recorded as a genuine Call reference (see
     [bind_var]'s [local_fns] shadowing-discipline comment; [check_fn] is
     only ever called for actual top-level/impl-method fns, never a nested
     local `fn`, so it is always correct to restore this membership here). *)
  let env_rec =
    let arity = match def.fn_clauses with
      | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
    { env_rec with fn_arities =
        StrMap.add def.fn_name.txt (arity, def.fn_name.span) env_rec.fn_arities;
      local_fns =
        if was_local_fn then StrMap.add def.fn_name.txt () env_rec.local_fns
        else env_rec.local_fns } in

  let sch = match def.fn_clauses with
    | [] ->
      Err.error env.errors ~span:fn_span
        (Printf.sprintf "Function `%s` has no clauses." def.fn_name.txt);
      Mono TError

    | [clause] ->
      (* Shared type variable mapping for this function's signature.
         Using a single ref across all param annotations, return type, and
         class constraints ensures that the same type variable name (e.g. `a`)
         in `fn foo(x : a, y : a) : a when Eq(a)` maps to the same
         unification variable everywhere. *)
      let fn_tvars = ref [] in

      (* Pre-register explicit bound type variables from fn_bounds and build
         bound constraints.  Bounds like [s : ConnState] pre-register `s` in
         fn_tvars so that param annotations referencing `s` (e.g.
         Handle(Conn, s)) share the same unification variable. *)
      let bound_constraints =
        List.filter_map (fun ((var_name : Ast.name), bound_surface) ->
            let tv = match List.assoc_opt var_name.txt !fn_tvars with
              | Some t -> t
              | None ->
                let fv = fresh_var env'.level in
                fn_tvars := (var_name.txt, fv) :: !fn_tvars;
                fv
            in
            match bound_surface with
            | Ast.TyNat _ -> Some (CTNatBound tv)
            | Ast.TyCon (n, []) ->
              if n.txt = "Nat" then Some (CTNatBound tv)
              else if StrMap.mem n.txt env.interfaces
              then Some (CInterface (n.txt, tv))
              else begin
                (* Validate that the ADT exists in scope *)
                match lookup_type n.txt env with
                | None ->
                  Err.error env.errors ~span:n.span
                    (Printf.sprintf
                       "Bound `%s` is not a known ADT or interface name."
                       n.txt);
                  None
                | Some _ -> Some (CADTBound (n.txt, tv))
              end
            | _ ->
              Err.error env.errors ~span:var_name.span
                (Printf.sprintf
                   "Bound `%s` on type variable `%s` must be an ADT name, \
                    interface name, or `Nat`."
                   (Ast.show_ty bound_surface) var_name.txt);
              None
          ) def.fn_bounds
      in

      (* Bind parameters *)
      let param_tys, body_env =
        List.fold_right (fun fp (tys, env) ->
            match fp with
            | Ast.FPNamed p ->
              let t = match p.param_ty with
                | Some ann -> surface_ty env' ~tvars:fn_tvars ann
                | None -> fresh_var env'.level
              in
              let effective_lin = match p.param_lin with
                | Ast.Unrestricted ->
                  (match repr t with
                   | TCon (tname, _) when resolves_always_linear tname env' -> Ast.Linear
                   (* A session-channel parameter (`ch : Chan(Role, Proto)`)
                      resolves to a [TLin] wrapper.  Track it as AFFINE so a
                      RE-READ of the endpoint inside the body is caught (F7 hole
                      b) while a channel parameter merely declared and never
                      driven stays legal — the create-and-drop leniency the
                      session corpus already relies on for endpoints (a param at
                      a mid-protocol state is not required to be consumed; only
                      the `End`-drop of a LET-bound channel is an error, handled
                      in [infer_block]).  Full linear consumption of endpoints is
                      the stricter F6 direction, deliberately out of scope. *)
                   | TLin (lin, _) when lin <> Ast.Unrestricted -> Ast.Affine
                   | _ -> Ast.Unrestricted)
                | lin -> lin
              in
              (* Track the linear param at its inner (unwrapped) type. *)
              let bind_ty = match repr t with TLin (_, inner) -> inner | _ -> t in
              let env' = match effective_lin with
                | Ast.Unrestricted ->
                  (* Register per-field linear sentinels for a record-typed param
                     with `linear`/`affine` fields (L3): mirrors [bind_lam_param]
                     so a top-level `fn f(p : Rec)` tracks `p.field` double-use as
                     an ERROR, not a warning — previously only let-bound and lambda
                     params registered these, so fn-param field linearity was
                     silently warning-only. *)
                  let env1 = bind_var p.param_name.txt (Mono t) env in
                  bind_linear_field_sentinels p.param_name.txt t env1
                | lin              -> bind_linear p.param_name.txt lin bind_ty env
              in
              (t :: tys, env')
            | Ast.FPPat (Ast.PatVar name) ->
              (* Single variable pattern — trivially named; bind it directly *)
              let t = fresh_var env'.level in
              let env' = bind_var name.txt (Mono t) env in
              (t :: tys, env')
            | Ast.FPPat pat ->
              (* Complex pattern parameter: should have been desugared into a
                 match, but handle gracefully by binding inferred pattern vars *)
              let t = fresh_var env'.level in
              let pat_bindings, _ = infer_pattern env pat in
              let env' = bind_vars pat_bindings env in
              (t :: tys, env')
            | Ast.FPDefault (p, _) ->
              (* Default should have been expanded by desugar; handle gracefully *)
              let t = match p.param_ty with
                | Some ann -> surface_ty env' ~tvars:fn_tvars ann
                | None -> fresh_var env'.level
              in
              let env' = bind_var p.param_name.txt (Mono t) env in
              (t :: tys, env')
          ) clause.fc_params ([], env_rec)
      in

      (* Proof-cap mint gate context: the body is inside a PUBLIC fn iff fn_vis
         is Public. Set on body_env so the `mint_cap` EApp special-case can
         require declaring-module + public provenance. Lambdas inherit this
         (they don't call check_fn); nested named fns/modules reset it via their
         own check_fn. *)
      let body_env = { body_env with cur_fn_public = (def.fn_vis = Ast.Public) } in

      (* Record each named parameter's type in the type map *)
      List.iter2 (fun fp pty ->
          match fp with
          | Ast.FPNamed p ->
            Hashtbl.replace env.type_map p.param_name.span (repr pty)
          | Ast.FPPat (Ast.PatVar name) ->
            Hashtbl.replace env.type_map name.span (repr pty)
          | Ast.FPPat _ -> ()
          | Ast.FPDefault (p, _) ->
            Hashtbl.replace env.type_map p.param_name.span (repr pty)
        ) clause.fc_params param_tys;

      (* Process the when-clause: distinguish class constraints from guards.
         A class constraint looks like `ECon("Eq", [EVar "a"])` where "Eq"
         is a known interface name.  Such guards are treated as type-class
         constraints added to the function scheme rather than checked as Bool
         expressions. *)
      let class_constraints =
        match clause.fc_guard with
        | None -> []
        | Some (Ast.ECon (iface_name, args, _))
          when StrMap.mem iface_name.txt env.interfaces ->
          (* It's a class constraint: Eq(a), Ord(b), etc. *)
          List.filter_map (fun arg ->
              match arg with
              | Ast.EVar v ->
                let ty = match List.assoc_opt v.txt !fn_tvars with
                  | Some t -> t
                  | None   ->
                    (* Not a signature type-variable name (e.g. the annotation
                       type-var `a` in `fn f(x : a) when Eq(a)`, or a bound
                       `[s : I]`).  In `fn same(a, b) when Eq(a)` the `a` names
                       a VALUE PARAMETER whose type is a fresh var bound in
                       body_env — resolve to THAT type so the constraint rides
                       on the parameter's own type variable and is re-checked at
                       call sites (finding 15).  Only if the name is neither a
                       signature type var nor a bound value do we fall back to a
                       fresh, registered placeholder. *)
                    (match lookup_var v.txt body_env with
                     | Some (Mono t) -> t
                     | Some (Poly (_, _, t)) -> t
                     | None ->
                       let fv = fresh_var env'.level in
                       fn_tvars := (v.txt, fv) :: !fn_tvars;
                       fv)
                in
                Some (CInterface (iface_name.txt, ty))
              | _ -> None
            ) args
        | Some g ->
          (* Normal expression guard: type-check it as Bool *)
          check_expr body_env g t_bool
            ~reason:(Some (RBuiltin "Function guards must be Bool."));
          []
      in

      (* Check or infer the body, sharing fn_tvars with the return annotation *)
      let body_ty = match def.fn_ret_ty with
        | Some ann ->
          let expected = surface_ty env' ~tvars:fn_tvars ann in
          check_expr body_env clause.fc_body expected
            ~reason:(Some (RFnReturn (def.fn_name.txt, fn_span)));
          expected
        | None ->
          let t = infer_expr body_env clause.fc_body in
          (* A fn that RETURNS a Vault handle without saying what the table
             holds must not hand every caller a freshly-instantiated element
             type — that is the same erasure as an unannotated `let`, moved
             one call frame out.  Annotating the return (`: Vault(v)`) is the
             deliberate opt-out and is what the handle factories
             (Vault.new/open/whereis, Config's table getters) use.  See
             [demote_vault_handle_vars]. *)
          demote_vault_handle_vars t;
          t
      in

      (* Check linear params were all consumed *)
      let param_names = List.filter_map (function
          | Ast.FPNamed p -> Some p.param_name.txt
          | Ast.FPDefault (p, _) -> Some p.param_name.txt
          | Ast.FPPat _ -> None) clause.fc_params in
      check_linear_all_consumed body_env ~scope_span:fn_span param_names;

      (* Warn about unrestricted params not referenced in the body *)
      warn_unused_params env clause.fc_params clause.fc_body fn_span;

      (* Proof-cap forge value restriction across fn boundaries: if this fn's
         body is (or launders) a [cap_narrow] result (e.g.
         `fn mk(cap) do cap_narrow(cap) end`), its cap-producer return var must
         NOT generalize — otherwise each cross-module call instantiates a fresh,
         untagged copy that escapes the unify hook and can be forged into a proof
         cap.  Demote the return type's vars to level 0 so [generalize] below
         keeps them monomorphic, and re-tag so the shared var is caught when a
         call binds it to a proof cap. *)
      (* Record a cap-narrow-factory fn: its body launders a [cap_narrow] result,
         so a cross-module call to it (which resolves to the prebound scheme,
         invisible to the unify hook's per-var tag) must taint its result at the
         call site — see the [EApp] handling of a factory name. *)
      if ty_has_tagged_cap_producer env body_ty then begin
        Hashtbl.replace env.cap_narrow_factory_fns def.fn_name.txt fn_span;
        if env.current_module <> "" then
          Hashtbl.replace env.cap_narrow_factory_fns
            (env.current_module ^ "." ^ def.fn_name.txt) fn_span
      end;

      let fn_ty =
        List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty
      in
      (* Record the function's overall type at the function name's span *)
      Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty);
      (* Unify self_ty so recursive calls get the correct type *)
      unify env' ~span:fn_span self_ty fn_ty;

      (* Generalize; attach bound constraints and any when-clause class constraints *)
      let all_constraints = bound_constraints @ class_constraints in
      let base_sch = generalize env.level fn_ty in
      (match all_constraints with
       | [] -> base_sch
       | cs  ->
         match base_sch with
         | Poly (ids, existing_cs, t) -> Poly (ids, cs @ existing_cs, t)
         | Mono t ->
           (* Collect ids of quantified vars referenced in constraints so they
              are properly generalized even when not referenced in the type *)
           let constraint_tv = function
             | CInterface (_, tv) | CADTBound (_, tv) | CTNatBound tv -> Some tv
             | CNum tv | COrd tv -> Some tv
           in
           let extra_ids = List.filter_map (fun c ->
               match constraint_tv c with
               | None -> None
               | Some tv ->
                 (match repr tv with
                  | TVar r ->
                    (match !r with
                     | Unbound (id, l) when l > env.level -> Some id
                     | _ -> None)
                  | _ -> None)
             ) cs in
           Poly (extra_ids, cs, t))

    | _ ->
      (* Multi-clause fn — desugar pass should have eliminated these *)
      Err.error env.errors ~span:fn_span
        (Printf.sprintf
           "Internal error: fn `%s` has multiple clauses after desugaring."
           def.fn_name.txt);
      Mono TError
  in

  (* Reconcile the pass-1 forward-reference placeholder with the inferred type.
     During pass 1 every module function is pre-bound to a single placeholder
     var so forward references resolve.  A caller checked BEFORE this definition
     unified its use site against that placeholder; if we now simply discard it,
     the caller can be left with an unresolved free type var (e.g.
     `List('_NNNN)`).  That miscompiles: a polymorphic list is RC-handled
     differently than its concrete instance, causing a use-after-free.

     We only reconcile when this function's inferred scheme is MONOMORPHIC
     (`Mono _`, no type parameters).  A monomorphic function has exactly one
     type, so unifying every forward use site with it is always sound.  A
     POLYMORPHIC function must keep its per-use instantiation (a caller may use
     it at several types — see the "forward-ref pfn called at two element
     types" test), so we leave the placeholder alone in that case. *)
  (match placeholder, sch with
   | Some pv, Mono t ->
     unify env' ~span:fn_span ~reason:None pv t
   | _ -> ());

  ignore (leave_level env');
  sch)

(** [impl_matches_ty impl_ty target_ty] returns true if [target_ty] could be
    satisfied by an implementation typed as [impl_ty].  Free unification
    variables in [impl_ty] (from parameterised impls like [List(a)]) are
    treated as wildcards that match any type. *)
let rec impl_matches_ty impl_ty target_ty =
  match repr impl_ty, repr target_ty with
  | TVar _, _ -> true  (* polymorphic impl var — matches anything *)
  | _, TVar _ -> false (* target still unresolved — cannot confirm *)
  | TCon (n1, as1), TCon (n2, as2)
    when n1 = n2 && List.length as1 = List.length as2 ->
    List.for_all2 impl_matches_ty as1 as2
  | TArrow (a1, b1), TArrow (a2, b2) ->
    impl_matches_ty a1 a2 && impl_matches_ty b1 b2
  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.for_all2 impl_matches_ty ts1 ts2
  | TRecord f1, TRecord f2
    when List.map fst f1 = List.map fst f2 ->
    List.for_all2 (fun (_, t1) (_, t2) -> impl_matches_ty t1 t2) f1 f2
  | TLin (_, t1), TLin (_, t2) -> impl_matches_ty t1 t2
  | TError, _ | _, TError -> true
  | a, b -> a = b

(** Pre-register an interface implementation's SHAPE (pass 1) so that
    CInterface constraints from modules checked earlier in the unit can be
    discharged against impls declared in modules checked later.  Conversion
    is lenient — [impl_matches_ty] only compares constructor names and
    shapes, so unresolved type names are embedded as-is rather than resolved
    against the (still incomplete) pass-1 environment.  The full registration
    with properly instantiated types still happens in check_decl's DImpl
    case; duplicates are harmless because discharge uses List.exists. *)
(* Do two impl HEAD types OVERLAP — i.e. is there a substitution of their free
   type variables making them equal?  This is the coherence-overlap test
   (T-ImplCoherent), covering BOTH Stage 1 (exact / alpha-equal heads: two
   `impl Speak(Dog)`, or `impl Show(List(a))` × 2) AND Stage 2 (parametric:
   `impl Show(List(a))` vs `impl Show(List(Int))` overlap with `a ↦ Int`).
   Non-overlapping: `Dog`/`Cat`, `List(a)`/`Option(a)` (different head ctor),
   `Pair(a,a)`/`Pair(Int,Bool)` (`a` can't be both).

   PURE and non-mutating: it never touches the stored heads' [TVar] refs — a
   local id-keyed substitution stands in for unification, so a var bound once
   must match consistently on every later occurrence (that is what rejects the
   `Pair(a,a)` row).  Both heads carry DISTINCT fresh var ids (from
   [lenient_ty]/[surface_ty]), so their bindings never collide. *)
let types_overlap (a0 : ty) (b0 : ty) : bool =
  let subst : (int, ty) Hashtbl.t = Hashtbl.create 8 in
  let rec go t1 t2 =
    let t1 = repr t1 and t2 = repr t2 in
    match t1, t2 with
    | TVar r1, _ ->
      (match !r1 with
       | Unbound (id, _) ->
         (match Hashtbl.find_opt subst id with
          | Some bound -> go bound t2
          | None -> Hashtbl.replace subst id t2; true)
       | Link _ -> go t1 t2)
    | _, TVar r2 ->
      (match !r2 with
       | Unbound (id, _) ->
         (match Hashtbl.find_opt subst id with
          | Some bound -> go t1 bound
          | None -> Hashtbl.replace subst id t1; true)
       | Link _ -> go t1 t2)
    | TCon (n1, a1), TCon (n2, a2) ->
      n1 = n2 && List.length a1 = List.length a2 && List.for_all2 go a1 a2
    | TTuple l1, TTuple l2 ->
      List.length l1 = List.length l2 && List.for_all2 go l1 l2
    | TRecord f1, TRecord f2 ->
      List.length f1 = List.length f2
      && List.for_all2 (fun (n1, x1) (n2, x2) -> n1 = n2 && go x1 x2) f1 f2
    | TArrow (p1, r1), TArrow (p2, r2) -> go p1 p2 && go r1 r2
    | TLin (_, x1), TLin (_, x2) -> go x1 x2
    | TLin (_, x1), _ -> go x1 t2
    | _, TLin (_, x2) -> go t1 x2
    | TNat n1, TNat n2 -> n1 = n2
    | TError, _ | _, TError -> false
    | _ -> t1 = t2
  in go a0 b0

let register_impl_shape ?(decl_module="") env (idef : Ast.impl_def) =
  let module M = Map.Make (String) in
  let tvars = ref M.empty in
  let rec lenient_ty (t : Ast.ty) : ty =
    match t with
    | Ast.TyVar n ->
      (match M.find_opt n.txt !tvars with
       | Some v -> v
       | None ->
         let v = fresh_var 1 in
         tvars := M.add n.txt v !tvars;
         v)
    | Ast.TyCon (n, args)  ->
      let args' = List.map lenient_ty args in
      (* Expand a record type name to its structural form, exactly as
         [surface_ty] (and so [check_decl]'s DImpl handler) does. Without this,
         an impl on a record type is registered here under the NOMINAL name
         (`TCon "T"`) while the dispatch site sees the structural record
         (`TRecord [...]`); they don't unify, so `impl Iface(Record)` is invisible
         to a call in a module checked before the impl's own module — which is
         exactly the cross-module / multi-file case. Variant types are unaffected
         (they are not in [env.records] and stay nominal) — except a variant
         whose bare name collides with a record from another module, which
         [name_is_variant] guards against exactly as [surface_ty] does. *)
      (match StrMap.find_opt n.txt env.records with
       | Some (params, field_decls)
         when List.length params = List.length args'
              && not (name_is_variant env n.txt) ->
         let saved = !tvars in
         List.iter2 (fun pname arg -> tvars := M.add pname arg !tvars) params args';
         let flds = List.map (fun (fn, fty) -> (fn, lenient_ty fty)) field_decls in
         tvars := saved;
         TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
       | _ -> TCon (n.txt, args'))
    | Ast.TyArrow (a, b)   -> TArrow (lenient_ty a, lenient_ty b)
    | Ast.TyTuple ts       -> TTuple (List.map lenient_ty ts)
    | Ast.TyRecord fs      ->
      TRecord (List.map (fun ((n : Ast.name), ft) -> (n.txt, lenient_ty ft)) fs)
    | Ast.TyLinear (l, t') -> TLin (l, lenient_ty t')
    | Ast.TyNat _ | Ast.TyNatOp _ | Ast.TyChan _ -> fresh_var 1
    | Ast.TyRefine (base, _, _) -> lenient_ty base
  in
  let inst_ty = lenient_ty idef.impl_ty in
  let key = idef.impl_iface.txt in
  let sp  = idef.impl_iface.span in
  let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
  (* Resolve the head type's DECLARING MODULE (verified 2026-07-20):
     - qualified head "Mod.T" → the "Mod" prefix (the type's real module,
       regardless of where the impl is written — keeps orphan impls colliding);
     - bare head "T" declared locally by the impl's own module → decl_module
       ([decl_module ^ ".T"] is registered in env.types by the pass-1 prebind);
     - otherwise None → conservative (treated as overlapping, no false negative,
       e.g. two modules both implementing the SAME imported type). *)
  let head_type_module =
    match idef.impl_ty with
    | Ast.TyCon (n, _) ->
      let name = n.txt in
      (match String.rindex_opt name '.' with
       | Some i -> Some (String.sub name 0 i)
       | None ->
         if decl_module <> ""
            && StrMap.mem (decl_module ^ "." ^ name) env.types
         then Some decl_module
         else None)
    | _ -> None
  in
  let modules_distinct m1 m2 =
    match m1, m2 with Some a, Some b -> a <> b | _ -> false in
  (* Declaring-module coherence relaxation (FQN dispatch, all stages landed):
     two same-short-name types declared in DIFFERENT modules are genuinely
     distinct, so each may implement the SAME interface without overlapping.
     This is sound for EVERY interface — not just the type-dispatched built-ins
     Eq/Ord/Show/Hash — because Stage 3 taught the native backend to give each
     colliding type a globally-unique runtime tag, force uniform Boxed repr,
     mangle each impl to a module-qualified symbol, and route ambiguous call
     sites through a generated runtime tag-switch dispatch fn; the interpreter
     qualifies iface_method_tbl the same way. A general interface therefore
     dispatches on the value's real type in BOTH backends (verified
     `from-A`/`from-B` — accept/t89, test/imports/speak_collision_native).

     This relaxation is now UNCONDITIONAL — no residual ctor-sharing carve-out.
     Even when the two colliding types ALSO share a constructor NAME (a "double
     collision", e.g. both `type Thing = Shared | …`), the constructor module-
     qualified identity plan resolves ctor identity upstream: native
     ECon/pattern-match qualify a colliding type's ctor key with its declaring
     module, and the interpreter qualifies the VCon tag the same way, so the
     backends and interpreter route each module's `Shared` to its OWN impl body
     (was the interim Task-6b `ctor_sets_disjoint` stopgap, removed at this
     plan's flag-day; verified accept/t90,
     test/imports/speak_double_collision_native). See
     specs/plans/2026-07-20-fqn-impl-dispatch-identity.md. *)
  (* Coherence (T-ImplCoherent), Stage 1 exact overlap: at most ONE impl per
     (interface, type-head).  A second impl whose head is alpha-equal to an
     already-registered one is a compile error — this is what makes the two
     backends agree by construction (interp's last-write-wins `impl_tbl` vs the
     monomorphizer's list order would otherwise run DIFFERENT method bodies).
     [register_impl_shape] runs per-impl across the Pass-1 folds and may see the
     SAME impl twice (nested/entry re-registration), so distinguish by SPAN:
     same span = re-registration (no-op); different span = genuine duplicate. *)
  (* A DIFFERENT-span USER entry whose head OVERLAPS this one is a coherence
     violation (exact duplicate OR parametric overlap); our own entry (same
     span, from a Pass-1 re-registration) is not.  Built-in impls live in
     [env.impls] too (seeded with [dummy_span] by [base_env]) but are SKIPPED
     here: a user impl on a primitive (`impl Eq(Int)`) coexisting with the
     built-in is the pre-existing behavior and is heavily used by the interface-
     machinery test fixtures — rejecting it (DECIDE-1) is deferred as a follow-on
     so this ships without that disruptive change. *)
  match List.find_opt
          (fun (t, s, m_old) ->
             s <> sp && s <> Ast.dummy_span
             && types_overlap t inst_ty
             && not (modules_distinct m_old head_type_module))
          lst with
  | Some (_, prev_sp, _) ->
    Err.error env.errors ~span:sp
      (Printf.sprintf
         "Overlapping implementation: `impl %s(%s)` conflicts with the \
          implementation at %s:%d:%d — their heads overlap.\n\
          A type may implement an interface at most once (coherence). If you \
          meant a different behavior, wrap the type in a newtype and implement \
          the interface on that."
         key (pp_ty inst_ty)
         prev_sp.Ast.file prev_sp.Ast.start_line prev_sp.Ast.start_col);
    env   (* keep the first impl — deterministic *)
  | None ->
    (* No conflict. Register (unless our own same-span entry is already present
       from a Pass-1 re-registration, in which case this is a no-op). *)
    if List.exists (fun (t, s, _) -> s = sp && types_overlap t inst_ty) lst
    then env
    else { env with impls =
             StrMap.add key ((inst_ty, sp, head_type_module) :: lst) env.impls }

(** Pre-register a forward-reference interface declared in [prefix]: its name
    (qualified `Mod.Iface` AND bare `Iface`) plus each method (qualified and
    bare) with an interface-constrained scheme, so a sibling module's `impl` /
    method call resolves even when that module is checked before the interface's
    own module. Shared by the pre-passes of [check_module_core] and
    [check_module_with_env] so the two cannot diverge — a divergence here (the
    incremental pass omitted interfaces entirely) previously hid sibling
    interfaces from the LSP's per-file analysis ("Unknown interface"). *)
let prebind_interface_decl ~prefix (idef : Ast.interface_def) (e : env) : env =
  let iface_qname = prefix ^ "." ^ idef.iface_name.txt in
  let iface_sname = idef.iface_name.txt in
  let e1 = if StrMap.mem iface_qname e.interfaces then e
           else { e with interfaces = StrMap.add iface_qname idef e.interfaces } in
  let e1 = if StrMap.mem iface_sname e1.interfaces then e1
           else { e1 with interfaces = StrMap.add iface_sname idef e1.interfaces } in
  if StrMap.mem (prefix ^ "." ^ idef.iface_name.txt ^ "." ^
                 (match idef.iface_methods with m :: _ -> m.md_name.txt | [] -> ""))
       e.vars
  then e1  (* already bound — skip to avoid duplicate work *)
  else
  List.fold_left (fun e (m : Ast.method_decl) ->
    let full_qualified = prefix ^ "." ^ idef.iface_name.txt ^ "." ^ m.md_name.txt in
    let iface_qualified = idef.iface_name.txt ^ "." ^ m.md_name.txt in
    if StrMap.mem full_qualified e.vars then e
    else begin
      let tmp_errors = Err.create () in
      let tmp_env = { e with errors = tmp_errors } in
      let a = fresh_var 1 in
      let tvars = ref [(idef.iface_param.txt, a)] in
      (* Prebinding an interface method's own signature has no enclosing
         function either — see [with_no_caller]. [tmp_env] shares [refs] and
         [current_decl] with [e] (record-copy, not clone of the ref cells),
         so blanking through [tmp_env] is equally visible to the [TyCon]
         hook. *)
      let ty = with_no_caller tmp_env (fun () -> surface_ty tmp_env ~tvars m.md_ty) in
      let a_id = match a with
        | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
        | _ -> 0
      in
      let base_sch = generalize 0 ty in
      let sch = match base_sch with
        | Poly (ids, cs, t) -> Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
        | Mono t -> Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
      in
      (* Both dotted keys bound here ([full_qualified] = "Mod.Iface.method",
         [iface_qualified] = "Iface.method") are genuine function bindings —
         an interface method, never a [DLet] value — so both are also
         registered in [qual_fn_names]. This is a THIRD source of qualified
         function names (alongside [Ast.DMod] exports and registry [ExFn]
         entries): call syntax like `Show.show(x)` normalizes to
         [Ast.EVar "Show.show"] (the [Ast.EApp (Ast.EField (Ast.ECon ...))]
         rule) and resolves straight out of [env.vars] here, bypassing both
         of the other two sources entirely — so without this, the [EVar]
         reference-recording hook's [qual_fn_names] gate would wrongly treat
         every qualified interface-method call as non-function-backed and
         silently drop it. See [qual_fn_names]'s doc comment. *)
      let e1 = { e with vars = StrMap.add full_qualified sch e.vars;
                        qual_fn_names = StrMap.add full_qualified () e.qual_fn_names } in
      let e1 = if StrMap.mem iface_qualified e1.vars then e1
               else { e1 with vars = StrMap.add iface_qualified sch e1.vars;
                              qual_fn_names = StrMap.add iface_qualified () e1.qual_fn_names } in
      if StrMap.mem m.md_name.txt e1.vars then e1
      else { e1 with vars = StrMap.add m.md_name.txt sch e1.vars }
    end
  ) e1 idef.iface_methods

(** Discharge all pending Num/Ord/CInterface constraints accumulated during
    inference.  Called at each declaration boundary (DFn, DLet) to verify
    that constrained type variables were unified with a compatible type. *)
let discharge_constraints env span =
  (* Linearity is transparent to constraint discharge: `linear T` satisfies
     exactly the constraints `T` satisfies.  impl_matches_ty already strips
     TLin (its TLin/TLin arm) and unification coerces TLin transparently —
     but the discharge arms below match on the repr'd type directly, so
     without this strip an expression-position `linear Int` (a linear
     record-field access, or a `linear Int`-returning call, used in
     arithmetic) falls to the catch-all and rejects with "`linear Int` does
     not implement Num" before the linearity tracker ever runs (slice-7
     finding L2). *)
  let rec strip_lin t = match repr t with
    | TLin (_, inner) -> strip_lin inner
    | t' -> t'
  in
  (* Dedup CInterface constraints: when the same concrete type is constrained
     on the same interface multiple times (e.g., 10 calls to Storage.get on
     the same storage variable), we only need to check the impl once.
     Uses pp_ty on the repr'd type as a canonical string key. *)
  let seen = Hashtbl.create 16 in
  List.iter (fun c ->
      let dominated = match c with
        | CInterface (name, t) ->
          let rt = strip_lin t in
          (match rt with
           | TVar _ -> false  (* polymorphic -- will be skipped anyway *)
           | _ ->
             let key = name ^ ":" ^ pp_ty rt in
             if Hashtbl.mem seen key then true
             else (Hashtbl.add seen key (); false))
        | _ -> false
      in
      if not dominated then
      match c with
      | CNum t | COrd t ->
        let ty   = strip_lin t in
        let kind = match c with CNum _ -> "Num" | COrd _ -> "Ord" | _ -> assert false in
        (match ty with
         | TCon ("Int",   []) | TCon ("Float", []) -> ()   (* Num + Ord *)
         | TCon ("String",[]) ->
           (match c with
            | COrd _ -> ()   (* String is Ord *)
            | _ ->
              Err.error env.errors ~span
                "String does not implement Num (only Int and Float do).")
         | TVar r ->
           (match c with
            | CNum _ -> r := Link (TCon ("Int", []))  (* numeric defaulting: unresolved Num → Int *)
            | _ -> ())  (* COrd unresolved — leave polymorphic *)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "`%s` does not implement %s." (pp_ty ty) kind))
      | CInterface (iface_name, t) ->
        let ty = strip_lin t in
        (match ty with
         | TVar _ -> ()   (* Still polymorphic — cannot check yet *)
         | _ ->
           let satisfied = match StrMap.find_opt iface_name env.impls with
             | None -> false
             | Some impl_tys -> List.exists (fun (impl_ty, _, _) ->
                 impl_matches_ty (repr impl_ty) ty) impl_tys
           in
           if not satisfied then begin
             (* Record field auto-satisfy: discharge a single-method
                accessor-shaped interface against an anonymous TRecord when
                the record has a field whose name and type match the method.
                Eligibility: anonymous TRecord, exactly one interface method,
                method shape `a -> T` (a = iface param), matching field. *)
             let auto_satisfied =
               match ty with
               | TRecord flds ->
                 (match StrMap.find_opt iface_name env.interfaces with
                  | Some iface when List.length iface.iface_methods = 1 ->
                    let m = List.hd iface.iface_methods in
                    (match m.md_ty with
                     | Ast.TyArrow (Ast.TyVar param, ret_surface)
                       when param.txt = iface.iface_param.txt ->
                       let tvars = ref [(iface.iface_param.txt, ty)] in
                       let ret_ty = surface_ty env ~tvars ret_surface in
                       (match List.assoc_opt m.md_name.txt flds with
                        | Some fld_ty -> impl_matches_ty (repr fld_ty) ret_ty
                        | None -> false)
                     | _ -> false)
                  | _ -> false)
               | _ -> false
             in
             if not auto_satisfied then
               Err.error env.errors ~span
                 (Printf.sprintf
                    "`%s` does not implement interface `%s`.\n\
                     Add `impl %s(%s) do ... end` to provide an implementation."
                    (pp_ty ty) iface_name iface_name (pp_ty ty))
           end)
      | CADTBound (adt_name, t) ->
        let ty = repr t in
        (match ty with
         | TVar _ -> ()  (* still polymorphic — cannot check yet *)
         | TCon (ctor_name, []) ->
           (* Check ctor_name is a constructor whose parent type matches adt_name.
              ci_type may be module-qualified (e.g. "Conn.ConnState"), so we accept
              an exact match OR a ".<adt_name>" suffix match. *)
           let matches_adt ci_type =
             ci_type = adt_name ||
             let n = String.length adt_name in
             let len = String.length ci_type in
             len > n && ci_type.[len - n - 1] = '.' &&
             String.sub ci_type (len - n) n = adt_name
           in
           let found = match StrMap.find_opt ctor_name env.ctors with
             | None -> false
             | Some cis -> List.exists (fun ci -> matches_adt ci.ci_type) cis
           in
           if not found then
             Err.error env.errors ~span
               (Printf.sprintf "`%s` is not a variant of `%s`."
                  ctor_name adt_name)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "Expected a variant of `%s`, got `%s`."
                adt_name (pp_ty ty)))
      | CTNatBound t ->
        let ty = repr t in
        (match ty with
         | TVar _            -> ()  (* still polymorphic *)
         | TNat _            -> ()  (* exact TNat — OK *)
         | TNatOp _          -> ()  (* type-level nat arithmetic — OK *)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "Expected a type-level natural number (Nat), got `%s`."
                (pp_ty ty)))
    ) !(env.pending_constraints);
  env.pending_constraints := []

(** Structural equality after repr — works for concrete types; may give
    false-positive wrong-type hints when two distinct unresolved TVars
    happen not to be linked yet (acceptable in actor handler context). *)
let types_equal a b = repr a = repr b

(** Build hint strings explaining why an actor handler body has the wrong type.
    state_ty and inferred_ty should both be repr-ed before calling. *)
let actor_handler_hints state_ty inferred_ty =
  match inferred_ty with
  | TRecord inferred_fields ->
    (match state_ty with
     | TRecord [] ->
       ["the state has no fields — return an empty record {}"]
     | TRecord state_fields ->
       let state_names    = List.map fst state_fields in
       let inferred_names = List.map fst inferred_fields in
       let extra   = List.filter (fun n -> not (List.mem n state_names)) inferred_names in
       let missing = List.filter (fun n -> not (List.mem n inferred_names)) state_names in
       let wrong_type = List.filter_map (fun (fname, st) ->
           match List.assoc_opt fname inferred_fields with
           | Some it when not (types_equal st it) ->
             Some (Printf.sprintf
               "field '%s' has type %s but state declares it as %s"
               fname (pp_ty (repr it)) (pp_ty (repr st)))
           | _ -> None) state_fields in
       List.map (fun n -> Printf.sprintf
         "field '%s' is not part of the actor state \
          — remove it, or add it to the state declaration" n) extra
       @ List.map (fun n -> Printf.sprintf
         "field '%s' is missing from the returned record" n) missing
       @ wrong_type
     | _ -> [])
  | t ->
    [Printf.sprintf "handler must return a record matching the state, not %s" (pp_ty t)]

(** Validate the island module protocol.

    If a module defines types named [State] and [Msg] and at least one of
    [init], [update], or [render], we treat it as an island module and check
    that the required functions are present:

    - [update(State, Msg) -> State]   — required
    - [render(State) -> IOList]        — required
    - [create(Props) -> State]          — recommended (warning if missing)
    - [merge(State, State) -> State]   — optional, no warning *)
let validate_island_protocol (env : env) (mod_name : Ast.name) (decls : Ast.decl list) =
  (* Inspect the module's OWN declarations, not the accumulated environment:
     inner_env inherits every bare type/fn name exported by previously
     checked sibling modules, so once any island module defined State/Msg,
     every later module with a fn named update/render/create was falsely
     flagged as an incomplete island. *)
  let has_type n =
    List.exists (function
      | Ast.DType (_, tn, _, _, _) | Ast.DAlwaysLinearType (_, tn, _, _, _) -> tn.Ast.txt = n
      | _ -> false) decls
  in
  let has_fn n =
    List.exists (function
      | Ast.DFn (def, _) -> def.fn_name.txt = n
      | _ -> false) decls
  in
  if not (has_type "State" && has_type "Msg") then ()
  else begin
    let has_update = has_fn "update" in
    let has_render = has_fn "render" in
    let has_create = has_fn "create" in
    (* Only validate if at least one protocol function exists — avoids
       false positives on modules that coincidentally have State/Msg types. *)
    if has_update || has_render || has_create then begin
      if not has_update then
        Err.error env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` is missing required function `update`.\n  \
              Island modules with State and Msg types must define:\n  \
              \  fn update(state : State, msg : Msg) : State"
             mod_name.txt);
      if not has_render then
        Err.error env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` is missing required function `render`.\n  \
              Island modules with State and Msg types must define:\n  \
              \  fn render(state : State) : IOList"
             mod_name.txt);
      if not has_create then
        Err.warning env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` does not define `create`.\n  \
              Consider adding: fn create(props : Props) : State"
             mod_name.txt)
    end
  end

(* =================================================================
   The capability / [needs] checker — now lib/typecheck/typecheck_caps.ml.
   [include] for the same reason as the modules above; six of these names are
   declared in typecheck.mli.
   ================================================================= *)
include Typecheck_caps
(* =================================================================
   §7  Top-level declaration dispatch and import warnings

   [check_decl] — the per-declaration dispatcher the module entry point folds
   over — and [warn_unused_imports].  The session-type projection this header
   used to name moved to lib/typecheck/typecheck_session.ml on 2026-08-27
   (see the include just below); the header was renumbered by Phase 6's task
   6.9 and had been describing the wrong band ever since.
   ================================================================= *)

(* =================================================================
   Session-type projection and duality — now
   lib/typecheck/typecheck_session.ml.  [include], not [open], for the same
   reason as the modules above.
   ================================================================= *)
include Typecheck_session

(* =================================================================
   Declaration dependency ordering — now
   lib/typecheck/typecheck_reorder.ml.  [include], not [open]: only
   [include] re-exports these names as part of [Typecheck]'s own surface,
   and consumers reach them through [let open] and through aliases
   (Tc., TC., T.) that no grep can see.
   ================================================================= *)
include Typecheck_reorder

(* =================================================================
   The module-level capability checkers and the panic-surface tables —
   now lib/typecheck/typecheck_modcaps.ml.  [include], not [open]: only
   [include] re-exports these names as part of [Typecheck]'s own surface,
   and it ALIASES [proof_based_panic_surface] rather than copying it, which
   is what keeps bin/main.ml's writes and check_no_panic_module's read
   pointing at one cell.
   ================================================================= *)
include Typecheck_modcaps

let rec check_decl env (d : Ast.decl) : env =
  match d with
  | Ast.DFn (def, sp) ->
    let sch = check_fn env def sp in
    discharge_constraints env sp;
    let was_local_fn = StrMap.mem def.fn_name.txt env.local_fns in
    let env = bind_var def.fn_name.txt sch env in
    (* bind_var cleared this fn's own fn_arities/local_fns entries (shadow
       semantics); restore them so later same-module calls keep the
       direct-call arity check AND keep being recorded as genuine Call
       references (see [bind_var]'s [local_fns] shadowing-discipline
       comment — this is [check_fn]'s post-hoc mirror site: the module's
       pass-1 prebind put this fn's name in [local_fns] before [check_fn]
       ran; without restoring it here, EVERY same-module call to a fn
       checked later than its own definition would silently stop being
       recorded, since [bind_var]'s unconditional removal has nothing left
       to re-add it). *)
    let env =
      let arity = match def.fn_clauses with
        | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
      { env with fn_arities =
          StrMap.add def.fn_name.txt (arity, def.fn_name.span) env.fn_arities;
        local_fns =
          if was_local_fn then StrMap.add def.fn_name.txt () env.local_fns
          else env.local_fns } in
    (* Reconcile the QUALIFIED prebind (`Mod.fn`) with the fn's REAL body-checked
       scheme.  desugar's [qualify_module_refs] (lib/desugar/desugar.ml) rewrites
       every intra-nested-module reference to the qualified form (e.g. `App.id`),
       and [prebind_mod_members] seeds that name with either a fresh
       `Mono (fresh_var 1)` placeholder (UNANNOTATED fn — [prebind_fn_scheme]
       returned None) or a scheme built purely from annotation SYNTAX
       (ANNOTATED fn — never unified against the body, so `fn launder(x:a):b do x`
       keeps a decoupled `a -> b` that erases through every call).  Either way the
       prebind is NOT the validated scheme; a sibling fn resolving the qualified
       name gets a decoupled `?a -> ?b` that ERASES the type of anything laundered
       through it (a general type-soundness hole; the proof-cap forge was one
       exploitation).  Bind the qualified name to [sch] — the scheme [check_fn]
       actually validated against the body — UNCONDITIONALLY (both the placeholder
       and the un-body-validated-annotation cases).  This is codegen-safe: mono/TIR
       key on the per-span [type_map] types, not this env scheme, and the full
       [llvm_ir_validity_gate] (CRDT/distributed fixtures) is clean under it.
       Forward references — where a caller earlier in the module already pinned the
       placeholder to its own decoupled use — are handled UPSTREAM by
       [dependency_order_dfn_run]: its [deps_of]/[local_of] now sees the qualified
       reference (`App.id`) as a dependency on the local `id`, so `id` is checked
       (and this rebind runs) BEFORE any caller.

       [prebind_mod_members] seeds a fn's qualified key under TWO prefixes,
       reconcile BOTH so no qualified key retains a decoupled scheme:
       - [cap_qual_prefix] — the accumulated dotted path of ENCLOSING nested
         modules ("" at the entry module, then the nested names, entry mod
         stripped): matches [prebind_mod_members]'s [prefix] recursion (:8626).
       - [current_module] — the CURRENT module's own name.  At the ENTRY module,
         [check_module_core] seeds the entry's own top-level fns under
         `EntryMod.fn` (`prebind_mod_members m.mod_name.txt`, :8732) while
         [cap_qual_prefix] is still "", so the entry-self-qualified key
         (`Main.id`, or a nested sibling's `T.id` reference to the entry `T`)
         would otherwise never be reconciled — a memory-unsafe erasure when the
         explicit `EntryMod.id` form is written.  (For a nested module both
         prefixes may coincide or nest; deduping by the [<>""] guards + a set
         avoids a redundant rebind, and rebinding the same real [sch] twice is
         harmless anyway.) *)
    let reconcile_qkey env prefix =
      if prefix = "" then env
      else
        let qname = prefix ^ "." ^ def.fn_name.txt in
        (match StrMap.find_opt qname env.vars with
         | Some _ -> bind_var qname sch env
         | None   -> env)
    in
    let env = reconcile_qkey env env.cap_qual_prefix in
    let env =
      if env.current_module <> env.cap_qual_prefix
      then reconcile_qkey env env.current_module else env
    in
    env

  | Ast.DLet (_vis, b, sp) ->
    let env' = enter_level env in
    (* A top-level `let` binding's RHS has no enclosing function — see
       [with_no_caller]. Without this, any Call/Ctor reference in the RHS
       gets misattributed to whatever [DFn] [check_decl] happened to check
       last in module order (or a stale caller from an earlier file in a
       multi-file compilation). *)
    let rhs_ty = with_no_caller env' (fun () -> infer_expr env' b.bind_expr) in
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    let bindings, pat_ty = infer_pattern ~expected:rhs_ty env' b.bind_pat in
    unify env' ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    discharge_constraints env sp;
    ignore (leave_level env');
    (* Same Vault value restriction as the block-[let] path above. *)
    if b.bind_ty = None then demote_vault_handle_vars rhs_ty;
    (* Generalise simple variable bindings at module level *)
    let gen_bnd bnd = match bnd with
      | (name, Mono t) -> (name, generalize env.level t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_bnd bindings
      | _            -> bindings
    in
    bind_vars bindings' env

  | Ast.DType (_vis, name, params, typedef, _sp) ->
    let is_canonical_dist_link_down_reason =
      let nullary name (v : Ast.variant) =
        v.var_name.txt = name && v.var_args = []
      in
      let crash_with_string (v : Ast.variant) =
        v.var_name.txt = "Crash"
        && match v.var_args with
           | [Ast.TyCon (arg, [])] -> arg.txt = "String"
           | _ -> false
      in
      env.current_module = "DistLink"
      && env.enclosing_package = "DistLink"
      && name.txt = "DownReason"
      && params = []
      && match typedef with
         | Ast.TDVariant [normal; killed; crash; node_down] ->
           nullary "Normal" normal
           && nullary "Killed" killed
           && crash_with_string crash
           && nullary "NodeDown" node_down
         | _ -> false
    in
    if env.current_module = env.enclosing_package
       && (name.txt = "Down" || name.txt = "DownReason")
       && not is_canonical_dist_link_down_reason then begin
      Err.error env.errors ~span:name.span
        (Printf.sprintf
           "type `%s` is reserved by the local-monitor runtime ABI and cannot be redeclared"
           name.txt);
      env
    end else
    let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
    (match typedef with
     | Ast.TDVariant variants ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       (* Check for duplicate constructor names within this type.
          Track (name, span) pairs so we can point at both occurrences. *)
       let _ = List.fold_left (fun seen (v : Ast.variant) ->
           match List.assoc_opt v.var_name.txt seen with
           | Some first_sp ->
             Err.error env.errors ~span:v.var_name.span
               (Printf.sprintf
                  "type `%s` defines constructor `%s` more than once\n\
                   Constructors are the named cases of a variant type — \
                   each must have a unique name within the type.\n\
                   First defined at %s:%d:%d"
                  name.txt v.var_name.txt
                  first_sp.Ast.file first_sp.Ast.start_line first_sp.Ast.start_col);
             seen
           | None -> (v.var_name.txt, v.var_name.span) :: seen
         ) [] variants in
       List.fold_left (fun e (v : Ast.variant) ->
           let ci = { ci_type    = name.txt
                    ; ci_params  = param_names
                    ; ci_arg_tys = v.var_args
                    ; ci_module  = env.current_module
                    ; ci_vis     = v.var_vis
                    ; ci_is_actor_msg = false } in
           (* Register both bare "CtorName" and qualified "TypeName.CtorName"
              so users can write either form for disambiguation. *)
           let qual_key = name.txt ^ "." ^ v.var_name.txt in
           { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
         ) env1 variants
     | Ast.TDRecord fields ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       (* Check for duplicate field names within this record.
          Track (name, span) pairs so we can point at both occurrences. *)
       let _ = List.fold_left (fun seen (f : Ast.field) ->
           match List.assoc_opt f.fld_name.txt seen with
           | Some first_sp ->
             Err.error env.errors ~span:f.fld_name.span
               (Printf.sprintf
                  "record `%s` defines field `%s` more than once\n\
                   First defined at %s:%d:%d"
                  name.txt f.fld_name.txt
                  first_sp.Ast.file first_sp.Ast.start_line first_sp.Ast.start_col);
             seen
           | None -> (f.fld_name.txt, f.fld_name.span) :: seen
         ) [] fields in
       (* Propagate field-level linearity annotations into the surface type so
          that expand_record returns TLin wrappers for linear fields.  This
          enables both the EField check and let-binding linearity propagation
          (bind_vars_with_linearity) to see the linear field constraint. *)
       let field_pairs = List.map (fun (f : Ast.field) ->
           let fty = match f.fld_lin with
             | Ast.Unrestricted -> f.fld_ty
             | lin -> Ast.TyLinear (lin, f.fld_ty)
           in
           (f.fld_name.txt, fty)
         ) fields in
       register_record_name ~name:name.txt (List.map fst field_pairs);
       { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
     | Ast.TDAlias _ -> env1)

  | Ast.DActor (_vis, name, actor, _sp) ->
    (* Build the state record type from field declarations *)
    let state_ty =
      let tvars = ref [] in
      let flds = List.map (fun (f : Ast.field) ->
          (f.fld_name.txt, surface_ty env ~tvars f.fld_ty)) actor.actor_state in
      TRecord (List.sort (fun (a,_)(b,_) -> String.compare a b) flds)
    in
    (* Check for duplicate handler names — two `on Msg(...)` arms for the
       same message name is always a programmer error. *)
    let _ = List.fold_left (fun seen (h : Ast.actor_handler) ->
        if List.mem h.ah_msg.txt seen then
          Err.error env.errors ~span:h.ah_msg.span
            (Printf.sprintf
               "actor '%s' defines handler '%s' more than once;\
                \nremove the duplicate or rename one of them"
               name.txt h.ah_msg.txt);
        h.ah_msg.txt :: seen
      ) [] actor.actor_handlers in
    (* Register actor name as a zero-arg constructor (so spawn(ActorName) typechecks)
       and message constructors so ECon lookups succeed.
       Include ALL params — annotated and unannotated — so constructor arity
       is always correct.  Unannotated params are given a unique TyVar placeholder
       (named "$p<i>_<Msg>") that resolves to a fresh unification variable during
       instantiation; this ensures `send(pid, Msg(x))` typechecks correctly even
       when the handler omits a type annotation. *)
    let env_with_actor_ctor = { env with ctors =
      add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = env.current_module; ci_vis = Ast.Public;
                          ci_is_actor_msg = false }
        env.ctors } in
    let env_with_ctors = List.fold_left (fun acc_env (h : Ast.actor_handler) ->
        let arg_tys = List.mapi (fun i (p : Ast.param) ->
            match p.param_ty with
            | Some ty -> ty
            | None ->
              (* Unique name per (handler, position) so each instantiation
                 gets an independent fresh variable. *)
              Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                          span = p.param_name.span }
          ) h.ah_params in
        let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                   ci_arg_tys = arg_tys; ci_module = env.current_module; ci_vis = Ast.Public;
                   ci_is_actor_msg = true } in
        { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
      ) env_with_actor_ctor actor.actor_handlers in
    (* Check init expression — must return the state record type.  Neither
       the init expr nor any handler body below is checked via [check_fn], so
       there is no enclosing function — see [with_no_caller]. *)
    with_no_caller env_with_ctors (fun () ->
      check_expr env_with_ctors actor.actor_init state_ty
        ~reason:(Some (RBuiltin "actor init must return the initial state record")));
    (* Check handlers with state and message params in scope *)
    List.iter (fun (h : Ast.actor_handler) ->
        let handler_env = bind_var "state" (Mono state_ty) env_with_ctors in
        (* Shadow the global `self` builtin (registered as plain Int — see
           its definition above) with this actor's own Pid[state_ty], the
           same type `spawn(name)` produces for this actor elsewhere.  Only
           valid inside a handler body, exactly like `state` above. *)
        let handler_env =
          bind_var "self" (Mono (TCon ("Pid", [state_ty]))) handler_env in
        let handler_env =
          List.fold_left (fun e p ->
              bind_var p.Ast.param_name.txt
                (Mono (match p.param_ty with
                   | Some ann -> let tvars = ref [] in surface_ty env ~tvars ann
                   | None     -> fresh_var env.level))
                e
            ) handler_env h.ah_params
        in
        (* Handler body must return the state record type — emit rich
           diagnostic. No enclosing function — see [with_no_caller]. *)
        let inferred = with_no_caller handler_env (fun () -> infer_expr handler_env h.ah_body) in
        let shadow_env = { handler_env with errors = Err.create () } in
        (* Note: pending_constraints and type_map are shared (shallow copy) —
           intentional; only error reporting is isolated. *)
        unify shadow_env ~span:h.ah_msg.span ~reason:None
          (repr inferred) (repr state_ty);
        if Err.has_errors shadow_env.errors then
          Err.report handler_env.errors
            { severity = Error;
              span = h.ah_msg.span;
              message = Printf.sprintf
                "handler '%s' in actor '%s' must return the state type\
                 \n  expected: %s\
                 \n  got:      %s"
                h.ah_msg.txt name.txt
                (pp_ty (repr state_ty)) (pp_ty (repr inferred));
              labels = [];
              notes = actor_handler_hints (repr state_ty) (repr inferred);
              code = None; fix = None }
      ) actor.actor_handlers;
    bind_var name.txt (Mono (TCon ("Pid", [state_ty]))) env_with_ctors

  | Ast.DMod (name, _vis, decls, _sp) ->
    (* Reset local_fns for this module's scope: a nested module's locally
       defined fn names shadow bulk imports inside it (see env.local_fns). *)
    let pre_env = List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) ->
          let arity = match def.fn_clauses with
            | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
          (* bind_var FIRST (it clears any shadowed fn_arities entry), then
             register this fn's own arity so the entry survives — see the
             fn_arities shadow-semantics comment on bind_var. *)
          let e = bind_var def.fn_name.txt (Mono (fresh_var (env.level + 1))) e in
          { e with local_fns = StrMap.add def.fn_name.txt () e.local_fns;
                   fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) e.fn_arities }
        | _ -> e
      ) { env with local_fns = StrMap.empty; current_module = name.txt;
          cap_qual_prefix =
            (if env.cap_qual_prefix = "" then name.txt
             else env.cap_qual_prefix ^ "." ^ name.txt) } decls in
    let inner_env = List.fold_left check_decl pre_env (reorder_decls decls) in
    (* Collect the names that are explicitly public within this module. *)
    let pub_set =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public -> Some def.fn_name.txt
        | Ast.DFn _ -> None
        | Ast.DLet (Ast.Public, b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | Ast.DLet _ -> None
        | Ast.DType (Ast.Public, n, _, _, _) -> Some n.txt
        | Ast.DType _ -> None
        | Ast.DAlwaysLinearType (Ast.Public, n, _, _, _) -> Some n.txt
        | Ast.DAlwaysLinearType _ -> None
        | Ast.DActor (Ast.Public, n, _, _) -> Some n.txt
        | Ast.DActor _ -> None
        | Ast.DMod (n, Ast.Public, _, _) -> Some n.txt
        | Ast.DMod _ -> None
        (* Interface declarations are always public — export interface name so that
           its methods (bound as "IfaceName.method" in inner_env) get exported
           as "ModName.IfaceName.method" into the outer scope. *)
        | Ast.DInterface (idef, _) -> Some idef.iface_name.txt
        | _ -> None
      ) decls
    in
    (* Private value/function members of this module (declared but not exported).
       Recorded in [env.local_mods] under the module's name so a same-file
       qualified reference to one (e.g. `A.secret` where `secret` is a `pfn`)
       is diagnosed as "private to module `A`" instead of the misleading
       "Unknown module `A`" (see [qualified_error_msg]). *)
    let priv_members =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Private -> Some def.fn_name.txt
        | Ast.DLet (Ast.Private, b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | _ -> None
      ) decls
    in
    (* Check conformance against any matching sig declaration (Phase 2) *)
    let opaque_types =
      match List.assoc_opt name.txt env.sigs with
      | None -> []
      | Some sdef ->
        (* Verify all sig_fns are present with matching types *)
        List.iter (fun ((fname : Ast.name), sig_ty) ->
            match StrMap.find_opt fname.txt inner_env.vars with
            | None ->
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not implement `%s` required by `sig %s`."
                   name.txt fname.txt name.txt)
            | Some sch ->
              (* Convert sig_ty to internal type and check unification via a
                 temporary error context so we can produce a clean error message. *)
              let tvars = ref [] in
              let expected = surface_ty inner_env ~tvars sig_ty in
              let actual = instantiate env.level inner_env sch in
              let tmp_errors = Err.create () in
              let tmp_env = { inner_env with errors = tmp_errors } in
              unify tmp_env ~span:fname.span expected actual;
              if Err.has_errors tmp_errors then
                Err.error env.errors ~span:fname.span
                  (Printf.sprintf
                     "Module `%s` implements `%s` with wrong type.\n  \
                      Expected: %s  (from sig %s)\n  \
                      Got:      %s"
                     name.txt fname.txt
                     (pp_ty (repr expected)) name.txt
                     (pp_ty (repr actual)))
          ) sdef.sig_fns;
        (* Verify all sig_types are declared in the module *)
        List.iter (fun ((tname : Ast.name), _params) ->
            if not (StrMap.mem tname.txt inner_env.types) then
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not declare type `%s` required by `sig %s`."
                   name.txt tname.txt name.txt)
          ) sdef.sig_types;
        (* Return the list of opaque type names for constructor hiding below *)
        List.map (fun ((tname : Ast.name), _) -> tname.txt) sdef.sig_types
    in
    (* Validate capability declarations for this module *)
    check_module_needs env name decls
      ~cap_qname_prefix:(if env.cap_qual_prefix = "" then name.txt
                         else env.cap_qual_prefix ^ "." ^ name.txt);
    (* Validate island module protocol if applicable *)
    validate_island_protocol env name decls;
    (* Expose only public names as "ModName.name" in the outer env.
       Also export sub-module keys: if "B" is in pub_set, export "B.f" as "A.B.f". *)
    let is_pub_key k =
      List.exists (fun n ->
        k = n ||
        (String.length k > String.length n + 1 &&
         String.sub k 0 (String.length n + 1) = n ^ ".")
      ) pub_set
    in
    (* Collect exported names from inner_env.vars.
       StrMap guarantees one entry per key so deduplication is not needed. *)
    let new_names = StrMap.fold (fun k sch acc ->
        if is_pub_key k
        then (name.txt ^ "." ^ k, sch) :: acc
        else acc
      ) inner_env.vars [] in
    (* Of the newly-exported qualified names, which denote a genuine function
       (as opposed to a plain [DLet] value/constant)?  A key [k] is
       function-backed either because it's one of THIS module's own [DFn]s
       (tracked bare in [inner_env.local_fns]) or because it is itself an
       already-qualified key re-exported from a nested public [DMod] (tracked
       in [inner_env.qual_fn_names], populated by that nested module's own
       pass through this same branch) — see [qual_fn_names]'s doc comment. *)
    let new_fn_quals = StrMap.fold (fun k _sch acc ->
        if is_pub_key k &&
           (StrMap.mem k inner_env.local_fns || StrMap.mem k inner_env.qual_fn_names)
        then StrMap.add (name.txt ^ "." ^ k) () acc
        else acc
      ) inner_env.vars StrMap.empty in
    (* Also export type names and constructors from public DMod into outer scope.
       Types defined in a module (e.g. IOList, Option) are referred to by their
       bare name throughout user code, not prefixed.
       Opaque types listed in the sig have their constructors hidden: only the
       type name is exported, not the constructors (encapsulation). *)
    let proof_cap_type_keys = List.map fst inner_env.proof_caps in
    let new_types = StrMap.filter (fun k _ ->
        List.mem k pub_set || List.mem k proof_cap_type_keys
      ) inner_env.types in
    let new_ctors = StrMap.filter_map (fun _k cis ->
        let filtered = List.filter (fun ci ->
          (* Hide constructors for opaque types declared in the sig *)
          not (List.mem ci.ci_type opaque_types) &&
          (* Export constructor only if its parent type is public AND
             the constructor itself is explicitly marked Public. *)
          List.mem ci.ci_type pub_set && ci.ci_vis = Ast.Public
        ) cis in
        match filtered with [] -> None | _ -> Some filtered
      ) inner_env.ctors in
    (* Also register qualified ctor keys "ModName.CtorName" so that the
       desugared form ECon("ModName.CtorName") can be resolved directly from
       env.ctors without going through Module_registry.  This is critical for
       REPL-defined modules which are never added to the global registry, and
       also makes qualified ctor lookup consistent for all modules. *)
    let qual_ctors = StrMap.fold (fun ctor_name cis acc ->
        StrMap.add (name.txt ^ "." ^ ctor_name) cis acc
      ) new_ctors StrMap.empty in
    (* Collect this module's declared capabilities for transitive enforcement *)
    let inner_needs = List.concat_map (function
        | Ast.DNeeds (caps, _) -> List.map (fun (p, _) -> cap_path_of_names p) caps
        | _ -> []) decls in
    (* Key those needs by the FULLY-QUALIFIED module path, the same one
       [check_module_needs] is given as [~cap_qname_prefix] just above and the
       same convention TIR attribution uses (lower.ml's [mod_prefix]) — the
       --cap-strict ceiling in bin/main.ml matches [module_caps] against that
       attribution by owner name.  Keying by the BARE name made every module
       nested two or more deep read as "uses X but does not declare needs X"
       even when it declared exactly X, because attribution named it
       `Outer.Inner` while this list said `Inner`.  At depth 1 the two spellings
       coincide (the entry module is unwrapped, so [cap_qual_prefix] is "" in
       its body), which is why the bug only showed from depth 2.

       The bare key is kept alongside it: Check 4 and [module_wide_caps] look
       up `use` paths AS WRITTEN, so a sibling imported by its short name must
       still resolve.  And [inner_env.module_caps] — not the outer env's — is
       carried outward, or entries recorded by modules nested inside this one
       (which is exactly where the mis-keyed ones lived) are dropped at this
       boundary and never reach the ceiling check at all. *)
    let cap_qname =
      if env.cap_qual_prefix = "" then name.txt
      else env.cap_qual_prefix ^ "." ^ name.txt
    in
    let module_caps' =
      let with_qual = (cap_qname, inner_needs) :: inner_env.module_caps in
      if cap_qname = name.txt then with_qual
      else (name.txt, inner_needs) :: with_qual
    in
    (* Also export record field layouts for public record types so that
       cross-module field access (e.g. conn.fd) works correctly.
       Export both the local name ("JobRow") and the fully-qualified name
       ("Conduit.JobRow") so that type annotations written with the module
       prefix also resolve to a structural TRecord instead of opaque TCon. *)
    let new_records = StrMap.fold (fun k v acc ->
        if List.mem k pub_set then
          StrMap.add (name.txt ^ "." ^ k) v (StrMap.add k v acc)
        else acc
      ) inner_env.records StrMap.empty in
    (* Validate capability invariants for this nested module if declared *)
    if inner_env.no_panic_mod then
      check_no_panic_module env.errors inner_env decls;
    if inner_env.pure_mod then
      check_pure_module env.errors inner_env decls;
    if inner_env.no_extern_mod then
      check_no_extern_module env.errors inner_env decls;
    if inner_env.deterministic_mod then
      check_deterministic_module env.errors inner_env decls;
    let env' = bind_vars new_names env in
    let no_panic_modules' =
      if inner_env.no_panic_mod then name.txt :: env'.no_panic_modules
      else env'.no_panic_modules
    in
    { env' with
      types   = StrMap.union (fun _k v _ -> Some v) new_types env'.types;
      ctors   = (let all_new = StrMap.union (fun _k a _ -> Some a) qual_ctors new_ctors in
                  StrMap.union (fun _k new_cis old_cis ->
                    (* Merge lists; new_cis are more local, so prepend them *)
                    let merged = List.fold_right (fun ci acc ->
                      if List.exists (fun c -> c.ci_type = ci.ci_type) acc then acc
                      else ci :: acc) new_cis old_cis in
                    Some merged) all_new env'.ctors);
      records = StrMap.union (fun _k v _ -> Some v) new_records env'.records;
      qual_fn_names = StrMap.union (fun _k a _ -> Some a) new_fn_quals env'.qual_fn_names;
      module_caps = module_caps';
      proof_caps = inner_env.proof_caps;
      always_linear_types = inner_env.always_linear_types;
      no_panic_modules = no_panic_modules';
      local_mods =
        (if priv_members = [] then env'.local_mods
         else StrMap.add name.txt priv_members env'.local_mods) }

  | Ast.DProtocol (name, pdef, sp) ->
    (* Register the protocol and validate structural well-formedness. *)
    if StrMap.mem name.txt env.protocols then
      Err.error env.errors ~span:sp
        (Printf.sprintf "Duplicate protocol definition `%s`." name.txt);
    if pdef.proto_steps = [] then
      Err.warning env.errors ~span:sp
        (Printf.sprintf "Protocol `%s` has no steps — it describes no communication."
           name.txt);
    (* Validate each step for structural correctness. [in_loop] tracks
       whether we're nested (directly, or via a `choose` branch) inside a
       `loop` block — `stop` is only meaningful there. *)
    let rec validate_step ~in_loop = function
      | Ast.ProtoMsg (sender, receiver, msg_ty) ->
        if sender.txt = receiver.txt then
          Err.error env.errors ~span:sender.span
            (Printf.sprintf
               "Protocol `%s`: participant `%s` cannot send a message to itself."
               name.txt sender.txt);
        let tvars = ref [] in
        ignore (surface_ty env ~tvars msg_ty)
      | Ast.ProtoLoop steps ->
        if steps = [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf "Protocol `%s`: a `loop` block must contain at least one step."
               name.txt);
        List.iter (validate_step ~in_loop:true) steps
      | Ast.ProtoChoice (participant, branches) ->
        if List.length branches < 2 then
          Err.error env.errors ~span:participant.span
            (Printf.sprintf
               "Protocol `%s`: `choice` by `%s` must have at least 2 branches."
               name.txt participant.txt);
        List.iter (fun (_, steps) -> List.iter (validate_step ~in_loop) steps) branches
      | Ast.ProtoStop stop_sp ->
        if not in_loop then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: `stop` outside of a `loop` has no effect — the \
                protocol already ends here if you just write nothing."
               name.txt)
    in
    List.iter (validate_step ~in_loop:false) pdef.proto_steps;
    (* A `loop` never exits (its projection is `Rec X. S[X]`), so any step that
       follows one at the same nesting level is unreachable. *)
    (* [tail] is what follows at every ENCLOSING level.  A `choose` branch's
       real continuation is its own steps FOLLOWED BY the post-`choose` tail
       (`project_steps`' `ProtoChoice` arm projects `rest_ty ()` into every
       branch), so a branch ending in a `loop` makes that projected tail
       unreachable just as surely as a written-out step would — walking each
       branch with `rest = []` and no tail missed exactly that case. *)
    let rec check_unreachable_after_loop ~tail steps =
      match steps with
      | Ast.ProtoLoop inner :: rest ->
        check_unreachable_after_loop ~tail:[] inner;
        if rest <> [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: the steps after this `loop` can never run — \
                a `loop` block repeats forever, so it must be the last step."
               name.txt)
        else if tail <> [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: this `choose` branch ends in a `loop`, but the \
                protocol continues after the `choose` — those following steps \
                are projected into EVERY branch, so they can never run in this \
                one. Move them inside the branches that can reach them."
               name.txt)
      | Ast.ProtoStop stop_sp :: rest ->
        (* `stop` projects to `SEnd` unconditionally (see [project_steps]),
           discarding both [rest] here and the enclosing [tail] — same
           unreachability shape as `loop`, just via early exit instead of
           looping forever. *)
        if rest <> [] then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: the steps after `stop` can never run — `stop` \
                exits the loop immediately, so it must be the last step."
               name.txt)
        else if tail <> [] then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: this `choose` branch ends in `stop`, but the \
                protocol continues after the `choose` — those following steps \
                are projected into EVERY branch, so they can never run in this \
                one. Move them inside the branches that can reach them."
               name.txt)
      | Ast.ProtoChoice (_, branches) :: rest ->
        List.iter (fun (_, arm) ->
            check_unreachable_after_loop ~tail:(rest @ tail) arm) branches;
        check_unreachable_after_loop ~tail rest
      | _ :: rest -> check_unreachable_after_loop ~tail rest
      | [] -> ()
    in
    check_unreachable_after_loop ~tail:[] pdef.proto_steps;
    (* Project the protocol onto each role and verify duality. *)
    let projections = project_protocol env ~span:sp ~proto_name:name.txt pdef in
    let participants = List.map fst projections in
    if participants <> [] && List.length participants < 2 then
      Err.warning env.errors ~span:sp
        (Printf.sprintf
           "Protocol `%s` only names one participant (`%s`). \
            A protocol usually involves at least two parties."
           name.txt (List.hd participants));
    (* Protocol roles are their own namespace — they are NOT type or actor
       names, so no "unknown participant" hint is emitted (F8, removed
       2026-07-24: it fired on every ordinary protocol, including the
       reference chapter's own Echo example). *)
    (* Check against previously-declared protocols for cross-protocol conflicts. *)
    let pi = { pi_def = pdef; pi_projections = projections; pi_span = sp } in
    let new_env = { env with protocols = StrMap.add name.txt pi env.protocols } in
    (if StrMap.cardinal new_env.protocols > 1 then
       StrMap.iter (fun other_name other_pi ->
           if other_name <> name.txt then begin
             let other_parts = List.map fst other_pi.pi_projections in
             if List.length participants >= 2 && List.length other_parts >= 2
             && List.sort compare participants = List.sort compare other_parts then
               Err.hint env.errors ~span:sp
                 (Printf.sprintf
                    "Protocol `%s` involves the same participants as `%s`. \
                     If these are dual protocols (one for each direction), \
                     this is expected. Otherwise, consider merging them."
                    name.txt other_name)
           end
         ) env.protocols);
    new_env

  | Ast.DSig (name, sdef, _sp) ->
    (* Store the signature so DMod can check conformance later. *)
    { env with sigs = (name.txt, sdef) :: env.sigs }

  | Ast.DInterface (idef, _sp) ->
    (* Register the interface definition for impl validation, and register
       each method as a polymorphic function binding in scope.
       Methods get CInterface constraints so call sites verify the type
       satisfies the interface (discharged in discharge_constraints). *)
    let env' = { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces } in
    List.fold_left (fun env (m : Ast.method_decl) ->
        (* Use level+1 so the interface type parameter gets quantified by generalize. *)
        let a = fresh_var (env.level + 1) in
        let tvars = ref [(idef.iface_param.txt, a)] in
        (* An interface method signature has no enclosing function — see
           [with_no_caller]. *)
        let ty = with_no_caller env (fun () -> surface_ty env ~tvars m.md_ty) in
        let a_id = match a with
          | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
          | _ -> 0
        in
        (* Build scheme: ∀a. [CInterface(iface, a)] => method_ty *)
        let base_sch = generalize env.level ty in
        let sch = match base_sch with
          | Poly (ids, cs, t) ->
            Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
          | Mono t ->
            Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
        in
        (* Register both unqualified (eq) and qualified (Eq.eq) names so
           that Eq.eq(x, y) resolves via the EField module-path lookup. *)
        let qualified = idef.iface_name.txt ^ "." ^ m.md_name.txt in
        let env1 = bind_var m.md_name.txt sch env in
        bind_var qualified sch env1
      ) env' idef.iface_methods

  | Ast.DImpl (idef, _sp) ->
    (* Instantiate the impl type, sharing tvars so the 'when' constraints
       can reference the same type variables as the impl type itself. *)
    let tvars = ref [] in
    (* The impl header's own type (`impl Iface(T)`) has no enclosing
       function — see [with_no_caller]. *)
    let inst_ty = with_no_caller env (fun () -> surface_ty env ~tvars idef.impl_ty) in
    (* Register this implementation so CInterface constraints can be discharged. *)
    let env_with_impl = { env with impls =
      (let key = idef.impl_iface.txt in
       let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
       (* Pass-2 re-registration for constraint discharge; coherence is enforced
          in [register_impl_shape] (Pass 1). Carry the span for the new shape. *)
       StrMap.add key ((inst_ty, idef.impl_iface.span, None) :: lst) env.impls) } in
    (* Check 'when' constraints: each C(T) must already be implemented. *)
    List.iter (fun ((cname : Ast.name), ctys) ->
        (* A `when C(T)` constraint type is also part of the impl header,
           with no enclosing function — see [with_no_caller]. *)
        match with_no_caller env (fun () -> List.map (surface_ty env ~tvars) ctys) with
        | [cty] ->
          let cty = repr cty in
          (match cty with
           | TVar _ -> ()   (* Polymorphic param — checked at use sites *)
           | _ ->
             if not (match StrMap.find_opt cname.txt env.impls with
                 | None -> false
                 | Some tys -> List.exists (fun (impl_ty, _, _) ->
                     impl_matches_ty (repr impl_ty) cty) tys) then
               Err.error env.errors ~span:cname.span
                 (Printf.sprintf
                    "Constraint `%s(%s)` in `when` clause is not satisfied.\n\
                     No `impl %s(%s)` is in scope."
                    cname.txt (pp_ty cty) cname.txt (pp_ty cty)))
        | _ -> ()
      ) idef.impl_constraints;
    (* Validate each method against the interface declaration. *)
    (match StrMap.find_opt idef.impl_iface.txt env.interfaces with
     | None ->
       (* For derive-generated pseudo-interfaces (e.g. JsonTo, JsonFrom),
          skip interface validation but still type-check and bind each method
          as a standalone function in the environment. *)
       let is_json_derive =
         String.length idef.impl_iface.txt >= 4
         && String.sub idef.impl_iface.txt 0 4 = "Json"
       in
       if not is_json_derive then
         Err.error env.errors ~span:idef.impl_iface.span
           (Printf.sprintf "Unknown interface `%s` — is it declared above this impl?"
              idef.impl_iface.txt)
     | Some interface ->
       (* Check superclass constraints: each required superclass must already have an impl *)
       let sc_tvars = ref [(interface.iface_param.txt, inst_ty)] in
       List.iter (fun ((sc_name : Ast.name), sc_tys) ->
           let sc_inst_tys = List.map (surface_ty env ~tvars:sc_tvars) sc_tys in
           (match sc_inst_tys with
            | [sc_inst_ty] ->
              let sc_inst_ty = repr sc_inst_ty in
              (match sc_inst_ty with
               | TVar _ -> ()  (* polymorphic param — checked at use sites *)
               | _ ->
                 if not (match StrMap.find_opt sc_name.txt env.impls with
                     | None -> false
                     | Some tys -> List.exists (fun (impl_ty, _, _) ->
                         impl_matches_ty (repr impl_ty) sc_inst_ty) tys) then
                   Err.error env.errors ~span:idef.impl_iface.span
                     (Printf.sprintf
                        "Cannot implement `%s(%s)`: required superclass `%s(%s)` is not \
                         satisfied.\n\
                         Add `impl %s(%s) do ... end` before this implementation."
                        idef.impl_iface.txt (pp_ty inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)))
            | _ -> ()  (* multi-param superclasses not yet supported *)
           )
         ) interface.iface_superclasses;
       (* Check all required methods are provided (error for non-default missing) *)
       List.iter (fun (iface_m : Ast.method_decl) ->
           let provided = List.exists
             (fun ((mname : Ast.name), _) -> mname.txt = iface_m.md_name.txt)
             idef.impl_methods
           in
           if not provided && iface_m.md_default = None then
             Err.error env.errors ~span:idef.impl_iface.span
               (Printf.sprintf
                  "Missing method `%s` in `impl %s(%s)`.\n\
                   Interface `%s` requires this method to be implemented."
                  iface_m.md_name.txt idef.impl_iface.txt (pp_ty inst_ty)
                  idef.impl_iface.txt)
         ) interface.iface_methods;
       List.iter (fun ((mname : Ast.name), (def : Ast.fn_def)) ->
           match List.find_opt
                   (fun (m : Ast.method_decl) -> m.md_name.txt = mname.txt)
                   interface.iface_methods with
           | None ->
             Err.error env.errors ~span:mname.span
               (Printf.sprintf "Interface `%s` does not declare a method `%s`."
                  idef.impl_iface.txt mname.txt)
           | Some iface_method ->
             (* Expected type: substitute interface param → concrete impl type *)
             let expected_ty =
               surface_ty env
                 ~tvars:(ref [(interface.iface_param.txt, inst_ty)])
                 iface_method.md_ty
             in
             (* Infer the method body's actual type.
                For injected default methods (zero params, body = default expr),
                use check_expr directly against the expected type. *)
             (match def.fn_clauses with
              | [{ fc_params = []; fc_body; _ }] when iface_method.md_default <> None ->
                (* Default method injected by desugar — just check the body
                   expr. This bypasses [check_fn], so there is no enclosing
                   function — see [with_no_caller]. *)
                with_no_caller env (fun () ->
                  check_expr env fc_body expected_ty
                    ~reason:(Some (RBuiltin
                      (Printf.sprintf "default `%s` in interface `%s`"
                         mname.txt idef.impl_iface.txt))))
              | _ ->
                let actual_sch = check_fn env def _sp in
                let actual_ty = instantiate env.level env actual_sch in
                unify env ~span:mname.span actual_ty expected_ty
                  ~reason:(Some (RBuiltin
                     (Printf.sprintf "`%s` in `impl %s` must match the interface signature"
                        mname.txt idef.impl_iface.txt))))
         ) idef.impl_methods);
    (* For Json derive pseudo-interfaces, to_json/from_json are already bound
       as polymorphic builtins in the base environment (∀a b. a -> b).
       We still type-check each method body for local correctness, but we do NOT
       re-bind the name — that would shadow the polymorphic builtin with a
       monomorphic version, breaking modules that derive Json for multiple types. *)
    let is_json_derive =
      String.length idef.impl_iface.txt >= 4
      && String.sub idef.impl_iface.txt 0 4 = "Json"
    in
    if is_json_derive then begin
      (* Type-check the method bodies for correctness, but discard the schemes *)
      List.iter (fun ((_mname : Ast.name), (def : Ast.fn_def)) ->
          ignore (check_fn env def _sp)
        ) idef.impl_methods;
      discharge_constraints env_with_impl _sp;
      env_with_impl
    end else begin
      discharge_constraints env_with_impl _sp;
      env_with_impl
    end

  | Ast.DExtern (edef, _sp) ->
    (* Register each foreign function as a monomorphic binding. An extern
       fn's own signature has no enclosing function — see [with_no_caller]. *)
    List.fold_left (fun env (ef : Ast.extern_fn) ->
        let tvars = ref [] in
        let param_tys, ret_ty = with_no_caller env (fun () ->
            let param_tys = List.map (fun (_, t) -> surface_ty env ~tvars t) ef.ef_params in
            let ret_ty = surface_ty env ~tvars ef.ef_ret_ty in
            (param_tys, ret_ty)) in
        let ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
        bind_var ef.ef_name.txt (Mono ty) env
      ) env edef.ext_fns

  | Ast.DUse (ud, sp) ->
    let mod_str = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
    let prefix = mod_str ^ "." in
    (match ud.use_sel with
     | Ast.UseSingle ->
       (* A single-segment `use Foo` needs no new bindings: bare references
          like `Foo.bar` already match the qualified key "Foo.bar" directly.
          A DOTTED `use A.B` is different — the module's members are bound
          under the FULL qualified key "A.B.bar", which a bare "B.bar"
          reference (the natural way to use the last, most-specific segment
          after importing it) does not match. Re-export every "A.B.name" as
          "B.name" — identical in spirit to how `alias A.B as C` re-exports
          under the chosen short name — so `use A.B` then `B.bar(...)` works
          the same way `alias A.B as B` would. A single-segment path makes
          [last_seg] equal [mod_str], so the rebind is a same-key no-op and
          this subsumes the old behavior exactly. *)
       let last_seg = match List.rev ud.use_path with
         | last :: _ -> last.Ast.txt
         | [] -> mod_str
       in
       let short_prefix = last_seg ^ "." in
       let new_bindings = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen && String.sub k 0 plen = prefix then
             let rest = String.sub k plen (String.length k - plen) in
             let short_key = short_prefix ^ rest in
             if StrMap.mem short_key env.vars then acc
             else (short_key, sch) :: acc
           else acc) env.vars [] in
       (* The entry is registered UNCONDITIONALLY, but pre-marked used when it
          rebound nothing.  A single-segment `use Foo` rebinds nothing (every
          "Foo.bar" short key is already the qualified key), so it used to file
          no entry at all and therefore tracked no references — which left
          demand-driven capability propagation (see [import_required_caps])
          with nothing to go on and forced it back to the module-granular
          answer for exactly the qualified-reference form `use` exists to
          serve.  Seeding [ie_used] with [new_bindings = []] keeps the
          unused-import warning byte-identical to before (a rebind-nothing
          `use` never warned, because it had no entry); the entry now exists
          purely so [record_use] can record WHICH members were referenced. *)
       let entry = { ie_span = sp
                   ; ie_desc = Printf.sprintf
                       "Unused import: nothing from `%s` is used.\n\
                        Remove this import or use something from it." mod_str
                   ; ie_matches = (fun name ->
                       name = mod_str
                       || (String.length name > String.length short_prefix
                           && String.sub name 0 (String.length short_prefix) = short_prefix)
                       || (String.length name > String.length prefix
                           && String.sub name 0 (String.length prefix) = prefix))
                   ; ie_used = ref (new_bindings = [])
                   ; ie_used_names = Hashtbl.create 8 } in
       env.import_tracker := entry :: !(env.import_tracker);
       import_index_add_exact env.import_idx mod_str entry;
       import_index_add_prefix env.import_idx last_seg entry;
       let prefix_root = match String.index_opt mod_str '.' with
         | Some i -> String.sub mod_str 0 i | None -> mod_str in
       import_index_add_prefix env.import_idx prefix_root entry;
       bind_vars new_bindings env
     | Ast.UseAll ->
       (* Find all vars with "Prefix.name" and rebind them as plain "name".
          Skip names the current module defines itself (env.local_fns):
          the local definition shadows the bulk import — rebinding would
          clobber the local fn's pass-1 placeholder and make check_fn unify
          the local definition against the imported fn's type. *)
       let matching = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if StrMap.mem short env.local_fns then acc
             else (short, sch) :: acc
           else acc) env.vars [] in
       (* Import interfaces from the module prefix into scope as short names *)
       let env = StrMap.fold (fun k idef e ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if StrMap.mem short e.interfaces then e
             else { e with interfaces = StrMap.add short idef e.interfaces }
           else e) env.interfaces env in
       (* Track for unused-import warning: warn if nothing from this module is
          used.  A QUALIFIED use (HttpServer.query_string) must count too —
          matching only the rebound short names produced false "unused import"
          warnings on modules that are used exclusively via qualified calls
          (common in wrapper modules whose own fns shadow the short names). *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name ->
                         List.mem name short_names
                         || name = mod_str
                         || (String.length name > String.length prefix
                             && String.sub name 0 (String.length prefix) = prefix))
                     ; ie_used = ref false
                     ; ie_used_names = Hashtbl.create 8 } in
         env.import_tracker := entry :: !(env.import_tracker);
         (* Index for O(1) [record_use] lookup: every rebound short name is an
            exact-match key, as is the bare module name itself (ie_matches's
            "name = mod_str" clause -- an EVar referencing the module path
            literally); the module's first path segment is the prefix-index
            key a qualified reference (e.g. "Depot.Gate.foo") hashes to (see
            [record_use] -- it looks up by its own first-dot split, which is
            independent of [split_qualified]'s rindex/module-load convention
            elsewhere in this file: unused-import tracking only ever needs
            the declared import's own root segment, never a full module-load
            resolution). *)
         List.iter (fun n -> import_index_add_exact env.import_idx n entry) short_names;
         import_index_add_exact env.import_idx mod_str entry;
         let prefix_root = match String.index_opt mod_str '.' with
           | Some i -> String.sub mod_str 0 i | None -> mod_str in
         import_index_add_prefix env.import_idx prefix_root entry
       end;
       bind_vars matching env
     | Ast.UseNames names ->
       List.fold_left (fun env n ->
           match StrMap.find_opt (prefix ^ n.Ast.txt) env.vars with
           | Some sch ->
             (* Track for unused-import warning: warn if this specific name is unused. *)
             let entry = { ie_span = n.Ast.span
                         ; ie_desc = Printf.sprintf
                             "Unused import `%s` from `%s`.\n\
                              Remove it from the import list or use it." n.Ast.txt mod_str
                         ; ie_matches = (fun name -> name = n.Ast.txt)
                         ; ie_used = ref false
                         ; ie_used_names = Hashtbl.create 8 } in
             env.import_tracker := entry :: !(env.import_tracker);
             import_index_add_exact env.import_idx n.Ast.txt entry;
             bind_var n.Ast.txt sch env
           | None ->
             Err.error env.errors ~span:n.Ast.span
               (Printf.sprintf "Module `%s` does not export `%s`."
                  mod_str n.Ast.txt);
             env) env names
     | Ast.UseExcept excluded ->
       let excl_set = List.map (fun n -> n.Ast.txt) excluded in
       let matching = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if List.mem short excl_set then acc
             (* Local definitions shadow bulk imports — see UseAll. *)
             else if StrMap.mem short env.local_fns then acc
             else (short, sch) :: acc
           else acc) env.vars [] in
       (* Track for unused-import warning: warn if nothing from this module is
          used.  A QUALIFIED use (HttpServer.query_string) must count too —
          matching only the rebound short names produced false "unused import"
          warnings on modules that are used exclusively via qualified calls
          (common in wrapper modules whose own fns shadow the short names). *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name ->
                         List.mem name short_names
                         || name = mod_str
                         || (String.length name > String.length prefix
                             && String.sub name 0 (String.length prefix) = prefix))
                     ; ie_used = ref false
                     ; ie_used_names = Hashtbl.create 8 } in
         env.import_tracker := entry :: !(env.import_tracker);
         List.iter (fun n -> import_index_add_exact env.import_idx n entry) short_names;
         import_index_add_exact env.import_idx mod_str entry;
         let prefix_root = match String.index_opt mod_str '.' with
           | Some i -> String.sub mod_str 0 i | None -> mod_str in
         import_index_add_prefix env.import_idx prefix_root entry
       end;
       bind_vars matching env)

  | Ast.DAlias (ad, sp) ->
    let orig_prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) ^ "." in
    let short_name = ad.alias_name.Ast.txt in
    let short_prefix = short_name ^ "." in
    (* Re-export all "Orig.name" as "Short.name" *)
    let new_bindings = StrMap.fold (fun k sch acc ->
        let plen = String.length orig_prefix in
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          let rest = String.sub k plen (String.length k - plen) in
          (short_prefix ^ rest, sch) :: acc
        else acc) env.vars [] in
    (* Track for unused-alias warning: warn if no "Short.*" name is referenced. *)
    if new_bindings <> [] then begin
      let orig_str = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) in
      let entry = { ie_span = sp
                  ; ie_desc = Printf.sprintf
                      "Unused alias `%s` for `%s`.\n\
                       Remove this alias or use it to qualify a name." short_name orig_str
                  ; ie_matches = (fun name ->
                      let plen = String.length short_prefix in
                      (String.length name >= plen && String.sub name 0 plen = short_prefix)
                      || name = short_name)
                  ; ie_used = ref false
                  ; ie_used_names = Hashtbl.create 8 } in
      env.import_tracker := entry :: !(env.import_tracker);
      (* [short_name] has no dots, so it is both the exact-match key (bare
         alias reference) and the prefix-index key (qualified reference
         "FB.baz" first-dot-splits to exactly "FB" = short_name). *)
      import_index_add_exact env.import_idx short_name entry;
      import_index_add_prefix env.import_idx short_name entry
    end;
    bind_vars new_bindings env

  | Ast.DNeeds (caps, _sp) ->
    (* Record declared capability paths in env for DMod validation.
       Each path is a list of names e.g. ["IO"; "Network"] → "IO.Network" *)
    let scoped = List.map (fun (names, scope) ->
        (String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names), scope)
      ) caps in
    let paths = List.map fst scoped in
    { env with mod_needs = paths @ env.mod_needs;
               mod_need_scopes = scoped @ env.mod_need_scopes }

  | Ast.DProofCap (name, _sp) ->
    (* Register proof cap: full qualified path → declaring module name.
       Also register the cap name as a 0-arity type so Cap(Mod.Name) is
       valid in type annotations (just like Cap(IO.Network)). *)
    let full_path =
      if env.current_module = "" then name.txt
      else env.current_module ^ "." ^ name.txt
    in
    { env with
      proof_caps = (full_path, env.current_module) :: env.proof_caps;
      types = StrMap.add full_path 0 env.types }

  | Ast.DAlwaysLinearType (vis, name, params, typedef, sp) ->
    (* Process the type definition exactly like DType (registers constructors, records, etc.),
       then register both the bare name and the qualified name in always_linear_types.
       TCon internals use the bare name (e.g. "Handle"), while type annotations after module
       export may use the qualified name (e.g. "Handle.Handle") — store both so List.mem
       matches regardless of which form repr produces at a given call site. *)
    let bare_name = name.txt in
    let qual_name =
      if env.current_module = "" then name.txt
      else env.current_module ^ "." ^ name.txt
    in
    let env1 = check_decl env (Ast.DType (vis, name, params, typedef, sp)) in
    let names = if bare_name = qual_name then [bare_name]
                else [bare_name; qual_name] in
    { env1 with always_linear_types = names @ env1.always_linear_types }

  | Ast.DApp _ ->
    (* DApp is desugared to DFn(__app_init__) before typecheck; reaching here is a bug. *)
    env

  | Ast.DDeriving _ ->
    (* DDeriving is expanded to DImpl blocks by the desugar pass; should not reach here. *)
    env

  | Ast.DTest (tdef, sp) ->
    (* Typecheck the test body; it must be Unit. No enclosing function — see
       [with_no_caller]. *)
    (* R2 exemption: a test body has no [main] to be granted the root from, so
       [root_cap] stays nameable here (see [env.root_cap_allowed]). *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env tdef.test_body t_unit
        ~reason:(Some (RBuiltin (Printf.sprintf "test body of \"%s\" must produce Unit" tdef.test_name))));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DDescribe (_name, decls, sp) ->
    let env' = List.fold_left check_decl env decls in
    Hashtbl.replace env'.type_map sp t_unit;
    env'

  | Ast.DSetup (body, sp) ->
    (* No enclosing function — see [with_no_caller]. *)
    (* R2 exemption, same rationale as [DTest]. *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env body t_unit ~reason:(Some (RBuiltin "setup body must produce Unit")));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DSetupAll (body, sp) ->
    (* No enclosing function — see [with_no_caller]. *)
    (* R2 exemption, same rationale as [DTest]. *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env body t_unit ~reason:(Some (RBuiltin "setup_all body must produce Unit")));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DTransitions (handle_ty, arms, sp) ->
    let handle_name = handle_ty.txt in
    (* Extract the last (state) type argument from Handle(args).
       Handles both single-param Handle(s) and two-param Handle(r,s). *)
    let last_arg = function
      | [] -> None
      | args -> Some (repr (List.nth args (List.length args - 1)))
    in
    (* Validate each declared transition arm's via function. *)
    let declared_vias = List.filter_map (fun (a : Ast.transition) ->
        let via_name = a.tr_via.txt in
        let sch_opt =
          match lookup_var via_name env with
          | Some s -> Some s
          | None ->
            let qname = if env.current_module = "" then via_name
                        else env.current_module ^ "." ^ via_name in
            lookup_var qname env
        in
        match sch_opt with
        | None ->
          Err.error env.errors ~span:a.tr_via.span
            (Printf.sprintf
               "Via function `%s` is not defined in this module. \
                Expected: fn %s(h : %s(%s)) : %s(%s) do ... end"
               via_name via_name handle_name a.tr_from.txt
               handle_name a.tr_to.txt);
          None
        | Some sch ->
          let ty = repr (instantiate env.level env sch) in
          (match ty with
           | TArrow (TCon (hn, param_args), ret_t) when hn = handle_name ->
             (match last_arg param_args with
              | Some (TCon (s, []) as from_t) when s <> a.tr_from.txt ->
                Err.error env.errors ~span:a.tr_span
                  (Printf.sprintf
                     "Via function `%s` takes state `%s` but transition declares from-state `%s`."
                     via_name (pp_ty from_t) a.tr_from.txt)
              | _ -> ());
             (match repr ret_t with
              | TCon (hn2, ret_args) when hn2 = handle_name ->
                (match last_arg ret_args with
                 | Some (TCon (s, []) as to_t) when s <> a.tr_to.txt ->
                   Err.error env.errors ~span:a.tr_span
                     (Printf.sprintf
                        "Via function `%s` returns state `%s` but transition declares to-state `%s`."
                        via_name (pp_ty to_t) a.tr_to.txt)
                 | _ -> ())
              | _ ->
                Err.error env.errors ~span:a.tr_span
                  (Printf.sprintf
                     "Via function `%s` has return type `%s`, expected `%s(_, %s)`."
                     via_name (pp_ty ret_t) handle_name a.tr_to.txt))
           | TArrow (param_t, _) ->
             Err.error env.errors ~span:a.tr_via.span
               (Printf.sprintf
                  "Via function `%s` takes `%s`, expected `%s(..., %s)`."
                  via_name (pp_ty param_t) handle_name a.tr_from.txt)
           | _ ->
             Err.error env.errors ~span:a.tr_via.span
               (Printf.sprintf
                  "Via function `%s` has type `%s`, expected `%s(..., %s) -> %s(..., %s)`."
                  via_name (pp_ty ty) handle_name a.tr_from.txt handle_name a.tr_to.txt));
          Some via_name
      ) arms in
    (* Warn about local functions whose type looks like a transition but are
       not declared in this transitions block — suggest adding them. *)
    StrMap.iter (fun fn_name sch ->
        if not (StrMap.mem fn_name env.local_fns) then ()
        else if List.mem fn_name declared_vias then ()
        else begin
          let ty = repr (instantiate env.level env sch) in
          match ty with
          | TArrow (TCon (hn, param_args), TCon (hn2, ret_args))
            when hn = handle_name && hn2 = handle_name ->
            (match last_arg param_args, last_arg ret_args with
             | Some from_t, Some to_t ->
               let from_s = pp_ty from_t in
               let to_s   = pp_ty to_t in
               if from_s <> to_s then
                 Err.warning env.errors ~span:sp
                   (Printf.sprintf
                      "`%s` looks like a transition function (`%s` -> `%s`) \
                       but is not declared in `transitions %s`. \
                       Consider adding:\n    %s: %s -> %s via %s"
                      fn_name from_s to_s handle_name
                      (String.capitalize_ascii from_s) from_s to_s fn_name)
             | _ -> ())
          | _ -> ()
        end
      ) env.vars;
    env

  | Ast.DOpts (opts, _sp) ->
    let env = if List.mem "no_panic"      opts then { env with no_panic_mod      = true } else env in
    let env = if List.mem "pure"          opts then { env with pure_mod          = true } else env in
    let env = if List.mem "no_extern"     opts then { env with no_extern_mod     = true } else env in
    let env = if List.mem "deterministic" opts then { env with deterministic_mod = true } else env in
    env

  | Ast.DSatisfy _ ->
    (* DSatisfy is expanded to DImpl blocks by the desugar pass; nothing to typecheck here. *)
    env

(** Emit warnings for any imports or aliases that were never referenced. *)
let warn_unused_imports env =
  List.iter (fun ie ->
    if not !(ie.ie_used) then
      Err.warning_with_code env.errors ~span:ie.ie_span ~code:"unused_import" ie.ie_desc
  ) !(env.import_tracker)

(* =================================================================
   Tail-call enforcement — now lib/typecheck/typecheck_tailcall.ml.
   [include], not [open]: only [include] re-exports these names as part of
   [Typecheck]'s own surface, and consumers reach this module through
   [let open] and through aliases (Tc., TC., T.) that no grep can see.
   ================================================================= *)
include Typecheck_tailcall

(* =================================================================
   §8  Module entry point
   ================================================================= *)

(** Build a function's declared type scheme from its annotations, for pass-1
    forward cross-module reference resolution.  Returns None when the signature
    cannot be built structurally (unannotated/pattern params, no return
    annotation, zero params, multiple clauses, or exotic annotation forms) — the
    caller then falls back to the [fresh_var] placeholder.

    The scheme carries NO class/bound constraints; this is sound because the
    prior placeholder ([Mono (fresh_var _)]) carried none either, and each
    function's own [check_fn] re-derives and enforces its full constrained type.
    The only gain is that a module checked BEFORE this function now sees its real
    argument and RESULT types instead of an unconstrained type variable — which
    is what lets niche-encoded [Option]/ADT results lower with the correct match
    strategy regardless of stdlib check order. *)
let prebind_fn_scheme (def : Ast.fn_def) : scheme option =
  let opt_all xs =
    List.fold_right (fun x acc -> match x, acc with
      | Some v, Some vs -> Some (v :: vs)
      | _ -> None) xs (Some []) in
  let tvars : (string * ty) list ref = ref [] in
  let rec conv (s : Ast.ty) : ty option =
    match s with
    | Ast.TyCon (name, args) ->
      (* Decline to build a scheme from a QUALIFIED type name.  This prebind
         pass has no env, so it cannot reproduce [surface_ty]'s type resolution:
         [surface_ty] canonicalizes a qualified variant to its bare nominal
         (`Conduit.ConduitError` -> `ConduitError`) AND expands a qualified
         record to a structural [TRecord].  Emitting a verbatim qualified nominal
         `TCon("Mod.T")` here made a prebind fn scheme — used at a call site
         checked BEFORE the callee's Pass-2 re-derivation — mismatch the bare
         (or structural) type the caller's argument carries, an order-dependent
         "expected Mod.T but got T".  Guessing bare unconditionally instead
         wrongly conflates two same-suffixed types (`Conduit.Config` vs stdlib
         `Config`).  Returning None falls back to the [fresh_var] placeholder,
         which unifies with anything and imposes no false constraint; the
         callee's own [check_fn] still derives and enforces its real type. *)
      if String.contains name.txt '.' then None
      else
        (match opt_all (List.map conv args) with
         | Some args' -> Some (TCon (name.txt, args'))
         | None -> None)
    | Ast.TyVar v ->
      (match List.assoc_opt v.txt !tvars with
       | Some t -> Some t
       | None -> let fv = fresh_var 1 in tvars := (v.txt, fv) :: !tvars; Some fv)
    | Ast.TyArrow (a, b) ->
      (match conv a, conv b with Some a', Some b' -> Some (TArrow (a', b')) | _ -> None)
    | Ast.TyTuple ts ->
      (match opt_all (List.map conv ts) with Some ts' -> Some (TTuple ts') | None -> None)
    | Ast.TyLinear (_, t) -> conv t
    | _ -> None
  in
  match def.fn_clauses with
  | [clause] when clause.fc_params <> [] ->
    let param_ty (fp : Ast.fn_param) : ty option =
      match fp with
      | Ast.FPNamed p | Ast.FPDefault (p, _) ->
        (match p.param_ty with Some t -> conv t | None -> None)
      | Ast.FPPat _ -> None
    in
    (match def.fn_ret_ty with
     | None -> None
     | Some ret ->
       (match conv ret, opt_all (List.map param_ty clause.fc_params) with
        | Some ret_ty, Some param_tys ->
          let arrow = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
          Some (generalize 0 arrow)
        | _ -> None))
  | _ -> None

(** Type-check a whole module.

    Pass 1: collect all top-level function names into the environment
            as monomorphic placeholders.  This allows forward references
            and simple mutual recursion (the placeholder is unified with
            the actual type as the body is inferred).

    Pass 2: check declarations in order, updating the environment.

    Returns the [Err.ctx] containing all diagnostics.

    [seed_env], when given, is used as pass 1's starting environment instead
    of [base_env errors type_map] — its [vars]/[types]/[ctors]/[interfaces]/etc.
    (e.g. an already-typechecked stdlib) are visible to [m]'s own forward-reference
    prebinding and [check_decl] pass with NO other change to pass 1/1b/2's
    structure, so passing [None] is exactly today's behavior. [seed_env]'s own
    [type_map] is reused (shared, mutated in place with [m]'s new span→type
    entries) instead of allocating a fresh one, so a caller who built [seed_env]
    from a separately-checked module can still recover types for BOTH that
    module's spans and [m]'s own via the single returned [type_map]. *)
(* ── R1 stages A+B: the grant check ──────────────────────────────────────
   specs/2026-08-08-r1-no-ambient-io-design.md.

   `main`'s capability parameter IS the program's grant, and the program's
   transitive capability closure from `main` must sit under it.  This is the
   first check in the capability system that says NO rather than "declare
   it": every earlier check (1b, the ceiling, R3, R2) verifies that the
   MANIFEST is truthful, and a hostile module with a truthful manifest passes
   them all.  Here, `fn main(cap : Cap(IO.Console))` makes "this program
   reaches nothing beyond the console" a compile-time property no `needs`
   line can override.

   Adoption contract (each clause pinned in test_compiler's cap_grant group):
   - no capability parameter → NO gate.  Ambient, exactly today's behavior;
     stage A/B breaks no existing program.
   - `Cap(IO)` → the full grant; every IO-lattice point sits under it.
   - `Cap(IO.X)` → narrow grant, enforced transitively through helpers and
     the stdlib alike.
   - `IO.Foreign` under a narrow grant is REFUSED with its own message: what
     linked C does is not modellable, so certifying a bound over it would be
     a lie (ladder doc, "interactions to design for").

   Design constraints inherited from a week of capability bugs:
   - Judged on the TYPECHECK-side closure ([fn_transitive_capability_
     closures_tbl]), which both the interpreter and compile paths share — the
     unused-warning contradiction came from gating one path on an analysis
     the other path does not run.
   - Reachability-based: caps(main), not the file's union.  Dead code costs
     nothing, matching the ceiling's post-#225 semantics.
   - Non-IO capability roots (FFI caps like `Ffi`/`LibC`) are OUTSIDE the IO
     lattice and outside this check — they are governed by the extern checks;
     holding them under an IO grant would reject every FFI program with a
     message about a lattice they are not in.  Their IO shadow (`IO.Foreign`)
     is what the Foreign clause above bounds.
   - The check runs at the end of [check_module_core] only — never on the
     REPL's [check_module_with_env] path, which has no entry point to be
     granted from (the same exemption R2 gives it). *)
(* The chain of references from [from] to a function that directly holds
   [cap]. Same BFS and same two-way name resolution as [check_main_grant]'s
   [reachable_from_main] below, but keeps the path rather than only the
   reachable set — "who reaches what through whom" is exactly the evidence
   the ceiling's attribution pass produces on the TIR side, and this is the
   typecheck-side equivalent, available on BOTH the interpreter and compile
   paths. Used by [check_main_grant] to attribute a grant violation to the
   user's own call chain instead of only the stdlib function that directly
   holds the capability. *)
(* The single shared rendering of a capability call chain, used by both
   diagnostics in the compiler that print one to a user: this module's own
   [check_main_grant] (a grant-violation attribution) and
   [March_refinecheck.Cap_infer.chain_note] (a missing-`needs` body-scan
   attribution). [chain] is the full path from the entry point, with `main`
   (or whichever entry) as its first element — callers that compute a path
   NOT including the entry (like [cap_reach_chain] below) must prepend it
   before calling this.

   Before this function existed the two call sites each built the string
   inline and happened to agree only by construction; they diverged once
   (one truncated past 4 frames with an ASCII `->` and dropped the entry
   frame, the other did not) before being brought back in sync by hand. This
   is the one place both now go through, so a future format change (e.g. a
   frame cap) is made once and both diagnostics move together. Deciding
   whether to add such a cap is intentionally NOT done here — see
   specs/progress/2026-08-17-capability-chain-rendering-unify-elision.md. *)
let render_cap_chain (chain : string list) : string =
  String.concat " \xe2\x86\x92 " chain

let cap_reach_chain (env : env) ~(from : string) ~(cap : string)
  : string list option =
  let holds k =
    match Hashtbl.find_opt env.own_cap_closures k with
    | Some own -> List.mem cap own
    | None -> false
  in
  let visited = Hashtbl.create 64 in
  let queue = Queue.create () in
  Queue.push (from, []) queue;
  let result = ref None in
  while !result = None && not (Queue.is_empty queue) do
    let k, path = Queue.pop queue in
    if not (Hashtbl.mem visited k) then begin
      Hashtbl.replace visited k ();
      let path = if k = from then path else path @ [ k ] in
      if k <> from && holds k then result := Some path
      else
        let prefix =
          match String.rindex_opt k '.' with
          | Some i -> String.sub k 0 (i + 1)
          | None -> ""
        in
        List.iter
          (fun r ->
             let known n =
               Hashtbl.mem env.own_cap_closures n || Hashtbl.mem env.fn_refs n
             in
             if known r then Queue.push (r, path) queue;
             let q = prefix ^ r in
             if q <> r && known q then Queue.push (q, path) queue)
          (Option.value ~default:[] (Hashtbl.find_opt env.fn_refs k))
    end
  done;
  !result

let check_main_grant ?rows (env : env) (decls : Ast.decl list) : unit =
  (* [rows] lets the caller hand in an already-solved row table. Stage C made
     the flat closure a projection of that solve, and stage D added a second
     end-of-module consumer ([check_fn_grants]) — so without sharing, every
     `--check` ran the fixpoint twice over the whole stdlib-prepended program.
     That cost ~10% of wall-clock per file and pushed CI's @types-check step
     (288 files, a 10-minute budget it was already using 9 of) over the limit.
     [check_fn_grants] was REMOVED 2026-08-13 (see [fn_grant_points]'s doc
     comment), so [check_module_core] is [rows]'s only caller now — but the
     parameter stays, both as the cheapest way to keep this signature stable
     for any future second consumer, and because [rows] is still how the
     caller controls [~with_rows] (see its own call site: this function never
     reads [deps]/[unknown], so it is solved caps-only there). *)
  (* R1 stage D: `main`'s grant is the UNION over ALL of its capability
     parameters, not the head of the first one's caps.  Same rule as
     [check_fn_grants]; [Desugar.check_main_signature] guarantees every
     parameter is a `Cap(P)`.

     [main_site] is found whether or not a grant is present, because stage D
     needs the span to report a MISSING grant — the case where [grants] is
     empty and the program is nonetheless not pure. *)
  let main_site : (string list * Ast.span * Ast.span) option =
    List.find_map
      (function
        | Ast.DFn (def, _) when def.Ast.fn_name.txt = "main" ->
          (match def.Ast.fn_clauses with
           | clause :: _ ->
             let grants =
               List.concat_map
                 (fun p ->
                    match p with
                    | Ast.FPNamed p | Ast.FPDefault (p, _) -> (
                      match p.Ast.param_ty with
                      | Some ty -> March_caps.Cap_surface_ty.caps_in_ty ty
                      | None -> [])
                    | Ast.FPPat _ -> [])
                 clause.Ast.fc_params
             in
             Some (List.sort_uniq String.compare grants, clause.Ast.fc_span,
                   clause.Ast.fc_params_span)
           | [] -> None)
        | _ -> None)
      decls
  in
  let main_grant : (string list * Ast.span) option =
    match main_site with
    | Some ((_ :: _ as grants), span, _) -> Some (grants, span)
    | _ -> None
  in
  let solved = lazy (match rows with
    | Some r -> r
    | None -> fn_capability_rows_tbl env)
  in
  let closures_tbl () =
    let tbl : (string, string list) Hashtbl.t = Hashtbl.create 64 in
    Hashtbl.iter
      (fun k (r : March_caps.Cap_rows.row) -> Hashtbl.replace tbl k r.caps)
      (Lazy.force solved);
    tbl
  in
  let main_closure () =
    match Hashtbl.find_opt (closures_tbl ()) "main" with
    | Some caps -> caps
    | None -> []
  in
  (* R1 stage D: a program that performs IO must SAY what it performs it
     under.  This arm is the whole of R1's opt-in gap — before stage D it was
     `| None -> ()`, and that single line is why "March programs cannot
     perform undeclared IO" was false while stages A–C were shipped.

     An empty closure still passes: a `main` that touches nothing satisfies a
     grant of nothing, which is why the majority of existing programs (212 of
     330 measured) are untouched by the flip.

     The row's [unknown] flag is deliberately NOT consulted here — see the
     design's §D3.  [unknown] exists because a FUNCTION can receive a closure
     from outside itself, so no caller can be charged for what it does.  At
     `main` the program is closed: every closure it invokes was created
     somewhere inside it and charged at its creation site.  The two genuine
     "outside" routes are handled elsewhere — FFI surfaces as `IO.Foreign`,
     and hot code reload is outside the claim entirely. *)
  (match main_site with
   | Some ([], span, params_span) -> (
     match List.sort_uniq String.compare (main_closure ()) with
     | [] -> ()
     | caps ->
       let named = List.filter (fun c -> cap_subsumes "IO" c) caps in
       if named <> [] then
         let show_caps =
           String.concat ", " (List.map (fun c -> Printf.sprintf "`%s`" c) named)
         in
         let suggested =
           String.concat ", "
             (List.map
                (fun c ->
                   (* `cap_` prefix, not the bare leaf: `IO.Spawn` would give
                      `spawn`, which is a RESERVED KEYWORD and does not parse.
                      A fixed prefix cannot collide with any keyword and needs
                      no reserved-word table kept in sync with the lexer. *)
                   let leaf =
                     match String.rindex_opt c '.' with
                     | Some i -> String.sub c (i + 1) (String.length c - i - 1)
                     | None -> c
                   in
                   Printf.sprintf "_cap_%s : Cap(%s)"
                     (String.lowercase_ascii leaf) c)
                named)
         in
         (* The fix is MECHANICAL, not a suggestion: the grant a program must
            declare IS `caps(main)`, which this check already computed in
            order to report the error at all. Emitting it as a `FReplace` over
            the parameter list lets `forge fix` apply it, which under a hard
            flip is the only migration help code outside this repo gets.

            The span has to be [fc_params_span] specifically — `main`'s NAME
            span would yield `fn main(…)() : ()`, and the clause span covers
            the body. That is why `fn_clause` grew the field. *)
         Err.error_with_fix env.errors ~span ~code:"cap_grant"
           ~fix:(Err.FReplace
                   { span = params_span; text = Printf.sprintf "(%s)" suggested })
           (Printf.sprintf
              "`main` performs IO but declares no grant. The program reaches \
               %s; a `main` with no capability parameter is granted nothing.\n\
               help: declare the grant `main` actually needs —\n\
              \        fn main(%s) : ()\n\
               or grant everything with `fn main(cap : Cap(IO))`.\n\
               `forge fix` can apply this."
              show_caps suggested))
   | _ -> ());
  match main_grant with
  | None -> ()
  | Some (grants, span) ->
    let closure =
      match Hashtbl.find_opt (closures_tbl ()) "main" with
      | Some caps -> caps
      | None -> []
    in
    let covered c = List.exists (fun g -> cap_subsumes g c) grants in
    let show_grant =
      String.concat " + " (List.map (fun g -> Printf.sprintf "`Cap(%s)`" g) grants)
    in
    List.iter
      (fun c ->
         if not (cap_subsumes "IO" c) then ()  (* FFI root; not this lattice *)
         else if covered c then ()
         (* R1 stage D moved this behind [covered], matching
            [check_fn_grants].  While `main` could hold exactly ONE
            capability, refusing `IO.Foreign` under anything but `Cap(IO)` was
            right: certifying a console bound over an extern block would be a
            lie, and there was no way to say "console AND foreign".  Now that
            the grant is a SET, a `Cap(IO.Foreign)` parameter IS an explicit
            grant of the unbounded thing, written by someone who knows what
            they authorized.  So the refusal applies only where the grant does
            not cover it — where it would otherwise be an ordinary violation,
            and this is the more informative message to give. *)
         else if cap_subsumes "IO.Foreign" c then
           Err.error env.errors ~span
             (Printf.sprintf
                "`main` is granted %s, but the program reaches `%s` — \
                 linked C code, whose behavior the capability lattice cannot \
                 bound. A narrow grant cannot be certified over an `extern` \
                 block.\n\
                 help: grant `Cap(IO)`, or add a `Cap(IO.Foreign)` parameter \
                 to accept that bound explicitly, or remove the extern \
                 dependency from everything `main` reaches."
                show_grant c)
         else
           (* Suggest the PRECISE least-privilege fix — add a parameter for
              exactly the reached capability — before the broad `Cap(IO)`
              escape hatch.  The whole system promotes least privilege, so the
              help must not steer the user to the widest grant.  Parameter name
              mirrors the no-grant path's `_cap_<leaf>` spelling (a fixed
              prefix, never a bare leaf like `spawn`, which is a reserved
              keyword and would not parse). *)
           let leaf =
             match String.rindex_opt c '.' with
             | Some i -> String.sub c (i + 1) (String.length c - i - 1)
             | None -> c
           in
           let param_hint =
             Printf.sprintf "_cap_%s : Cap(%s)" (String.lowercase_ascii leaf) c
           in
           Err.error env.errors ~span
             (Printf.sprintf
                "`main` is granted %s, but the program reaches `%s`%s. \
                 The grant is a ceiling on the WHOLE program — declaring \
                 `needs %s` does not raise it.\n\
                 help: add a `Cap(%s)` parameter to `main` (e.g. \
                 `fn main(…, %s)`), or widen the whole grant to `Cap(IO)`, \
                 or remove the use."
                show_grant c
                (* Renders exactly like the sibling missing-`needs`
                   diagnostic's [Cap_infer.chain_note]
                   (lib/refinecheck/cap_infer.ml) through the shared
                   [render_cap_chain] above: the FULL chain (no elision —
                   neither diagnostic elides today), `main` included as the
                   first frame, joined with `→`. Both read as a matched
                   pair, so they must render the same way. *)
                (match cap_reach_chain env ~from:"main" ~cap:c with
                 | Some (_ :: _ as chain) ->
                   Printf.sprintf " (reached from `main`: %s)"
                     (render_cap_chain ("main" :: chain))
                 | _ -> "")
                c c param_hint))
      (List.sort_uniq String.compare closure)

(* ── R1 stage C: per-function grants — REMOVED 2026-08-13 ──────────────────
   Formerly specs/2026-08-10-r1-stage-c-effect-rows-design.md; the removal is
   specs/progress/2026-08-13-remove-per-function-grant-ceiling.md.

   Stage C used to make every function that took a concrete `Cap(P)`
   parameter its own grant discharge point: its static reach had to fit under
   its parameters' capabilities (checked here, by the now-deleted
   [check_fn_grants]).  That made a capability PARAMETER a per-function
   ceiling over everything the function transitively reached, so taking one
   forced a function to enumerate every other capability it touched or add a
   parameter for it — capability threading, which contradicts capabilities
   being module-scoped.  It is gone.  What remains: `needs` (Check 1), the
   per-module ceiling, and [check_main_grant] — none of them require passing
   a capability value to satisfy a check.

   [cap_reach_chain], which outlived the check that was its only caller, is
   now defined above [check_main_grant] (it moved from here in Task 8) and
   used by it to attribute a whole-program grant violation to the user's call
   chain — the same "who reaches what through whom" evidence this used to
   produce for a per-function violation, now serving the program-level one
   instead. *)

(* [MARCH_DUMP_CAP_ROWS=1] prints the solved row table to stderr, one function
   per line, sorted.  This exists to make the `unknown` REFUSAL's blast radius
   measurable rather than assumed: the design gate for stage C was "count how
   many functions carry a transitive unknown across the real stdlib before
   deciding the refusal's severity", and a claim like that needs a way to
   re-run it after any change to the seed walk. *)
let dump_cap_rows (env : env) : unit =
  match Sys.getenv_opt "MARCH_DUMP_CAP_ROWS" with
  | None | Some "" | Some "0" -> ()
  | Some _ ->
    let rows =
      Hashtbl.fold (fun k v acc -> (k, v) :: acc) (fn_capability_rows_tbl env) []
    in
    let rows = List.sort (fun (a, _) (b, _) -> String.compare a b) rows in
    let unknown_count =
      List.length
        (List.filter (fun (_, (r : March_caps.Cap_rows.row)) -> r.unknown) rows)
    in
    List.iter
      (fun (k, (r : March_caps.Cap_rows.row)) ->
         Printf.eprintf "cap-row %s caps=[%s] deps=[%s]%s\n" k
           (String.concat "," r.caps) (String.concat "," r.deps)
           (if r.unknown then " UNKNOWN" else ""))
      rows;
    Printf.eprintf "cap-row-summary total=%d unknown=%d\n" (List.length rows)
      unknown_count

(* The `--check`-side capability ceiling.  Closes the one route the four
   source-level checks miss: a stdlib-MEDIATED call (`File.read` rather than
   the builtin `file_read`), which Check 1b's direct-builtin scan does not see
   and Check 4's `use`-walk does not either (stdlib is ambient).  `--compile`
   already catches it via [March_tir.Cap_attrib] over emitted TIR; this brings
   the same rule to `--check`/`--check-json` without lowering.

   Sound-by-construction as a strict SUBSET of the `--compile` ceiling: it
   attributes a capability to a user module ONLY when a clear forward chain
   `M.f -> stdlib... -> builtin` exists, mirroring Cap_attrib's roll-up of
   transparent (stdlib) callees to the nearest user caller.  Anything it cannot
   see this way it leaves alone — under-reporting, never breaking a build
   `--compile` accepts.  It deliberately does NOT reproduce Cap_attrib's
   fail-closed [Unattributed] arm (indirect-call caps), which over-reports on
   closure-heavy code; `--compile` remains the complete check. *)
let check_stdlib_mediated_ceiling (env : env) (errors : Err.ctx)
    ~(entry_name : string) ~(entry_needs : string list)
    ~(module_spans : (string * Ast.span) list) : unit =
  (* [IO.Foreign]/[.Blocking] are emitted from the PRESENCE of an extern
     block, not an attributed call site — Check 5 already errors on an
     undeclared extern cap, and the `--compile` ceiling excludes them too. *)
  let is_foreign_cap c = c = "IO.Foreign" || c = "IO.Foreign.Blocking" in
  let is_stdlib q = Hashtbl.mem env.stdlib_fns q in
  let body_caps q = Option.value ~default:[] (Hashtbl.find_opt env.body_cap_closures q) in
  let refs q = Option.value ~default:[] (Hashtbl.find_opt env.fn_refs q) in
  (* Caps reachable from a STDLIB function through stdlib-only edges — its own
     body builtins plus those of the stdlib helpers it calls.  Stops at the
     first non-stdlib name (a user callee owns its own caps; an indirect
     callback is not a static edge).  Memoized; cycle-guarded. *)
  let reach_memo : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  let in_progress : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  let rec stdlib_reach q =
    match Hashtbl.find_opt reach_memo q with
    | Some r -> r
    | None ->
      if Hashtbl.mem in_progress q then []  (* cycle: contribute nothing yet *)
      else begin
        Hashtbl.replace in_progress q ();
        let acc =
          List.fold_left
            (fun acc r -> if is_stdlib r then stdlib_reach r @ acc else acc)
            (body_caps q) (refs q)
        in
        Hashtbl.remove in_progress q;
        let r = March_caps.Cap_lattice.normalize acc in
        Hashtbl.replace reach_memo q r;
        r
      end
  in
  (* Owner module of a qualified function name: its last-dot prefix, or the
     entry module for a bare name (the entry module's own functions are
     unprefixed, matching TIR's entry unwrap). *)
  let owner_of q =
    (* Mirror [Cap_attrib.owner_of] exactly, including the interface-impl case:
       an impl/interface-default method keys as `[Prefix.]Iface$Ty.method`, and
       the naive last-dot prefix would yield the SYNTHETIC module `Iface$Ty` —
       which no `needs` line can declare, so a correctly-declared program would
       get a spurious violation (masked today only by a downstream dummy-span
       filter — do not rely on that). The real owner is what precedes the
       mangled segment: the declaring module, or the entry module when nothing
       does. A user qname never contains `$`. *)
    if String.contains q '$' then
      let n =
        match String.index_opt q '$' with
        | Some j -> (
          match String.rindex_from_opt q j '.' with
          | Some i -> String.sub q 0 i
          | None -> "")
        | None -> q
      in
      if n = "" then entry_name else n
    else
      match String.rindex_opt q '.' with
      | Some i -> String.sub q 0 i
      | None -> entry_name
  in
  let declared m =
    if m = entry_name then entry_needs
    else Option.value ~default:[] (List.assoc_opt m env.module_caps)
  in
  let covered m c = List.exists (fun need -> cap_subsumes need c) (declared m) in
  let span_of m =
    Option.value ~default:Ast.dummy_span (List.assoc_opt m module_spans)
  in
  (* One (module, cap) per report.  A user function's OWN direct builtins are
     deliberately excluded (Check 1b already reports those); only the
     stdlib-mediated additions are attributed here, so the two checks never
     double-report the same cap. *)
  let reported : (string * string, unit) Hashtbl.t = Hashtbl.create 16 in
  (* Match `--compile`'s reachability exactly, or this over-reports on dead
     code.  [March_tir.Dce] roots reachability at `main` WHEN A `main` EXISTS
     (a function `main` never calls is genuinely dead and its stdlib-mediated
     use is pruned before [Cap_attrib] ever sees it); only a module WITHOUT a
     `main` falls back to treating every user function as a root (a library
     checked on its own — its public functions are its callable surface).  We
     mirror both: reachable-from-`main` when present, else all user functions.
     Getting this wrong is the difference between a strict subset and a false
     positive on a half-wired helper. *)
  let has_main =
    Hashtbl.fold
      (fun k _ found ->
         found || k = "main"
         || (String.length k > 5 && String.sub k (String.length k - 5) 5 = ".main"))
      env.fn_refs false
  in
  let reachable : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  if has_main then begin
    let q = Queue.create () in
    let seed k =
      if not (Hashtbl.mem reachable k) then
        (Hashtbl.replace reachable k (); Queue.push k q)
    in
    (* Seed with the SAME unconditional roots [March_tir.Dce.root_names] keeps
       alongside `main`: the entry itself, module-level `let`s and
       `_migrate_state` functions (always-run setup effects). Missing any of
       these would silently drop a violation `--compile` still reports. *)
    Hashtbl.iter
      (fun k _ ->
         if k = "main"
            || (String.length k > 5 && String.sub k (String.length k - 5) 5 = ".main")
            || is_migrate_fn_name k
            || Hashtbl.mem env.ceiling_extra_roots k
         then seed k)
      env.fn_refs;
    while not (Queue.is_empty q) do
      let n = Queue.pop q in
      List.iter
        (fun r ->
           if not (Hashtbl.mem reachable r) then begin
             Hashtbl.replace reachable r ();
             Queue.push r q
           end)
        (refs n)
    done
  end;
  let is_reachable k = (not has_main) || Hashtbl.mem reachable k in
  let user_fns =
    Hashtbl.fold
      (fun k _ acc -> if is_stdlib k || not (is_reachable k) then acc else k :: acc)
      env.fn_refs []
  in
  List.iter
    (fun f ->
       let owner = owner_of f in
       let attributed =
         List.fold_left
           (fun acc r -> if is_stdlib r then stdlib_reach r @ acc else acc)
           [] (refs f)
       in
       List.iter
         (fun c ->
            if (not (is_foreign_cap c)) && not (covered owner c)
               && not (Hashtbl.mem reported (owner, c))
            then begin
              Hashtbl.replace reported (owner, c) ();
              let sp = span_of owner in
              let msg =
                Printf.sprintf
                  "module `%s` uses `%s` but does not declare `needs %s`.\n\
                   help: add `needs %s` to the module body."
                  owner c c c
              in
              (* Only attach the machine-applicable fix when the owner's span is
                 real and in this file. A module absent from [module_spans] (a
                 cross-file dependency) falls back to [dummy_span]
                 (start_line = 0); inserting `needs` at line 0 of the ENTRY file
                 would write it into the wrong module — see the latent-trap note
                 in specs/todos/2026-08-14-cap-ceiling-under-check-needs-body-only-closure.md.
                 Under-deliver the fix there rather than mis-place it. *)
              if sp == Ast.dummy_span || sp.Ast.start_line <= 0 then
                Err.error errors ~span:sp msg
              else
                (* Indent the inserted line to the owner's own declaration
                   column (the span points at its first `needs`/header), so a
                   nested module's fix lands at the right depth rather than a
                   hardcoded two spaces. *)
                let indent = String.make (max 0 (sp.Ast.start_col)) ' ' in
                Err.error_with_fix errors ~span:sp
                  ~code:("cap_ceiling:" ^ c)
                  ~fix:(Err.FInsert { after_line = sp.Ast.start_line;
                                      text = indent ^ "needs " ^ c })
                  msg
            end)
         (March_caps.Cap_lattice.normalize attributed))
    user_fns

let check_module_core ?(errors = Err.create ()) ?seed_env (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let type_map = match seed_env with
    | Some (se : env) -> se.type_map
    | None -> Hashtbl.create 256
  in
  (* Helper: recursively collect qualified "Mod.fn" names from nested DMod
     declarations so that cross-module forward references are pre-bound in
     pass 1. This mirrors the eval.ml global module_registry approach.
     Only pre-binds public functions to preserve private-access restrictions. *)
  let rec prebind_mod_members ?(opaque = StringSet.empty) prefix env decls =
    (* Opaque type names per submodule, taken from a sibling `sig <Mod>`
       declaration.  A type a signature exports opaquely (`type Stack a`, no
       constructors) must keep its constructors HIDDEN outside the module — so
       the bare-constructor seeding below is suppressed for them, matching the
       Pass-2 export filter (:7467) and preserving order-independence (hidden
       ctors stay unreferenceable cross-module by design). *)
    let sub_opaque =
      List.fold_left (fun m d -> match d with
        | Ast.DSig (sname, sdef, _) ->
          let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                     StringSet.empty sdef.Ast.sig_types in
          StrMap.add sname.Ast.txt ts m
        | _ -> m) StrMap.empty decls in
    List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
          let qname = prefix ^ "." ^ def.fn_name.txt in
          if StrMap.mem qname e.vars then e
          else
            let sch = match prebind_fn_scheme def with
              | Some s -> s
              | None -> Mono (fresh_var 1)
            in
            bind_var qname sch e
        | Ast.DType (vis, name, params, typedef, _)
        | Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
          let qname = prefix ^ "." ^ name.txt in
          let e1 =
            let e = if StrMap.mem qname e.types then e
              else { e with types = StrMap.add qname (List.length params) e.types } in
            (* Register the BARE type name too, not just the module-qualified
               one.  A submodule of a cyclically-dependent module set (e.g.
               `Conduit.WorkflowContext` referencing `WorkflowError`, defined in
               parent `Conduit`) has no `use`/`import` and resolves the parent's
               types by bare name.  With only the qualified key seeded in Pass 1,
               the bare form was registered lazily during the definer's Pass-2
               check — so a referrer checked BEFORE the definer failed, making
               resolution depend on check order (which a cyclic module graph
               cannot make deterministic).  Top-level types (:8929) and records
               (below) already seed the bare name here; this closes the gap for
               nested-module types.  Don't clobber a bare name already bound by a
               top-level/entry definition. *)
            if StrMap.mem name.txt e.types then e
            else { e with types = StrMap.add name.txt (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 (* [ci_type] is the BARE type name, matching check_decl (:7217)
                    and the top-level Pass-1 path (:8929).  Using the qualified
                    [qname] here was the sole site producing a qualified nominal
                    type for a constructor: a cross-module fully-qualified
                    reference (`Conduit.Telemetry.JobEnqueued`) resolved through
                    this prebind entry BEFORE the definer's Pass-2 check yielded
                    `TCon("Conduit.Telemetry.ConduitTelemetryEvent")`, which does
                    not unify with the bare `ConduitTelemetryEvent` that every
                    signature uses ("expected X but got Mod.X").  The type side
                    already canonicalizes qualified->bare (see [canon_name]); the
                    constructor side must agree by carrying the bare type. *)
                 let ci = { ci_type = name.txt; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                            ci_is_actor_msg = false } in
                 (* Only seed the bare module-qualified ctor key (`Mod.Ctor`)
                    for PUBLIC constructors.  A private constructor — notably an
                    `opaque type`'s, whose variants the parser marks Private
                    while keeping the type Public — must stay unreferenceable
                    from a sibling module, or `Mod.Ctor(...)` from outside would
                    typecheck clean and bypass the opacity boundary.  The
                    disambiguated `Mod.Type.Ctor` key below is already gated the
                    same way; the Pass-2 DMod export step also keeps only public
                    ctors, but it StrMap.unions over this Pass-1 entry, so an
                    ungated bare key here would survive and defeat that filter. *)
                 let acc =
                   if v.var_vis = Ast.Public
                   then { acc with ctors = add_ctor qctor ci acc.ctors }
                   else acc in
                 (* Also register the disambiguated module.type.ctor form
                    ("Md.Inline.Text").  A wrapped sibling gets this key from the
                    DMod export step, but the ENTRY module is unwrapped (top
                    level) so Pass 1b is the only place it is registered — a
                    sibling that writes `Md.Inline.Text` to disambiguate a shared
                    constructor name would otherwise fail to resolve it.  The
                    ci_type is the BARE type name, matching the constructor's
                    lowering key, so it cannot perturb codegen. *)
                 if v.var_vis <> Ast.Public then acc
                 else
                   let type_qctor = qname ^ "." ^ v.var_name.txt in
                   let type_ci = { ci_type = name.txt; ci_params = param_names;
                                   ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                                   ci_is_actor_msg = false } in
                   let acc = { acc with ctors = add_ctor type_qctor type_ci acc.ctors } in
                   (* A type exported opaquely by a sibling `sig` keeps its
                      constructors hidden: don't seed the short (bare / bare-type)
                      forms that would let a cross-module reference reach them. *)
                   if StringSet.mem name.txt opaque then acc
                   else
                     (* The disambiguation form written in code uses the BARE type
                        name (`WorkflowError.Failed`), not the module-qualified
                        type (`Conduit.WorkflowError.Failed`).  The top-level path
                        (:8929 `qual_key`) seeds this bare-type key; nested-module
                        types need it too, else a cross-module `Type.Ctor`
                        reference stays order-dependent even after the bare-ctor
                        key is seeded. *)
                     let bare_type_qctor = name.txt ^ "." ^ v.var_name.txt in
                     let acc = { acc with ctors = add_ctor bare_type_qctor type_ci acc.ctors } in
                     (* Seed the BARE constructor key with the same [ci_type =
                        name.txt] the top-level path (:8929) and check_decl use, so
                        a cross-module bare reference (e.g. `StorageError` from a
                        sibling of the defining `Conduit` module) resolves
                        regardless of check order.  add_ctor dedups by ci_type, so
                        this is a no-op once the definer's Pass-2 check registers
                        the same bare key — it does not manufacture a spurious
                        "defined by multiple types" ambiguity. *)
                     { acc with ctors = add_ctor v.var_name.txt type_ci acc.ctors }
               ) e1 variants
           | Ast.TDRecord fields ->
             (* Register both local name and fully-qualified name in env.records
                so cross-module type annotations like "Conduit.JobRow" resolve
                to a structural TRecord, not an opaque TCon. *)
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
             register_record_name ~name:name.txt (List.map fst field_pairs);
             register_record_name ~name:qname (List.map fst field_pairs);
             let e2 = { e1 with records = StrMap.add name.txt (param_names, field_pairs) e1.records } in
             { e2 with records = StrMap.add qname (param_names, field_pairs) e2.records }
           | _ -> e1)
        | Ast.DInterface (idef, _) -> prebind_interface_decl ~prefix idef e
        | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
          let child_opaque = Option.value ~default:StringSet.empty
              (StrMap.find_opt mname.Ast.txt sub_opaque) in
          prebind_mod_members ~opaque:child_opaque (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) env decls
  in
  (* Pass 1: forward-reference placeholders for functions and type/ctor names *)
  (* Opaque type names per top-level module, from sibling `sig <Mod>` decls: the
     entry module is unwrapped so its `sig`/`mod` pairs are siblings here, not
     inside [prebind_mod_members] (see the same map built there). *)
  let top_sub_opaque =
    List.fold_left (fun m d -> match d with
      | Ast.DSig (sname, sdef, _) ->
        let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                   StringSet.empty sdef.Ast.sig_types in
        StrMap.add sname.Ast.txt ts m
      | _ -> m) StrMap.empty m.Ast.mod_decls in
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        (* Record the name as locally defined so bulk imports cannot clobber
           its binding (local definitions shadow imports — see env.local_fns). *)
        let arity = match def.fn_clauses with
          | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
        (* Don't shadow existing bindings (e.g., builtins) with mono forward refs.
           bind_var FIRST (it clears any shadowed fn_arities entry), then register
           this fn's own arity so the entry survives — see bind_var's comment. *)
        let env =
          if StrMap.mem def.fn_name.txt env.vars then env
          else bind_var def.fn_name.txt (Mono (fresh_var 1)) env in
        { env with local_fns = StrMap.add def.fn_name.txt () env.local_fns;
                   fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) env.fn_arities }
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Pre-bind all public qualified names "ModName.fn" so that sibling
           modules that reference each other don't fail during pass 2. *)
        let child_opaque = Option.value ~default:StringSet.empty
            (StrMap.find_opt mname.Ast.txt top_sub_opaque) in
        let env = prebind_mod_members ~opaque:child_opaque mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
            | _ -> e
          ) env inner_decls
      | Ast.DType (_, name, params, typedef, _)
      | Ast.DAlwaysLinearType (_, name, params, typedef, _) ->
        let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_module  = m.Ast.mod_name.txt
                        ; ci_vis     = v.var_vis
                        ; ci_is_actor_msg = false } in
               (* Register the type-qualified key ("TypeName.CtorName") in this
                  forward-reference pass, not just in check_decl: sibling DMods
                  are typechecked before the entry module's own DTypes are
                  reached, so a sibling that imports the entry and
                  disambiguates with `Expr.Col` would otherwise fail to
                  resolve the constructor. *)
               let qual_key = name.txt ^ "." ^ v.var_name.txt in
               { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           register_record_name ~name:name.txt (List.map fst field_pairs);
           { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
         | _ -> env1)
      | Ast.DActor (_, name, actor, _) ->
        (* Register actor name as a zero-arg constructor and message ctors.
           Same arity fix as in check_decl: include unannotated params as
           unique TyVar placeholders so constructor arity is always correct. *)
        let env1 = { env with ctors =
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                              ci_is_actor_msg = false }
            env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.mapi (fun i (p : Ast.param) ->
                match p.param_ty with
                | Some ty -> ty
                | None ->
                  Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                              span = p.param_name.span }
              ) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                       ci_is_actor_msg = true } in
            { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces }
      | Ast.DImpl (idef, _) ->
        register_impl_shape env idef ~decl_module:m.Ast.mod_name.txt
      | Ast.DMod (mname, _, inner_decls, _) ->
        (* Interface implementations declared in sibling modules must be
           visible unit-wide regardless of the order modules are checked in:
           CInterface constraints discharge at declaration boundaries, so an
           impl that is only registered when its defining module is reached
           cannot satisfy constraints from modules checked earlier. *)
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
            | _ -> e
          ) env inner_decls
      | _ -> env
    ) (match seed_env with
        | Some se -> { se with errors; type_map }
        | None -> base_env errors type_map)
      m.Ast.mod_decls
  in
  (* Pass 1b: the entry module's own declarations live at the TOP LEVEL of the
     combined module (only the imported sibling modules are wrapped in [DMod]).
     They were registered under their BARE names above, but sibling modules
     refer to the entry's types with the entry module's QUALIFIED prefix
     (`Config.Site`).  Without a qualified binding those references fall through
     to the module registry, which has no record-field information and so
     resolves a record type to a NOMINAL `TCon` that will not unify with the
     entry module's own structural use of it.  Pre-bind the entry's top-level
     declarations under its module name exactly as a wrapped sibling would be,
     so qualified and unqualified references resolve to the same type.  Skip
     [DMod]s so imported modules are not double-prefixed. *)
  let pre_env =
    let top_level = List.filter
      (function Ast.DMod _ -> false | _ -> true) m.Ast.mod_decls in
    prebind_mod_members m.Ast.mod_name.txt pre_env top_level
  in
  (* Pass 2: full checking *)
  let pre_env =
    { pre_env with
      current_module = m.Ast.mod_name.txt;
      enclosing_package =
        (if pre_env.enclosing_package = "" then m.Ast.mod_name.txt
         else pre_env.enclosing_package) } in
  let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
  (* Part 1: the cap_narrow proof-cap forge is closed by the [unify] hook
     ([cap_producer_ivars]), which fires at the exact moment a cap_narrow-derived
     inner var is bound to a nominal proof cap — position- and flow-independent
     (direct, let-generalized, or laundered through a polymorphic function).  A
     post-checking recorded-node sweep is NOT used for cap_narrow: a laundered
     value leaves the recorded node unbound, which the sweep cannot distinguish
     from legitimate laundered IO narrowing.
     Part 2: enforce the mint_cap gate on every recorded site (result now pinned;
     enclosing fn/module context captured at record time). Shared ref → one sweep
     at the entry module covers every nested module's sites. *)
  check_mint_cap_sites final_env;
  check_json_cap_sites final_env;
  check_cap_narrow_sites final_env;
  (* Validate capability declarations for the top-level module *)
  (* The entry module's own name is NOT a prefix segment for cap-closure keys:
     TIR unwraps the entry module (see [lib/tir/lower.ml]'s [mod_prefix]
     accumulation, which starts empty at the entry level), so top-level
     functions are keyed by their bare name and nested DMod functions are
     keyed starting from that nested module's own name (e.g. "Lib.Sub.f"),
     never "EntryName.Lib.Sub.f". *)
  check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls
    ~cap_qname_prefix:"";
  (* R1: hold the program's capability closure under main's grant. *)
  (* [check_main_grant] deliberately does not consult [deps]/[unknown] (see
     its own comment on the [unknown]-ignoring arm), and after stage C's
     removal nothing else reads them from THIS table either — [dump_cap_rows]
     solves its own copy independently, gated behind [MARCH_DUMP_CAP_ROWS], so
     it does not benefit from (or need) this one being solved with rows.
     [~with_rows:false] keeps this call at the caps-only fixpoint, which is
     what [check_main_grant] actually reads — this was the pre-stage-C cost
     and stays that with stage C gone. *)
  let cap_rows = fn_capability_rows_tbl ~with_rows:false final_env in
  dump_cap_rows final_env;
  check_main_grant ~rows:cap_rows final_env m.Ast.mod_decls;
  (* The `--check`-side capability ceiling (opt-in via [cap_strict_ceiling],
     set by the driver on the `--check`/`--check-json` path). Build a
     module -> diagnostic-span map: each module's first [DNeeds] span, or its
     header span if it declares none, so a violation and its `needs` fix land
     where a user would add the line. The entry module is keyed by its own
     name to match [owner_of]'s resolution of bare (entry-unwrapped) names. *)
  if !cap_strict_ceiling then begin
    let module_spans = ref [] in
    let first_needs_span decls hdr =
      let rec go = function
        | Ast.DNeeds (_, sp) :: _ -> sp
        | _ :: rest -> go rest
        | [] -> hdr
      in
      go decls
    in
    let rec collect prefix decls hdr =
      let name = if prefix = "" then m.Ast.mod_name.Ast.txt else prefix in
      module_spans := (name, first_needs_span decls hdr) :: !module_spans;
      List.iter
        (function
          | Ast.DMod (n, _, inner, msp) ->
            let p = if prefix = "" then n.Ast.txt else prefix ^ "." ^ n.Ast.txt in
            collect p inner msp
          | _ -> ())
        decls
    in
    collect "" m.Ast.mod_decls m.Ast.mod_name.Ast.span;
    check_stdlib_mediated_ceiling final_env errors
      ~entry_name:m.Ast.mod_name.Ast.txt
      ~entry_needs:final_env.mod_needs
      ~module_spans:!module_spans
  end;
  (* Validate cap no_panic invariant if declared *)
  if final_env.no_panic_mod then
    check_no_panic_module errors final_env m.Ast.mod_decls;
  (* Validate cap pure invariant if declared *)
  if final_env.pure_mod then
    check_pure_module errors final_env m.Ast.mod_decls;
  (* Validate cap no_extern invariant if declared *)
  if final_env.no_extern_mod then
    check_no_extern_module errors final_env m.Ast.mod_decls;
  (* Validate cap deterministic invariant if declared *)
  if final_env.deterministic_mod then
    check_deterministic_module errors final_env m.Ast.mod_decls;
  (* Warn about any unused imports or aliases *)
  warn_unused_imports final_env;
  (* Pass 3: tail-call enforcement *)
  enforce_tail_calls_in_decls ~file_mod:m.Ast.mod_name.txt errors m.Ast.mod_decls;
  (errors, type_map, final_env)

let check_module ?errors (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let (errs, type_map, _env) = check_module_core ?errors m in
  (errs, type_map)

(** Like [check_module], but also returns every resolved call/ctor/type
    reference recorded during checking — used by [forge search --callers].
    Order is call-order, most-recent-first is reversed back to source order. *)
let check_module_with_refs ?errors (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * ref_record list =
  let (errs, type_map, final_env) = check_module_core ?errors m in
  (errs, type_map, List.rev !(final_env.refs))

(** Like [check_module] but starts from a pre-built environment.
    Used by the REPL JIT to typecheck user expressions incrementally
    without re-typechecking stdlib on every input.

    [env] should be the environment produced by loading stdlib
    (via [base_env] + repeated [check_decl] calls).  The [type_map]
    inside [env] is mutated in place with new span→type entries. *)

(* Side channel for [check_module_with_env_full]: the last final env produced
   by [check_module_with_env].  Set at the end of pass 2; read immediately by
   the [_full] wrapper.  Single-threaded use only (LSP analyse / REPL JIT). *)
let last_with_env_final : env ref = ref (make_env (Err.create ()) (Hashtbl.create 0))

let check_module_with_env (env : env) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  (* R2: the REPL has no entry point to be granted the root capability from, so
     [root_cap] stays nameable there.  This entry point is the REPL's — its
     only caller is [lib/jit/repl_jit.ml] — which is what makes it the right
     place to carry the exemption rather than a flag threaded from the CLI. *)
  let env = { env with root_cap_allowed = true } in
  let errors = env.errors in
  let type_map = env.type_map in
  let rec prebind_mod_members_inc ?(opaque = StringSet.empty) prefix e decls =
    (* See [prebind_mod_members]: suppress bare-constructor seeding for types a
       sibling `sig` exports opaquely. *)
    let sub_opaque =
      List.fold_left (fun m d -> match d with
        | Ast.DSig (sname, sdef, _) ->
          let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                     StringSet.empty sdef.Ast.sig_types in
          StrMap.add sname.Ast.txt ts m
        | _ -> m) StrMap.empty decls in
    List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
          let qname = prefix ^ "." ^ def.fn_name.txt in
          if StrMap.mem qname e.vars then e
          else bind_var qname (Mono (fresh_var 0)) e
        | Ast.DType (vis, name, params, typedef, _)
        | Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
          let qname = prefix ^ "." ^ name.txt in
          let e1 =
            let e = if StrMap.mem qname e.types then e
              else { e with types = StrMap.add qname (List.length params) e.types } in
            (* Register the BARE type name too, not just the module-qualified
               one.  A submodule of a cyclically-dependent module set (e.g.
               `Conduit.WorkflowContext` referencing `WorkflowError`, defined in
               parent `Conduit`) has no `use`/`import` and resolves the parent's
               types by bare name.  With only the qualified key seeded in Pass 1,
               the bare form was registered lazily during the definer's Pass-2
               check — so a referrer checked BEFORE the definer failed, making
               resolution depend on check order (which a cyclic module graph
               cannot make deterministic).  Top-level types (:8929) and records
               (below) already seed the bare name here; this closes the gap for
               nested-module types.  Don't clobber a bare name already bound by a
               top-level/entry definition. *)
            if StrMap.mem name.txt e.types then e
            else { e with types = StrMap.add name.txt (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 (* [ci_type] is the BARE type name, matching check_decl (:7217)
                    and the top-level Pass-1 path (:8929).  Using the qualified
                    [qname] here was the sole site producing a qualified nominal
                    type for a constructor: a cross-module fully-qualified
                    reference (`Conduit.Telemetry.JobEnqueued`) resolved through
                    this prebind entry BEFORE the definer's Pass-2 check yielded
                    `TCon("Conduit.Telemetry.ConduitTelemetryEvent")`, which does
                    not unify with the bare `ConduitTelemetryEvent` that every
                    signature uses ("expected X but got Mod.X").  The type side
                    already canonicalizes qualified->bare (see [canon_name]); the
                    constructor side must agree by carrying the bare type. *)
                 let ci = { ci_type = name.txt; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                            ci_is_actor_msg = false } in
                 (* Only seed the bare module-qualified ctor key (`Mod.Ctor`)
                    for PUBLIC constructors.  A private constructor — notably an
                    `opaque type`'s, whose variants the parser marks Private
                    while keeping the type Public — must stay unreferenceable
                    from a sibling module, or `Mod.Ctor(...)` from outside would
                    typecheck clean and bypass the opacity boundary.  The
                    disambiguated `Mod.Type.Ctor` key below is already gated the
                    same way; the Pass-2 DMod export step also keeps only public
                    ctors, but it StrMap.unions over this Pass-1 entry, so an
                    ungated bare key here would survive and defeat that filter. *)
                 let acc =
                   if v.var_vis = Ast.Public
                   then { acc with ctors = add_ctor qctor ci acc.ctors }
                   else acc in
                 (* Also register the disambiguated module.type.ctor form
                    ("Md.Inline.Text").  A wrapped sibling gets this key from the
                    DMod export step, but the ENTRY module is unwrapped (top
                    level) so Pass 1b is the only place it is registered — a
                    sibling that writes `Md.Inline.Text` to disambiguate a shared
                    constructor name would otherwise fail to resolve it.  The
                    ci_type is the BARE type name, matching the constructor's
                    lowering key, so it cannot perturb codegen. *)
                 if v.var_vis <> Ast.Public then acc
                 else
                   let type_qctor = qname ^ "." ^ v.var_name.txt in
                   let type_ci = { ci_type = name.txt; ci_params = param_names;
                                   ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                                   ci_is_actor_msg = false } in
                   let acc = { acc with ctors = add_ctor type_qctor type_ci acc.ctors } in
                   (* A type exported opaquely by a sibling `sig` keeps its
                      constructors hidden: don't seed the short (bare / bare-type)
                      forms that would let a cross-module reference reach them. *)
                   if StringSet.mem name.txt opaque then acc
                   else
                     (* The disambiguation form written in code uses the BARE type
                        name (`WorkflowError.Failed`), not the module-qualified
                        type (`Conduit.WorkflowError.Failed`).  The top-level path
                        (:8929 `qual_key`) seeds this bare-type key; nested-module
                        types need it too, else a cross-module `Type.Ctor`
                        reference stays order-dependent even after the bare-ctor
                        key is seeded. *)
                     let bare_type_qctor = name.txt ^ "." ^ v.var_name.txt in
                     let acc = { acc with ctors = add_ctor bare_type_qctor type_ci acc.ctors } in
                     (* Seed the BARE constructor key with the same [ci_type =
                        name.txt] the top-level path (:8929) and check_decl use, so
                        a cross-module bare reference (e.g. `StorageError` from a
                        sibling of the defining `Conduit` module) resolves
                        regardless of check order.  add_ctor dedups by ci_type, so
                        this is a no-op once the definer's Pass-2 check registers
                        the same bare key — it does not manufacture a spurious
                        "defined by multiple types" ambiguity. *)
                     { acc with ctors = add_ctor v.var_name.txt type_ci acc.ctors }
               ) e1 variants
           | Ast.TDRecord fields ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
             register_record_name ~name:name.txt (List.map fst field_pairs);
             register_record_name ~name:qname (List.map fst field_pairs);
             let e2 = { e1 with records = StrMap.add name.txt (param_names, field_pairs) e1.records } in
             { e2 with records = StrMap.add qname (param_names, field_pairs) e2.records }
           | _ -> e1)
        | Ast.DInterface (idef, _) -> prebind_interface_decl ~prefix idef e
        | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
          let child_opaque = Option.value ~default:StringSet.empty
              (StrMap.find_opt mname.Ast.txt sub_opaque) in
          prebind_mod_members_inc ~opaque:child_opaque (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) e decls
  in
  (* Pass 1: forward-reference placeholders for new declarations *)
  let top_sub_opaque =
    List.fold_left (fun m d -> match d with
      | Ast.DSig (sname, sdef, _) ->
        let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                   StringSet.empty sdef.Ast.sig_types in
        StrMap.add sname.Ast.txt ts m
      | _ -> m) StrMap.empty m.Ast.mod_decls in
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        if StrMap.mem def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 0)) env
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Register the sibling module's members, then its interface impls — an
           impl declared in a sibling must satisfy constraints unit-wide
           regardless of check order (mirrors check_module_core's pass 1). *)
        let child_opaque = Option.value ~default:StringSet.empty
            (StrMap.find_opt mname.Ast.txt top_sub_opaque) in
        let env = prebind_mod_members_inc ~opaque:child_opaque mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
            | _ -> e
          ) env inner_decls
      | Ast.DType (_, name, params, typedef, _)
      | Ast.DAlwaysLinearType (_, name, params, typedef, _) ->
        let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_module  = m.Ast.mod_name.txt
                        ; ci_vis     = v.var_vis
                        ; ci_is_actor_msg = false } in
               (* Register the type-qualified key ("TypeName.CtorName") in this
                  forward-reference pass, not just in check_decl: sibling DMods
                  are typechecked before the entry module's own DTypes are
                  reached, so a sibling that imports the entry and
                  disambiguates with `Expr.Col` would otherwise fail to
                  resolve the constructor. *)
               let qual_key = name.txt ^ "." ^ v.var_name.txt in
               { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           register_record_name ~name:name.txt (List.map fst field_pairs);
           { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
         | _ -> env1)
      | Ast.DActor (_, name, actor, _) ->
        let env1 = { env with ctors =
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                              ci_is_actor_msg = false }
            env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.mapi (fun i (p : Ast.param) ->
                match p.param_ty with
                | Some ty -> ty
                | None ->
                  Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                              span = p.param_name.span }
              ) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                       ci_is_actor_msg = true } in
            { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces }
      | _ -> env
    ) env m.Ast.mod_decls
  in
  (* Pass 2: full checking of new declarations *)
  let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
  last_with_env_final := final_env;
  (* Pass 3: tail-call enforcement *)
  enforce_tail_calls_in_decls ~file_mod:m.Ast.mod_name.txt errors m.Ast.mod_decls;
  (errors, type_map)

(** Like [check_module_with_env] but also returns the final typing env.
    The LSP needs the env (ctors/vars/types/interfaces/impls) for completion
    and constructor enumeration; the non-[_full] form discards it. *)
let check_module_with_env_full (env : env) (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let (errs, tm) = check_module_with_env env m in
  (errs, tm, !last_with_env_final)

(** Like [check_module] but also returns the final typing environment.
    Used by the LSP for hover/completion.  Delegates to [check_module_core]
    so editor diagnostics run the EXACT same passes as `march --check` —
    a reduced duplicate here previously skipped the pass-1 type/ctor/record
    prebinding, so qualified type annotations (Bastion.Channel.ChannelConn)
    failed to resolve only in the LSP. *)
let check_module_full ?(errors = Err.create ()) ?seed_env (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  check_module_core ~errors ?seed_env m

let check_letq_repl (env : env) (p : Ast.pattern) (e : Ast.expr) : env =
  let env' = enter_level env in
  let result_ty = infer_expr env' e in
  let t_ok  = fresh_var env'.level in
  let t_err = fresh_var env'.level in
  let sp = span_of_expr e in
  unify env' ~span:sp
    ~reason:(Some (RBuiltin "The right-hand side of `let?` must be a Result value."))
    result_ty (t_result t_ok t_err);
  let bindings, pat_ty = infer_pattern ~expected:t_ok env' p in
  unify env' ~span:sp ~reason:(Some (RLetBind sp)) t_ok pat_ty;
  ignore (leave_level env');
  bind_vars bindings env

(** REPL counterpart of [ELetStar]'s [infer_expr] arm: bind [p] to the payload
    of [e]'s monadic value so the binding persists across prompts.

    Shares [ELetStar]'s resolution EXACTLY -- current scope first, then the
    stdlib module loader -- so `let* x = e` at the prompt can never resolve a
    different `flat_map` than the same line inside a function would.  There is
    no continuation at a prompt, so unlike [ELetStar] this only needs the
    payload type [A] from `flat_map`'s `M(a) -> (a -> M(b)) -> M(b)` shape;
    the result type is discarded.  See [lib/repl/repl.ml]'s [ReplLetStar] arm
    for the matching runtime semantics (bind the FIRST value yielded). *)
let check_letstar_repl (env : env) (p : Ast.pattern) (e : Ast.expr) : env =
  let env' = enter_level env in
  let result_ty = infer_expr env' e in
  let sp = span_of_expr e in
  let bindings_opt =
    match repr result_ty with
    | TCon (head_name, _) ->
      let flat_map_name = head_name ^ ".flat_map" in
      let env'', scheme_opt =
        match lookup_var flat_map_name env' with
        | Some sc -> env', Some sc
        | None    -> resolve_qualified_var flat_map_name env'
      in
      (match scheme_opt with
       | None ->
         Err.error env''.errors ~span:sp
           (Printf.sprintf
              "`let*` needs `%s`, but it doesn't exist.\n\
               Define `flat_map(x : %s(a), f : a -> %s(b)) : %s(b)` in a \
               module named `%s` to make `let*` work with `%s`."
              flat_map_name head_name head_name head_name head_name head_name);
         None
       | Some scheme ->
         (match repr (instantiate env''.level env'' scheme) with
          | TArrow (m_arg, TArrow (TArrow (a_ty, _), _)) ->
            unify env'' ~span:sp
              ~reason:(Some (RBuiltin
                (Printf.sprintf
                   "The right-hand side of `let*` must match `%s`'s own type."
                   flat_map_name)))
              result_ty m_arg;
            let bindings, pat_ty = infer_pattern ~expected:a_ty env'' p in
            unify env'' ~span:sp ~reason:(Some (RLetBind sp)) a_ty pat_ty;
            Some bindings
          | _ ->
            Err.error env''.errors ~span:sp
              (Printf.sprintf
                 "`%s` doesn't have the shape `let*` needs: \
                  `%s(a) -> (a -> %s(b)) -> %s(b)`."
                 flat_map_name head_name head_name head_name);
            None))
    | _ ->
      Err.error env'.errors ~span:sp
        "`let*`'s right-hand side must have a concrete type (e.g. `Option(a)`, \
         `Result(a, e)`) so `let*` can find its `flat_map` — its type could \
         not be determined here.";
      None
  in
  ignore (leave_level env');
  match bindings_opt with
  | Some bindings -> bind_vars bindings env
  | None -> env
