(** Refinement checking, §1–§6: the SMT encoding and sort discipline.

    The bottom of the refinement pipeline, moved VERBATIM out of
    [Refine_check] (see
    [specs/plans/2026-08-28-refine-check-decomposition.md]).  It is the one
    band in that file with ZERO backward dependencies — nothing here refers to
    anything defined later in the pass — which is why it comes out first.

    Sections, using the numbering of [Refine_check]'s own table of contents:

      §1  Refined parameters and base-type classification
      §2  SMT sorts: strings, scalars, measures, well-sortedness
      §3  Predicate scope and parameter substitution
      §4  Function signatures, measures, and stdlib-provided names
      §5  ADT and record sorts: registry and SMT preamble builders
      §6  AST traversal helpers and measure gating

    ── Why [Refine_check] pulls this back in with [include] ─────────────────

    Not aliases.  This band owns SIXTEEN of the pass's twenty top-level
    mutable cells — [registered_measures], [withdrawals], [adt_ctors],
    [axiom_measures], [ctor_field_sorts], the measure preambles — and every
    one of them is MUTATED from the far end of the pass ([registered_measures]
    is cleared and rebuilt during registration; [withdrawals] is reset per
    module).  [include] re-exports the same ref cell, so those writes still
    land where the readers here look.  Re-declaring a cell instead would
    silently create a SECOND one: the reset would clear a ref nobody reads,
    and every fixture that merely ACCEPTS would still pass.  [refine_check.mli]
    also exports several of these names, which [include] preserves for free. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

(* =================================================================
   §1  Refined parameters and base-type classification
   ================================================================= *)

(* A refined parameter: position, predicate binder, predicate expression, and
   the SMT sort of its base type when that base is NOT `Int`:
     - [str_sort] when the base is `String` — the binder reflects into the
       opaque `Str` sort rather than `Int`;
     - a registered ADT's sort name — the call site reflects the actual
       argument as a datatype term instead of a scalar;
     - a registered 1-constructor RECORD's sort name (`Some "M_Config"`), a
       special case of the ADT line above: the call site additionally resolves
       the predicate's `v.field` projections through that sort's selectors;
     - [None] for a plain `Int`.
   Use [rp_is_str] rather than comparing against [str_sort] by hand, and
   [is_record_sort] rather than testing for a record shape by hand. *)
type rparam = { idx : int; binder : string; pred : A.expr; sort : string option }

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

let is_string_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "String"; _ }, []) -> true
  | _ -> false

let is_bool_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> true
  | _ -> false

let is_float_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Float"; _ }, []) -> true
  | _ -> false

(* =================================================================
   §2  SMT sorts: strings, scalars, measures, well-sortedness
   ================================================================= *)

(* ── The String encoding ───────────────────────────────────────────────────
   `String` is modelled as an UNINTERPRETED SORT and `len` as an uninterpreted
   function `Str -> Int` constrained only by non-negativity.  Each distinct
   string literal appearing in a VC becomes a declared constant with its length
   pinned and its distinctness from every other literal asserted.

   This deliberately stays inside the EUF + linear-arithmetic fragment that
   `Smt.render` already emits — structurally the same trick as list `len`.  We
   do NOT use Z3's string theory (`str.len`, `str.++`, the built-in `String`
   sort, regex): staying decidable and cheap is the whole point of the scoping.

   The consequence to keep in mind is that `Str` is opaque: knowing a value is
   DISTINCT from the empty literal does not establish its length (there is no
   injectivity axiom relating a string to its length).  So an `s == ""` guard
   proves nothing about `len(s)` in the else-branch, and the checker stays
   silent there — correct under the definite-failure stance, and documented as
   a limitation rather than papered over.

   All three SMT names below contain `$`, which is legal in an SMT-LIB simple
   symbol but CANNOT occur in a March identifier.  That is load-bearing, not
   cosmetic: a plain `len` symbol collides with any user or stdlib variable
   named `len`, and a colliding `(declare-const len Int)` next to
   `(declare-fun len …)` makes z3 emit an error line.  The solver is one
   long-lived `z3 -in` process shared by the whole compilation and the driver
   reads exactly one verdict line per query, so a single such error
   DESYNCHRONISES the channel and corrupts every subsequent VC in the run. *)
let str_sort = "$Str"
let strlen_fn = "$strlen"

let string_preamble =
  Printf.sprintf
    "(declare-sort %s 0)\n\
     (declare-fun %s (%s) Int)\n\
     (assert (forall ((s %s)) (! (>= (%s s) 0) :pattern ((%s s)))))\n"
    str_sort strlen_fn str_sort str_sort strlen_fn strlen_fn

(* Does this refined parameter's base type reflect into the `Str` sort?  The
   one place [rparam.sort] is compared against [str_sort]; every other consumer
   of [sort] treats a `Some _` it does not recognise as an ADT sort name. *)
let rp_is_str (rp : rparam) : bool = rp.sort = Some str_sort

(* ── Bool and Float: markers for BUILT-IN SMT sorts ───────────────────────
   The `sort` marker channel ([rparam.sort], [scope]'s third component,
   [fn_sig.ret_sort]) was originally "None = Int, Some s = a DECLARED sort
   name" — an ADT's `M_Foo`, or the opaque `$Str`.  Bool and Float need a third
   shape: a scalar that is neither Int nor a declared sort, but one of Z3's
   BUILT-IN sorts (`Bool`, `Float64`).

   They travel as markers in the same channel, so every consumer that reads a
   `Some s` it does not recognise as an ADT sort name MUST test [is_scalar_sort]
   first.  Handing `$Bool` to the ADT path would emit `(declare-const b $Bool)`
   for a sort nobody declared, and a z3 `(error …)` on the shared `z3 -in`
   channel is the failure this subsystem guards hardest against (it used to
   desynchronise the channel outright; since the containment fix it merely
   makes the VC silently undecidable, which is a quieter but equally real loss).

   Like [str_sort] both names contain `$`, which is a legal SMT-LIB simple
   symbol character but cannot occur in a March identifier or in
   [adt_sort_name]'s output, so neither can ever collide with a real sort. *)
let bool_sort = "$Bool"
let float_sort = "$Float"

let is_scalar_sort (s : string) : bool = s = bool_sort || s = float_sort

(* ── The MEASURE-ONLY marker ───────────────────────────────────────────────
   A fourth shape in the same marker channel, for a refined LOCAL/PARAMETER at
   an ADT base type that the checker carries only through its MEASURES (`len`
   over a list, a user measure over a variant), never as a datatype term.

   It must be readable as "not a scalar, not a record, not `$Str`, and NOT a
   sort any VC may declare a constant at": the value never becomes an SMT term
   here, only `len$x`-style Int symbols standing for measures OF it.  Hence the
   `$Meas:` prefix, which
     - contains `$`, illegal in a March identifier and in [adt_sort_name]'s
       output, so it can never collide with a real declared sort;
     - is distinct from `$Str`/`$Bool`/`$Float` by the `:` and the payload;
     - carries the underlying `M_…` sort name after the prefix, so a future
       consumer that DOES want the datatype sort can recover it, while every
       existing consumer (which tests marker equality against a specific sort
       name, or [is_record_sort], or [scalar_sort_of_marker]) sees a value none
       of its tests match and keeps its previous behaviour.

   The one consumer that had a CATCH-ALL `Some sort_name ->` arm is
   [scope_facts]; it is given an explicit arm below, because declaring a
   constant at the sort `$Meas:M_List` would be a `(declare-const … )` for a
   sort nobody declared — exactly the z3 `(error …)` the marker channel's
   comment above warns about.

   ([meas_sort_name], which needs [adt_sort_name], is defined alongside it.) *)
let meas_sort_prefix = "$Meas:"
let is_meas_sort (s : string) : bool = String.starts_with ~prefix:meas_sort_prefix s

(* The BUILT-IN SMT sort a marker denotes, or [None] when the marker names a
   declared sort (an ADT, a record, `$Str`) and so is not a scalar at all.
   [None] marker = Int is the original, unchanged meaning. *)
let scalar_sort_of_marker : string option -> Smt.sort option = function
  | None -> Some Smt.SInt
  | Some s when s = bool_sort -> Some Smt.SBool
  | Some s when s = float_sort -> Some Smt.SFloat
  | Some _ -> None

(* Same, defaulted to `Int` — for the many sites whose pre-existing behaviour
   for an unrecognised marker was "declare it Int". *)
let scalar_sort_or_int (m : string option) : Smt.sort =
  match scalar_sort_of_marker m with Some s -> s | None -> Smt.SInt

(* The full SMT sort a marker denotes, scalar or declared. *)
let smt_sort_of_marker (m : string option) : Smt.sort =
  match scalar_sort_of_marker m with
  | Some s -> s
  | None -> (match m with Some s -> Smt.SData s | None -> Smt.SInt)

(* A VC that declares one symbol at two different sorts is REJECTED by z3.  Each
   producer is supposed to agree with every other on a name's sort, and the
   [str_names] / [is_recvar] guards enforce that for the two sorts that existed
   before; this is the belt-and-braces check over the finished declaration list,
   so a path nobody anticipated costs a silent SKIP rather than an `(error …)`
   line on the shared solver channel. *)
let sort_conflict (ds : (string * Smt.sort) list) : bool =
  List.exists (fun (n, s) -> List.exists (fun (n', s') -> n = n' && s <> s') ds) ds

(* ── Well-sortedness guard ────────────────────────────────────────────────
   `$Str` is a sort apart, and the rest of the VC language is Int/Bool.  A term
   that mixes them (`(= caller_var $str0)` where the caller variable was
   reflected as an Int) is not merely useless — z3 REJECTS it, with the
   channel-desynchronising consequence described above.  So a term mentioning a
   string is admitted only where it is genuinely well-sorted: as the argument of
   [strlen_fn], or with both sides of an =/≠ being string constants.

   [mentions_str] deliberately stops at [strlen_fn]: `($strlen c)` is an Int and
   may be added, compared and multiplied like any other. *)
let rec mentions_str (is_str : string -> bool) (t : Smt.term) : bool =
  let m = mentions_str is_str in
  match t with
  | Smt.App (f, [ _ ]) when f = strlen_fn -> false
  | Smt.Const c -> is_str c
  | Smt.App (_, args) -> List.exists m args
  (* A datatype tester ranges over an ADT sort, never over `Str`; it only
     "mentions a string" if its subject somehow does. *)
  | Smt.IsCtor (_, a) -> m a
  | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> false
  | Smt.Not a | Smt.Neg a | Smt.MulLit (_, a) -> m a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b) | Smt.And (a, b)
  | Smt.Or (a, b)
  | Smt.Implies (a, b) | Smt.Eq (a, b) | Smt.Ne (a, b) | Smt.Lt (a, b)
  | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b) | Smt.FpGt (a, b)
  | Smt.FpGe (a, b) -> m a || m b

