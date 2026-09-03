(** Refinement checking, §16–§18: postconditions.

    Moved VERBATIM out of [Refine_check] (R5 of
    [specs/plans/2026-08-28-refine-check-decomposition.md]):

      §16 Postcondition checking
      §17 Postconditions by induction
      §18 Function-level postcondition entry points and gating

    The mirror of [Refine_call]'s §15: where [check_call] proves a callee's
    PREconditions at a call site, [check_post] proves a function's return
    refinement holds on every tail, and §17 discharges the recursive cases by
    structural induction.

    [check_post] is invoked twice per refined-return function — once from the
    [gate_unverified_posts] pre-pass with [~emit:false], once from the walk
    with [emit = true] — and both are threaded as [~record:emit], so only the
    reporting run records an outcome and no postcondition is counted twice.
    Preserve that pairing when touching anything here; the obligation COUNTS
    are what [scripts/refine-oracle.sh] pins.

    Verify against the REJECT corpus. Forcing [check_post] to return [true]
    (every postcondition "holds") leaves all 298 of refine-oracle's accepting
    fixtures byte-identical and is caught only by
    `dune build @types-check --force`. Measured. *)

include Refine_call

(* =================================================================
   §16 Postcondition checking
   ================================================================= *)

(* ── Postconditions: a function's return value must satisfy its return
   refinement.  We check each *tail* expression (a return position) under the
   path/scope reaching it, with the same definite-failure soundness stance. ── *)

(* The return refinements [check_post] can discharge DIRECTLY: an Int return, or
   a record return (whose SMT sort name is reported so [check_post] can reflect
   `_.field`).  A variant-ADT return is deliberately absent — it is proven, when
   it can be, by [check_post_induction] instead. *)
