(** Refinement checking, §12–§13: name resolution and argument reflection.

    Moved VERBATIM out of [Refine_check] (R3 of
    [specs/plans/2026-08-28-refine-check-decomposition.md]):

      §12 Name resolution: module paths, aliases, call targets
      §13 Reflecting actual arguments: fields, records, scalars

    §12 is the FOURTH fact channel — callee resolution.  Resolving a call the
    way the typechecker does (bare names bind to the nearest enclosing module
    that defines them, with shadowing) is what decides WHICH contract a call
    site is checked against, so a bug here silently checks the wrong function's
    preconditions.

    Note for anyone re-verifying this band: [scripts/refine-oracle.sh] is
    NOT sufficient here.  Forcing [term_fits_sort] to [false] leaves all 298
    of its accepting fixtures byte-identical while breaking the reject corpus
    (`dune build @types-check --force`).  Measured, not assumed. *)

include Refine_scope

(* =================================================================
   §12 Name resolution: module paths, aliases, call targets
   ================================================================= *)

(* ── Use/alias-aware call resolution ───────────────────────────────────────
   Resolve a call name the way the typechecker does: a bare name binds to the
   nearest enclosing module that defines it (lexical scope, with shadowing); an
   alias-qualified name (`alias X.Y as P` → `P.foo`) expands to the original; a
   `use`-imported bare name binds to the exporting module.  This replaces the
   previous "qualified key OR globally-unique bare name" matching, which dropped
   sibling calls on any cross-module name collision and never resolved aliased or
   `use`-imported names. *)
let dotted (path : A.name list) : string = String.concat "." (List.map (fun n -> n.A.txt) path)

type rctx = {
  modpath : string;                       (* enclosing module prefix, "" at top *)
  aliases : (string * string) list;       (* (alias short, original dotted prefix) *)
  (* (exporting module dotted, selector, scope) — [scope] is the modpath of
     the module that OWNS this `use` (recorded at [A.DUse]-gathering time,
     where [ctx.modpath] is exactly that module).  Needed because [ctx.uses]
     inherits into nested modules while declaration-list competition does
     not: without a scope tag, [resolve_call] cannot tell an inner module's
     own `use` from an enclosing one, and either always preferring defs over
     uses (the pre-fix bug: an enclosing def wrongly beats a nearer `use`) or
     always preferring uses over defs (the mirror-image bug: an outer `use`
     wrongly beats an inner module's own def) is wrong in one direction. *)
  uses : (string * A.use_selector * string) list;
  (* Names bound by an ENCLOSING BINDER (parameter, `let`, `let?`, lambda
     parameter, local `fn` name/parameter, `match` arm binder).  See
     [local_shadow]. *)
  locals : string list;
}

let rctx0 = { modpath = ""; aliases = []; uses = []; locals = [] }

(* ── The FOURTH fact channel: callee resolution ────────────────────────────
   [scope], [path], [recenv] and [cbenv] each carry facts keyed by a variable
   NAME, and each one already retires a name a binding construct rebinds.  The
   GLOBAL DEFINITION TABLE consulted by [resolve_call] is a fact channel of
   exactly the same shape — "the name `f` denotes this contract" — and it needs
   exactly the same discipline:

     fn takepos(k : {Int | _ >= 0}) : Int do k end
     fn probe() : Int do
       let takepos = fn n -> n     -- a LOCAL, unrefined, that runs
       takepos(-3)                 -- must NOT be checked against the global
     end

   Resolving that call to the module-level `takepos` checks correct code
   against a contract it never touches — a false positive, the one failure
   this subsystem must never have.  So [rctx.locals] records every name an
   enclosing binder introduced, and [resolve_call] refuses to resolve one.

   Retiring a name here can only turn a check into a SKIP, never the reverse,
   so over-approximating [locals] is always safe. *)
let local_shadow (ctx : rctx) (names : string list) : rctx =
  if names = [] then ctx else { ctx with locals = names @ ctx.locals }

let fnparam_binders : A.fn_param -> string list = function
  | A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ]
  | A.FPPat pat -> pat_binders pat

(* Enclosing-module prefixes of [mp], innermost first: "A.B" -> ["A.B"; "A"; ""]. *)
let modpath_prefixes (mp : string) : string list =
  let segs = if mp = "" then [] else String.split_on_char '.' mp in
  let n = List.length segs in
  List.init (n + 1) (fun i -> String.concat "." (List.filteri (fun j _ -> j < n - i) segs))

(* Resolve a call name to a definition:
     Some (Some sig) -> a refined function (check it)
     Some None       -> a real but non-refined function (skip — no predicate)
     None            -> unresolved / external (skip)
   Only Some (Some sig) leads to a check, so a wrong resolution can at worst
   *skip* — it can never check against the wrong predicate. *)
let resolve_call (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (fname : string)
  : fn_sig option option =
  let lookup k = Hashtbl.find_opt defs k in
  let qualify p n = if p = "" then n else p ^ "." ^ n in
  (* 0. A name an enclosing binder introduced is a LOCAL, not this module's
        function of that name — see [local_shadow].  Bail out before any
        lookup: the local shadows the global at every one of the three
        resolution steps below, alias- and `use`-imported names included. *)
  if List.mem fname ctx.locals then None
  else
  (* 1. Scope-aware walk: at each prefix `p` of [ctx.modpath], from innermost
        to outermost, that prefix's own DEFINITION wins first, then that
        SAME prefix's own `use`-imports, before falling outward to the next
        prefix.  This is what makes a nested `use` beat an enclosing
        definition (the fix — the `use` is recorded at the inner prefix, so
        it is consulted before the walk ever reaches the outer prefix that
        owns the shadowed definition) while an outer module's `use` still
        loses to an inner module's own definition (the inner prefix's own
        def is found before the walk ever reaches the outer prefix that owns
        the `use`). *)
  let use_at prefix =
    (* `use`-imported names are always bare (never dotted) — see the old
       step 3's guard, preserved here. *)
    if String.contains fname '.' then None
    else
      List.find_map
        (fun (m, sel, scope) ->
          if scope <> prefix then None
          else
            let imported =
              match sel with
              | A.UseAll -> true
              | A.UseNames ns -> List.exists (fun (n : A.name) -> n.A.txt = fname) ns
              | A.UseExcept ns -> not (List.exists (fun (n : A.name) -> n.A.txt = fname) ns)
              | A.UseSingle -> false
            in
            if imported then lookup (qualify m fname) else None)
        ctx.uses
  in
  match
    List.find_map
      (fun p -> match lookup (qualify p fname) with Some r -> Some r | None -> use_at p)
      (modpath_prefixes ctx.modpath)
  with
  | Some r -> Some r
  | None ->
    (* 2. Alias-qualified `P.rest` with `alias X.Y as P` -> `X.Y.rest`. *)
    let aliased =
      match String.index_opt fname '.' with
      | Some i ->
        let head = String.sub fname 0 i in
        let rest = String.sub fname (i + 1) (String.length fname - i - 1) in
        (match List.assoc_opt head ctx.aliases with Some orig -> lookup (orig ^ "." ^ rest) | None -> None)
      | None -> None
    in
    aliased

(* True iff a call written as the bare [name] from inside [ctx]'s module
   resolves to exactly [sg] — i.e. the contract every caller is obliged to
   establish IS this definition's.  Used to decide whether an `impl` method's
   parameter refinements may be assumed while walking its body; see
   [collect_all_defs]'s merge step for the cases where it is false. *)
let contract_is_enforced (ctx : rctx) defs (name : string) (sg : fn_sig) : bool =
  match resolve_call ctx defs name with
  | Some (Some found) -> found.refined = sg.refined
  | _ -> false

(* Populate [cbenv] from a LOCAL ALIAS of a named refined function (Task 2):
   only a bare-variable RHS that [resolve_call] resolves to a refined function
   counts — a call, a field access, or a lambda RHS is never chased, so the
   alias fact is only ever a straight rename of a known callee, never a guess
   about the shape of a computed value.  Shadowing happens FIRST, matching
   [scope_add_binding]/[recenv_add_binding]. *)
let cb_add_binding (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (cb : cbenv)
    (b : A.binding) : cbenv =
  let cb = cb_shadow cb (pat_binders b.A.bind_pat) in
  match b.A.bind_pat, b.A.bind_expr with
  | A.PatVar n, A.EVar { A.txt = fname; _ } ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) -> (n.A.txt, sg) :: cb
     | _ -> cb)
  | _ -> cb

(* Resolve a call name and its actual arguments to the callee's return
   refinement, expressed entirely in the CALLER's namespace, or None.  This is
   the single place the usability filter is applied, so both use sites (a
   let-bound local and an inline argument) agree.

   [Closed]        the predicate mentions only the binder; it means the same
                   thing at every call site, so it is returned unchanged.
   [Relational ps] the predicate mentions parameters; the call's actuals are
                   substituted for them SIMULTANEOUSLY, so the result talks
                   about the caller's terms and the existing reflection
                   machinery needs no changes.
   [Unusable]      never propagated.

   Skip, don't guess: if any parameter the predicate mentions has no
   corresponding actual (arity mismatch, a pattern parameter, an omitted
   defaulted argument), propagation is abandoned for this call.  A partially
   substituted predicate would mix the callee's and caller's namespaces —
   exactly the conflation that has produced false positives here before.

   The other half of the filter is applied earlier: [gate_unverified_posts]
   has already cleared [ret] on every signature whose postcondition the
   definition side did not PROVE, so anything reaching here is a fact.

   The third component of the result is the returned value's SMT sort ([None]
   for Int); see [fn_sig.ret_sort] for why every consumer must branch on it. *)
let postcond_of (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (fname : string)
    (args : A.expr list) : (string * A.expr * string option) option =
  match resolve_call ctx defs fname with
  | Some (Some sg) ->
    (match sg.ret with
     | Some (b, p) ->
       let srt = sg.ret_sort in
       (match classify_pred b sg.param_names p with
        | Closed -> Some (b, p, srt)
        | Unusable -> None
        | Relational ps ->
          (* Positional formal -> actual.  A formal recorded as "_" is a
             pattern parameter with no usable name; it can never be a member of
             [ps] (the classifier reads "_" as the binder), and mapping it would
             be meaningless, so it is excluded here too. *)
          let env =
            List.mapi (fun i n -> (n, List.nth_opt args i)) sg.param_names
            |> List.filter_map (function
                 | "_", _ | _, None -> None
                 | n, Some a -> Some (n, a))
          in
          if List.for_all (fun p -> List.mem_assoc p env) ps then
            Some (b, subst_params env p, srt)
          else None)
     | _ -> None)
  | _ -> None

(* =================================================================
   §13 Reflecting actual arguments: fields, records, scalars
   ================================================================= *)

(* Fresh-name counter for SMT constants standing in for a call's return value.
   Monotonic per compilation; freshness is all that is required. *)
let ret_ctr = ref 0

(* ── Record reflection helpers ────────────────────────────────────────────
   Shared by the call-site (precondition) and return-site (postcondition)
   checks, so both sides map a record value and its field projections into SMT
   exactly the same way. *)

(* Build a resolve_field closure for a known record binder: v.fname becomes the
   SMT selector applied to the term representing v. *)
let make_field_resolver (binder : string) (sort_name : string) (binder_term : Smt.term)
    : string -> string -> Smt.term option =
  fun varname fname ->
    if varname <> binder && varname <> "_" then None
    else
      match Hashtbl.find_opt adt_ctors sort_name with
      | Some [ ctor ] ->
        (match Hashtbl.find_opt ctor_field_names ctor with
         | None -> None
         | Some names ->
           let rec find_idx i = function
             | [] -> None
             | n :: _ when n = fname -> Some i
             | _ :: rest -> find_idx (i + 1) rest
           in
           (match find_idx 0 names with
            | None -> None
            | Some idx ->
              Some (Smt.App (Printf.sprintf "%s_%d" ctor idx, [ binder_term ]))))
      | _ -> None

(* Evaluate a field-selector application on a concrete constructor term.
   <ctor>_<idx>(App(ctor, args)) → args[idx] — enables concrete len evaluation
   through record field projections like State_1(State(1, Nil)) → Nil. *)
let rec selector_reduce (term : Smt.term) : Smt.term =
  match term with
  | Smt.App (selector, [ (Smt.App (ctor, args) as inner) ]) ->
    let prefix = ctor ^ "_" in
    let plen = String.length prefix in
    if String.length selector > plen && String.sub selector 0 plen = prefix then
      match int_of_string_opt (String.sub selector plen (String.length selector - plen)) with
      | Some idx when idx >= 0 && idx < List.length args -> selector_reduce (List.nth args idx)
      | _ -> Smt.App (selector, [ inner ])
    else Smt.App (selector, [ inner ])
  | other -> other

(* Evaluate `len` on a concrete SMT list term (Nil / Cons / selector chain).
   Returns None for opaque (variable/unknown) terms — avoids quantifier-based
   axioms that would cause Z3 to return `unknown` instead of sat/unsat. *)
let rec concrete_len (term : Smt.term) : int option =
  match selector_reduce term with
  | Smt.App ("Nil", []) -> Some 0
  | Smt.App ("Cons", [ _h; t ]) -> Option.map (( + ) 1) (concrete_len t)
  | _ -> None

(* Try to evaluate an axiom measure on a concrete SMT term.
   Uses selector_reduce to unfold record projections, then matches the
   constructor against known base cases (measure_base_cases).  For
   inductive cases we recurse up to a depth limit to avoid loops.
   Returns None if the term is opaque, not a base case, or too deep. *)
let concrete_measure_app (name : string) (arg_term : Smt.term) : int option =
  match Hashtbl.find_opt measure_base_cases name with
  | None -> None
  | Some bases ->
    let go term =
      match selector_reduce term with
        | Smt.App (ctor, []) ->
          (* Zero-arg constructor: look up in base cases *)
          List.assoc_opt ctor bases
        | Smt.App (_ctor, _args) ->
          (* Multi-arg constructor: not a base case for simple measures;
             would need the step case — give up for now *)
          None
        | _ ->
          (* Non-App after selector_reduce: opaque (variable, literal, etc.).
             selector_reduce is a fixed point on non-App terms, so further
             recursion cannot reduce it — return None immediately. *)
          None
    in
    go arg_term

(* True when [t] is a WELL-SORTED term for a constructor field of [sort].

   This check is not cosmetic.  The scalar reflection declares every variable it
   meets as `SInt`, so a record field of a non-Int type bound to a variable
   (`{ port: 8080, name: n }` where `name : String` has SMT sort `Elem`) would
   build a constructor application whose argument sorts do not match the
   datatype declaration.  Z3 answers such a VC with an `(error …)` rather than
   sat/unsat, and that error desynchronises the long-lived `z3 -in` channel —
   silently disabling refinement checking for the REST of the compilation.  A
   malformed VC is therefore far worse than a skipped one, so any field we
   cannot place at its declared sort makes the whole record unreflectable.

   Int/Bool fields accept any scalar term except a constructor application;
   a datatype-sorted field accepts only a constructor OF THAT SORT (so
   `history: Nil` still reflects, while `history: xs` — an opaque variable —
   does not).

   The check RECURSES into a constructor's arguments, because a top-level fit
   is not enough: `history: Cons(1, Nil)` places a well-sorted `M_List`
   constructor at an `M_List` field, but `Cons`'s own head field is declared
   `Elem` (the built-in `List` is generic, so its element sort is opaque) and
   the scalar reflection hands it the integer `1`.  Z3 rejects `(Cons 1 Nil)`
   with a multi-line `(error …)`, which is the very desynchronisation this
   function exists to prevent — so a list literal with concrete elements makes
   the record unreflectable, and the call is skipped. *)
let rec term_fits_sort (sort : Smt.sort) (t : Smt.term) : bool =
  let is_ctor_app = function
    | Smt.App (c, _) -> Hashtbl.mem ctor_field_sorts c
    | _ -> false
  in
  match sort with
  | Smt.SInt | Smt.SBool -> not (is_ctor_app t)
  (* Float RECORD FIELDS are out of scope: [smt_sort_of_field] never produces
     `SFloat` (a `Float` field is opaque `Elem`), so this arm is unreachable —
     and if a later change makes it reachable, refusing the fit makes the record
     unreflectable and the call skipped, which is the safe direction. *)
  | Smt.SFloat -> false
  | Smt.SData s ->
    (match t with
     | Smt.App (ctor, args) ->
       (match Hashtbl.find_opt adt_ctors s with
        | Some cs when List.mem ctor cs ->
          (* Every argument must sit at its own declared field sort.  An arity
             mismatch, or a constructor we have no field sorts for, is treated
             as a non-fit — again the skip direction. *)
          (match Hashtbl.find_opt ctor_field_sorts ctor with
           | Some fsorts when List.length fsorts = List.length args ->
             List.for_all2 term_fits_sort fsorts args
           | Some _ -> false
           | None -> args = [])
        | _ -> false)
     | _ -> false)

(* Reflect an ERecord literal as a constructor application in SMT.
   Fields are reordered to match the declaration order stored in ctor_field_names.
   Returns None if any field is MISSING.

   [opaque] decides what happens to a field that is untranslatable, or that
   reflects to a term not WELL-SORTED at its declared sort (`history:
   Cons(1, Nil)`, `name: n` for a `String` `n`).  Without it — the default, and
   what the postcondition side keeps — the whole record reflects to None and
   the check is skipped, losing the perfectly checkable sibling fields with it.
   With it, the offending field is replaced by a FRESH constant that [opaque]
   mints and declares AT THAT FIELD'S DECLARED SORT.

   Why the substitution is sound *for the call-site check only*.  The stand-in
   carries no assumptions whatsoever, so it denotes an arbitrary value of the
   right sort and nothing can be concluded about it in either direction.  The
   call-site decision procedure reports only when `¬goal` is VERIFIED — valid
   for every assignment — so a goal that depends on the stand-in is never
   reported (nor ever discharged), while a goal that depends only on the
   reflected siblings is decided exactly as if the record had been fully known.

   It must NOT be used by [check_post]: with a concrete record in scope that
   check switches to "a SAT model is a definite violation", and a model free to
   assign the stand-in a bad value would then be reported as a counterexample
   even though the real field holds a fine value — a false positive.  Hence the
   argument is optional and the return side never passes it. *)
let reflect_record_literal ?(opaque : (Smt.sort -> Smt.term) option)
    (sort_name : string) (fields : (A.name * A.expr) list)
    (reflect_scalar : A.expr -> Smt.term option) : Smt.term option =
  match Hashtbl.find_opt adt_ctors sort_name with
  | Some [ ctor ] ->
    (match Hashtbl.find_opt ctor_field_names ctor, Hashtbl.find_opt ctor_field_sorts ctor with
     | Some fname_list, Some fsorts when List.length fname_list = List.length fsorts ->
       let field_map = List.map (fun (n, e) -> (n.A.txt, e)) fields in
       let in_order =
         List.filter_map (fun fname -> List.assoc_opt fname field_map) fname_list
       in
       if List.length in_order <> List.length fname_list then None
       else
         let reflected =
           List.map2
             (fun e s ->
               match reflect_scalar e with
               | Some t when term_fits_sort s t -> Some t
               | _ -> Option.map (fun mk -> mk s) opaque)
             in_order fsorts
         in
         if List.exists Option.is_none reflected then None
         else Some (Smt.App (ctor, List.filter_map Fun.id reflected))
     | _ -> None)
  | _ -> None

(* ── Reflect a scalar actual argument into (term, decls, assumptions) ─────── *)
(* [sort] is the SCALAR SMT sort the reflected value lives at — `Int` (the
   original and still the default), `Bool`, or `Float64`.  It is chosen from a
   DECLARED type by the caller, never inferred from the actual, and it governs
   both the declaration emitted for a variable and the one for a propagated
   postcondition's constant.  Getting it wrong puts one symbol at a sort its
   uses disagree with, which z3 rejects. *)
(* [foreign_var] / [foreign_measure]: how a name in a caller-scope refinement
   that is NOT that refinement's own subject resolves.

   `fn pick(n : Int, i : {Int | _ < n}) … at(n, i)` — the promise carried by `i`
   mentions `n`, a sibling PARAMETER. Until these existed, the resolver below
   mapped every non-subject name to [None], and [smt_of] fails on a sub-term, so
   ONE foreign name discarded the WHOLE predicate: the VC for `at(n, i)` was its
   negated goal and nothing else, satisfiable both ways, silently skipped. The
   identical fact arriving as a path guard (`if i < n do at(n, i)`) proved,
   because THAT channel has a full caller-namespace resolver — so the defect was
   never in the solver or the goal, only in which facts reached it.

   Defaulting both to [None] keeps every other caller byte-identical: only the
   call-site builder, which owns the caller namespace (sorts, string/record
   registries, the measure memo), passes them. *)
let rec reflect_scalar
    ~(postcond : string -> A.expr list -> (string * A.expr * string option) option)
    ?(foreign_var : (string -> (Smt.term * (string * Smt.sort)) option) option)
    ?(foreign_measure : (string -> string -> Smt.term option) option)
    ?(foreign_field :
        (string -> string -> (Smt.term * (string * Smt.sort) list) option) option)
    ?(sort : Smt.sort = Smt.SInt) (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  let foreign_var = Option.value foreign_var ~default:(fun _ -> None) in
  let foreign_measure =
    Option.value foreign_measure ~default:(fun _ _ -> None)
  in
  (* A field read in ACTUAL position — `takepos(a.rem)`.  The caller supplies
     the same selector term its PATH conditions reflect `a.rem` to, so a guard
     (`if a.rem >= 0`) and this goal meet on one symbol; without it the field
     access reached [smt_of]'s default resolver, came back None, and took the
     whole obligation down with it as "unreflectable" — silently, since an
     undecidable obligation is accepted. Callers that cannot model the record
     leave it unset and get exactly the old behaviour. *)
  let foreign_field = Option.value foreign_field ~default:(fun _ _ -> None) in
  (* Reflect an expression with no scope help — also the fallback for a call
     whose callee has no usable postcondition. *)
  let plain e =
    let extra = ref [] in
    let resolve_field x fname =
      match foreign_field x fname with
      | Some (t, ds) ->
        List.iter (fun d -> if not (List.mem d !extra) then extra := d :: !extra) ds;
        Some t
      | None -> None
    in
    match smt_of ~resolve_var:(fun _ -> None) ~resolve_measure:(fun _ _ -> None)
            ~resolve_field e with
    | Some t -> Some (t, !extra, [])
    | None -> None
  in
  match actual with
  | A.EVar { A.txt = x; _ } ->
    let xc = Smt.Const x in
    (match List.assoc_opt x sc with
     (* A refined local at the SAME scalar sort we are reflecting into (Int for
        the original `None` marker, Bool for `$Bool`): carry its own refinement
        as an assumption.  A scope entry at a DIFFERENT sort says nothing about
        the value at this one, and loading it would be ill-sorted, so it falls
        through to the unconstrained constant below. *)
     | Some (b, q, m) when scalar_sort_of_marker m = Some sort ->
       (* All three spellings of the refined value denote it: the anonymous `_`,
          the declared binder [b], and the variable's own name [x].  Matches
          [load_scope_measure_facts]'s [is_self_spelling] — the two sides of the
          same fact must accept the same spellings or they meet on different
          symbols. *)
       let extra = ref [] in
       let rv n =
         if n = b || n = "_" || n = x then Some xc
         else
           match foreign_var n with
           | Some (t, d) ->
             if not (List.mem d !extra) then extra := d :: !extra;
             Some t
           | None -> None
       in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:foreign_measure q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (xc, (x, sort) :: !extra, assumptions)
     | Some _ | None ->
       (* An ordinary variable: reflect it as a constant so a path-context
          guard about it can constrain it.  Without a guard it stays
          unconstrained and the definite-failure check keeps us silent. *)
       Some (xc, [ (x, sort) ], []))
  (* An infix operator is spelled as an application of its name.  Dispatching
     it as a named call sends it to [plain], whose variable resolver is
     hard-coded to None, so `n - 1` never reflected and the PREDICATE was
     blamed for a subject the caller never gave a chance to reflect.  Reflect
     the operands through this same function — same [sc]/[sort]/resolvers —
     so a guard on `n` reaches `n - 1`. Any operand that fails to reflect
     falls the WHOLE actual back to [plain], never a partial term. *)
  | A.EApp (A.EVar { A.txt = ("+" | "-") as op; _ }, [ a; b ], _) ->
    (match
       reflect_scalar ~postcond ~foreign_var ~foreign_measure ~foreign_field ~sort sc
         a,
       reflect_scalar ~postcond ~foreign_var ~foreign_measure ~foreign_field ~sort sc
         b
     with
     | Some (ta, da, aa), Some (tb, db, ab) ->
       let t = if op = "+" then Smt.Add (ta, tb) else Smt.Sub (ta, tb) in
       Some (t, da @ db, aa @ ab)
     | _ -> plain actual)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), e | e, A.ELit (A.LitInt k, _) ->
       (match
          reflect_scalar ~postcond ~foreign_var ~foreign_measure ~foreign_field
            ~sort sc e
        with
        | Some (te, de, ae) -> Some (Smt.MulLit (k, te), de, ae)
        | None -> plain actual)
     | _ -> plain actual)
  (* A direct named call: stand its result up as a fresh constant carrying the
     callee's declared postcondition.  `.` is a legal SMT-LIB simple-symbol
     character, so a qualified name needs no mangling. *)
  | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) ->
    (* A postcondition at any OTHER sort than the one we are reflecting into is
       not a fact about this value: an ADT-sorted one (carried by [reflect_dt]
       instead), or a Bool one where an Int is expected.  Standing it up here
       would declare one symbol at two sorts, so it falls through to [plain]. *)
    (match postcond fname cargs with
     | Some (b, q, m) when scalar_sort_of_marker m = Some sort ->
       incr ret_ctr;
       let nm = Printf.sprintf "%s$ret%d" fname !ret_ctr in
       let c = Smt.Const nm in
       let rv n = if n = b || n = "_" then Some c else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (c, [ (nm, sort) ], assumptions)
     | Some _ | None -> plain actual)
  | _ -> plain actual

(* The registered ADT sort a constructor belongs to.  None when the name is
   unknown OR when it is ambiguous across two registered ADTs (March allows the
   same bare constructor name in two modules): an ambiguous tag identifies no
   particular datatype, so the tester says nothing definite and is skipped. *)
let sort_of_ctor (ctor : string) : string option =
  match
    Hashtbl.fold
      (fun sort ctors acc -> if List.mem ctor ctors then sort :: acc else acc)
      adt_ctors []
  with
  | [ s ] -> Some s
  | _ -> None