let rec wellsorted (is_str : string -> bool) (t : Smt.term) : bool =
  let w = wellsorted is_str and m = mentions_str is_str in
  let int_side a = (not (m a)) && w a in
  match t with
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> true
  | Smt.App (f, [ a ]) when f = strlen_fn ->
    (match a with Smt.Const c -> is_str c | _ -> false)
  | Smt.App (_, args) -> List.for_all int_side args
  (* `((_ is Ctor) x)` is a Bool over a datatype subject.  It is well-sorted
     exactly when its subject is a datatype term, i.e. does not drag a `Str`
     constant in — which cannot happen, but is checked rather than assumed. *)
  | Smt.IsCtor (_, a) -> not (m a)
  | Smt.Eq (a, b) | Smt.Ne (a, b) ->
    (match a, b with
     | Smt.Const x, Smt.Const y when is_str x && is_str y -> true
     | _ -> int_side a && int_side b)
  | Smt.Not a -> w a
  | Smt.Neg a | Smt.MulLit (_, a) -> int_side a
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) -> w a && w b
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b) | Smt.Lt (a, b)
  | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b) -> int_side a && int_side b
  (* Floats and `$Str` are disjoint sorts; an `fp.*` term is well-sorted here
     exactly when neither operand drags a string in.  Whether its operands are
     genuinely FLOATS is [float_wellsorted]'s job, not this guard's. *)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b) | Smt.FpGt (a, b)
  | Smt.FpGe (a, b) -> (not (m a)) && not (m b)

(* ── Float: the IEEE rewrite and its well-sortedness guard ─────────────────
   March spells float comparison with the ORDINARY operators — `x >= 0.0`, not a
   float-specific `>=.` — so [smt_of] cannot tell an Int comparison from a Float
   one and builds [Smt.Ge] for both.  This pass runs over the finished term and
   rewrites a comparison whose operands are both float-sorted into its IEEE
   form.  Integer comparisons are untouched: [float_term] is true only of a
   float literal or a constant this VC declared at `Float64`.

   `==` becomes `fp.eq` (and `!=` its negation), NOT `=`.  `=` on Float64 is
   BITWISE identity, under which `-0.0 ≠ 0.0`; the contract `{Float | _ != 0.0}`
   would then accept `-0.0`, a divisor every bit as bad as `+0.0`.  `fp.eq` is
   IEEE equality: `+0.0 = -0.0`, and NaN equals nothing including itself. *)
let float_term (is_float : string -> bool) (t : Smt.term) : bool =
  match t with Smt.FloatLit _ -> true | Smt.Const c -> is_float c | _ -> false

let rec fp_rewrite (is_float : string -> bool) (t : Smt.term) : Smt.term =
  let f = fp_rewrite is_float and fl = float_term is_float in
  let both a b = fl a && fl b in
  match t with
  | Smt.Ge (a, b) when both a b -> Smt.FpGe (a, b)
  | Smt.Gt (a, b) when both a b -> Smt.FpGt (a, b)
  | Smt.Le (a, b) when both a b -> Smt.FpLe (a, b)
  | Smt.Lt (a, b) when both a b -> Smt.FpLt (a, b)
  | Smt.Eq (a, b) when both a b -> Smt.FpEq (a, b)
  | Smt.Ne (a, b) when both a b -> Smt.Not (Smt.FpEq (a, b))
  | Smt.Not a -> Smt.Not (f a)
  | Smt.And (a, b) -> Smt.And (f a, f b)
  | Smt.Or (a, b) -> Smt.Or (f a, f b)
  | Smt.Implies (a, b) -> Smt.Implies (f a, f b)
  | t -> t

(* Does [t] mention a float anywhere? *)
let rec mentions_float (is_float : string -> bool) (t : Smt.term) : bool =
  let m = mentions_float is_float in
  match t with
  | Smt.FloatLit _ -> true
  | Smt.Const c -> is_float c
  | Smt.IntLit _ | Smt.BoolLit _ -> false
  | Smt.App (_, args) -> List.exists m args
  | Smt.IsCtor (_, a) | Smt.Not a | Smt.Neg a | Smt.MulLit (_, a) -> m a
  | Smt.Mul (a, b)
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.And (a, b) | Smt.Or (a, b)
  | Smt.Implies (a, b) | Smt.Eq (a, b) | Smt.Ne (a, b) | Smt.Lt (a, b)
  | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b) | Smt.FpGt (a, b)
  | Smt.FpGe (a, b) -> m a || m b

(* After [fp_rewrite], a float may appear ONLY as a direct operand of an `fp.*`
   comparison.  Anywhere else — an Int comparison [fp_rewrite] declined because
   only one side was float, an arithmetic term, a measure argument — the term
   mixes sorts, and z3 REJECTS such a query.  Before the error containment that
   desynchronised the shared `z3 -in` channel outright; it now costs only this
   VC, but silently, so the mixing is caught here instead of being emitted.

   The direction is the safe one: a term that fails this is DROPPED (an
   assumption) or abandons the VC (a goal), i.e. silence. *)
let rec float_wellsorted (is_float : string -> bool) (t : Smt.term) : bool =
  let w = float_wellsorted is_float in
  match t with
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b) | Smt.FpGt (a, b)
  | Smt.FpGe (a, b) -> float_term is_float a && float_term is_float b
  | Smt.Not a -> w a
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) -> w a && w b
  (* A bare float where the enclosing context wants a Bool or an Int. *)
  | t -> not (mentions_float is_float t)

(* ── Boolean-position guard ────────────────────────────────────────────────
   A term asserted as a hypothesis, or used as a goal, must actually BE a
   formula.  March lets a bare Bool variable stand as a condition — `if j do …`,
   `{Bool | _}` — and [smt_of] reflects that to `Const "j"`.  If the variable
   was declared `Int` (the historical default for any caller-scope name), the
   VC contains `(assert j)` over an integer and z3 answers
   `invalid assert command, term is not Boolean`.

   Now that a symbol CAN be declared `Bool`, the honest test is possible: a bare
   constant is a formula exactly when this VC declared it at `Bool`.  Anything
   else is dropped — an assumption is discarded (weaker hypotheses, so only more
   silence) and a goal abandons the VC.  Both directions are skips, never
   reports. *)
let rec formula_wellsorted (sort_of : string -> Smt.sort option) (t : Smt.term) : bool =
  let w = formula_wellsorted sort_of in
  match t with
  | Smt.BoolLit _ | Smt.IsCtor _ -> true
  | Smt.Const c -> sort_of c = Some Smt.SBool
  | Smt.Not a -> w a
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) -> w a && w b
  | Smt.Eq _ | Smt.Ne _ | Smt.Lt _ | Smt.Le _ | Smt.Gt _ | Smt.Ge _
  | Smt.FpEq _ | Smt.FpLt _ | Smt.FpLe _ | Smt.FpGt _ | Smt.FpGe _ -> true
  (* Nothing in this checker declares an uninterpreted function at `Bool`
     (measures and selectors return Int or a datatype), so an application in
     Boolean position is a sort error just as arithmetic and literals are. *)
  | Smt.App _ | Smt.IntLit _ | Smt.FloatLit _ | Smt.Add _ | Smt.Sub _
  | Smt.MulLit _ | Smt.Mul _ | Smt.Neg _ -> false

(* =================================================================
   §3  Predicate scope and parameter substitution
   ================================================================= *)

(* How a return refinement's predicate relates to the callee's parameters.

   [Closed]      — mentions only the refinement binder; usable as-is (Tier 0).
                   `{Int | _ >= 0}`
   [Relational]  — mentions the binder plus exactly these parameters; usable at
                   a call site only after substituting the call's actuals for
                   them (Tier 1).
                   `{Int | _ == n + 1}`, `{Int | _ < len(xs)}`
   [Unusable]    — mentions a name that is neither the binder nor a parameter,
                   or contains syntax the checker cannot reason about; never
                   propagated.

   The `_ -> Unusable` fallback is what keeps unfamiliar syntax out: an
   unrecognised predicate is skipped rather than trusted. *)
type pred_scope = Closed | Relational of string list | Unusable

let classify_pred (binder : string) (params : string list) (pred : A.expr) : pred_scope =
  let used = ref [] and bad = ref false in
  let rec go (e : A.expr) =
    match e with
    | A.EVar { A.txt; _ } ->
      if txt = binder || txt = "_" then ()
      else if List.mem txt params then
        (if not (List.mem txt !used) then used := txt :: !used)
      else bad := true
    (* The head of an application is a function/operator name, not a value
       reference: only its arguments can carry free variables. *)
    | A.EApp (A.EVar _, args, _) -> List.iter go args
    | A.EApp (f, args, _) -> go f; List.iter go args
    | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.iter go es
    (* A field projection is classified by its RECEIVER: `v.port` on the binder
       is closed, `c.port` on a parameter is relational, anything else is
       unusable — exactly the variable's own classification.  Without this arm
       every record postcondition fell to the catch-all below and was reported
       [Unusable], so a record-returning function's postcondition could never
       reach a call site even though the definition side had proven it.
       [subst_params] has the mirror-image arm, so a relational one is
       rewritten into the caller's namespace rather than left half-translated. *)
    | A.EField (r, _, _) -> go r
    | A.EAnnot (e, _, _) -> go e
    | A.ELit _ -> ()
    | _ -> bad := true
  in
  go pred;
  if !bad then Unusable
  else if !used = [] then Closed
  else Relational (List.rev !used)

(* Simultaneous substitution of formals by actual expressions.  Simultaneous,
   not sequential: with `f(m, 1)` against `{Int | _ < n + m}`, rewriting n := m
   and then m := 1 would rewrite the freshly-introduced `m` and yield
   `_ < 1 + 1` — a fact about the caller that was never proven.  One traversal
   consulting the original map avoids that.

   The arms mirror what [classify_pred] admits; anything it rejects as
   [Unusable] never reaches here, so the `_ -> e` fallback is unreachable in
   practice and inert if reached.  An application's HEAD is deliberately left
   alone: it names a function, operator or measure, not a value, so a parameter
   that happens to share a measure's name must not rewrite the call itself. *)
let rec subst_params (env : (string * A.expr) list) (e : A.expr) : A.expr =
  let go = subst_params env in
  match e with
  | A.EVar { A.txt; _ } -> (match List.assoc_opt txt env with Some a -> a | None -> e)
  | A.EApp ((A.EVar _ as hd), args, sp) -> A.EApp (hd, List.map go args, sp)
  | A.EApp (f, args, sp) -> A.EApp (go f, List.map go args, sp)
  | A.ETuple (es, sp) -> A.ETuple (List.map go es, sp)
  | A.ECon (c, es, sp) -> A.ECon (c, List.map go es, sp)
  | A.EAtom (a, es, sp) -> A.EAtom (a, List.map go es, sp)
  (* Mirrors [classify_pred]'s [EField] arm: the RECEIVER is the value
     reference, the field name is a selector.  Rewriting the receiver is what
     keeps a relational record postcondition entirely in the caller's
     namespace; leaving it would mix the two, the conflation that has produced
     false positives here before. *)
  | A.EField (r, n, sp) -> A.EField (go r, n, sp)
  | A.EAnnot (inner, t, sp) -> A.EAnnot (go inner, t, sp)
  | _ -> e

(* =================================================================
   §4  Function signatures, measures, and stdlib-provided names
   ================================================================= *)

(* A function's signature: parameter names by position, its refined params, and
   its declared return refinement (binder + predicate) when the return type is
   an Int refinement.  [ret] is stored UNFILTERED — the closedness test is
   applied at the use sites via [postcond_of], so relaxing it for relational
   postconditions (Tier 1) is a one-place change. *)
type fn_sig = {
  param_names : string list;
  (* Parallel to [param_names]: true where the parameter's declared base type is
     String (bare or refined).  This is what makes the `len` OVERLOAD safe — the
     string meaning is chosen only from a declared type, never guessed. *)
  param_str : bool list;
  (* Parallel to [param_names]: the SCALAR SMT sort each parameter's declared
     base type reflects into — `Bool` for a (refined or bare) `Bool`, `Float64`
     for a `Float`, `Int` for everything else including the sorts that are not
     scalars at all (a String or ADT parameter is routed by [param_str] /
     [rparam.sort] before its scalar sort is ever consulted).  This is what lets
     an argument at a Bool/Float position be DECLARED at that sort rather than
     silently at `Int`, which z3 rejects the moment the predicate uses it. *)
  param_scalar : Smt.sort list;
  refined : rparam list;
  ret : (string * A.expr) option;
  (* SMT sort of the refined RETURN value: [None] for an Int return (the Tier 0
     / Tier 1 case), [Some "M_Tree"] for a value at a registered ADT sort
     (Tier 2).  Consumers of a propagated postcondition MUST branch on this: the
     Int consumers ([reflect_scalar], [scope_add_binding]) declare an `Int`
     constant, and handing them an ADT-valued fact would put one symbol at two
     sorts — the z3 `(error …)` that desynchronises the shared solver channel
     and silently disables refinement checking for the rest of the
     compilation. *)
  ret_sort : string option;
}

(* Length of a list literal (a Cons/Nil ECon chain); None if not a literal. *)
let rec list_len (e : A.expr) : int option =
  match e with
  | A.ECon ({ A.txt = "Nil"; _ }, _, _) -> Some 0
  | A.ECon ({ A.txt = "Cons"; _ }, [ _; tl ], _) ->
    (match list_len tl with Some n -> Some (n + 1) | None -> None)
  | _ -> None

(* Registered measure names for this compilation: the builtin `len` plus any
   user function annotated `@[measure]`.  Set once per [check_module]. *)
let registered_measures : string list ref = ref []
let is_measure (m : string) : bool = m = "len" || List.mem m !registered_measures

(* ── Zero-argument constant functions ──────────────────────────────────────
   `fn size_x() : Int do 128 end` is, after inlining, the literal 128, so a
   predicate `{Int | _ < size_x()}` can be checked exactly like `{Int | _ < 128}`
   — which is what lets a program name its array dimensions once instead of
   freezing them as literals at every refinement.  [const_fns] maps every
   spelling a predicate may use for such a function (bare name, and each
   module-qualified suffix `World.size` / `M.World.size`) to the literal its
   body folds to; [register_const_fns] populates it once per [check_module].

   [const_fn_rejected] records, for a zero-argument function that did NOT
   qualify, why — its body does not fold, or the spelling is ambiguous — so the
   vocabulary warning can say what would make it usable rather than sending
   the user to `@[measure]`, which cannot help here (see
   [measure_shape_error]). *)
let const_fns : (string, Smt.term) Hashtbl.t = Hashtbl.create 16
let const_fn_rejected : (string, string) Hashtbl.t = Hashtbl.create 16

(* Names bound ANYWHERE inside the function currently being visited
   ([Refine_check.visit_fn] sets and restores it; see [fn_binders]).  A
   constant function is folded wherever [smt_of_r] runs — a predicate, a
   guard, an actual, a tail — and in a BODY a local `let size_x = fn -> 7`
   can shadow the top-level `size_x`; folding `size_x()` to 128 there would
   assert a false fact.  So a name bound anywhere in the enclosing function
   is not folded in that function at all.  Over-retiring is the safe
   direction: it costs a proof, never soundness.  (A parameter refinement
   cannot see locals, so the vocabulary warning, which runs outside any
   [visit_fn], sees the table empty and judges the unshadowed name.) *)
let const_shadowed : (string, unit) Hashtbl.t = Hashtbl.create 16
let is_const_fn (m : string) : bool =
  Hashtbl.mem const_fns m && not (Hashtbl.mem const_shadowed m)

(* ── Measure aliases ───────────────────────────────────────────────────────
   Runtime functions that ARE a measure under a different name.  Reflecting
   `List.length(xs)` to the same SMT term as `len(xs)` is what lets an ordinary
   runtime guard discharge a `len` obligation; without it the two are
   unconnected symbols, the guard translates to nothing, and a guarded call is
   SKIPPED rather than proved.

   For LIST length, only the QUALIFIED spelling is aliased.  A bare `length`
   would also catch a user module's own unrelated `fn length(...)`, and an alias
   is a fact ADDED to the assumption set that `discharge(¬goal)` proves against
   — so a wrong alias makes violations easier to prove ON CORRECT CODE.  A
   missed proof is always cheaper than a wrong fact.

   ── STRING length is BYTES, and only byte-valued spellings may be aliased ──
   `len` over a String reflects to [strlen_fn] (`$strlen`), whose meaning is
   pinned in BYTES: the string-literal axiom below fixes `($strlen c)` to
   OCaml's `String.length`, i.e. the literal's UTF-8 byte count.  So only a
   function that returns a BYTE count may be equated with it.  Aliasing a
   codepoint count would assert bytes == codepoints, false for every
   non-ASCII string, and — since assumptions make `discharge(¬goal)` STRONGER
   — would manufacture violations on correct code.

   Aliased:
     - `String.byte_size` — stdlib, defined as `string_byte_length(s)`.
     - `string_byte_length` — the compiler builtin it forwards to.

   NOT aliased:
     - `String.codepoint_count` / `String.grapheme_count` — codepoints, not
       bytes.  Equating either with `$strlen` is the unsoundness above.
     - `string_length` — a deliberate abstention, NOT a semantic claim.  It is
       byte length today in every backend (typecheck's builtin table types it
       `String -> Int`; llvm_builtins lowers it to the same
       `march_string_byte_length` C symbol as `string_byte_length`; eval uses
       OCaml `String.length`; the wasm runtime reads the same `length` field —
       all four measured at 2 for "é").  But the NAME does not say "byte", the
       String module's own documentation steers callers to `byte_size` for
       bytes and `codepoint_count` for characters, and a future correction of
       `string_length` to codepoints would silently turn this alias into the
       false assumption described above.  Callers who want the proof have two
       precisely-named spellings; abstaining costs them nothing but a rename. *)

(* ── The shadowing gate ────────────────────────────────────────────────────
   The alias keys on a SPELLING, and March lets a program define its own
   `List.length`, which then wins at runtime.  Aliasing that to `len` attaches
   the list-length meaning to a function that is not the list's length: the
   wrong fact enters the assumption set `discharge(¬goal)` proves against, and
   a violation becomes provable on code that cannot violate anything.  This is
   the same hazard [string_len_available] already guards for bare `len` — the
   moment the name is taken, the built-in meaning is withdrawn.

   Set once per [check_module] by [list_length_defs_ok].  The default is the
   SUPPRESSING one: a path that forgets to set it loses a proof rather than
   gains a wrong fact. *)
let list_length_is_stdlib : bool ref = ref false

(* Same gate, same default, for the `String.byte_size` spelling: true only while
   it still denotes the standard library's own byte-length function.  A program
   may define `mod String do fn byte_size … end`, which then wins at runtime;
   aliasing that would attach `$strlen`'s meaning to an arbitrary function. *)
let string_byte_size_is_stdlib : bool ref = ref false

(* And for the BARE `string_byte_length`.  This one is not a stdlib March
   function to be identified — it is a COMPILER BUILTIN (typecheck's builtin
   table; lowered to the `march_string_byte_length` C symbol), so there is no
   "the stdlib's own definition" to allow: every binding of that name is a
   competing one, and withdraws the alias.

   "Every binding" means the ones [bare_builtin_undefined] actually scans —
   declaration forms plus expression binders (`let`, lambda/`fn` parameters,
   local `fn`, match binders) throughout every `DFn` clause.  That is exactly
   the region the checker visits, so it is complete where it needs to be; see
   that function for the argument.  Default suppressing, like the two above. *)
let string_byte_length_is_builtin : bool ref = ref false

(* The source files the CALLER loaded as the standard library, supplied to
   [check_module].  This is an IDENTITY, not a path pattern: bin/main.ml reads
   it off the stdlib declarations it actually prepended, so it follows
   `MARCH_STDLIB`, the installed `share/march` layout, and the marshalled
   stdlib-AST cache automatically, and a vendored `MARCH_LIB_PATH` copy — which
   arrives as user decls, not stdlib decls — is correctly excluded.

   Empty (the default) means "the caller told us nothing", under which no
   definition is the stdlib's and the alias is withdrawn the moment any
   `List.length` is in scope. *)
let stdlib_source_files : string list ref = ref []

(* The single predicate for "this span came from the standard library's own
   sources".  Defined HERE rather than beside its first caller because it now
   has two very different callers at two different depths: the measure-alias
   gates in [Refine_check] (see the long comment there for why the identity
   must not be inferred from the path's shape), and the call-site PROMOTION in
   [Refine_call], which must decline a span the user can never see a
   diagnostic for.  Two copies of this test would be two things to keep in
   agreement; there is one. *)
let is_stdlib_source_file (f : string) : bool = List.mem f !stdlib_source_files

(* ── Why an alias was withdrawn ────────────────────────────────────────────
   The three gates above are unit-global, syntactic, and default to
   SUPPRESSING — all correct, and none of it changes here.  What a withdrawal
   costs under the default stance is a missed proof, i.e. silence.  Under
   `cap verified` a skipped obligation is a hard ERROR, and then the withdrawal
   becomes invisible in the worst way: the author wrote exactly the guard the
   feature asks for, the alias silently did not apply, and the error text
   blames the solver and the predicate.  Both remedies it offers are ones the
   author already took.

   So record, at the point a gate withdraws, WHICH spelling went and WHERE the
   competing binding is.  This is observation only: nothing here is consulted
   by [measure_alias], and suppression is bit-for-bit what it was. *)
type withdrawal = {
  wd_spelling : string;      (* the spelling whose alias was withdrawn *)
  wd_measure : string;       (* the measure it would have aliased to *)
  (* Which KIND of subject the spelling measures.  All three spellings route to
     the single measure name `len`, so [wd_measure] alone cannot tell a list
     length from a string byte length — and without this a withdrawn
     `List.length` was blamed for an undischarged `{String | len(_) > 0}`,
     naming a list definition that had nothing to do with it. *)
  wd_str : bool;
  wd_span : A.span option;   (* the binding that caused it, when identified *)
}

let withdrawals : withdrawal list ref = ref []

(* All three route to the single name `len`.  Whether `len` then resolves to a
   `len$x` constant or to `($strlen t)` is decided downstream by
   [resolve_measure], on the DECLARED BASE TYPE of the argument — so the String
   spellings need no separate reflection path, and a `String.byte_size` applied
   to something the checker does not see as a String simply fails to reflect
   (skipped) rather than asserting a list fact.

   ADDING A QUALIFIED (dotted) SPELLING HERE?  Mirror it in
   [qualified_measure_spelling] too, or the predicate warning silently drops to
   its generic remedy for that spelling — degraded advice, not wrong advice,
   but the two lists are meant to agree.  A bare spelling like
   [string_byte_length] needs no mirror: that warning only fires on dotted
   paths. *)
let measure_alias (m : string) : string option =
  match m with
  | "List.length" when !list_length_is_stdlib -> Some "len"
  | "String.byte_size" when !string_byte_size_is_stdlib -> Some "len"
  | "string_byte_length" when !string_byte_length_is_builtin -> Some "len"
  | _ -> None

(* The measure name [m] denotes, following an alias.  Every dispatch site must
   normalize through this BEFORE consulting [is_measure]/[resolve_measure], or
   the guard reflects to one symbol and the predicate to another and the two
   never meet. *)
let measure_name (m : string) : string =
  match measure_alias m with Some m' -> m' | None -> m

let is_measure_app (m : string) : bool = measure_alias m <> None || is_measure m

(* Measures known to be non-negative (so `m(x) >= 0` is a sound axiom).  `len`
   always; a user measure when its body is syntactically non-negative. *)
let measure_nonneg : string list ref = ref []
let is_nonneg_measure (m : string) : bool = m = "len" || List.mem m !measure_nonneg

(* `len` over strings is only safe to encode while `len` still MEANS the builtin
   measure.  A user `@[measure] fn len(…)` would be axiomatised over its own ADT
   sort, and declaring a second `len : Str -> Int` in the same VC would either
   collide or silently assert a fact about the wrong function.  When the name is
   taken, we disable the string meaning entirely and skip — a wrong resolution
   asserts a wrong fact, which is the one thing that must never happen. *)
let string_len_available () : bool = not (List.mem "len" !registered_measures)

(* ── The predicate vocabulary ──────────────────────────────────────────────
   Which names carry meaning inside a refinement predicate.  Previously this
   knowledge was implicit: spread across [is_measure], [is_nonneg_measure] and
   inline "len" comparisons at four sites, and otherwise encoded only in
   [smt_of]'s match arms.  Naming it lets us (a) warn about a predicate the
   checker will silently ignore, and (b) give the ADT feature one place to
   register its constructor testers. *)

(* Operators [smt_of] translates.  Kept in sync with its match arms by the
   `every operator is known vocabulary` test in test_refinecheck.ml. *)
let predicate_operators =
  [ "+"; "-"; "*"; "negate"; "not"; "&&"; "||"
  ; "=="; "!="; "<"; "<="; ">"; ">="
  (* The float operators are vocabulary even though [smt_of] translates them
     only over LITERALS: a predicate using one symbolically is skipped by
     design, and warning "this has no effect" about a deliberate scope boundary
     would be misleading. *)
  ; "+."; "-."; "*."; "/." ]

let is_predicate_operator (m : string) : bool = List.mem m predicate_operators

(* [known_predicate_fn] is defined below [adt_ctors], since the vocabulary now
   includes the auto-derived `is_<Ctor>` testers. *)

(* Conservative syntactic non-negativity of a measure body: every return path is
   a non-negative literal, a sum/product of non-negatives, or a call to a measure
   already known non-negative (incl. the measure itself, inductively). *)
let measure_body_nonneg (self : string) (known : string list) (body : A.expr) : bool =
  let rec go e =
    match e with
    | A.ELit (A.LitInt n, _) -> n >= 0
    | A.EApp (A.EVar { A.txt = ("+" | "*"); _ }, [ a; b ], _) -> go a && go b
    | A.EApp (A.EVar { A.txt = m; _ }, [ _ ], _)
      when m = self || m = "len" || List.mem m known -> true
    | A.EIf (_, t, e, _) -> go t && go e
    | A.ECond (arms, _) -> List.for_all (fun (_, b) -> go b) arms
    | A.EMatch (_, brs, _) -> List.for_all (fun (br : A.branch) -> go br.A.branch_body) brs
    | A.EBlock (es, _) -> (match List.rev es with last :: _ -> go last | [] -> false)
    | _ -> false (* variables, subtraction, arbitrary calls: unknown sign *)
  in
  go body

(* =================================================================
   §5  ADT and record sorts: registry and SMT preamble builders
   ================================================================= *)

(* ── Measure axioms (M-a): datatype model + recursion-equation preamble ───── *)
(* ctor name -> field sorts as the measure sees them (recursive self -> SData adt,
   type params / other ADTs -> opaque "Elem", Int/Bool concrete). *)
let ctor_field_sorts : (string, Smt.sort list) Hashtbl.t = Hashtbl.create 32
let adt_ctors : (string, string list) Hashtbl.t = Hashtbl.create 16

(* ── Constructor testers ───────────────────────────────────────────────────
   Every constructor of every registered ADT implicitly gains an `is_<Ctor>`
   predicate: "is_Some" -> Some "Some", when `Some` is a constructor of some
   registered ADT.  The match is EXACT-CASE, so `is_some` (the lowercase
   stdlib helper `Option.is_some`) is NOT a tester: a misspelling keeps drawing
   the unrecognized-predicate warning rather than silently meaning something. *)
let ctor_of_tester (m : string) : string option =
  let pfx = "is_" in
  let n = String.length pfx in
  if String.length m <= n || String.sub m 0 n <> pfx then None
  else
    let ctor = String.sub m n (String.length m - n) in
    let known =
      Hashtbl.fold (fun _ ctors acc -> acc || List.mem ctor ctors) adt_ctors false
    in
    if known then Some ctor else None

(* True iff the checker attaches meaning to [m] applied inside a predicate. *)
let known_predicate_fn (m : string) : bool =
  is_predicate_operator m || is_measure_app m || ctor_of_tester m <> None
  || is_const_fn m

(* measures we soundly axiomatize: name -> its argument ADT name. *)
let axiom_measures : (string, string) Hashtbl.t = Hashtbl.create 16
let is_axiom_measure m = Hashtbl.mem axiom_measures m

(* Axiomatised measures whose VALUE depends on a scalar (non-datatype)
   constructor field, e.g. `PVec(n,_,_,_) -> n`.  Such a measure is axiomatised
   correctly and is nonetheless INERT at every call site: [reflect_field] below
   replaces every non-datatype constructor field with a fresh unconstrained
   constant (a sound choice for a structurally recursive measure, whose value
   depends only on tags and sub-measures), so the measure applied to a literal
   constructor evaluates to an unknown and neither the predicate nor its
   negation is provable.

   Populated purely to WARN.  It feeds no axiom, no VC and no verdict — adding
   a name here cannot change what any existing contract proves.  It exists
   because the failure it names is silent: the measure compiles clean, the
   soundness gate passes, the preamble is correct, obligations are raised, and
   nothing ever discharges.  See
   specs/todos/2026-08-05-measure-over-scalar-ctor-field.md. *)
let measure_scalar_field_dep : (string, unit) Hashtbl.t = Hashtbl.create 8

(* Base-case ground values for axiom measures: name -> [(ctor_name, int_value)].
   Populated for arms whose body is a concrete integer (no recursion).
   Used to evaluate measures over concrete SMT terms without quantifier axioms,
   avoiding Z3 returning `unknown` for trivially SAT queries. *)
let measure_base_cases : (string, (string * int) list) Hashtbl.t = Hashtbl.create 8
let measure_preamble : string ref = ref ""

(* ctor name -> field names in declaration order.  Populated for TDRecord
   1-ctor datatypes; used to map EField/ERecord field names to selector indices. *)
let ctor_field_names : (string, string list) Hashtbl.t = Hashtbl.create 16

(* declare-datatypes preamble for TDRecord types; included in every VC that
   refines over a record value.  Built after measure_preamble so sort
   deduplication (measure_preamble_sorts) works. *)
let type_preamble : string ref = ref ""

(* ADT sort names already declared in measure_preamble; populated by
   build_measure_preamble so build_type_preamble can skip them and avoid
   duplicate sort declarations in the same VC (Z3 rejects those). *)
let measure_preamble_sorts : (string, unit) Hashtbl.t = Hashtbl.create 8

(* SMT sort name for a March ADT.  z3 reserves several sort names (`List`,
   `Array`, `Seq`, `Set`, …); keeping our datatype sorts in a private `M_`
   namespace guarantees no user/builtin ADT name collides with a reserved one.
   [adt_ctors] / [SData] are keyed by this safe name; constructors are not
   renamed. *)
let adt_sort_name (march_name : string) : string = "M_" ^ march_name

(* The MEASURE-ONLY marker for a March ADT — see [meas_sort_prefix]. *)
let meas_sort_name (march_name : string) : string =
  meas_sort_prefix ^ adt_sort_name march_name

(* True when [t] is a bare TyCon that maps to a registered 1-constructor
   TDRecord sort — used to gate record-typed refinements on both the param
   and return sides. *)
let is_record_base (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = name; _ }, []) ->
    (match Hashtbl.find_opt adt_ctors (adt_sort_name name) with
     | Some [ ctor ] -> Hashtbl.mem ctor_field_names ctor
     | _ -> false)
  | _ -> false

(* [is_record_base] on an already-computed SMT sort name.  Records are a strict
   SUBSET of the ADT sorts, so a consumer that wants the record-specific path
   (field selectors) must test this rather than merely observing `sort = Some
   _`, which is also true of a String ([str_sort]) and of a plain variant. *)
let is_record_sort (s : string) : bool =
  s <> str_sort
  && (match Hashtbl.find_opt adt_ctors s with
      | Some [ ctor ] -> Hashtbl.mem ctor_field_names ctor
      | _ -> false)

(* True when [t] is a bare TyCon naming any registered ADT — variant or
   record, and (unlike [is_record_base]) whether or not it is applied to type
   arguments, e.g. `Option(Int)`.  The ADT-tag feature dispatches on this. *)
let is_adt_base (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = name; _ }, _) -> Hashtbl.mem adt_ctors (adt_sort_name name)
  | _ -> false

(* The SMT sort a measure sees for a constructor field: Int/Bool concrete, ANY
   registered ADT (self or another — so cross-ADT measure calls are well-sorted,
   M-c) its datatype sort, everything else (type params, unmodelled types) the
   opaque `Elem`.  Requires every ADT name already registered in [adt_ctors] —
   hence the two-pass registration (names, then field sorts). *)
let smt_sort_of_field (t : A.ty) : Smt.sort =
  match t with
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> Smt.SInt
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Smt.SBool
  | A.TyCon ({ A.txt; _ }, _) when Hashtbl.mem adt_ctors (adt_sort_name txt) ->
    Smt.SData (adt_sort_name txt)
  | _ -> Smt.SData "Elem"

(* Pass 1: register every ADT's constructor list (keyed by sort name). *)
let rec register_adt_names (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, name, _, A.TDVariant variants, _)
      | A.DAlwaysLinearType (_, name, _, A.TDVariant variants, _) ->
        Hashtbl.replace adt_ctors (adt_sort_name name.A.txt)
          (List.map (fun (v : A.variant) -> v.A.var_name.A.txt) variants)
      | A.DType (_, name, _, A.TDRecord _, _)
      | A.DAlwaysLinearType (_, name, _, A.TDRecord _, _) ->
        Hashtbl.replace adt_ctors (adt_sort_name name.A.txt) [ name.A.txt ]
      | A.DMod (_, _, ds, _) -> register_adt_names ds
      | _ -> ())
    decls

(* Pass 2: register each constructor's field sorts (needs all names from pass 1). *)
let rec register_field_sorts (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, _, _, A.TDVariant variants, _)
      | A.DAlwaysLinearType (_, _, _, A.TDVariant variants, _) ->
        List.iter
          (fun (v : A.variant) ->
            Hashtbl.replace ctor_field_sorts v.A.var_name.A.txt
              (List.map smt_sort_of_field v.A.var_args))
          variants
      | A.DType (_, name, _, A.TDRecord fields, _)
      | A.DAlwaysLinearType (_, name, _, A.TDRecord fields, _) ->
        let ctor = name.A.txt in
        Hashtbl.replace ctor_field_sorts ctor
          (List.map (fun (f : A.field) -> smt_sort_of_field f.A.fld_ty) fields);
        Hashtbl.replace ctor_field_names ctor
          (List.map (fun (f : A.field) -> f.A.fld_name.A.txt) fields)
      | A.DMod (_, _, ds, _) -> register_field_sorts ds
      | _ -> ())
    decls

(* The matched argument's name + its ADT, if the (first) parameter is a
   registered ADT. *)
let clause_param_adt (c : A.fn_clause) : (string * string) option =
  match c.A.fc_params with
  | A.FPNamed p :: _ -> (
      match p.A.param_ty with
      | Some (A.TyCon (adt, _)) when Hashtbl.mem adt_ctors (adt_sort_name adt.A.txt) ->
        Some (p.A.param_name.A.txt, adt_sort_name adt.A.txt)
      | _ -> None)
  | _ -> None

(* The (first) parameter's name, whatever its type (for the termination gate). *)
let clause_param_name (c : A.fn_clause) : string option =
  match c.A.fc_params with
  | (A.FPNamed p | A.FPDefault (p, _)) :: _ -> Some p.A.param_name.A.txt
  | _ -> None

let measure_param_adt (fd : A.fn_def) : (string * string) option =
  match fd.A.fn_clauses with c :: _ -> clause_param_adt c | [] -> None

let rec unblock = function
  | A.EBlock (es, sp) -> (match List.rev es with last :: _ -> unblock last | [] -> A.EBlock (es, sp))
  | e -> e

(* ── Constant-function folding ─────────────────────────────────────────────
   The value of a zero-argument function body built only from Int/Bool
   literals, `+ - * negate`, `&& || not`, and calls to OTHER zero-argument
   constant functions ([lookup]).  Deliberately no `/` or `%`: March's
   truncating division would have to be re-implemented here bit-for-bit, and a
   fold that disagrees with the runtime asserts a false fact — the one thing
   this subsystem must never do.  [Error] carries the reason in the words the
   vocabulary warning shows. *)
type const_val = CInt of int | CBool of bool

let term_of_const_val = function
  | CInt n -> Smt.IntLit n
  | CBool b -> Smt.BoolLit b

let rec fold_const_body (lookup : string -> (const_val, string) result) (e : A.expr)
    : (const_val, string) result =
  let go = fold_const_body lookup in
  let generic =
    Error
      "is not built only from literals, `+ - * negate`, `&& || not`, and other \
       zero-argument constant functions"
  in
  let int2 f a b =
    match go a, go b with
    | Ok (CInt x), Ok (CInt y) -> Ok (CInt (f x y))
    | (Error _ as err), _ | _, (Error _ as err) -> err
    | _ -> generic
  in
  let bool2 f a b =
    match go a, go b with
    | Ok (CBool x), Ok (CBool y) -> Ok (CBool (f x y))
    | (Error _ as err), _ | _, (Error _ as err) -> err
    | _ -> generic
  in
  match unblock e with
  | A.ELit (A.LitInt n, _) -> Ok (CInt n)
  | A.ELit (A.LitBool b, _) -> Ok (CBool b)
  | A.EAnnot (inner, _, _) -> go inner
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> int2 ( + ) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> int2 ( - ) a b
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) -> int2 ( * ) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) ->
    (match go a with Ok (CInt x) -> Ok (CInt (-x)) | Error _ as err -> err | _ -> generic)
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> bool2 ( && ) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> bool2 ( || ) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    (match go a with Ok (CBool x) -> Ok (CBool (not x)) | Error _ as err -> err | _ -> generic)
  | A.EApp (A.EVar { A.txt = f; _ }, [], _) -> lookup f
  | A.EApp (A.EVar { A.txt = f; _ }, _ :: _, _)
    when f <> "" && (match f.[0] with 'a' .. 'z' | '_' -> true | _ -> false) ->
    Error (Printf.sprintf "calls `%s`, which is not a zero-argument constant function" f)
  | _ -> generic

(* Populate [const_fns] / [const_fn_rejected] from [decls].

   A candidate is a single-clause, unguarded `fn f()` whose body folds
   ([fold_const_body]); a call to another candidate folds through it, with a
   visiting set so a (nonsensical, but writable) `fn a() do b() end`,
   `fn b() do a() end` pair is rejected rather than looped on.  Each
   candidate is registered under every spelling a predicate could use for it:
   its bare name and each suffix of its module path (`size`, `World.size`,
   `M.World.size`).  The stdlib's declarations are merged into the checked
   module, so a spelling can collide — two definitions under one spelling that
   do not fold to the same value make that spelling AMBIGUOUS and it is
   withdrawn with a reason, never resolved by guessing which one was meant. *)
let register_const_fns ~(mod_name : string) (decls : A.decl list) : unit =
  Hashtbl.reset const_fns;
  Hashtbl.reset const_fn_rejected;
  (* (module path, fn) for every zero-argument single-clause function.  The
     path starts at the checked module's own name so `Probe.size_x()` is a
     spelling too, not only the nested `World.size()`. *)
  let rec collect path decls =
    List.concat_map
      (function
        | A.DFn (fd, _) -> (
          match fd.A.fn_clauses with
          | [ { A.fc_params = []; fc_guard = None; _ } ] -> [ (path, fd) ]
          | _ -> [])
        | A.DMod (n, _, ds, _) -> collect (path @ [ n.A.txt ]) ds
        | _ -> [])
      decls
  in
  let cands = collect [ mod_name ] decls in
  (* Fold by BARE name (that is how a constant body spells a call to another
     constant); a bare name with several definitions folds only if they all
     agree, exactly as the spelling rule below. *)
  let memo : (string, (const_val, string) result) Hashtbl.t = Hashtbl.create 16 in
  let visiting = Hashtbl.create 16 in
  let recursive = Hashtbl.create 4 in
  let rec value_of_bare (f : string) : (const_val, string) result =
    match Hashtbl.find_opt memo f with
    | Some r -> r
    | None ->
      if Hashtbl.mem visiting f then begin
        Hashtbl.replace recursive f ();
        Error "is recursive"
      end
      else begin
        Hashtbl.replace visiting f ();
        let defs = List.filter (fun (_, fd) -> fd.A.fn_name.A.txt = f) cands in
        let r =
          match defs with
          | [] -> Error (Printf.sprintf "calls `%s`, which is not itself a zero-argument constant function" f)
          | _ ->
            let rs = List.map (fun (_, fd) -> fold_const_body lookup (List.hd fd.A.fn_clauses).A.fc_body) defs in
            combine f rs
        in
        Hashtbl.remove visiting f;
        Hashtbl.replace memo f r;
        r
      end
  (* A callee's own failure reason is about ITS body; the caller's reason
     names the callee instead. *)
  and lookup (f : string) : (const_val, string) result =
    match value_of_bare f with
    | Ok v -> Ok v
    | Error _ when Hashtbl.mem recursive f ->
      Error (Printf.sprintf "calls `%s`, which is recursive" f)
    | Error _ -> Error (Printf.sprintf "calls `%s`, which is not itself a zero-argument constant function" f)
  (* Several definitions under one spelling: all must fold to one value. *)
  and combine (spelling : string) (rs : (const_val, string) result list) =
    match rs with
    | [] -> assert false
    | [ r ] -> r
    | first :: rest ->
      if List.for_all (fun r -> r = first) rest then first
      else
        Error
          (Printf.sprintf
             "is defined more than once as `%s` and the definitions do not fold to the same value, so the spelling is ambiguous"
             spelling)
  in
  (* Every spelling of every candidate, then combine per spelling. *)
  let by_spelling : (string, (const_val, string) result list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (path, fd) ->
      let name = fd.A.fn_name.A.txt in
      let r = fold_const_body lookup (List.hd fd.A.fn_clauses).A.fc_body in
      let rec suffixes = function
        | [] -> [ name ]
        | _ :: tl as p -> String.concat "." (p @ [ name ]) :: suffixes tl
      in
      List.iter
        (fun sp ->
          let prev = try Hashtbl.find by_spelling sp with Not_found -> [] in
          Hashtbl.replace by_spelling sp (prev @ [ r ]))
        (suffixes path))
    cands;
  Hashtbl.iter
    (fun sp rs ->
      match combine sp rs with
      | Ok v -> Hashtbl.replace const_fns sp (term_of_const_val v)
      | Error why -> Hashtbl.replace const_fn_rejected sp why)
    by_spelling

(* ── `@[measure]` shape gate ───────────────────────────────────────────────
   [is_measure] (which decides the predicate vocabulary) and
   [build_measure_preamble] / [resolve_measure] (which decide what a measure
   application reflects to) must agree on what a measure IS, or an annotated
   name is accepted by the first and dropped by the second: the warning goes
   quiet and every call site files an unreflectable-predicate hint instead.
   That was exactly the path `@[measure] fn size_x() : Int do 128 end` took.
   The shape both sides need is "a function of exactly the one value it
   measures": [smt_of_r] reflects a measure application only as `m(arg)`, to
   the symbolic `m$x` / `(m v)` (when the parameter's type is undeclared, as
   in the P1b fixtures) or to the axiomatised `(m (Ctor …))` (when it is a
   declared ADT).  A nullary or multi-parameter measure has no reflection at
   all — the only signal would be an unreflectable-predicate hint at every
   call site — so it is rejected HERE, at the annotation, with the remedy.
   Whether the parameter's type is a DECLARED ADT is deliberately not gated:
   symbolic fallback over an undeclared type is a translation, just a weaker
   one. *)
let measure_shape_error (fd : A.fn_def) : string option =
  let name = fd.A.fn_name.A.txt in
  match fd.A.fn_clauses with
  | [] -> None
  | c :: _ -> (
    match c.A.fc_params with
    | [] ->
      Some
        (Printf.sprintf
           "takes no parameters. A measure folds over the value it measures, so it must take \
            that value (an ADT such as `Tree` or `List(a)`) as its first parameter. A \
            zero-argument constant needs no annotation: a refinement predicate can call \
            `%s()` directly, and it is checked as the literal its body folds to."
           name)
    | [ _ ] -> None
    | ps ->
      Some
        (Printf.sprintf
           "takes %d parameters. A measure is a function of the single value it measures, \
            and a predicate can only apply it to one argument, so no predicate mentioning \
            `%s` could be translated."
           (List.length ps) name))

(* Is [e] EXACTLY one of [vars] — an arm body that is a bare field read?

   Deliberately this narrow, and not "mentions one of [vars] anywhere".  The
   broader test has a real false positive: `Zleaf(n) -> 0 * n` mentions the
   erased field `n` but its value does not depend on it, so the measure still
   evaluates fine and warning about it would be wrong.  (That exact fixture is
   a LOAD-BEARING case in test_refinecheck.ml's measure-base-case-axiom group,
   and it caught this while the broader version was in tree.)  This subsystem
   treats a false positive as its cardinal sin, so the warning under-covers on
   purpose: `Node(n, m) -> n + 0` is equally inert and draws nothing.  What it
   does catch is the exact shape that motivated it — a measure that IS a field
   read, which is how a count-carrying container like `Array` writes it. *)
let body_is_bare_field_read (vars : string list) (e : A.expr) : bool =
  match unblock e with A.EVar { A.txt; _ } -> List.mem txt vars | _ -> false

(* Extract `match param do Ctor(vars) -> body … end` arms (None if not that shape). *)
let measure_arms (param : string) (body : A.expr) : (string * string list * A.expr) list option =
  match unblock body with
  | A.EMatch (A.EVar { A.txt; _ }, branches, _) when txt = param -> (
      try
        Some
          (List.map
             (fun (br : A.branch) ->
               match br.A.branch_pat with
               | A.PatCon (ctor, pats) ->
                 (* Counter is per-arm so _w1/_w2/… are unique within an arm's
                    scope; cross-arm collisions are harmless (vars are per-arm). *)
                 let wildcard_ctr = ref 0 in
                 let vars =
                   List.map
                     (function
                       | A.PatVar n -> n.A.txt
                       | A.PatWild _ ->
                         incr wildcard_ctr;
                         Printf.sprintf "_w%d" !wildcard_ctr
                       | _ -> raise Exit)
                     pats
                 in
                 (ctor.A.txt, vars, br.A.branch_body)
               | _ -> raise Exit)
             branches)
      with Exit -> None)
  | _ -> None

(* Translate a measure arm body to SMT (function-app encoding): patvars -> Const,
   a measure call m(v) -> (m v) where m is the measure itself OR another
   axiomatisable measure ([allowed]) and v MUST be a bound patvar (a structurally
   smaller value).  Requiring a structural argument on EVERY measure call (self
   or cross — M-c) keeps the whole, possibly mutually-recursive, measure system
   structurally decreasing, hence total: axiomatising it is sound.  `len` and
   non-axiomatised measures are not [allowed], so an arm calling one stays
   untranslatable (symbolic fallback).  None => untranslatable. *)
let rec smt_of_axiom_body ~self ~allowed (bound : string list) (e : A.expr) : Smt.term option =
  let r = smt_of_axiom_body ~self ~allowed bound in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.EVar { A.txt; _ } when List.mem txt bound -> Some (Smt.Const txt)
  | A.EApp (A.EVar { A.txt = m; _ }, [ A.EVar { A.txt = v; _ } ], _)
    when (m = self || allowed m) && List.mem v bound ->
    Some (Smt.App (m, [ Smt.Const v ]))
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Add (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Sub (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ A.ELit (A.LitInt k, _); b ], _) ->
    Option.map (fun y -> Smt.MulLit (k, y)) (r b)
  | _ -> None

(* All ADT sorts reachable from [seeds] through constructor fields, so a single
   `declare-datatypes` covers every sort an axiom mentions (handles cross-ADT
   references and mutually-recursive datatypes). *)
let adt_closure (seeds : string list) : string list =
  let seen = Hashtbl.create 16 in
  let rec visit a =
    if not (Hashtbl.mem seen a) then begin
      Hashtbl.replace seen a ();
      List.iter
        (fun c ->
          List.iter
            (function Smt.SData s when s <> "Elem" -> visit s | _ -> ())
            (try Hashtbl.find ctor_field_sorts c with Not_found -> []))
        (try Hashtbl.find adt_ctors a with Not_found -> [])
    end
  in
  List.iter visit seeds;
  Hashtbl.fold (fun a () acc -> a :: acc) seen []

let ctor_decl (c : string) : string =
  let sorts = try Hashtbl.find ctor_field_sorts c with Not_found -> [] in
  if sorts = [] then Printf.sprintf "(%s)" c
  else
    Printf.sprintf "(%s %s)" c
      (String.concat " "
         (List.mapi (fun i s -> Printf.sprintf "(%s_%d %s)" c i (Smt.string_of_sort s)) sorts))

(* One `declare-datatypes` declaring all [adts] sorts together (mutual recursion
   among them resolves within the single command). *)
let datatype_decls (adts : string list) : string =
  if adts = [] then ""
  else
    let sort_decls = String.concat " " (List.map (fun a -> Printf.sprintf "(%s 0)" a) adts) in
    let bodies =
      String.concat " "
        (List.map
           (fun a ->
             Printf.sprintf "(%s)"
               (String.concat " " (List.map ctor_decl (try Hashtbl.find adt_ctors a with Not_found -> []))))
           adts)
    in
    Printf.sprintf "(declare-datatypes (%s) (%s))" sort_decls bodies

(* The recursion-equation axiom for one arm of [name] (None if untranslatable). *)
let arm_axiom ~allowed (name : string) ((ctor, vars, body) : string * string list * A.expr) : string option =
  match smt_of_axiom_body ~self:name ~allowed vars body with
  | None -> None
  | Some bsmt ->
    let sorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
    if List.length vars <> List.length sorts then None
    else
      let lhs =
        if vars = [] then Printf.sprintf "(%s %s)" name ctor
        else Printf.sprintf "(%s (%s %s))" name ctor (String.concat " " vars)
      in
      if vars = [] then Some (Printf.sprintf "(assert (= %s %s))" lhs (Smt.render bsmt))
      else
        let bound =
          List.map2 (fun v s -> Printf.sprintf "(%s %s)" v (Smt.string_of_sort s)) vars sorts
        in
        Some
          (Printf.sprintf "(assert (forall (%s) (! (= %s %s) :pattern (%s))))"
             (String.concat " " bound) lhs (Smt.render bsmt) lhs)

(* Build the global measure-axiom preamble; populates [axiom_measures].

   A measure is axiomatised iff (a) its body is an exhaustive `match` on its ADT
   parameter (shape + totality) and (b) every arm translates — which, since a
   cross-measure call is only translatable when its callee is itself
   axiomatisable (M-c), is a mutual dependency.  We resolve it with a greatest
   fixpoint: start with every shape-OK measure as a candidate and drop any whose
   arms fail to translate against the current candidate set, until stable.  All
   `declare-fun`s are emitted before any axiom so cross-measure (incl. mutually
   recursive) references resolve. *)
let build_measure_preamble (mdefs : (string * A.fn_def) list) : unit =
  Hashtbl.reset axiom_measures;
  (* shape-OK measures: (name, param-ADT, arms), exhaustive match on the param. *)
  let shaped =
    List.filter_map
      (fun (name, fd) ->
        match measure_param_adt fd, fd.A.fn_clauses with
        | Some (param, adt), c :: _ -> (
          match measure_arms param c.A.fc_body with
          | Some arms ->
            let covered = List.sort compare (List.map (fun (c, _, _) -> c) arms) in
            let all = List.sort compare (try Hashtbl.find adt_ctors adt with Not_found -> []) in
            if covered = all && all <> [] then Some (name, adt, arms) else None
          | None -> None)
        | _ -> None)
      mdefs
  in
  let translates allowed (name, _, arms) =
    List.for_all (fun arm -> arm_axiom ~allowed name arm <> None) arms
  in
  let candidates = ref (List.map (fun (n, _, _) -> n) shaped) in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun ((name, _, _) as s) ->
        if List.mem name !candidates && not (translates (fun m -> List.mem m !candidates) s)
        then begin
          candidates := List.filter (( <> ) name) !candidates;
          changed := true
        end)
      shaped
  done;
  let allowed m = List.mem m !candidates in
  let axiomatized = List.filter (fun (n, _, _) -> allowed n) shaped in
  List.iter (fun (name, adt, _) -> Hashtbl.replace axiom_measures name adt) axiomatized;
  (* Diagnostic-only (see [measure_scalar_field_dep]): flag an axiomatised
     measure whose value reads a field that call-site reflection erases.  Runs
     over [axiomatized] only, so a measure that was never axiomatised in the
     first place keeps its existing symbolic-fallback behaviour and draws
     nothing new. *)
  Hashtbl.reset measure_scalar_field_dep;
  List.iter
    (fun (name, _, arms) ->
      let arm_reads_erased_field (ctor, vars, body) =
        let sorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
        if List.length vars <> List.length sorts then false
        else
          (* "Erased" is exactly [reflect_field]'s own condition, inverted: it
             RECURSES into a datatype field other than the opaque `Elem`, and
             mints a fresh constant for everything else. *)
          let erased =
            List.filter_map
              (fun (v, s) ->
                match s with Smt.SData sub when sub <> "Elem" -> None | _ -> Some v)
              (List.combine vars sorts)
          in
          body_is_bare_field_read erased body
      in
      if List.exists arm_reads_erased_field arms then
        Hashtbl.replace measure_scalar_field_dep name ())
    axiomatized;
  Hashtbl.reset measure_base_cases;
  List.iter
    (fun (name, _, arms) ->
      let bases =
        List.filter_map
          (fun (ctor, _vars, body) ->
            (* A base case arm has a concrete-integer body.  We do not guard on
               vars=[] because wildcard arms (e.g. Leaf(_)) now produce generated
               names (_w1, …) in vars — but an ELit body is always variable-free
               regardless of how many wildcards appear in the pattern. *)
            match body with
            | A.ELit (A.LitInt n, _) -> Some (ctor, n)
            | _ -> None)
          arms
      in
      if bases <> [] then Hashtbl.replace measure_base_cases name bases)
    axiomatized;
  if axiomatized = [] then measure_preamble := ""
  else begin
    let buf = Buffer.create 256 in
    (* declare-funs first … *)
    List.iter
      (fun (name, adt, _) -> Buffer.add_string buf (Printf.sprintf "(declare-fun %s (%s) Int)\n" name adt))
      axiomatized;
    (* … then non-negativity axioms … *)
    List.iter
      (fun (name, adt, _) ->
        if is_nonneg_measure name then
          Buffer.add_string buf
            (Printf.sprintf "(assert (forall ((x %s)) (! (>= (%s x) 0) :pattern ((%s x)))))\n"
               adt name name))
      axiomatized;
    (* … then base-case linking axioms: for a measure whose base-case arm is a
       concrete integer literal, link that constructor's tester directly to the
       measure's value.

       This closes the same gap that motivated `path_resolve_tester`'s
       `is_Nil(xs) <-> len(xs) = 0` translation (see the comment there), but
       for a general user `@[measure]` rather than the one built-in measure
       (`len` over the built-in `List`) that hack special-cases.  A match arm
       reachable only because an earlier sibling's tag was excluded carries a
       bare `((_ is Ctor) x)` fact about a FREE variable (pushed by [visit]'s
       `A.EMatch` case's arm-order-exclusion narrowing).  For a user measure
       that has no `path_resolve_tester`-style hardcoding, the ordinary
       recursion-equation axiom cannot pick that up: its trigger pattern is the
       CONSTRUCTED term `(name (Ctor v1 v2 …))`, which never E-matches against
       a tester over a free variable.  (A NULLARY base case is ALSO a ground
       fact via [arm_axiom]'s `vars = []` branch, so strictly it needs no
       axiom of its own here either — but the collection loop above does not
       filter on arity, so a nullary constructor with a literal body, e.g.
       `Nil -> 0`, gets one anyway.  That is redundant, not wrong: the two
       axioms agree, so the solver just has one extra fact to skip.  The case
       this axiom actually exists for is a base case whose constructor takes
       fields but whose body is still a plain literal, e.g. `Cons(_, _) -> 0`.)

       Confirmed empirically to be the whole fix needed for the `len`/`List`
       shape — no change to the arm-order-exclusion narrowing itself was
       required, since it already pushes the negative tag fact; the missing
       piece was only ever the axiom connecting a tester over a free variable
       to the measure's value, and for `len` specifically that connection is
       `path_resolve_tester`'s hardcoded translation, not this axiom.  This
       axiom's own effect is currently a no-op across the stdlib (a full sweep
       before/after showed a byte-identical `--refine-report` on all 112
       modules — no proof gained, no proof lost); it exists to close the
       general case for the next user-defined measure that hits this shape. *)
    List.iter
      (fun (name, adt, _) ->
        match Hashtbl.find_opt measure_base_cases name with
        | None -> ()
        | Some bases ->
          List.iter
            (fun (ctor, n) ->
              Buffer.add_string buf
                (Printf.sprintf
                   "(assert (forall ((x %s)) (! (=> ((_ is %s) x) (= (%s x) %d)) :pattern ((%s x)))))\n"
                   adt ctor name n name))
            bases)
      axiomatized;
    (* … then the recursion-equation axioms. *)
    List.iter
      (fun (name, _, arms) ->
        List.iter
          (fun arm -> match arm_axiom ~allowed name arm with Some s -> Buffer.add_string buf (s ^ "\n") | None -> ())
          arms)
      axiomatized;
    let covered = adt_closure (List.map (fun (_, adt, _) -> adt) axiomatized) in
    let dts = datatype_decls covered in
    measure_preamble := "(declare-sort Elem 0)\n" ^ dts ^ "\n" ^ Buffer.contents buf;
    Hashtbl.reset measure_preamble_sorts;
    List.iter (fun s -> Hashtbl.replace measure_preamble_sorts s ()) covered
  end

(* The built-in ADTs, modelled so user measures and constructor testers over
   them work exactly like over user ADTs.  `List(a)` = `Nil | Cons(a, List(a))`
   with the element opaque (`Elem`) and the tail recursive.  `Option(a)` and
   `Result(a, e)` have no `type` declaration anywhere — not in the stdlib
   either; they are pre-registered by the typechecker (see [builtin_ctors] in
   typecheck.ml), so the refinement checker must seed them the same way or
   `is_Some` would name nothing.  Payloads are opaque (`Elem`): a constructor
   tester cares about the tag, not the contents.  Seeded before user types so a
   user-defined `List`/`Option` (unusual) still overrides. *)
let register_builtin_adts () : unit =
  Hashtbl.replace adt_ctors (adt_sort_name "List") [ "Nil"; "Cons" ];
  Hashtbl.replace ctor_field_sorts "Nil" [];
  Hashtbl.replace ctor_field_sorts "Cons" [ Smt.SData "Elem"; Smt.SData (adt_sort_name "List") ];
  Hashtbl.replace adt_ctors (adt_sort_name "Option") [ "None"; "Some" ];
  Hashtbl.replace ctor_field_sorts "None" [];
  Hashtbl.replace ctor_field_sorts "Some" [ Smt.SData "Elem" ];
  Hashtbl.replace adt_ctors (adt_sort_name "Result") [ "Ok"; "Err" ];
  Hashtbl.replace ctor_field_sorts "Ok" [ Smt.SData "Elem" ];
  Hashtbl.replace ctor_field_sorts "Err" [ Smt.SData "Elem" ]