let return_refine_ext (fd : A.fn_def) : (string * A.expr * string option) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_bool_base base ->
    Some (binder_name binder, pred, Some bool_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_float_base base ->
    Some (binder_name binder, pred, Some float_sort)
  | Some (A.TyRefine (A.TyCon ({ A.txt = name; _ }, []) as base, binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* Return-position expressions of a body, each with the path reaching it. *)
let rec tails (path : (A.expr * bool) list) (e : A.expr) : ((A.expr * bool) list * A.expr) list =
  match e with
  | A.EBlock (es, _) ->
    (match List.rev es with
     | last :: _ ->
       (* A `let` before the tail REBINDS its names, so any fact the path
          context holds about them is about the outer value — retire it
          (see [path_shadow]). *)
       let path =
         List.fold_left
           (fun p e ->
             match e with
             | A.ELet (b, _) -> path_shadow p (pat_binders b.A.bind_pat)
             | _ -> p)
           path es
       in
       tails path last
     | [] -> [ (path, e) ])
  | A.EIf (c, t, el, _) -> tails ((c, false) :: path) t @ tails ((c, true) :: path) el
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> tails ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let path = path_shadow path (pat_binders br.A.branch_pat) in
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        tails p br.A.branch_body)
      branches
  | _ -> [ (path, e) ]

(* Facts true throughout the body: each refined param contributes its predicate. *)
(* Returns (decls, assumptions, has_record).
   Int entries: declare an SInt const, reflect predicate over it.
   Record entries: declare a datatype const (SData sort_name), reflect the
   predicate with a field resolver so `s.field` becomes the SMT selector
   applied to the opaque const.  `has_record` is true when any record entry
   is present — signals check_post to include the datatype preamble. *)
let scope_facts (sc : scope) : (string * Smt.sort) list * Smt.term list * bool * bool =
  let has_string =
    List.exists (fun (_, (_, _, sort)) -> sort = Some str_sort) sc
  in
  let ds, asm, has_rec =
  List.fold_left
    (fun (ds, asm, has_rec) (name, (b, q, sort)) ->
      match sort with
      (* Every SCALAR entry — the original Int (`None`) and now Bool — declares
         one constant at its own sort and loads its predicate over it.  The sort
         must come from the marker, not be assumed `Int`: a Bool constant used
         where the VC says `Int` is exactly the one-symbol-two-sorts rejection
         the string and record paths already guard against. *)
      | _ when scalar_sort_of_marker sort <> None ->
        let s = scalar_sort_or_int sort in
        let c = Smt.Const name in
        let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
        let ds = (name, s) :: ds in
        (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> (ds, qa :: asm, has_rec)
         | None -> (ds, asm, has_rec))
      | None -> (ds, asm, has_rec)
      (* A String-refined entry declares a `Str` constant and loads its
         predicate, but MUST NOT set [has_rec]: that flag switches check_post
         onto the "a SAT model is a definite violation" path, which is only
         justified when the scope pins a concrete record.  An opaque `Str` pins
         nothing, so flipping it there would be a false-positive engine. *)
      | Some sort_name when sort_name = str_sort ->
        let c = Smt.Const name in
        let ds = (name, Smt.SData str_sort) :: ds in
        let rv n = if n = b || n = "_" then Some c else None in
        let rm m n =
          if m = "len" && string_len_available () && (n = b || n = "_") then
            Some (Smt.App (strlen_fn, [ c ]))
          else None
        in
        (match smt_of ~resolve_var:rv ~resolve_measure:rm q with
         | Some qa -> (ds, qa :: asm, has_rec)
         | None -> (ds, asm, has_rec))
      (* A MEASURE-ONLY entry ([meas_sort_prefix]) contributes NOTHING here, and
         must not fall into the ADT arm below: `$Meas:M_List` is a marker, not a
         declared sort, so `(declare-const xs $Meas:M_List)` would be a z3
         `(error …)` on the shared solver channel — and setting [has_rec] off a
         list predicate would switch [check_post] onto its "a SAT model is a
         definite violation" branch with nothing concrete pinned, which is a
         false-positive engine.  Skipping leaves [check_post] behaving exactly as
         it did before these entries existed; carrying a list measure through a
         POSTcondition is a separate piece of work. *)
      | Some sort_name when is_meas_sort sort_name -> (ds, asm, has_rec)
      | Some sort_name ->
        let c = Smt.Const name in
        let ds = (name, Smt.SData sort_name) :: ds in
        let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
        let rf = make_field_resolver b sort_name c in
        let rma m arg =
          if is_axiom_measure m then Some (Smt.App (m, [ arg ])) else None
        in
        (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                 ~resolve_field:rf ~resolve_measure_app:rma q with
         | Some qa -> (ds, qa :: asm, true)
         (* Predicate untranslatable: declare the const but don't set has_rec.
            Without a loaded assumption, scope_has_record would trigger the
            "SAT = definite error" path with an unconstrained cex — unsound. *)
         | None -> (ds, asm, has_rec)))
    ([], [], false) sc
  in
  (ds, asm, has_rec, has_string)

(* Check one return-position tail against the declared return refinement.

   Returns TRUE only when the tail was POSITIVELY VERIFIED — i.e. the solver
   proved the predicate holds on this path.  Anything else (an unreflectable
   tail, an unreflectable predicate, an `unknown` from the solver, a refutation)
   returns false.  That verdict is what gates postcondition *propagation*
   (see [postcond_of]): only a proven postcondition is a true fact, so only a
   proven one may be assumed at call sites.

   [emit] (default true) controls diagnostics.  The verdict pre-pass runs with
   [~emit:false] so it cannot double-report; the in-walk [check_fn_post] runs
   with the default and is the single reporting site.  The repeated discharge
   is served from the content-addressed VC cache. *)
(* [scalar_env] gives the SCALAR SMT sort of body names whose declared type
   fixes one — the clause's `Bool` parameters.  [sc] only carries REFINED
   locals, so without this a bare `fn f(b : Bool) : {Bool | _ == true} do b end`
   would declare `b` at `Int` and use it as a Bool. *)
let check_post ~root errctx ~span ?(record_sort : string option = None)
    ?(scalar_env : (string * Smt.sort) list = [])
    ?(fn_name : string option = None) ?(emit = true) ?(record = true)
    ?(fn_params : (string * A.ty option) list = [])
    (sc : scope) (binder : string) (ret_pred : A.expr)
    ((path, tail_e) : (A.expr * bool) list * A.expr) : bool =
  (* Mirrors [check_call]'s [note]: every exit records an outcome, so a return
     refinement that checks nothing is distinguishable from one that passes.
     [record] (NOT [emit]) gates whether this fires at all — [check_fn_post_verdict]
     is invoked twice per refined-return function, once from the
     [gate_unverified_posts] pre-pass with [~emit:false] and once from the walk
     with [emit = true]; both calls are threaded here as [~record:emit] by the
     caller, so only the emitting (reporting) run ever records, and the same
     postcondition is never counted twice. *)
  let note verdict =
    (* `@[trusted]` accepts a SKIP as an assertion rather than escalating it —
       mirrors [check_call]'s [note] exactly, including running before the
       verdict is recorded/escalated, so the ledger and the diagnostic agree.
       A [Violated] is untouched: a predicate the solver proved can never hold
       is a bug in the annotation, not an incompleteness [@[trusted]] waves
       through. *)
    let verdict =
      match verdict with
      | Obligation.Skipped _ when !trusted_fn -> Obligation.Trusted
      | _ -> verdict
    in
    if record then
      Obligation.record
        { Obligation.span; callee = Option.value ~default:"" fn_name
        ; predicate = pred_str ret_pred; verdict; kind = Obligation.Postcondition };
    (* `cap verified` escalates an undischarged POSTCONDITION exactly as
       [check_call] escalates an undischarged precondition — the last place a
       fact was granted without obliging anyone.  Gated on [record] (which
       [check_fn_post_verdict] threads as [~record:emit]) so only the emitting
       run escalates: the [gate_unverified_posts] pre-pass calls this with
       [~record:false] purely to decide propagation, and must never also
       report — that would print the same contract's failure twice. *)
    match verdict with
    | Obligation.Skipped r when !strict_verified && record ->
      let fn_label = match fn_name with Some n -> n | None -> "<anonymous>" in
      let remedy =
        "note: strengthen the return expression so the checker can see it \
         satisfies this contract, rewrite the predicate into the fragment the \
         checker supports, or remove `cap verified` from this module — it asks \
         for every obligation to be discharged"
      in
      Err.error errctx ~span
        (Printf.sprintf
           "`cap verified` module: cannot verify return type constraint `%s` on `%s` (%s: %s)\n%s"
           (pred_str ret_pred) fn_label (Obligation.reason_name r)
           (Obligation.reason_detail r) remedy)
    | _ -> ()
  in
  (* Obligation the solver never sees (unreflectable tail or predicate):
     probe the fixed small-value battery through the interpreter.  A
     confirmed, admissible, shrunk witness reports exactly like the
     model-confirmed case; anything else leaves the skip untouched.
     Emitting pass only — the pre-pass treats the verdict as unproven
     either way. *)
  let enum_witness_error () : bool =
    if not emit then false
    else
      match fn_name with
      | None -> false
      | Some fname ->
        (match
           Witness.confirm_enumerative ~fn_name:fname ~fn_params ~binder ~ret_pred
         with
         | Some (args, ret) ->
           (match Witness.render_call fname args, Witness.render_value ret with
            | Some call, Some ret_str ->
              let pred = pred_str ret_pred in
              let msg = Printf.sprintf
                "`%s` does not satisfy its return type constraint on all code paths.\n\nThe return type requires:\n\n    %s\n\nbut %s returns %s."
                fname pred call ret_str
              in
              let hint = Printf.sprintf
                "Every branch must produce a return value satisfying `%s`." pred
              in
              Err.report errctx
                { March_errors.Errors.severity = March_errors.Errors.Error
                ; span; message = msg; labels = []
                ; notes = [hint]; code = None; fix = None };
              true
            | _ -> false)
         | None -> false)
  in
  let base_decls, base_assume, scope_has_record, scope_has_string = scope_facts sc in
  let decls = ref base_decls and assume = ref base_assume in
  (* Scope names already declared into the `Str` sort by [scope_facts].  Both
     [var_const] and [resolve_measure] must agree with that sort, or the VC
     declares one symbol at two sorts and Z3 rejects the whole query. *)
  let is_str_scope name =
    List.exists (fun (n, (_, _, sort)) -> n = name && sort = Some str_sort) sc
  in
  let post_measure_ctr = ref 0 in
  (* Set when resolve_measure_app emits App(m, arg) — the VC then needs the full
     measure preamble (axioms + datatypes).  False => type_preamble only suffices
     (no quantified axioms → Z3 answers sat/unsat without returning `unknown`). *)
  let needs_axiom_preamble = ref false in
  (* The sort a body name is declared at: the refined-local scope decides first
     (it has already declared the name in [scope_facts]), then the declared-type
     environment, then the historical default of `Int`. *)
  let scalar_of name =
    match List.assoc_opt name sc with
    | Some (_, _, m) when scalar_sort_of_marker m <> None -> scalar_sort_or_int m
    | Some _ -> Smt.SInt
    | None -> (match List.assoc_opt name scalar_env with Some s -> s | None -> Smt.SInt)
  in
  let var_const name =
    if is_str_scope name then Some (Smt.Const name)
    else begin decls := (name, scalar_of name) :: !decls; Some (Smt.Const name) end
  in
  let resolve_measure m name =
    (* `len` over a String-sorted scope name is the string `len`, applied to the
       very constant scope_facts declared — so the param's own predicate and the
       return predicate talk about the same length. *)
    if m = "len" && string_len_available () && is_str_scope name then
      Some (Smt.App (strlen_fn, [ Smt.Const name ]))
    else
      let c = Smt.Const (m ^ "$" ^ name) in
      decls := (m ^ "$" ^ name, Smt.SInt) :: !decls;
      if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
      Some c
  in
  (* Handle measure applications where the argument is a non-variable expression
     (e.g. len(v.history) where v.history resolves to a concrete list term).
     - "len" on a concrete list: evaluated by concrete_len; avoids Z3 quantifier axioms
     - axiom measures (user @[measure]): OCaml-level evaluation first (avoids forall
       quantifiers that cause Z3 `unknown`); falls back to App(m,[arg]) for non-concrete
     - other: introduce a fresh symbolic constant with non-negativity if applicable *)
  let resolve_measure_app m arg_term =
    if m = "len" then
      match concrete_len arg_term with
      | Some n -> Some (Smt.IntLit n)
      | None ->
        incr post_measure_ctr;
        let nm = Printf.sprintf "len$app%d" !post_measure_ctr in
        decls := (nm, Smt.SInt) :: !decls;
        assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
        Some (Smt.Const nm)
    else if is_axiom_measure m then
      (match concrete_measure_app m arg_term with
       | Some n -> Some (Smt.IntLit n)
       | None ->
         (* Concrete evaluation failed — fall back to App(m, arg) and tell the
            preamble builder that the VC needs quantified axioms. *)
         needs_axiom_preamble := true;
         Some (Smt.App (m, [ arg_term ])))
    else begin
      incr post_measure_ctr;
      let nm = Printf.sprintf "%s$app%d" m !post_measure_ctr in
      decls := (nm, Smt.SInt) :: !decls;
      if is_nonneg_measure m then assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
      Some (Smt.Const nm)
    end
  in
  (* Field resolver covering record-typed scope params: resolves `old.field` in
     the return expression via the SMT selector for the opaque param const. *)
  let scope_field_resolver : string -> string -> Smt.term option =
    List.fold_left
      (fun rf (name, (_b, _q, sort)) ->
        match sort with
        (* `Str` is opaque — it has no fields and no selectors; nor is a
           scalar (`$Bool`) a declared record sort. *)
        | None -> rf
        | Some s when s = str_sort || is_scalar_sort s -> rf
        | Some sort_name ->
          let rf_param = make_field_resolver name sort_name (Smt.Const name) in
          fun varname fname ->
            match rf varname fname with
            | Some _ as r -> r
            | None -> rf_param varname fname)
      (fun _ _ -> None) sc
  in
  let scalar e = smt_of ~resolve_var:var_const ~resolve_measure ~resolve_measure_app ~resolve_field:scope_field_resolver e in
  let tail_term_opt =
    match record_sort with
    | Some sort_name ->
      (match tail_e with
       | A.ERecord (fields, _) -> reflect_record_literal sort_name fields scalar
       | _ -> scalar tail_e)
    | None -> scalar tail_e
  in
  match tail_term_opt with
  | None ->
    (* This is the postcondition's SUBJECT failing, not the predicate: the
       TAIL expression (the return value) is what [scalar tail_e] could not
       reflect -- [ret_pred] itself is never even reached. Blaming the
       predicate here (as an earlier revision of this task did, per the
       brief's literal Step 4 text) is a false statement whenever the
       predicate is perfectly reflectable, e.g. a `g()` opaque-call tail
       under `{Int | _ > 0}`: `_ > 0` translates fine, `g()` does not. Mirrors
       [check_call]'s `self_display` guard (Task 2): [pred_str] falls back to
       the literal placeholder `<predicate>` for a tail it cannot render as
       source syntax (an `if`, a lambda, …); naming the return expression
       `<predicate>` would read as if that were the user's own spelling, so
       fall back to the function name instead when it does. *)
    let tail_display =
      let rendered = pred_str tail_e in
      if rendered <> "<predicate>" then rendered
      else Option.value ~default:"<anonymous>" fn_name
    in
    if enum_witness_error () then note Obligation.Violated
    else note (Obligation.Skipped (Obligation.Unreflectable_subject tail_display));
    false
  | Some tail_term ->
    let resolve_field = match record_sort with
      | Some sort_name -> make_field_resolver binder sort_name tail_term
      | None -> fun _ _ -> None
    in
    let resolve_var name = if name = binder || name = "_" then Some tail_term else var_const name in
    (* ── Body-namespace resolvers, for the PATH CONTEXT only ────────────────
       A path condition was collected from the function BODY, so every name in
       it is a body name — a parameter or a local — and denotes itself.  The
       return BINDER is not a body name at all: it exists only inside the
       refinement predicate, where it stands for the returned value.  Routing
       the path through [resolve_var] therefore re-points any body variable that
       happens to share the binder's spelling at the returned expression:

         fn f(v : Int, k : Int) : {v : Int | v > 0} do
           if v < 0 do k else 1 end     -- the guard is about the PARAMETER `v`

       read through the binder, `v < 0` becomes `k < 0`, which makes `v > 0`
       (i.e. `k > 0`) definitely false and reports correct code.  This is the
       same caller/callee conflation already fixed for [check_call]'s path
       conditions (see [path_resolve_var] there).

       `_` is left pointing at the return term: it is not a legal variable in
       body code, so it can only have come from a predicate, and mapping it
       through [var_const] would declare a constant named `_`. *)
    let path_resolve_var name = if name = "_" then Some tail_term else var_const name in
    (* Same split for field selectors: `old.count` in a guard projects from the
       SCOPE's record parameter, not from the returned record. *)
    let path_resolve_field varname fname =
      if varname = "_" then resolve_field varname fname
      else scope_field_resolver varname fname
    in
    List.iter
      (fun (cond, negated) ->
        match
          smt_of ~resolve_var:path_resolve_var ~resolve_measure
            ~resolve_field:path_resolve_field ~resolve_measure_app cond
        with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of_r ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app ret_pred with
     | Error e ->
       if enum_witness_error () then note Obligation.Violated
       else note (Obligation.Skipped (Obligation.Unreflectable_predicate (pred_str e)));
       false
     | Ok goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       if sort_conflict decls then (note (Obligation.Skipped Obligation.Sort_conflict); false)
       else
       (* See [check_call] for why the IEEE rewrite runs here, once the
          declarations — and hence which symbols are `Float64` — are final. *)
       let sort_of n = List.assoc_opt n decls in
       let is_float n = sort_of n = Some Smt.SFloat in
       let goal = fp_rewrite is_float goal in
       if not (float_wellsorted is_float goal && formula_wellsorted sort_of goal) then
         (note (Obligation.Skipped Obligation.Float_sort_gate); false)
       else
       let assumptions =
         List.filter_map
           (fun a ->
             let a = fp_rewrite is_float a in
             if float_wellsorted is_float a && formula_wellsorted sort_of a then Some a
             else None)
           !assume
       in
       let vc = { Smt.decls; assumptions; goal } in
       let str_pre = if scope_has_string then string_preamble else "" in
       let preamble = str_pre ^
         if record_sort <> None || scope_has_record then
           (* When all measure apps were evaluated concretely (needs_axiom_preamble=false),
              skip the quantified-axiom measure_preamble.  The quantified forall axioms
              cause Z3 to return `unknown` for SAT queries even when the goal is trivial
              and measures no longer appear in it.  Type preamble alone suffices. *)
           if !needs_axiom_preamble then record_vc_preamble ()
           else type_only_preamble ()
         else ""
       in
       (match Refine.discharge ~root ~preamble vc with
        | Refine.Verified -> note Obligation.Proved; true
        | first ->
          let emit_error () =
            if emit then begin
              ignore tail_e;
              let pred = pred_str ret_pred in
              let fn_prefix = match fn_name with
                | Some n -> Printf.sprintf "`%s` does not satisfy" n
                | None   -> "The return value does not satisfy"
              in
              let msg = Printf.sprintf
                "%s its return type constraint on all code paths.\n\nThe return type requires:\n\n    %s%s"
                fn_prefix pred (cx_block (model_of first))
              in
              let hint = Printf.sprintf
                "Every branch must produce a return value satisfying `%s`." pred
              in
              Err.report errctx
                { March_errors.Errors.severity = March_errors.Errors.Error
                ; span; message = msg; labels = []
                ; notes = [hint]; code = None; fix = None }
            end
          in
          (* An executed-and-confirmed witness reports with the failing call
             itself rather than the raw model block. *)
          let emit_witness_error (args, ret) =
            if emit then begin
              let pred = pred_str ret_pred in
              let fn_prefix = match fn_name with
                | Some n -> Printf.sprintf "`%s` does not satisfy" n
                | None   -> "The return value does not satisfy"
              in
              match fn_name, Witness.render_value ret with
              | Some fname, Some ret_str ->
                (match Witness.render_call fname args with
                 | Some call ->
                   let msg = Printf.sprintf
                     "%s its return type constraint on all code paths.\n\nThe return type requires:\n\n    %s\n\nbut %s returns %s."
                     fn_prefix pred call ret_str
                   in
                   let hint = Printf.sprintf
                     "Every branch must produce a return value satisfying `%s`." pred
                   in
                   Err.report errctx
                     { March_errors.Errors.severity = March_errors.Errors.Error
                     ; span; message = msg; labels = []
                     ; notes = [hint]; code = None; fix = None }
                 | None -> emit_error ())
              | _ -> emit_error ()
            end
          in
          (* Whether this IS a violation is independent of [emit] — [emit_error]
             merely gates whether we tell the user; [note] below must still
             record the true verdict either way. *)
          let violated =
            if scope_has_record then
              (* With concrete record preconditions in scope, a SAT counterexample
                 satisfying those preconditions IS a real violation — report it. *)
              (match first with Refine.Refuted _ -> emit_error (); true | _ -> false)
            else
              (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
               | Refine.Verified -> emit_error (); true
               | _ ->
                 (* Refuted-for-SOME-input: the positive discharge's model is a
                    candidate counterexample.  It only counts once the
                    interpreter confirms it (the VC drops unreflectable path
                    conditions, so a raw model can describe an unreachable
                    input).  Confirmation only runs on the emitting pass —
                    the [gate_unverified_posts] pre-pass already treats this
                    verdict as unproven either way. *)
                 (match fn_name, first with
                  | Some fname, Refine.Refuted model when emit ->
                    (match
                       Witness.confirm_post ~fn_name:fname ~fn_params ~binder
                         ~ret_pred ~model
                     with
                     | Some witness -> emit_witness_error witness; true
                     | None -> false)
                  | _ -> false))
          in
          (* Not [Verified] on the positive goal ⇒ not proven, whatever the
             refutation attempt said. *)
          if violated then note Obligation.Violated
          else note (Obligation.Skipped Obligation.Solver_undecided);
          false))

(* =================================================================
   §17 Postconditions by induction
   ================================================================= *)

(* ══ Tier 2: structural induction over a recursive function ═════════════════

   A RELATIONAL postcondition on a recursive function — `fn insert(t, x) :
   {Tree | size(_) == size(t) + 1}` — cannot be discharged by Z3 alone: Z3 does
   not do induction.  But full induction is not needed.  For a function that
   recurses structurally on one parameter it suffices to make the postcondition
   available as an ASSUMPTION at each recursive call whose argument is a proper
   component of the matched parameter — the induction hypothesis — and then
   discharge each arm separately against the measure's recursion equations:

     Leaf arm:        size(Node(Leaf,x,Leaf)) == size(Leaf) + 1
                      reduces via the axioms to 1 + 0 + 0 == 0 + 1.  No IH needed.
     Node(l,v,r) arm: size(Node(insert(l,x),v,r)) == size(t) + 1
                      needs size(insert(l,x)) == size(l) + 1 — the postcondition
                      instantiated at `l`, which IS structurally smaller.

   ── THE SOUNDNESS PROPERTY ────────────────────────────────────────────────
   The IH may be assumed ONLY at a recursive call whose recursion argument is
   structurally smaller than the matched parameter.  Assuming it at an arbitrary
   argument is circular — you would assume exactly what you are proving — and it
   fails in the DANGEROUS direction: a proven postcondition is ADDED to the
   assumption set that later call-site checks prove `¬goal` against, and adding
   assumptions makes a violation EASIER to prove.  An unsound IH therefore does
   not merely fail to help, it manufactures FALSE POSITIVES on correct code.
   [structural_subvars] is the gate, unchanged and unwidened — the same gate that
   makes `@[measure]` axiomatisation sound.

   The induction is on the matched parameter alone, so only the argument at THAT
   position must shrink; the IH is universally quantified over the others (an
   accumulator may grow freely).

   ── WHY THIS IS A SEPARATE PATH, AND WHY IT NEVER EMITS ────────────────────
   [check_post] handles Int and record returns.  A VARIANT-ADT return was
   previously inert: [return_refine_ext] returns None for it, so nothing at all
   happened.  This function occupies exactly that previously-inert case, so it
   cannot regress any existing verdict.  It is VERDICT-ONLY: it returns "proven"
   or "not proven" and never reports a diagnostic, so the definition side of a
   Tier 2 function stays silent no matter what the solver says.  Its observable
   effects are enabling PROPAGATION via [gate_unverified_posts] and — for the
   constructor-literal shape only — writing a [Postcondition] entry to the
   obligation ledger, so `--refine-report` can tell "attempted and proved" from
   "never looked at".  That write is gated on [~record], NOT on emission,
   because [check_fn_post_verdict] runs twice per refined-return function and
   the same postcondition must never be counted twice; this mirrors exactly
   what [check_post]'s own [record] parameter is for.

   Everything outside a narrow, recognised shape returns false (= not proven =
   skipped): several clauses, a clause guard, a catch-all arm, a nested pattern,
   a binder that shadows a parameter, a sort we cannot pin down.  Skipping costs
   completeness; guessing would cost correctness. *)

(* The SMT sort of a DECLARED March type; None when the checker has no model. *)
let rec smt_sort_of_ty (t : A.ty) : Smt.sort option =
  match t with
  | A.TyRefine (base, _, _) -> smt_sort_of_ty base
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> Some Smt.SInt
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Some Smt.SBool
  | A.TyCon ({ A.txt; _ }, _) when Hashtbl.mem adt_ctors (adt_sort_name txt) ->
    Some (Smt.SData (adt_sort_name txt))
  | _ -> None

let ctor_belongs (ctor : string) (adt : string) : bool =
  match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor cs | None -> false

let check_post_induction ~root ?(record = true) (fd : A.fn_def) : bool =
  let self = fd.A.fn_name.A.txt in
  let dummy_span = fd.A.fn_name.A.span in
  let evar x = A.EVar { A.txt = x; A.span = dummy_span } in
  match fd.A.fn_ret_ty, fd.A.fn_clauses with
  | Some (A.TyRefine ((A.TyCon (rn, _) as rbase), bnd, pred)), [ c ]
    when is_adt_base rbase && (not (is_record_base rbase)) && c.A.fc_guard = None -> (
    let ret_adt = adt_sort_name rn.A.txt in
    let binder = binder_name bnd in
    let params = List.map param_name_of c.A.fc_params in
    let ps = match classify_pred binder params pred with
      | Unusable -> None
      | Closed -> Some []
      | Relational ps -> Some ps
    in
    (* Every sort this VC family mentions must already be declared by the
       measure preamble; otherwise the VC would reference an undeclared sort and
       z3 would answer with an `(error …)` line — the failure mode that
       desynchronises the shared solver channel.  (`--no-measure-axioms` empties
       the preamble, so this also disables Tier 2 under that flag.) *)
    match ps with
    | None -> false
    | Some _ when not (Hashtbl.mem measure_preamble_sorts ret_adt) -> false
    | Some ps ->
      (* ── The single VC builder, shared by every accepted body shape ────────
         [mctx] is the INDUCTION context — the matched parameter, its ADT sort,
         its index in the parameter list, and the structurally-smaller variables
         computed over the whole clause body.  It is the only thing that
         licenses an induction hypothesis, so a body with no top-level match
         passes [None] and can therefore never assume one.  [pat] is the pattern
         equation for the arm under check (its constructor and flat binders); it
         is meaningful only alongside an [mctx], since the equation's left-hand
         side IS the matched parameter.

         There is deliberately ONE generator: a second, parallel VC builder for
         the non-match shape could drift from this one, the hazard recorded at
         [postcond_infer.ml:25]. *)
      let check_tail
          ~(mctx : (string * string * int * (string, unit) Hashtbl.t) option)
          ~(pat : (string * (string * Smt.sort) list) option) ~(refute : bool)
          ((path, tail_e) : (A.expr * bool) list * A.expr) : Obligation.verdict option =
            (* ── Per-VC state ───────────────────────────────────────────────
               [declare] is the well-sortedness guard: one symbol at two sorts
               makes z3 emit an `(error …)`, which desynchronises the shared
               `z3 -in` channel and silently disables refinement checking for the
               rest of the compilation.  Any conflict abandons the whole VC. *)
            let decls : (string, Smt.sort) Hashtbl.t = Hashtbl.create 16 in
            let conflict = ref false in
            let declare n s =
              match Hashtbl.find_opt decls n with
              | None -> Hashtbl.replace decls n s; true
              | Some s' -> if s' = s then true else (conflict := true; false)
            in
            let assume = ref [] in
            let ctr = ref 0 in
            let fresh s =
              incr ctr;
              let n = Printf.sprintf "$t2f%d" !ctr in
              Hashtbl.replace decls n s;
              Smt.Const n
            in
            let ok = ref true in
            (match mctx with
             | Some (mparam, madt, _, _) ->
               if not (declare mparam (Smt.SData madt)) then ok := false
             | None -> ());
            (match pat with
             | Some (_, binder_sorts) ->
               List.iter
                 (fun (n, s) -> if not (declare n s) then ok := false)
                 binder_sorts
             | None -> ());
            List.iter
              (fun fp ->
                match Option.bind (param_ty_of fp) smt_sort_of_ty with
                | Some s -> if not (declare (param_name_of fp) s) then ok := false
                | None -> ())
              c.A.fc_params;
            (* ── Reflection, always at a KNOWN expected sort ─────────────── *)
            let rec reflect_at (s : Smt.sort) (e : A.expr) : Smt.term option =
              match s with
              | Smt.SData d when d <> "Elem" -> reflect_dt d e
              | Smt.SInt -> reflect_int e
              (* An `Elem` or Bool field is invisible to a structural measure:
                 an unconstrained constant of the right sort keeps the VC
                 well-sorted and asserts nothing. *)
              | _ -> Some (fresh s)
            and reflect_dt (d : string) (e : A.expr) : Smt.term option =
              match e with
              | A.EVar { A.txt = x; _ } ->
                if declare x (Smt.SData d) then Some (Smt.Const x) else None
              | A.ECon (ct, args, _) when ctor_belongs ct.A.txt d ->
                let fs = try Hashtbl.find ctor_field_sorts ct.A.txt with Not_found -> [] in
                if List.length fs <> List.length args then None
                else
                  List.fold_right2
                    (fun a s acc ->
                      match reflect_at s a, acc with
                      | Some t, Some ts -> Some (t :: ts)
                      | _ -> None)
                    args fs (Some [])
                  |> Option.map (fun ts -> Smt.App (ct.A.txt, ts))
              (* ── THE INDUCTION HYPOTHESIS ─────────────────────────────────
                 A self-recursive call returning this datatype.  It becomes a
                 fresh opaque constant; the postcondition is assumed ABOUT that
                 constant if and only if the argument at the MATCHED parameter's
                 position is a variable in [structural_subvars].  Any other
                 recursive call still reflects (so the arm can be attempted) but
                 carries NO assumption — an unconstrained constant proves
                 nothing, which is exactly the skip we want.  With no [mctx]
                 there is no matched parameter and hence nothing that could be
                 structurally smaller, so no IH is ever available. *)
              | A.EApp (A.EVar { A.txt = f; _ }, args, _) when f = self && d = ret_adt ->
                incr ctr;
                let nm = Printf.sprintf "$t2rec%d" !ctr in
                Hashtbl.replace decls nm (Smt.SData ret_adt);
                let cst = Smt.Const nm in
                let ih_arg =
                  match mctx with
                  | None -> None
                  | Some (_, _, mparam_idx, sset) -> (
                    match List.nth_opt args mparam_idx with
                    | Some (A.EVar v) when Hashtbl.mem sset v.A.txt -> Some v
                    | _ -> None)
                in
                (match ih_arg with
                 | Some _ ->
                   let env =
                     List.mapi (fun i n -> (n, List.nth_opt args i)) params
                     |> List.filter_map (function
                          | "_", _ | _, None -> None
                          | n, Some a -> Some (n, a))
                   in
                   if List.for_all (fun p -> List.mem_assoc p env) ps then
                     (match pred_term cst (subst_params env pred) with
                      | Some t -> assume := t :: !assume
                      | None -> ())
                 | None -> ());
                Some cst
              | _ -> None
            and reflect_int (e : A.expr) : Smt.term option =
              smt_of ~resolve_var:rv_int ~resolve_measure:rm ~resolve_measure_app:rma e
            and rv_int (x : string) : Smt.term option =
              if declare x Smt.SInt then Some (Smt.Const x) else None
            and rm (m : string) (x : string) : Smt.term option =
              if not (is_axiom_measure m) then None
              else
                let a = Hashtbl.find axiom_measures m in
                Option.map (fun t -> Smt.App (m, [ t ])) (reflect_dt a (evar x))
            and rma (m : string) (arg : Smt.term) : Smt.term option =
              if not (is_axiom_measure m) then None
              else
                match concrete_measure_app m arg with
                | Some n -> Some (Smt.IntLit n)
                | None -> Some (Smt.App (m, [ arg ]))
            (* Reflect the return PREDICATE with its binder standing for [bt].
               The binder is ADT-valued, so it can appear only under a measure
               (`size(_)`) or as a bare occurrence; both route to [bt]. *)
            and pred_term (bt : Smt.term) (p : A.expr) : Smt.term option =
              let rv x = if x = binder || x = "_" then Some bt else rv_int x in
              let rm' m x =
                if not (is_axiom_measure m) then None
                else if x = binder || x = "_" then Some (Smt.App (m, [ bt ]))
                else rm m x
              in
              smt_of ~resolve_var:rv ~resolve_measure:rm' ~resolve_measure_app:rma p
            in
            (* The pattern equation.  Without it a match arm knows nothing about
               the scrutinee, and even the BASE case (`size(t) + 1` with `t =
               Leaf`) is unprovable.  A body with no match has no scrutinee to
               constrain — the parameters stay universally quantified, which is
               strictly WEAKER than any equation, so omitting it cannot make a
               goal provable that would otherwise fail. *)
            (match pat, mctx with
             | None, _ -> ()
             | Some (ctor, binder_sorts), Some (mparam, _, _, _) ->
               let pat_eq =
                 List.fold_right
                   (fun (n, _) acc -> Option.map (fun ts -> Smt.Const n :: ts) acc)
                   binder_sorts (Some [])
                 |> Option.map (fun ts -> Smt.Eq (Smt.Const mparam, Smt.App (ctor, ts)))
               in
               (match pat_eq with Some t -> assume := t :: !assume | None -> ok := false)
             (* A pattern with no matched parameter is not a shape we build. *)
             | Some _, None -> ok := false);
            (* Reflecting the tail is what mints the IH assumptions, so it must
               happen before the assumption list is read. *)
            let tail_term = reflect_dt ret_adt tail_e in
            List.iter
              (fun (cond, negated) ->
                match reflect_int cond with
                | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
                | None -> ())
              path;
            match tail_term with
            | None -> None
            | Some tt -> (
              match pred_term tt pred with
              | None -> None
              | Some goal ->
                if (not !ok) || !conflict then None
                else
                  let decls =
                    Hashtbl.fold (fun n s acc -> (n, s) :: acc) decls []
                    |> List.sort compare
                  in
                  let vc = { Smt.decls; assumptions = !assume; goal } in
                  match Refine.discharge ~root ~preamble:!measure_preamble vc with
                  | Refine.Verified -> Some Obligation.Proved
                  | _ when not refute -> Some (Obligation.Skipped Obligation.Solver_undecided)
                  (* DEFINITE failure only: "not proved" is not "violated".  The
                     predicate is reported as violated only when its NEGATION is
                     itself Verified — i.e. it can never hold. *)
                  | _ ->
                    if Refine.discharge ~root ~preamble:!measure_preamble
                         { vc with Smt.goal = Smt.Not goal }
                       = Refine.Verified
                    then Some Obligation.Violated
                    else Some (Obligation.Skipped Obligation.Solver_undecided))
      in
      let proved_tail ~mctx ~pat t =
        check_tail ~mctx ~pat ~refute:false t = Some Obligation.Proved
      in
      (match c.A.fc_body with
      (* ── Shape 1: a constructor-literal body ───────────────────────────────
         The simplest possible case, and one that needs no induction at all:
         there is no recursive call to hypothesise over, so the goal is just the
         predicate with its binder replaced by the constructed term, discharged
         under the measure's own recursion axioms.  This shape used to fall
         through to `false` SILENTLY — Tier 2 is verdict-only — so a
         deliberately wrong postcondition on it reported no obligation of any
         kind.  Checked BEFORE the match shape so the path that already worked
         is reached unchanged. *)
      | A.ECon _ as body ->
        (* Unlike the match shape, this one RECORDS its verdict in the
           obligation ledger.  Tier 2 stays verdict-only in the sense that
           matters — it emits no diagnostic either way — but "attempted" has to
           be distinguishable from "never looked at", and the ledger is the only
           channel that carries that.  Gated on [record] (which the caller
           threads from [emit]) so the pre-pass run does not double-count.
           (Extending the same accounting to the match shape is a separate
           change: it would move counts under every existing Tier 2 fixture, so
           it is deliberately not bundled here.) *)
        let v =
          (* The refutation query exists only to classify a LEDGER verdict, so
             it is pointless on the non-recording pass — and skipping it there
             cannot change the boolean result, since [Violated] and
             [Skipped Solver_undecided] are both "not proven". *)
          match check_tail ~mctx:None ~pat:None ~refute:record ([], body) with
          | Some v -> v
          (* No VC could be built at all — reflection failed somewhere inside
             [check_tail]'s own [reflect_dt tail_e] / [pred_term] plumbing
             (not [smt_of_r], so no leaf sub-expression is ever in hand here).
             [check_tail] cannot distinguish "the TAIL failed to reflect" from
             "the predicate did", but the tail is this shape's subject in the
             same sense a call's actual argument is (Task 2) -- and every
             corpus/fixture case that reaches this arm is a tail failure, e.g.
             a constructor argument that is itself an opaque call. Blaming the
             predicate here would be the same false statement Finding 1 fixed
             at the sibling site above. Same [<predicate>]-placeholder guard,
             falling back to the callee name [self] (this arm's [pred_label]
             equivalent -- [fd.A.fn_name.A.txt] IS [self] here). *)
          | None ->
            let body_display =
              let rendered = pred_str body in
              if rendered <> "<predicate>" then rendered else self
            in
            Obligation.Skipped (Obligation.Unreflectable_subject body_display)
        in
        if record then
          Obligation.record
            { Obligation.span = fd.A.fn_name.A.span
            ; callee = self
            ; predicate = pred_str pred
            ; verdict = v
            ; kind = Obligation.Postcondition };
        v = Obligation.Proved
      (* ── Shape 2: one clause whose whole body matches on a parameter ─────── *)
      | A.EMatch (A.EVar sv, branches, _) when List.mem sv.A.txt params -> (
        let mparam = sv.A.txt in
        let mparam_idx =
          let rec ix i = function
            | [] -> -1
            | x :: r -> if x = mparam then i else ix (i + 1) r
          in
          ix 0 params
        in
        let mparam_ty =
          List.find_opt (fun fp -> param_name_of fp = mparam) c.A.fc_params
          |> (fun o -> Option.bind o param_ty_of)
          |> (fun o -> Option.bind o smt_sort_of_ty)
        in
        match mparam_ty with
        | Some (Smt.SData madt) when madt <> "Elem" ->
          if not (Hashtbl.mem measure_preamble_sorts madt) then false
          else begin
            (* Structurally smaller variables, computed over the WHOLE clause
               body so a nested match contributes its components too. *)
            let sset = structural_subvars mparam c.A.fc_body in
            let mctx = Some (mparam, madt, mparam_idx, sset) in
            let check_branch (br : A.branch) : bool =
              match br.A.branch_pat with
              | A.PatCon (ct, subpats) when ctor_belongs ct.A.txt madt -> (
                let ctor = ct.A.txt in
                let fsorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
                if List.length subpats <> List.length fsorts then false
                else
                  (* Only flat PatVar / PatWild sub-patterns: a nested pattern
                     would need an equation we do not build. *)
                  let names =
                    List.mapi
                      (fun i p ->
                        match p with
                        | A.PatVar n -> Some n.A.txt
                        | A.PatWild _ -> Some (Printf.sprintf "$w%s%d" ctor i)
                        | _ -> None)
                      subpats
                  in
                  if List.exists Option.is_none names then false
                  else
                    let names = List.map Option.get names in
                    (* A binder that reuses a parameter's name would be
                       conflated with it (both reflect to `Const name`). *)
                    if List.exists (fun n -> List.mem n params) names then false
                    else
                      let binder_sorts = List.combine names fsorts in
                      let base_path =
                        match br.A.branch_guard with Some g -> [ (g, false) ] | None -> []
                      in
                      let ts = tails base_path br.A.branch_body in
                      (* Fold, not for_all: no short-circuit, so the VC cache is
                         warmed uniformly and the verdict is order-independent. *)
                      ts <> []
                      && List.fold_left
                           (fun acc t ->
                             proved_tail ~mctx ~pat:(Some (ctor, binder_sorts)) t && acc)
                           true ts)
              (* A catch-all arm binds no constructor, so there is no pattern
                 equation pinning the scrutinee — nothing to prove from. *)
              | _ -> false
            in
            branches <> []
            && List.fold_left (fun acc br -> check_branch br && acc) true branches
          end
        | _ -> false)
      | _ -> false))
  | _ -> false

(* =================================================================
   §18 Function-level postcondition entry points and gating
   ================================================================= *)

(* Check every return-position tail of every clause of [fd] against its declared
   return refinement.  Returns true iff ALL of them positively verified (a
   function with no clauses, or a clause with no reachable tail, counts as NOT
   verified — silence is not proof).  [emit] threads through to [check_post].

   A return refinement [check_post] cannot handle at all (a variant-ADT return)
   falls through to [check_post_induction], the Tier 2 path.  That path never
   emits, so this stays the single reporting site.  [emit] IS threaded to it as
   [~record], though: its constructor-literal shape writes an obligation, and
   this function runs twice per refined-return function, so without the thread
   every such postcondition would be counted twice in `--refine-report`. *)
let check_fn_post_verdict ~root errctx ?(emit = true) (fd : A.fn_def) : bool =
  match return_refine_ext fd with
  | None -> check_post_induction ~root ~record:emit fd
  | Some (binder, ret_pred, marker) ->
    (* [record_sort] must carry only a DECLARED sort name.  A scalar marker
       (`$Bool`) is not one: handing it here would send the return value down
       the record-literal reflection and the datatype preamble, for a sort
       nobody declares. *)
    let record_sort =
      match marker with Some s when not (is_scalar_sort s) -> Some s | _ -> None
    in
    let clause_ok (c : A.fn_clause) =
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let scalar_env =
        List.map (fun fp -> (param_name_of fp, scalar_sort_of_param_ty (param_ty_of fp)))
          c.A.fc_params
      in
      let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      let ts = tails base c.A.fc_body in
      (* Fold (not List.for_all): every tail must be checked so every
         diagnostic is emitted — short-circuiting would hide errors. *)
      let fn_params =
        List.map (fun fp -> (param_name_of fp, param_ty_of fp)) c.A.fc_params
      in
      ts <> []
      && List.fold_left
           (fun acc t ->
             check_post ~root errctx ~span:c.A.fc_span ~record_sort ~scalar_env
               ~fn_name:(Some fd.A.fn_name.A.txt) ~emit ~record:emit ~fn_params
               sc binder ret_pred t
             && acc)
           true ts
    in
    fd.A.fn_clauses <> []
    && List.fold_left (fun acc c -> clause_ok c && acc) true fd.A.fn_clauses

let check_fn_post ~root errctx (fd : A.fn_def) : unit =
  ignore (check_fn_post_verdict ~root errctx fd)

(* ── Verification gate on postcondition propagation ────────────────────────
   A declared postcondition is only a FACT at a call site if the definition side
   PROVED it.  [check_fn_post] deliberately rejects only a postcondition that can
   never hold, so a merely *unproven* one is legal at the definition — but
   propagated facts are ADDED to the assumption set the call-site VC proves
   against, and a false assumption makes a violation easier to "prove".  An
   unproven postcondition that travelled would therefore be a false-positive
   engine (a stale `{Int | _ < 0}` on a function that returns 6 would flag the
   correct call `takepos(score(5))`).

   So: an unproven postcondition stays legal, it simply does not travel.  This
   pre-pass runs the definition-side check for every refined-return function
   (with diagnostics suppressed) and CLEARS [ret] on every signature that did
   not verify, so [postcond_of] — and hence both propagation sites — see only
   proven facts.

   Why a pre-pass rather than lazy memoization: [postcond_of] is consulted from
   arbitrary call sites during the AST walk, including calls that precede their
   callee's definition and calls that cross module boundaries.  Computing on
   first use would need a key→fn_def index and would still make the *result*
   order-independent only by construction of that index; a pre-pass reuses
   [collect_all_defs]'s own traversal, is order-independent by construction, and
   keeps [visit] unchanged.  Diagnostics are emitted exactly once, later, by
   [check_fn_post] during the walk; the repeated discharge hits the VC cache. *)
let gate_unverified_posts ~root errctx (defs : (string, fn_sig option) Hashtbl.t)
    (decls : A.decl list) : unit =
  let rec go prefix decls =
    List.iter
      (function
        | A.DFn (fd, _) ->
          let key = if prefix = "" then fd.A.fn_name.A.txt else prefix ^ "." ^ fd.A.fn_name.A.txt in
          (match Hashtbl.find_opt defs key with
           | Some (Some sg) when Option.is_some sg.ret ->
             if not (check_fn_post_verdict ~root errctx ~emit:false fd) then
               (* Keep the entry (it must still shadow an outer same-named
                  function for [resolve_call]); drop only the postcondition. *)
               Hashtbl.replace defs key (Some { sg with ret = None })
           | _ -> ())
        | A.DMod (name, _, ds, _) ->
          go (if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls

