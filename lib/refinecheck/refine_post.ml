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
  (* A String return, at the opaque `Str` sort a String PARAMETER already
     reflects to ([refined_param_ty]).  Absent until 2026-09-13: a
     `{String | ...}` return fell through to [check_post_induction], which
     has nothing to say about a non-ADT, and filed NOTHING — not even a
     skip — so `--refine-report` could not tell "no return refinement" from
     "silently unchecked" (specs/todos/2026-09-03-string-return-…). *)
  | Some (A.TyRefine (base, binder, pred)) when is_string_base base ->
    Some (binder_name binder, pred, Some str_sort)
  | Some (A.TyRefine (A.TyCon ({ A.txt = name; _ }, []) as base, binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  (* A LIST return, at the MEASURE-ONLY marker: the returned list is never a
     datatype term (its heads are opaque `Elem`), but its MEASURES are —
     `elts(_)` over a literal or a returned parameter (set refinements,
     specs/2026-09-13-set-refinements-design.md).  Before this arm a
     `{List(Int) | …}` return fell through to [check_post_induction] and,
     lacking an axiomatised list measure, filed nothing at all. *)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = "List"; _ }, _) as base), binder, pred))
    when is_adt_base base ->
    Some (binder_name binder, pred, Some (meas_sort_name "List"))
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
(* The fifth component, [complete], is true when EVERY refined scope entry's
   own predicate was loaded as an assumption.  [check_post] may treat a
   satisfiable model as a definite violation (the record fast path) only when
   it is: a model is a real input only if it satisfies every precondition the
   function declares, and a promise that failed to load is a precondition the
   solver never saw.  The shape that exposed this: a record parameter (which
   turns the fast path on) next to `xs : {List(Int) | len(_) > 0 &&
   member(1, elts(_))}`, whose promise does not translate because of `len`,
   so `elts(xs) = {}` — an input the contract forbids — was reported as the
   counterexample to a return of `xs`. *)
let scope_facts (sc : scope)
    : (string * Smt.sort) list * Smt.term list * bool * bool * bool =
  let has_string =
    List.exists (fun (_, (_, _, sort)) -> sort = Some str_sort) sc
  in
  let dropped = ref false in
  let loaded ds asm has_rec = function
    | Some qa -> (ds, qa :: asm, has_rec)
    | None -> dropped := true; (ds, asm, has_rec)
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
        loaded ds asm has_rec (smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q)
      | None -> (ds, asm, has_rec)
      (* A String-refined entry declares a `Str` constant and loads its
         predicate, but MUST NOT set [has_rec]: that flag switches check_post
         onto the "a SAT model is a definite violation" path, which is only
         justified when the scope pins a concrete record.  An opaque `Str` pins
         nothing, so flipping it there would be a false-positive engine. *)
      | Some sort_name when sort_name = str_sort ->
        let c = Smt.Const name in
        let ds = (name, Smt.sdata str_sort) :: ds in
        let rv n = if n = b || n = "_" then Some c else None in
        let rm m n =
          if m = "len" && string_len_available () && (n = b || n = "_") then
            Some (Smt.App (strlen_fn, [ c ]))
          else None
        in
        loaded ds asm has_rec (smt_of ~resolve_var:rv ~resolve_measure:rm q)
      (* A MEASURE-ONLY entry ([meas_sort_prefix]) contributes NOTHING here, and
         must not fall into the ADT arm below: `$Meas:M_List` is a marker, not a
         declared sort, so `(declare-const xs $Meas:M_List)` would be a z3
         `(error …)` on the shared solver channel — and setting [has_rec] off a
         list predicate would switch [check_post] onto its "a SAT model is a
         definite violation" branch with nothing concrete pinned, which is a
         false-positive engine.  Skipping leaves [check_post] behaving exactly as
         it did before these entries existed; carrying a list measure through a
         POSTcondition is a separate piece of work. *)
      | Some sort_name when is_meas_sort sort_name ->
        (* …except for its SET facts: `elts(_)` in the entry's own predicate is
           the constant `elts$name`, the very symbol [check_post]'s resolvers
           build for `elts(name)` in the return predicate.  Anything else in
           the predicate (a bare binder, `len`) drops the whole fact, as
           before — carrying `len` through a postcondition is still separate
           work, and adding only what set contracts need keeps every existing
           verdict where it was. *)
        let rv _ = None in
        let used = ref [] in
        let rm m n =
          if is_builtin_set_measure m && (n = b || n = "_" || n = name) then begin
            let c = set_const m name in
            if not (List.mem c !used) then used := c :: !used;
            Some (Smt.Const c)
          end
          else None
        in
        (match smt_of ~resolve_var:rv ~resolve_measure:rm q with
         | Some qa ->
           (List.map (fun c -> (c, Smt.SSet Smt.set_unknown_elem)) !used @ ds, qa :: asm, has_rec)
         | None -> dropped := true; (ds, asm, has_rec))
      | Some sort_name ->
        let c = Smt.Const name in
        let ds = (name, adt_sort sort_name) :: ds in
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
         | None -> dropped := true; (ds, asm, has_rec)))
    ([], [], false) sc
  in
  (ds, asm, has_rec, has_string, not !dropped)

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
(* ── Callee contracts inside a postcondition check (plan step 2.5) ─────────
   A return refinement whose tail is a CALL (`go(xs, Nil)` in `reverse`) is
   provable from the callee's own postcondition, exactly as a call site uses
   it.  The lookup is a cell rather than a parameter because every entry point
   ([gate_unverified_posts], the walk, a local `fn`) already threads a
   different context; each installs a lookup that sees only PROVED contracts,
   since an unproved one assumed here would make a false postcondition
   provable. *)
let post_lookup : (string -> A.expr list -> (string * A.expr * string option) option) ref =
  ref (fun _ _ -> None)

let with_post_lookup lookup (f : unit -> 'a) : 'a =
  let saved = !post_lookup in
  post_lookup := lookup;
  Fun.protect ~finally:(fun () -> post_lookup := saved) f

(* [sg]'s postcondition instantiated at [args], in the caller's namespace
   (the same rule [postcond_of] applies to a resolved callee). *)
let ret_instance (sg : fn_sig) (args : A.expr list) : (string * A.expr * string option) option =
  match sg.ret with
  | None -> None
  | Some (b, p) -> (
    match classify_pred b sg.param_names p with
    | Closed -> Some (b, p, sg.ret_sort)
    | Unusable -> None
    | Relational ps ->
      let env =
        List.mapi (fun i n -> (n, List.nth_opt args i)) sg.param_names
        |> List.filter_map (function "_", _ | _, None -> None | n, Some a -> Some (n, a))
      in
      if List.for_all (fun q -> List.mem_assoc q env) ps then Some (b, subst_params env p, sg.ret_sort)
      else None)

(* The conjuncts of a predicate, so one untranslatable conjunct of a callee's
   contract drops only itself. *)
let rec pred_conjuncts (e : A.expr) : A.expr list =
  match e with
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> pred_conjuncts a @ pred_conjuncts b
  | _ -> [ e ]

let check_post ~root errctx ~span ?(record_sort : string option = None)
    ?(scalar_env : (string * Smt.sort) list = [])
    ?(fn_name : string option = None) ?(emit = true) ?(record = true)
    ?(fn_params : (string * A.ty option) list = [])
    ?(string_ret = false)
    ?(list_ret = false)
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
  let base_decls, base_assume, scope_has_record, scope_has_string, scope_complete =
    scope_facts sc
  in
  let decls = ref base_decls and assume = ref base_assume in
  (* String literals, for a String RETURN ([string_ret]): the tail `"a"` and
     the predicate's `"a"` must meet on ONE constant, minted here exactly as
     [check_call]'s [str_lit_const] mints it — an indexed `$strN` at the `Str`
     sort, its byte length pinned, distinct from every literal already seen.
     [uses_string] attaches the string preamble when any was minted, the same
     "only when actually used" discipline [scope_has_string] follows. *)
  let str_lit_tbl : (string, string) Hashtbl.t = Hashtbl.create 4 in
  let uses_string = ref false in
  let str_lit_const (s : string) : Smt.term option =
    if not (string_len_available ()) then None
    else
      match Hashtbl.find_opt str_lit_tbl s with
      | Some c -> Some (Smt.Const c)
      | None ->
        let c = Printf.sprintf "$str%d" (Hashtbl.length str_lit_tbl) in
        Hashtbl.replace str_lit_tbl s c;
        uses_string := true;
        decls := (c, Smt.sdata str_sort) :: !decls;
        assume :=
          Smt.Eq (Smt.App (strlen_fn, [ Smt.Const c ]), Smt.IntLit (String.length s)) :: !assume;
        Hashtbl.iter
          (fun s' c' -> if s' <> s then assume := Smt.Ne (Smt.Const c, Smt.Const c') :: !assume)
          str_lit_tbl;
        Some (Smt.Const c)
  in
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
    (* `elts(xs)` over a body name: one set constant per name, at the
       placeholder element sort [resolve_set_sorts] settles.  No `>= 0`. *)
    else if is_builtin_set_measure m || is_set_measure m then begin
      let nm = m ^ "$" ^ name in
      decls := (nm, Smt.SSet Smt.set_unknown_elem) :: !decls;
      Some (Smt.Const nm)
    end
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
    if is_builtin_set_measure m then
      (* A literal is folded by [smt_of_r] before this is consulted; anything
         else is an opaque list/map, hence a fresh unconstrained set. *)
      match if m = elts_measure then concrete_elts arg_term else None with
      | Some t -> Some t
      | None ->
        incr post_measure_ctr;
        let nm = Printf.sprintf "%s$app%d" m !post_measure_ctr in
        decls := (nm, Smt.SSet Smt.set_unknown_elem) :: !decls;
        Some (Smt.Const nm)
    else if m = "len" then
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
  (* A built-in list measure of a CALL: a constant carrying the callee's
     proved contract, conjunct by conjunct; a nested call in that contract
     (`elts(reverse(xs))`) recurses. *)
  let call_ctr = ref 0 in
  let rec measure_of_call (m0 : string) (f : string) (cargs : A.expr list) : Smt.term option =
    match !post_lookup f cargs with
    | None -> None
    | Some (b, q, _) ->
      incr call_ctr;
      let nm = Printf.sprintf "%s$%s%d" f (if m0 = "len" then "len" else "set") !call_ctr in
      let c = Smt.Const nm in
      if m0 = "len" then begin
        decls := (nm, Smt.SInt) :: !decls;
        assume := Smt.Ge (c, Smt.IntLit 0) :: !assume
      end
      else decls := (nm, Smt.SSet Smt.set_unknown_elem) :: !decls;
      let rv n = if n = b || n = "_" then None else var_const n in
      let rm m n = if n = b || n = "_" then (if m = m0 then Some c else None) else resolve_measure m n in
      let rmc m g gargs =
        if is_builtin_set_measure m || m = "len" then measure_of_call m g gargs else None
      in
      List.iter
        (fun conj ->
          match
            smt_of ~resolve_var:rv ~resolve_measure:rm ~resolve_measure_app
              ~resolve_str_lit:str_lit_const ~resolve_measure_call:rmc conj
          with
          | Some t -> assume := t :: !assume
          | None -> ())
        (pred_conjuncts q);
      Some c
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
  let scalar e =
    smt_of ~resolve_var:var_const ~resolve_measure ~resolve_measure_app
      ~resolve_field:scope_field_resolver ~resolve_str_lit:str_lit_const e
  in
  let tail_term_opt =
    match record_sort with
    | Some sort_name ->
      (match tail_e with
       | A.ERecord (fields, _) -> reflect_record_literal sort_name fields scalar
       | _ -> scalar tail_e)
    (* A LIST tail is represented by its SET OF ELEMENTS, never by itself: a
       literal folds to a concrete set, a returned body name to that name's
       `elts$x` constant (the same symbol its own contract and `elts(x)` in
       the predicate resolve to).  A call or anything else is opaque and
       files the usual unreflectable-subject skip. *)
    | None when list_ret ->
      (match tail_e with
       | A.EVar { A.txt = x; _ } -> resolve_measure elts_measure x
       | A.ECon _ -> (match scalar tail_e with Some t -> concrete_elts t | None -> None)
       | A.EApp (A.EVar { A.txt = f; _ }, cargs, _) -> measure_of_call elts_measure f cargs
       | _ -> None)
    | None when string_ret ->
      (* A String tail: a literal mints its constant; a String-sorted scope
         name (a parameter the scope already declared at `Str`) denotes
         itself; anything else goes through [scalar], whose string resolver
         reflects a literal in a larger expression and nothing else.  A
         string built by a call is opaque and files a recorded skip. *)
      (match tail_e with
       | A.ELit (A.LitString s, _) -> str_lit_const s
       | A.EVar { A.txt = x; _ } when is_str_scope x -> uses_string := true; Some (Smt.Const x)
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
      if rendered <> "<predicate>" then Printf.sprintf "the return expression `%s`" rendered
      else
        Printf.sprintf "the return expression of `%s`"
          (Option.value ~default:"<anonymous>" fn_name)
    in
    if enum_witness_error () then note Obligation.Violated
    else note (Obligation.Skipped (Obligation.Unreflectable_subject tail_display));
    false
  | Some tail_term ->
    let resolve_field = match record_sort with
      | Some sort_name -> make_field_resolver binder sort_name tail_term
      | None -> fun _ _ -> None
    in
    (* Under [list_ret] the binder denotes a LIST, which is not a term here;
       only its measures are.  A predicate using it bare is untranslatable. *)
    let resolve_var name =
      if name = binder || name = "_" then (if list_ret then None else Some tail_term)
      else var_const name
    in
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
          smt_of ~vocab:false ~resolve_var:path_resolve_var ~resolve_measure
            ~resolve_field:path_resolve_field ~resolve_measure_app cond
        with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (* `len(_)` over a String return is the string length of the returned
       term — the same `$strlen` a String parameter's own `len` reflects to
       ([resolve_measure] above) — not a fresh Int measure constant. *)
    let goal_resolve_measure m name =
      if string_ret && m = "len" && (name = binder || name = "_") && string_len_available ()
      then Some (Smt.App (strlen_fn, [ tail_term ]))
      (* `elts(_)` over a list return IS the tail's set term. *)
      else if list_ret && m = elts_measure && (name = binder || name = "_") then Some tail_term
      else resolve_measure m name
    in
    (match
       smt_of_r ~resolve_var ~resolve_measure:goal_resolve_measure ~resolve_field
         ~resolve_measure_app ~resolve_str_lit:str_lit_const ret_pred
     with
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
       (* Settle every sort the producers left open (or skip on a
          contradiction) before rendering: see [resolve_sorts]. *)
       match resolve_sorts decls goal assumptions with
       | None -> note (Obligation.Skipped Obligation.Sort_conflict); false
       | Some (decls, goal, assumptions, measure_instances) ->
       let assumptions = card_facts decls goal assumptions in
       let vc = { Smt.decls; assumptions; goal } in
       let str_pre = if scope_has_string || !uses_string then string_preamble else "" in
       let preamble = str_pre ^
         if record_sort <> None || scope_has_record then
           (* When all measure apps were evaluated concretely (needs_axiom_preamble=false),
              skip the quantified-axiom measure_preamble.  The quantified forall axioms
              cause Z3 to return `unknown` for SAT queries even when the goal is trivial
              and measures no longer appear in it.  Type preamble alone suffices. *)
           let base = if !needs_axiom_preamble then record_vc_preamble () else type_only_preamble () in
           base ^ "\n"
           ^ query_instance_preamble ~declared:(str_pre ^ base) ~measures:!needs_axiom_preamble decls goal
               assumptions measure_instances
         else ""
       in
       let contains hay needle =
         let n = String.length needle and h = String.length hay in
         let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
         at 0
       in
       let preamble =
         preamble
         ^ set_preamble ~elem_declared:(contains preamble "(declare-sort Elem 0)")
             ~str_declared:(str_pre <> "")
             ~measure_attached:((record_sort <> None || scope_has_record) && !needs_axiom_preamble)
             vc
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
            if scope_has_record && scope_complete then
              (* With concrete record preconditions in scope, a SAT counterexample
                 satisfying those preconditions IS a real violation — report it.
                 Only when ALL of them were loaded ([scope_complete]): a model
                 that ignores an untranslated promise may be an input the
                 function's own signature rules out. *)
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
    Some (adt_sort (adt_sort_name txt))
  | _ -> None

let ctor_belongs (ctor : string) (adt : string) : bool =
  match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor cs | None -> false

(* The FULL solver-free acceptance test [check_post_induction] applies before
   it ever builds a VC: the outer shape match (a refined ADT-non-record
   return, one guardless clause), [classify_pred]'s usability filter, and the
   measure-preamble gate ("every sort this VC family mentions must already be
   declared by the measure preamble; otherwise the VC would reference an
   undeclared sort and z3 would answer with an `(error ...)` line -- the
   failure mode that desynchronises the shared solver channel."
   `--no-measure-axioms` empties the preamble, so this also disables Tier 2
   under that flag). Extracted so [Refine_audit.classify] can consult exactly
   what the checker consults, with no risk of drift, rather than duplicating
   the rule (see [refine_audit.ml]'s Return rule and Task 2's review, finding
   1). Everything here is a pattern match, a syntactic classifier, or a
   hashtable lookup; the first and only solver contact is [Refine.discharge],
   deep inside [check_tail] below, well past everything this function
   decides. Returns the destructured pieces the caller needs so nothing is
   computed twice. *)
(* A datatype Tier 2 can build queries over: one the measure preamble
   declares, or the built-in `List`, whose instances and structural `len`/`elts`
   each query declares itself (plan step 2.2). *)
let tier2_adt (adt : string) : bool = Hashtbl.mem measure_preamble_sorts adt || adt = list_adt

(* The internal structural measure a predicate's [m] means over a list, when it
   means one: `len` unless a user measure took that name, and `elts`. *)
let list_structure_measure (m : string) : string option =
  if m = "len" && not (is_axiom_measure "len") then Some list_len_measure
  else if m = elts_measure then Some list_elts_measure
  else None

let post_induction_shape (fd : A.fn_def)
  : (string * string * string list * A.expr * A.fn_clause * string list) option =
  match fd.A.fn_ret_ty, fd.A.fn_clauses with
  | Some (A.TyRefine ((A.TyCon (rn, _) as rbase), bnd, pred)), [ c ]
    when is_adt_base rbase && (not (is_record_base rbase)) && c.A.fc_guard = None -> (
    let ret_adt = adt_sort_name rn.A.txt in
    let binder = binder_name bnd in
    let params = List.map param_name_of c.A.fc_params in
    match classify_pred binder params pred with
    | Unusable -> None
    | Closed when tier2_adt ret_adt ->
      Some (ret_adt, binder, params, pred, c, [])
    | Relational ps when tier2_adt ret_adt ->
      Some (ret_adt, binder, params, pred, c, ps)
    | Closed | Relational _ -> None)
  | _ -> None

(* Shape 2's scrutinee requirement: the matched parameter's DECLARED type is
   an ADT the measure preamble declares.  An unannotated parameter has a name
   ([param_name_of]) but no sort, and is not a Shape 2 match. *)
let induction_match_adt (c : A.fn_clause) (mparam : string) : string option =
  List.find_opt (fun fp -> param_name_of fp = mparam) c.A.fc_params
  |> (fun o -> Option.bind o param_ty_of)
  |> (fun o -> Option.bind o smt_sort_of_ty)
  |> function
  | Some (Smt.SData (madt, _)) when madt <> "Elem" && tier2_adt madt ->
    Some madt
  | _ -> None

(* ── `let` in induction bodies (plan step 4.1) ────────────────────────────
   Tier 2 reads a body as constructors, calls and a match, so a `let` hides
   its value: `let new_r = make_node(lr, k, r); make_node(ll, lk, new_r)`.
   [inline_lets] substitutes each simple `let x = e` into the rest of its
   block, which is exactly the value the tail computes.  It is conservative:
   a later binder of `x` or of a name free in `e` would capture, and a node
   this substitution does not understand might bind names, so either gives
   [None] and the body is used as written (the tail is then not attempted,
   as before).  Leading local `fn`s are dropped here; their contracts reach
   the body through [post_lookup]. *)
let rec expr_vars (acc : string list) (e : A.expr) : string list option =
  let fold acc es =
    List.fold_left (fun acc x -> Option.bind acc (fun acc -> expr_vars acc x)) (Some acc) es
  in
  match e with
  | A.EVar { A.txt; _ } -> Some (txt :: acc)
  | A.ELit _ -> Some acc
  | A.EApp (f, args, _) -> fold acc (f :: args)
  | A.ECon (_, es, _) | A.ETuple (es, _) | A.EAtom (_, es, _) | A.EBlock (es, _) -> fold acc es
  | A.EField (r, _, _) | A.EAnnot (r, _, _) -> expr_vars acc r
  | A.EIf (c, t, f, _) -> fold acc [ c; t; f ]
  | A.ELet (b, _) -> fold (pat_binders b.A.bind_pat @ acc) [ b.A.bind_expr ]
  | A.EMatch (x, brs, _) ->
    List.fold_left
      (fun acc (br : A.branch) ->
        Option.bind acc (fun acc ->
            let acc = pat_binders br.A.branch_pat @ acc in
            let acc = match br.A.branch_guard with Some g -> expr_vars acc g | None -> Some acc in
            Option.bind acc (fun acc -> expr_vars acc br.A.branch_body)))
      (expr_vars acc x) brs
  | _ -> None

(* [e] with [x := rhs], or [None] when that could capture or [e] has a node
   this does not model.  [expr_vars] over-approximates every name a node
   binds or mentions, which is all the capture test needs. *)
let subst_let (x : string) (rhs : A.expr) (e : A.expr) : A.expr option =
  match expr_vars [] rhs, expr_vars [] e with
  | Some rhs_vars, Some _ ->
    let rec go (e : A.expr) : A.expr option =
      let all es = List.fold_right (fun a acc -> match go a, acc with Some a, Some l -> Some (a :: l) | _ -> None) es (Some []) in
      match e with
      | A.EVar { A.txt; _ } -> Some (if txt = x then rhs else e)
      | A.ELit _ -> Some e
      | A.EApp (f, args, sp) -> (match go f, all args with Some f, Some a -> Some (A.EApp (f, a, sp)) | _ -> None)
      | A.ECon (c, es, sp) -> Option.map (fun es -> A.ECon (c, es, sp)) (all es)
      | A.ETuple (es, sp) -> Option.map (fun es -> A.ETuple (es, sp)) (all es)
      | A.EAtom (a, es, sp) -> Option.map (fun es -> A.EAtom (a, es, sp)) (all es)
      | A.EField (r, n, sp) -> Option.map (fun r -> A.EField (r, n, sp)) (go r)
      | A.EAnnot (r, t, sp) -> Option.map (fun r -> A.EAnnot (r, t, sp)) (go r)
      | A.EIf (c, t, f, sp) -> (
        match go c, go t, go f with Some c, Some t, Some f -> Some (A.EIf (c, t, f, sp)) | _ -> None)
      | A.EBlock (es, sp) -> Option.map (fun es -> A.EBlock (es, sp)) (all es)
      | A.ELet (b, sp) ->
        let bs = pat_binders b.A.bind_pat in
        if List.exists (fun n -> n = x || List.mem n rhs_vars) bs then None
        else Option.map (fun r -> A.ELet ({ b with A.bind_expr = r }, sp)) (go b.A.bind_expr)
      | A.EMatch (s, brs, sp) ->
        let branch (br : A.branch) =
          let bs = pat_binders br.A.branch_pat in
          if List.exists (fun n -> n = x || List.mem n rhs_vars) bs then None
          else
            let g = match br.A.branch_guard with Some g -> Option.map Option.some (go g) | None -> Some None in
            match g, go br.A.branch_body with
            | Some g, Some b -> Some { br with A.branch_guard = g; branch_body = b }
            | _ -> None
        in
        let brs' = List.fold_right (fun br acc -> match branch br, acc with Some b, Some l -> Some (b :: l) | _ -> None) brs (Some []) in
        (match go s, brs' with Some s, Some brs -> Some (A.EMatch (s, brs, sp)) | _ -> None)
      | _ -> None
    in
    go e
  | _ -> None

let rec inline_lets (e : A.expr) : A.expr option =
  match e with
  | A.EBlock (es, _) ->
    let rec block = function
      | [] -> None
      | [ last ] -> inline_lets last
      | A.ELetFn _ :: rest -> block rest
      | A.ELet ({ A.bind_pat = A.PatVar { A.txt = x; _ }; bind_expr = rhs; _ }, _) :: rest -> (
        let rest' =
          List.fold_right
            (fun st acc -> match subst_let x rhs st, acc with Some st, Some l -> Some (st :: l) | _ -> None)
            rest (Some [])
        in
        match rest' with Some rest -> block rest | None -> None)
      | _ -> None
    in
    block es
  | A.EIf (c, t, f, sp) -> (
    match inline_lets t, inline_lets f with Some t, Some f -> Some (A.EIf (c, t, f, sp)) | _ -> None)
  | A.EMatch (s, brs, sp) ->
    let brs' =
      List.fold_right
        (fun (br : A.branch) acc ->
          match inline_lets br.A.branch_body, acc with
          | Some b, Some l -> Some ({ br with A.branch_body = b } :: l)
          | _ -> None)
        brs (Some [])
    in
    Option.map (fun brs -> A.EMatch (s, brs, sp)) brs'
  | _ -> Some e

(* The body Tier 2 reads: lets inlined where that is safe, else as written. *)
let induction_body (e : A.expr) : A.expr =
  match inline_lets e with Some b -> b | None -> e

(* Does [check_post_induction] reach a body shape it checks (Shape 1 or
   Shape 2), rather than its final `| _ -> false`?  Solver-free, for
   [Refine_audit]: [post_induction_shape] alone accepts the signature
   whatever the body is. *)
let post_induction_checks (fd : A.fn_def) : bool =
  match post_induction_shape fd with
  | None -> false
  | Some (_, _, params, _, c, _) -> (
    match induction_body c.A.fc_body with
    | A.ECon _ -> true
    | A.EMatch (A.EVar sv, _, _) when List.mem sv.A.txt params ->
      induction_match_adt c sv.A.txt <> None
    | _ -> false)

let check_post_induction ~root ?(record = true) (fd : A.fn_def) : bool =
  let self = fd.A.fn_name.A.txt in
  let dummy_span = fd.A.fn_name.A.span in
  let evar x = A.EVar { A.txt = x; A.span = dummy_span } in
  match post_induction_shape fd with
  | None -> false
  | Some (ret_adt, binder, params, pred, c, ps) ->
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
          ~(pat : ((string * Smt.sort) list * (string * string * string * string list) list) option)
          ~(refute : bool)
          ((path, tail_e) : (A.expr * bool) list * A.expr) : Obligation.verdict option =
            (* ── Per-VC state ───────────────────────────────────────────────
               [declare] is the well-sortedness guard: one symbol at two sorts
               makes z3 emit an `(error …)`, which desynchronises the shared
               `z3 -in` channel and silently disables refinement checking for the
               rest of the compilation.  Any conflict abandons the whole VC. *)
            let decls : (string, Smt.sort) Hashtbl.t = Hashtbl.create 16 in
            let conflict = ref false in
            (* The opaque `Elem` is "not known yet" (see [resolve_sorts]), so it
               agrees with any sort and gives way to a concrete one: a list
               pattern's `h` is `Elem` until a guard `h > 0` reads it as Int. *)
            let rec meet (a : Smt.sort) (b : Smt.sort) : Smt.sort option =
              match a, b with
              | Smt.SData ("Elem", []), x | x, Smt.SData ("Elem", []) -> Some x
              | Smt.SData (n, xs), Smt.SData (m, ys) when n = m && List.length xs = List.length ys ->
                let zs = List.map2 meet xs ys in
                if List.for_all Option.is_some zs then Some (Smt.SData (n, List.map Option.get zs)) else None
              | Smt.SSet x, Smt.SSet y -> Option.map (fun z -> Smt.SSet z) (meet x y)
              | x, y -> if x = y then Some x else None
            in
            let declare n s =
              match Hashtbl.find_opt decls n with
              | None -> Hashtbl.replace decls n s; true
              | Some s' -> (
                match meet s' s with
                | Some m -> Hashtbl.replace decls n m; true
                | None -> conflict := true; false)
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
               if not (declare mparam (adt_sort madt)) then ok := false
             | None -> ());
            (match pat with
             | Some (binder_sorts, _) ->
               List.iter
                 (fun (n, s) -> if not (declare n s) then ok := false)
                 binder_sorts
             | None -> ());
            List.iter
              (fun fp ->
                match param_ty_of fp with
                (* A type-variable parameter is an opaque element. *)
                | Some (A.TyVar _) -> if not (declare (param_name_of fp) (Smt.sdata "Elem")) then ok := false
                | t -> (
                  match Option.bind t smt_sort_of_ty with
                  | Some s -> if not (declare (param_name_of fp) s) then ok := false
                  | None -> ()))
              c.A.fc_params;
            (* Hypotheses loaded after the reflectors are defined (below). *)
            let param_refinements =
              List.filter_map
                (fun fp ->
                  match param_ty_of fp with
                  | Some (A.TyRefine (base, bnd, p)) ->
                    let adt =
                      match smt_sort_of_ty base with Some (Smt.SData (n, _)) -> n | _ -> ""
                    in
                    Some (param_name_of fp, binder_name bnd, adt, p)
                  | _ -> None)
                c.A.fc_params
            in
            (* ── Reflection, always at a KNOWN expected sort ─────────────── *)
            let rec reflect_at (s : Smt.sort) (e : A.expr) : Smt.term option =
              match s with
              | Smt.SData (d, _) when d <> "Elem" -> reflect_dt d e
              (* An Int payload the reflection cannot place (an `if` computing
                 a height) is an unconstrained Int: weaker, never wrong. *)
              | Smt.SInt -> (match reflect_int e with Some t -> Some t | None -> Some (fresh s))
              (* An `Elem` payload that is a variable stays that variable, so
                 `Cons(h, acc)` keeps `h` for a structural `elts`; its sort
                 is whatever the variable already has, or `Elem`, and
                 [resolve_sorts] settles the instance. *)
              | Smt.SData ("Elem", []) -> (
                match e with
                | A.EVar { A.txt = x; _ } -> if declare x s then Some (Smt.Const x) else None
                | _ -> Some (fresh s))
              (* A Bool field, or any other payload, is invisible to a
                 structural measure: an unconstrained constant of the right
                 sort keeps the VC well-sorted and asserts nothing. *)
              | _ -> Some (fresh s)
            and reflect_dt (d : string) (e : A.expr) : Smt.term option =
              match e with
              | A.EVar { A.txt = x; _ } ->
                if declare x (adt_sort d) then Some (Smt.Const x) else None
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
                  |> Option.map (fun ts -> ctor_term d ct.A.txt ts)
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
                Hashtbl.replace decls nm (adt_sort ret_adt);
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
                   (* A non-variable actual (`Cons(h, acc)` in an accumulator
                      call) is bound to a fresh constant reflected at its
                      parameter's sort, so the hypothesis reads a measure of a
                      NAME: the predicate translator would otherwise re-reflect
                      the constructor with its own resolvers, declaring `h`
                      at a sort that disagrees with its pattern binder. *)
                   let param_sort i =
                     match List.nth_opt c.A.fc_params i with
                     | Some fp -> Option.bind (param_ty_of fp) smt_sort_of_ty
                     | None -> None
                   in
                   let env =
                     List.mapi (fun i n -> (i, n, List.nth_opt args i)) params
                     |> List.filter_map (function
                          | _, "_", _ | _, _, None -> None
                          | _, n, Some (A.EVar _ as a) -> Some (n, a)
                          | i, n, Some a -> (
                            match param_sort i with
                            | Some srt -> (
                              match reflect_at srt a with
                              | Some t ->
                                incr ctr;
                                let nm = Printf.sprintf "$t2arg%d" !ctr in
                                Hashtbl.replace decls nm srt;
                                assume := Smt.Eq (Smt.Const nm, t) :: !assume;
                                Some (n, evar nm)
                              | None -> None)
                            | None -> Some (n, a)))
                   in
                   if List.for_all (fun p -> List.mem_assoc p env) ps then
                     (match pred_term cst (subst_params env pred) with
                      | Some t -> assume := t :: !assume
                      | None -> ())
                 | None -> ());
                Some cst
              (* Another function's call at a datatype sort Tier 2 declares: a
                 constant carrying that function's PROVED contract (plan steps
                 2.5 and 4.2), conjunct by conjunct, so `Nil -> reverse(acc)`
                 reads `reverse`'s postcondition and `make_node(l, k, r)` reads
                 `make_node`'s. *)
              | A.EApp (A.EVar { A.txt = f; _ }, args, _) when tier2_adt d -> (
                match !post_lookup f args with
                | None -> None
                | Some (b, q, _) ->
                  incr ctr;
                  let nm = Printf.sprintf "$t2call%d" !ctr in
                  Hashtbl.replace decls nm (adt_sort d);
                  let cst = Smt.Const nm in
                  List.iter
                    (fun conj ->
                      match pred_term_as ~bnd:b ~adt:d cst conj with
                      | Some t -> assume := t :: !assume
                      | None -> ())
                    (pred_conjuncts q);
                  Some cst)
              | _ -> None
            and reflect_int (e : A.expr) : Smt.term option =
              (* Program text (a tail or a guard): no set vocabulary. *)
              smt_of ~vocab:false ~resolve_var:rv_int ~resolve_measure:rm ~resolve_measure_app:rma e
            (* A name already declared (a type-variable parameter at `Elem`)
               keeps its sort; [resolve_sorts] settles it from its uses.  Only
               a name nothing declared is taken to be an Int. *)
            and rv_int (x : string) : Smt.term option =
              if Hashtbl.mem decls x then Some (Smt.Const x)
              else if declare x Smt.SInt then Some (Smt.Const x)
              else None
            and rm (m : string) (x : string) : Smt.term option =
              match list_structure_measure m with
              | Some lm -> Option.map (fun t -> Smt.App (lm, [ t ])) (reflect_dt list_adt (evar x))
              | None ->
              if not (is_axiom_measure m) then None
              else
                let a = Hashtbl.find axiom_measures m in
                Option.map (fun t -> Smt.App (m, [ t ])) (reflect_dt a (evar x))
            and rma (m : string) (arg : Smt.term) : Smt.term option =
              match list_structure_measure m with
              | Some lm -> Some (Smt.App (lm, [ arg ]))
              | None ->
              if not (is_axiom_measure m) then None
              else
                match concrete_measure_app m arg with
                | Some n -> Some (Smt.IntLit n)
                | None -> Some (Smt.App (m, [ arg ]))
            (* Reflect the return PREDICATE with its binder standing for [bt].
               The binder is ADT-valued, so it can appear only under a measure
               (`size(_)`) or as a bare occurrence; both route to [bt]. *)
            and pred_term (bt : Smt.term) (p : A.expr) : Smt.term option =
              pred_term_as ~bnd:binder ~adt:ret_adt bt p
            (* A predicate whose binder [bnd] stands for [bt], a term of datatype
               [adt]: this function's own return, or a callee's. *)
            and pred_term_as ~(bnd : string) ~(adt : string) (bt : Smt.term) (p : A.expr) :
                Smt.term option =
              let rv x = if x = bnd || x = "_" then Some bt else rv_int x in
              let rm' m x =
                match list_structure_measure m with
                | Some lm when (x = bnd || x = "_") && adt = list_adt -> Some (Smt.App (lm, [ bt ]))
                | Some _ -> rm m x
                | None ->
                if not (is_axiom_measure m) then None
                else if x = bnd || x = "_" then Some (Smt.App (m, [ bt ]))
                else rm m x
              in
              (* A measure over a CALL (`tree_elts(make_node(lr, k, r))` in a
                 substituted callee contract) reflects the call through
                 [reflect_dt], which carries that callee's own contract. *)
              let rmc m f cargs =
                let adt =
                  match list_structure_measure m with
                  | Some _ -> Some list_adt
                  | None -> if is_axiom_measure m then Hashtbl.find_opt axiom_measures m else None
                in
                match adt with
                | Some a ->
                  Option.bind
                    (reflect_dt a (A.EApp (A.EVar { A.txt = f; A.span = dummy_span }, cargs, dummy_span)))
                    (fun t -> rma m t)
                | None -> None
              in
              smt_of ~resolve_var:rv ~resolve_measure:rm' ~resolve_measure_app:rma
                ~resolve_measure_call:rmc p
            in
            (* The pattern equation.  Without it a match arm knows nothing about
               the scrutinee, and even the BASE case (`size(t) + 1` with `t =
               Leaf`) is unprovable.  A body with no match has no scrutinee to
               constrain — the parameters stay universally quantified, which is
               strictly WEAKER than any equation, so omitting it cannot make a
               goal provable that would otherwise fail. *)
            (match pat, mctx with
             | None, _ -> ()
             (* One equation per constructor pattern, nested ones included
                (plan step 4.3): `var = Ctor(names)`, the first over the
                matched parameter, each nested one over its fresh name. *)
             | Some (_, equations), Some _ ->
               List.iter
                 (fun (var, adt, ctor, names) ->
                   assume :=
                     Smt.Eq (Smt.Const var, ctor_term adt ctor (List.map (fun n -> Smt.Const n) names))
                     :: !assume)
                 equations
             (* A pattern with no matched parameter is not a shape we build. *)
             | Some _, None -> ok := false);
            (* A parameter's refinement is a hypothesis: every call site is
               obliged to establish it (a local that escapes reaches here with
               its parameter refinements stripped, see
               [Refine_check.visit_local_fn]).  A conjunct that does not
               translate is dropped, which only loses a proof. *)
            List.iter
              (fun (name, bnd, adt, p) ->
                List.iter
                  (fun conj ->
                    match pred_term_as ~bnd ~adt (Smt.Const name) conj with
                    | Some t -> assume := t :: !assume
                    | None -> ())
                  (pred_conjuncts p))
              param_refinements;
            (* Reflecting the tail is what mints the IH assumptions, so it must
               happen before the assumption list is read. *)
            let tail_term = reflect_dt ret_adt tail_e in
            (* A scalar call in a guard (`compare_by(cmp, x, k) < 0`, plan step
               4.4) becomes a constant carrying its callee's PROVED contract,
               so `c == 0` in the equal branch gives `x == k`.  A call with no
               scalar contract is left alone, and the guard then does not
               translate, as before. *)
            (* One constant per callee and variable arguments: `let c =
               compare_by(cmp, x, k)` is inlined into every guard that reads
               `c`, and those copies are one value.  Only all-variable
               arguments are identified, the shape an inlined `let` leaves. *)
            let call_consts : (string, string) Hashtbl.t = Hashtbl.create 4 in
            let rec abstract_calls (e : A.expr) : A.expr =
              match e with
              | A.EApp ((A.EVar { A.txt = f; _ } as hd), args, sp)
                when not (List.mem f predicate_operators) && not (is_measure_app f) -> (
                let args = List.map abstract_calls args in
                let key =
                  if List.for_all (function A.EVar _ -> true | _ -> false) args then
                    Some (f ^ "(" ^ String.concat "," (List.map (function A.EVar { A.txt; _ } -> txt | _ -> "") args) ^ ")")
                  else None
                in
                match Option.bind key (Hashtbl.find_opt call_consts) with
                | Some nm -> A.EVar { A.txt = nm; A.span = sp }
                | None ->
                match !post_lookup f args with
                | Some (b, q, marker) when scalar_sort_of_marker marker <> None ->
                  let srt = Option.get (scalar_sort_of_marker marker) in
                  incr ctr;
                  let nm = Printf.sprintf "$t2s%d" !ctr in
                  Option.iter (fun k -> Hashtbl.replace call_consts k nm) key;
                  Hashtbl.replace decls nm srt;
                  let rv x = if x = b || x = "_" then Some (Smt.Const nm) else rv_int x in
                  List.iter
                    (fun conj ->
                      match smt_of ~resolve_var:rv ~resolve_measure:rm ~resolve_measure_app:rma conj with
                      | Some t -> assume := t :: !assume
                      | None -> ())
                    (pred_conjuncts q);
                  A.EVar { A.txt = nm; A.span = sp }
                | _ -> A.EApp (hd, args, sp))
              | A.EApp (f, args, sp) -> A.EApp (abstract_calls f, List.map abstract_calls args, sp)
              | A.EAnnot (x, t, sp) -> A.EAnnot (abstract_calls x, t, sp)
              | _ -> e
            in
            List.iter
              (fun (cond, negated) ->
                match reflect_int (abstract_calls cond) with
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
                  (* The same sort resolution every other query gets: a
                     parameter declared at a generic instance meets measures
                     declared at their own instances here. *)
                  match resolve_sorts decls goal !assume with
                  | None -> Some (Obligation.Skipped Obligation.Sort_conflict)
                  | Some (decls, goal, assumptions, measure_instances) ->
                  let assumptions = card_facts decls goal assumptions in
                  let vc = { Smt.decls; assumptions; goal } in
                  let preamble =
                    !measure_preamble ^ "\n"
                    ^ query_instance_preamble ~declared:!measure_preamble ~measures:true decls goal
                        assumptions measure_instances
                  in
                  (* Set literals (`elts(Cons(h, Nil))` folds to one) need their
                     `define-sort`s, after everything that declares `Elem`. *)
                  let preamble =
                    let contains hay needle =
                      let n = String.length needle and h = String.length hay in
                      let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
                      at 0
                    in
                    preamble
                    ^ set_preamble ~elem_declared:(contains preamble "(declare-sort Elem 0)")
                        ~str_declared:false ~measure_attached:(!measure_preamble <> "") vc
                  in
                  match Refine.discharge ~root ~preamble vc with
                  | Refine.Verified -> Some Obligation.Proved
                  | _ when not refute -> Some (Obligation.Skipped Obligation.Solver_undecided)
                  (* DEFINITE failure only: "not proved" is not "violated".  The
                     predicate is reported as violated only when its NEGATION is
                     itself Verified — i.e. it can never hold. *)
                  | _ ->
                    if Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal }
                       = Refine.Verified
                    then Some Obligation.Violated
                    else Some (Obligation.Skipped Obligation.Solver_undecided))
      in
      (match induction_body c.A.fc_body with
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
              if rendered <> "<predicate>" then Printf.sprintf "the return expression `%s`" rendered
              else Printf.sprintf "the return expression of `%s`" self
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
        match induction_match_adt c mparam with
        | None -> false
        | Some madt ->
          begin
            (* Structurally smaller variables, computed over the WHOLE clause
               body so a nested match contributes its components too. *)
            let sset = structural_subvars mparam (induction_body c.A.fc_body) in
            let mctx = Some (mparam, madt, mparam_idx, sset) in
            (* Every tail's verdict, for the ledger (plan step 2.4).  A tail or
               branch no query could be built for is an unreflectable subject,
               as in Shape 1. *)
            let verdicts : Obligation.verdict list ref = ref [] in
            let unbuilt () =
              Obligation.Skipped
                (Obligation.Unreflectable_subject (Printf.sprintf "the return expression of `%s`" self))
            in
            let proved_tail ~mctx ~pat t =
              let v =
                match check_tail ~mctx ~pat ~refute:record t with Some v -> v | None -> unbuilt ()
              in
              verdicts := v :: !verdicts;
              v = Obligation.Proved
            in
            let reject () = verdicts := unbuilt () :: !verdicts; false in
            (* A constructor pattern as the binders it introduces and one
               equation per constructor in it, nested ones under fresh names
               (plan step 4.3).  [None] for a sub-pattern this does not model
               (a literal, a tuple). *)
            let pat_ctr = ref 0 in
            let rec flatten (var : string) (adt : string) (ctor : string) (subpats : A.pattern list)
                : ((string * Smt.sort) list * (string * string * string * string list) list) option =
              let fsorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
              if List.length subpats <> List.length fsorts then None
              else
                let parts =
                  List.map2
                    (fun p fs ->
                      match p with
                      | A.PatVar n -> Some (n.A.txt, [ (n.A.txt, fs) ], [])
                      | A.PatWild _ ->
                        incr pat_ctr;
                        let n = Printf.sprintf "$w%s%d" ctor !pat_ctr in
                        Some (n, [ (n, fs) ], [])
                      | A.PatCon (ct, sub) -> (
                        match fs with
                        | Smt.SData (sub_adt, _) when ctor_belongs ct.A.txt sub_adt -> (
                          incr pat_ctr;
                          let n = Printf.sprintf "$p%d" !pat_ctr in
                          match flatten n sub_adt ct.A.txt sub with
                          | Some (bs, eqs) -> Some (n, (n, fs) :: bs, eqs)
                          | None -> None)
                        | _ -> None)
                      | _ -> None)
                    subpats fsorts
                in
                if List.exists Option.is_none parts then None
                else
                  let parts = List.map Option.get parts in
                  let names = List.map (fun (n, _, _) -> n) parts in
                  Some
                    ( List.concat_map (fun (_, bs, _) -> bs) parts,
                      (var, adt, ctor, names) :: List.concat_map (fun (_, _, eqs) -> eqs) parts )
            in
            let check_branch (br : A.branch) : bool =
              let base_path =
                match br.A.branch_guard with Some g -> [ (g, false) ] | None -> []
              in
              (* Fold, not for_all: no short-circuit, so the VC cache is warmed
                 uniformly and the verdict is order-independent. *)
              let check_tails ~pat body =
                let ts = tails base_path body in
                (ts <> [] || reject ())
                && List.fold_left (fun acc t -> proved_tail ~mctx ~pat t && acc) true ts
              in
              match br.A.branch_pat with
              | A.PatCon (ct, subpats) when ctor_belongs ct.A.txt madt -> (
                match flatten mparam madt ct.A.txt subpats with
                | None -> reject ()
                | Some (binder_sorts, equations) ->
                  (* A binder that reuses a parameter's name would be
                     conflated with it (both reflect to `Const name`). *)
                  if List.exists (fun (n, _) -> List.mem n params) binder_sorts then reject ()
                  else check_tails ~pat:(Some (binder_sorts, equations)) br.A.branch_body)
              (* A catch-all arm pins nothing about the scrutinee, so it is
                 checked with no pattern equation, which is weaker: whatever
                 it proves holds for every value that reaches it (plan step
                 4.3).  A variable pattern names the matched parameter. *)
              | A.PatWild _ -> check_tails ~pat:None br.A.branch_body
              | A.PatVar v -> (
                match subst_let v.A.txt (A.EVar { A.txt = mparam; A.span = v.A.span }) br.A.branch_body with
                | Some body -> check_tails ~pat:None body
                | None -> reject ())
              | _ -> reject ()
            in
            let ok =
              branches <> []
              && List.fold_left (fun acc br -> check_branch br && acc) true branches
            in
            if record then begin
              let vs = List.rev !verdicts in
              let v =
                if ok then Obligation.Proved
                else if List.mem Obligation.Violated vs then Obligation.Violated
                else
                  match List.find_opt (fun v -> v <> Obligation.Proved) vs with
                  | Some v -> v
                  | None -> unbuilt ()
              in
              Obligation.record
                { Obligation.span = fd.A.fn_name.A.span
                ; callee = self
                ; predicate = pred_str pred
                ; verdict = v
                ; kind = Obligation.Postcondition }
            end;
            ok
          end)
      | _ -> false)

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
(* Does a predicate apply a built-in set measure (`elts`, `keys`) anywhere? *)
let rec pred_mentions_elts (e : A.expr) : bool =
  match e with
  | A.EApp (A.EVar { A.txt; _ }, args, _) ->
    is_builtin_set_measure txt || List.exists pred_mentions_elts args
  | A.EApp (f, args, _) -> pred_mentions_elts f || List.exists pred_mentions_elts args
  | A.ECon (_, args, _) | A.ETuple (args, _) -> List.exists pred_mentions_elts args
  | A.EField (r, _, _) | A.EAnnot (r, _, _) -> pred_mentions_elts r
  | _ -> false

(* ── `@[assume]`: an ASSUMED postcondition (plan §3.2) ─────────────────────
   Liquid Haskell's `assume`: the declared return refinement propagates to
   every call site WITHOUT a proof, and the body is not checked against it.
   It exists for a contract about a body the checker cannot see into — the
   stdlib `Set` HAMT, whose element set no measure can compute — and is
   counted in the ledger under `trusted`, kind postcondition, so
   `--refine-report` shows exactly how many facts a module takes on faith.
   Distinct from `@[trusted]`, which accepts a SKIP inside `cap verified` and
   never propagates anything. *)
let is_assumed (fd : A.fn_def) : bool = List.mem "assume" fd.A.fn_attrs

let assumed_return (fd : A.fn_def) : A.expr option =
  match Option.map unlinear fd.A.fn_ret_ty with
  | Some (A.TyRefine (_, _, pred)) -> Some pred
  | _ -> None

(* Does [check_fn_post_verdict] actually CHECK [fd]'s return refinement —
   file an obligation or produce a verdict — rather than fall through to a
   path that silently files nothing?  The same routing, solver-free, so
   [Refine_audit] cannot report Enforced for a contract the checker never
   looks at (a `{List(Int) | len(_) > 0}` return with no list measure, or a
   Tier 2 match on an unannotated parameter). *)
let return_refinement_checked (fd : A.fn_def) : bool =
  (is_assumed fd && assumed_return fd <> None)
  ||
  match return_refine_ext fd with
  | None -> post_induction_checks fd
  | Some (_, ret_pred, Some marker) when is_meas_sort marker && not (pred_mentions_elts ret_pred) ->
    post_induction_checks fd
  | Some _ -> true

let rec check_fn_post_verdict ~root errctx ?(emit = true) (fd : A.fn_def) : bool =
  (* A local `fn` with a refined return, defined in a clause's top-level block
     (`reverse`'s `go`), is proved first; each one proved joins the contract
     lookup for the functions after it and for the enclosing body (plan step
     2.5).  Checked with [~emit:false]: the walk checks and reports it again
     through [Refine_check.visit_local_fn]. *)
  let locals =
    List.concat_map
      (fun (c : A.fn_clause) ->
        match c.A.fc_body with
        | A.EBlock (es, _) ->
          List.filter_map
            (function
              | A.ELetFn (n, ps, (Some (A.TyRefine _) as rt), body, sp) ->
                Some (n.A.txt, local_fn_def n ps rt body sp)
              | _ -> None)
            es
        | _ -> [])
      fd.A.fn_clauses
  in
  if locals = [] then check_fn_post_verdict_core ~root errctx ~emit fd
  else
    let lookup =
      List.fold_left
        (fun lookup (n, lfd) ->
          if with_post_lookup lookup (fun () -> check_fn_post_verdict ~root errctx ~emit:false lfd)
          then
            let sg = sig_of_fn lfd in
            fun f args -> if f = n then ret_instance sg args else lookup f args
          else fun f args -> if f = n then None else lookup f args)
        !post_lookup locals
    in
    with_post_lookup lookup (fun () -> check_fn_post_verdict_core ~root errctx ~emit fd)

and check_fn_post_verdict_core ~root errctx ?(emit = true) (fd : A.fn_def) : bool =
  match assumed_return fd with
  | Some pred when is_assumed fd ->
    if emit then
      Obligation.record
        { Obligation.span = fd.A.fn_name.A.span; callee = fd.A.fn_name.A.txt
        ; predicate = pred_str pred; verdict = Obligation.Trusted
        ; kind = Obligation.Postcondition };
    true
  | _ ->
  match return_refine_ext fd with
  | None -> check_post_induction ~root ~record:emit fd
  (* A LIST return takes the elts path ONLY when its predicate uses `elts`;
     a list contract over an Int measure (`llen(_) == llen(xs) + 1`) keeps
     the Tier 2 induction path it always had, which the elts path cannot
     replace (it never reduces a measure through the recursion). *)
  | Some (_, ret_pred, Some marker) when is_meas_sort marker && not (pred_mentions_elts ret_pred) ->
    check_post_induction ~root ~record:emit fd
  (* An `elts` list contract whose body recurses over a list parameter is
     proved by induction when it can be (plan step 2.3); the elts path below,
     which reports definite failures but never reduces through the
     recursion, still runs when induction does not prove it. *)
  | Some (_, ret_pred, Some marker)
    when is_meas_sort marker && post_induction_checks fd
         && check_post_induction ~root ~record:false fd ->
    (* Recorded here, once: the elts path records its own verdict when it runs
       instead, so the induction attempt itself must not. *)
    if emit then
      Obligation.record
        { Obligation.span = fd.A.fn_name.A.span; callee = fd.A.fn_name.A.txt
        ; predicate = pred_str ret_pred; verdict = Obligation.Proved
        ; kind = Obligation.Postcondition };
    true
  | Some (binder, ret_pred, marker) ->
    (* [record_sort] must carry only a DECLARED sort name.  A scalar marker
       (`$Bool`) is not one: handing it here would send the return value down
       the record-literal reflection and the datatype preamble, for a sort
       nobody declares. *)
    (* …nor is the opaque `Str` sort a record: a String return takes
       [check_post]'s [string_ret] path (literal minting, `$strlen`), never
       the record-literal reflection. *)
    let record_sort =
      match marker with
      | Some s when not (is_scalar_sort s) && s <> str_sort && not (is_meas_sort s) -> Some s
      | _ -> None
    in
    let string_ret = marker = Some str_sort in
    let list_ret = (match marker with Some s -> is_meas_sort s | None -> false) in
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
             check_post ~root errctx ~span:c.A.fc_span ~record_sort ~scalar_env ~string_ret
               ~list_ret ~fn_name:(Some fd.A.fn_name.A.txt) ~emit ~record:emit ~fn_params
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
   [check_fn_post] during the walk; the repeated discharge hits the VC cache. 


   Since plan step 2.5 a postcondition check may itself use a callee's
   contract ([post_lookup]), so the gate is a monotone fixpoint: every
   postcondition starts unproven (absent from [defs]), each round checks the
   ones not yet proven with only the contracts proven so far in view, and a
   proof is admitted to [defs] at once.  A contract is therefore never used
   before it is proved, cycles included (neither side of a mutual dependency
   can be proved from the other's unproven contract).  A later round
   re-checks only a function that calls a name proved in the round before. *)
let gate_unverified_posts ~root errctx (defs : (string, fn_sig option) Hashtbl.t)
    (decls : A.decl list) : unit =
  let pending = ref [] in
  let rec collect prefix decls =
    List.iter
      (function
        | A.DFn (fd, _) ->
          let key = if prefix = "" then fd.A.fn_name.A.txt else prefix ^ "." ^ fd.A.fn_name.A.txt in
          (match Hashtbl.find_opt defs key with
           (* Only a declaration that itself carries a refined return: two
              declarations can share a key (checking `stdlib/list.march`
              directly puts `List`'s functions beside the prelude's own
              unrefined `reverse`), and checking the unrefined one used to
              drop the other's postcondition. *)
           | Some (Some sg) when Option.is_some sg.ret && assumed_return fd <> None ->
             (* Keep the entry (it must still shadow an outer same-named
                function for [resolve_call]); drop the postcondition until it
                is proved. *)
             Hashtbl.replace defs key (Some { sg with ret = None });
             pending := (key, prefix, fd, sg) :: !pending
           | _ -> ())
        | A.DMod (name, _, ds, _) ->
          collect (if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt) ds
        | _ -> ())
      decls
  in
  collect "" decls;
  let rec calls_of (acc : string list) (e : A.expr) : string list =
    match e with
    | A.EApp (A.EVar { A.txt; _ }, args, _) -> List.fold_left calls_of (txt :: acc) args
    | A.EApp (f, args, _) -> List.fold_left calls_of (calls_of acc f) args
    | A.EBlock (es, _) | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) ->
      List.fold_left calls_of acc es
    | A.ELet (b, _) -> calls_of acc b.A.bind_expr
    | A.ELetFn (_, _, _, body, _) | A.ELam (_, body, _) -> calls_of acc body
    | A.EMatch (x, brs, _) ->
      List.fold_left
        (fun acc (br : A.branch) ->
          let acc = match br.A.branch_guard with Some g -> calls_of acc g | None -> acc in
          calls_of acc br.A.branch_body)
        (calls_of acc x) brs
    | A.EIf (c, t, f, _) -> calls_of (calls_of (calls_of acc c) t) f
    | A.EPipe (a, b, _) -> calls_of (calls_of acc a) b
    | A.EAnnot (x, _, _) | A.EField (x, _, _) -> calls_of acc x
    | _ -> acc
  in
  let short key = match String.rindex_opt key '.' with Some i -> String.sub key (i + 1) (String.length key - i - 1) | None -> key in
  let check (key, prefix, fd, sg) =
    let lookup = postcond_of { rctx0 with modpath = prefix } defs in
    if with_post_lookup lookup (fun () -> check_fn_post_verdict ~root errctx ~emit:false fd) then begin
      Hashtbl.replace defs key (Some sg);
      true
    end
    else false
  in
  let rec rounds (todo : (string * string * A.fn_def * fn_sig) list) (fresh : string list option) =
    let eligible (_, _, (fd : A.fn_def), _) =
      match fresh with
      | None -> true
      | Some names ->
        let called =
          List.concat_map (fun (c : A.fn_clause) -> calls_of [] c.A.fc_body) fd.A.fn_clauses
        in
        List.exists (fun n -> List.mem n names || List.mem (short n) names) called
    in
    let proved, rest =
      List.partition (fun item -> eligible item && check item) todo
    in
    if proved <> [] && rest <> [] then
      rounds rest (Some (List.concat_map (fun (k, _, _, _) -> [ k; short k ]) proved))
  in
  rounds (List.rev !pending) None