(* Build type_preamble from all registered TDRecord sorts, excluding any sorts
   already declared in measure_preamble (tracked in measure_preamble_sorts). *)
let build_type_preamble () : unit =
  let record_sorts =
    Hashtbl.fold
      (fun sort _ctors acc ->
        match Hashtbl.find_opt adt_ctors sort with
        | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> sort :: acc
        | _ -> acc)
      adt_ctors []
  in
  if record_sorts = [] then type_preamble := ""
  else begin
    let all_sorts = adt_closure record_sorts in
    let new_sorts = List.filter (fun s -> not (Hashtbl.mem measure_preamble_sorts s)) all_sorts in
    if new_sorts = [] then type_preamble := ""
    else
      (* Only emit (declare-sort Elem 0) if measure_preamble doesn't already
         have it — the two preambles are concatenated in record_vc_preamble and
         a duplicate declaration causes a Z3 error inside the same push. *)
      let elem_decl = if !measure_preamble = "" then "(declare-sort Elem 0)\n" else "" in
      type_preamble := elem_decl ^ datatype_decls new_sorts
  end

(* All sorts needed for a record VC, WITHOUT measure axioms — used when all
   measure applications were evaluated concretely at the OCaml level.  Avoids
   the quantified forall axioms that cause Z3 to return `unknown` for SAT
   queries even when the goal no longer references any measure function. *)
let type_only_preamble () : string =
  let record_sorts =
    Hashtbl.fold
      (fun sort _ctors acc ->
        match Hashtbl.find_opt adt_ctors sort with
        | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> sort :: acc
        | _ -> acc)
      adt_ctors []
  in
  if record_sorts = [] then ""
  else
    let all_sorts = adt_closure record_sorts in
    if all_sorts = [] then ""
    else
      (* Only emit `(declare-sort Elem 0)` when a sort in the closure actually
         uses Elem-typed fields (i.e. a List ADT is reachable).  Pure record
         types with no list fields don't need Elem and emitting it is harmless
         but inconsistent with build_type_preamble's deduplication logic. *)
      let needs_elem =
        List.exists
          (fun sort ->
            List.exists
              (fun ctor ->
                List.exists
                  (fun s -> s = Smt.SData "Elem")
                  (try Hashtbl.find ctor_field_sorts ctor with Not_found -> []))
              (try Hashtbl.find adt_ctors sort with Not_found -> []))
          all_sorts
      in
      (if needs_elem then "(declare-sort Elem 0)\n" else "") ^ datatype_decls all_sorts

(* Datatype declarations for [seeds] and everything reachable from them — the
   preamble a VC needs when a constructor tester ranges over those sorts.
   [skip] drops sorts already declared elsewhere in the same VC (Z3 rejects a
   duplicate sort inside one push), and [skip_elem] does the same for the
   opaque `Elem` sort. *)
let adt_vc_preamble ~(skip : string -> bool) ~(skip_elem : bool) (seeds : string list) : string =
  let sorts = List.filter (fun s -> not (skip s)) (adt_closure seeds) in
  if sorts = [] then ""
  else
    let needs_elem =
      (not skip_elem)
      && List.exists
           (fun sort ->
             List.exists
               (fun ctor ->
                 List.exists
                   (fun s -> s = Smt.SData "Elem")
                   (try Hashtbl.find ctor_field_sorts ctor with Not_found -> []))
               (try Hashtbl.find adt_ctors sort with Not_found -> []))
           sorts
    in
    (if needs_elem then "(declare-sort Elem 0)\n" else "") ^ datatype_decls sorts

let record_vc_preamble () : string =
  match !measure_preamble, !type_preamble with
  | "", t -> t
  | m, "" -> m
  | m, t -> m ^ "\n" ^ t

(* =================================================================
   §6  AST traversal helpers and measure gating
   ================================================================= *)

(* Does [t] carry a refinement ANYWHERE -- either position of an arrow spine
   (so both a parameter and the return), or nested inside a type argument,
   tuple, record field or linearity wrapper?  Every one of those positions is
   equally inert in an interface method signature, so the detector must not be
   narrowed to the spine.  Mirrors [warn_predicate_ty]'s traversal exactly
   (see [refine_check.ml]).

   Lives here, not in [refine_check.ml] where it originated, because
   [Refine_audit] (a separate, non-included module -- see its own top
   comment) needs to call it and cannot depend on [Refine_check] without
   creating a cycle: [Refine_check] is the last link in this file's own
   [include] chain ([refine_check.ml] includes [refine_post.ml] includes
   ... includes this file), so anything [Refine_check] can see, everything
   downstream of it in the chain can see too, but not the reverse. Moved
   here per Task 2's re-review (finding 9), which proved the cycle with a
   real build and verified this exact move compiles clean and needs no
   [.mli] change: [refine_check.mli]'s [val ty_has_refinement] keeps
   re-exporting it through the [include] chain unchanged. *)
let rec ty_has_refinement (t : A.ty) : bool =
  match t with
  | A.TyRefine _ -> true
  | A.TyCon (_, args) -> List.exists ty_has_refinement args
  | A.TyArrow (a, b) -> ty_has_refinement a || ty_has_refinement b
  | A.TyTuple ts -> List.exists ty_has_refinement ts
  | A.TyRecord fs -> List.exists (fun (_, t) -> ty_has_refinement t) fs
  | A.TyLinear (_, t) -> ty_has_refinement t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> false

(* ── M-b: the @[measure] soundness gate ─────────────────────────────────────
   `@[measure]` is a promise that the function is a TOTAL, TERMINATING, PURE
   mathematical function.  The axiom encoding trusts that promise: axiomatising a
   partial / non-terminating / effectful "measure" makes the SMT context
   inconsistent, from which the solver can prove ANYTHING — silent unsoundness,
   the worst failure mode.  So breaking the promise is a HARD compile error, not
   a silent fallback: a user relying on the measure in a predicate deserves to
   know it cannot be trusted.

   The checks are conservative syntactic over-approximations.  A measure that is
   sound but merely outside the v1 axiom *encoding* fragment (multi-argument,
   element-inspecting, `let`-bodied) is NOT an error — it falls back to a sound
   symbolic reflection.  Only the three soundness properties are gated. *)

(* Immediate sub-expressions, for a structure-agnostic traversal. *)
let children : A.expr -> A.expr list = function
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> []
  | A.EApp (f, args, _) -> f :: args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> args
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> [ b ]
  | A.EBlock (es, _) -> es
  | A.ELet (b, _) -> [ b.A.bind_expr ]
  | A.EMatch (s, brs, _) ->
    s
    :: List.concat_map
         (fun (br : A.branch) ->
           (match br.A.branch_guard with Some g -> [ g ] | None -> []) @ [ br.A.branch_body ])
         brs
  | A.ERecord (fs, _) -> List.map snd fs
  | A.ERecordUpdate (r, fs, _) -> r :: List.map snd fs
  | A.EField (r, _, _) -> [ r ]
  | A.EIf (c, t, e, _) -> [ c; t; e ]
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> [ c; b ]) arms
  | A.EPipe (a, b, _) -> [ a; b ]
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> [ e ]
  | A.ESend (a, b, _) -> [ a; b ]
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> [ e1; e2 ]

let rec iter_all (f : A.expr -> unit) (e : A.expr) : unit =
  f e;
  List.iter (iter_all f) (children e)

(* Variables structurally smaller than [param]: bound by a constructor pattern
   when matching [param] (or an already-structural variable, so a nested
   `match l do …` contributes l's components too).  Accumulated top-down. *)
let structural_subvars (param : string) (body : A.expr) : (string, unit) Hashtbl.t =
  let set = Hashtbl.create 16 in
  let is_struct v = v = param || Hashtbl.mem set v in
  let rec pat_vars = function
    | A.PatVar n -> [ n.A.txt ]
    | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) -> List.concat_map pat_vars ps
    | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
    | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
    | A.PatOr (ps, _) -> List.concat_map pat_vars ps
    | A.PatWild _ | A.PatLit _ -> []
  in
  iter_all
    (fun e ->
      match e with
      | A.EMatch (A.EVar s, brs, _) when is_struct s.A.txt ->
        List.iter
          (fun (br : A.branch) ->
            match br.A.branch_pat with
            | A.PatCon (_, pats) ->
              List.iter (fun v -> Hashtbl.replace set v ()) (List.concat_map pat_vars pats)
            | _ -> ())
          brs
      | _ -> ())
    body;
  set

(* Every name a function binds: its parameters, and every `let` / `let fn` /
   `let?` / `let*` / lambda / match binder anywhere in its bodies (a union
   over all clauses; over-approximation is the safe direction for
   [const_shadowed]). *)
let fn_binders (fd : A.fn_def) : string list =
  let acc = ref [] in
  let add n = acc := n :: !acc in
  let rec pat_vars = function
    | A.PatVar n -> add n.A.txt
    | A.PatAs (p, n, _) -> add n.A.txt; pat_vars p
    | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
      List.iter pat_vars ps
    | A.PatRecord (fs, _) -> List.iter (fun (_, p) -> pat_vars p) fs
    | A.PatWild _ | A.PatLit _ -> ()
  in
  let params ps = List.iter (fun (p : A.param) -> add p.A.param_name.A.txt) ps in
  List.iter
    (fun (c : A.fn_clause) ->
      List.iter
        (function
          | A.FPNamed p | A.FPDefault (p, _) -> add p.A.param_name.A.txt
          | A.FPPat p -> pat_vars p)
        c.A.fc_params;
      iter_all
        (fun e ->
          match e with
          | A.ELet (b, _) -> pat_vars b.A.bind_pat
          | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) -> pat_vars p
          | A.ELetFn (n, ps, _, _, _) -> add n.A.txt; params ps
          | A.ELam (ps, _, _) -> params ps
          | A.EMatch (_, brs, _) ->
            List.iter (fun (br : A.branch) -> pat_vars br.A.branch_pat) brs
          | _ -> ())
        c.A.fc_body)
    fd.A.fn_clauses;
  !acc

(* Builtins that diverge or abort: a body calling one is not a total function. *)
let measure_partial_calls =
  [ "panic"; "panic_"; "todo"; "todo_"; "unreachable"; "unreachable_"; "exit" ]

(* Gate violations of a `@[measure]`, as human-readable predicate clauses. *)
let measure_gate_errors (fd : A.fn_def) : string list =
  let self = fd.A.fn_name.A.txt in
  let errs = ref [] in
  let add m = if not (List.mem m !errs) then errs := m :: !errs in
  List.iter
    (fun (c : A.fn_clause) ->
      let body = c.A.fc_body in
      (* (1) Purity & totality of operations. *)
      iter_all
        (fun e ->
          match e with
          | A.ESpawn _ -> add "must be pure (it spawns an actor)"
          | A.ESend _ -> add "must be pure (it sends a message)"
          | A.EDbg _ -> add "must be pure (it uses a `dbg` expression)"
          | A.EAssert _ -> add "must be total (an `assert` can abort)"
          | A.EApp (A.EVar { A.txt; _ }, _, _) when List.mem txt measure_partial_calls ->
            add (Printf.sprintf "must be total (it calls `%s`, which does not return)" txt)
          | A.EApp (A.EVar { A.txt = ("/" | "%") as op; _ }, [ _; d ], _) -> (
            match d with
            | A.ELit (A.LitInt n, _) when n <> 0 -> ()
            | _ -> add (Printf.sprintf "must be total (`%s` can divide by zero)" op))
          | _ -> ())
        body;
      (* (2) Termination via structural recursion. *)
      (match clause_param_name c with
       | Some param ->
         let sset = structural_subvars param body in
         iter_all
           (fun e ->
             match e with
             | A.EApp (A.EVar { A.txt; _ }, args, _) when txt = self -> (
               match args with
               | [ A.EVar v ] when Hashtbl.mem sset v.A.txt -> ()
               | _ ->
                 add
                   "is not structurally recursive (every recursive call must be on a \
                    component of the matched parameter)")
             | _ -> ())
           body
       | None ->
         iter_all
           (fun e ->
             match e with
             | A.EApp (A.EVar { A.txt; _ }, _, _) when txt = self ->
               add
                 "cannot be shown to terminate (a recursive @[measure] must take an ADT \
                  parameter and recurse on its components)"
             | _ -> ())
           body);
      (* (3) Totality via an exhaustive match on the ADT parameter. *)
      match clause_param_adt c with
      | Some (param, adt) -> (
        match measure_arms param body with
        | Some arms ->
          let covered = List.map (fun (ctor, _, _) -> ctor) arms in
          let all = try Hashtbl.find adt_ctors adt with Not_found -> [] in
          let missing = List.filter (fun ctor -> not (List.mem ctor covered)) all in
          if all <> [] && missing <> [] then
            add
              (Printf.sprintf "must be total (its `match` does not cover %s)"
                 (String.concat ", " missing))
        | None -> ())
      | None -> ())
    fd.A.fn_clauses;
  List.rev !errs

