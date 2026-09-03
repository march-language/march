(* Obligation ledger for the refinement checker.
   March reports a violation only when a predicate can NEVER hold; every other
   outcome is silence.  That makes silence ambiguous between "proved", "skipped
   because the checker could not reflect it", and "the solver did not decide" —
   and that ambiguity is not cosmetic: `{List(a) | len(_) > 0}` shipped
   enforcing nothing while the suite stayed green, because a contract that
   checks nothing and a contract that passes look identical from outside.
   Every obligation now leaves a record, so the outcome is countable. *)

type reason =
  (* The rule between this reason and [Unreflectable_subject]: the SUBJECT is
     tried first: a call's actual argument, or a postcondition's own return
     expression. Only once the subject reflects fine does a further
     failure blame the predicate. So [Unreflectable_predicate] fires when the
     self binder (or the postcondition's return expression) reflected but some
     other sub-expression of the predicate did not; it names that innermost
     failing leaf, via [smt_of_r] at the two goal sites that reflect through it
     (`refine_call.ml`, `refine_post.ml:406`). Payload discipline follows
     [Alias_withdrawn]/[Unreflectable_subject]: the failing sub-expression,
     rendered by [pred_str], rides in [reason_detail] only; [reason_name]
     stays payload-free so `--refine-report` groups every
     unreflectable-predicate skip into one bucket instead of one per distinct
     sub-expression. *)
  | Unreflectable_predicate of string
  (* The SUBJECT did not reflect: a call's actual argument, or a
     postcondition's own return expression, whichever is being checked. Filed
     before the predicate is ever reached, so a subject failure never gets
     misattributed to a predicate that would have translated fine. Payload
     discipline follows [Alias_withdrawn]: the subject, rendered by
     [pred_str], rides in [reason_detail] only; [reason_name] stays
     payload-free so `--refine-report` groups every failed-subject skip into
     one bucket instead of one per distinct subject. *)
  | Unreflectable_subject of string
  | Sort_conflict            (* a symbol would have been declared at two sorts *)
  | Float_sort_gate          (* the float/formula wellsortedness gate rejected it *)
  | Solver_undecided         (* neither goal nor its negation was Verified *)
  (* A measure ALIAS that the guard relied on was withdrawn, because this
     compilation unit binds the spelling carried here.  Strictly a refinement
     of [Solver_undecided]: the VC was built and the solver ran, it just had no
     fact connecting the guard to the measure.  It exists because the two are
     not the same message to a USER — "the solver proved neither the predicate
     nor its negation" points at Z3 and at the predicate, and every remedy that
     text offers ("guard the call", "rewrite the predicate") is one the author
     already applied.  The cause is a name-shadowing decision made elsewhere in
     the unit, possibly in another file entirely, and only naming it is
     actionable.  See [Refine_check.withdrawals] for when a skip is attributed
     here — deliberately narrowly, since a WRONG attribution is worse than a
     vague one.

     NOTE for anyone changing how reports GROUP skips: this is the first reason
     carrying a payload, so two withdrawn spellings in one unit are two
     distinct keys and print as two `alias-withdrawn` lines.  Cosmetic — the
     headline totals are unaffected — but the fix would have to touch TWO
     places, because [summary] below is used only by the tests: bin/main.ml's
     [print_refine_report] keeps its own `Hashtbl` keyed on the whole reason. *)
  | Alias_withdrawn of string
  (* Refinements of [Solver_undecided], split out because they are different
     pieces of advice.  The residual keeps the old constructor: a reason we
     cannot name must not be dressed up as one we can.

     Payload discipline follows [Alias_withdrawn]: the NAME rides in the
     detail, not the slug, so `--refine-report` groups all unconstrained
     subjects into one bucket instead of one bucket per variable.

     A third variant, [Nonlinear_goal], was cut before it shipped: the only
     [smt_of] used to build a goal never produces [Smt.Mul] for two
     non-literal operands (it returns [None], so such a predicate fails
     earlier as [Unreflectable_predicate]), so the diagnosis was dead code
     with no reachable fixture.  Making it reachable would mean teaching
     [smt_of] to reflect general multiplication, which sends previously
     unreflectable predicates to z3 for the first time — an improvement in
     checker PRECISION, out of scope for a task that only explains existing
     skips. *)
  | Unconstrained_subject of string  (* the subject appears in no assumption *)
  | Opaque_application of string     (* goal names an undeclared function symbol *)
  (* The goal is a top-level conjunction and the per-conjunct discharge (over
     the SAME assumption set as the whole-goal proof attempt — no new facts,
     no precision change) proved some conjuncts and not others.  This is the
     costliest diagnosis to compute (one extra [Refine.discharge] per
     conjunct) and the highest-value one to report: a `List.nth`-shaped
     bounds contract with the lower bound guarded and the upper bound not is
     exactly "the solver proved neither the predicate nor its negation", and
     that sentence gives the reader no way to tell their guard partially
     worked.
     Payload is rendered SOURCE syntax, not SMT: it goes straight into user
     text.  Both lists are kept because "`i >= 0` holds" and "`i < len(xs)`
     does not" are both load-bearing — the first tells the reader their guard
     worked and stops them rewriting it. *)
  | Partial_conjunct of { held : string list; missing : string list }

(* [Trusted]: the obligation was [Skipped] for some ordinary reason, but the
   enclosing function carries `@[trusted]`, so under `cap verified` it is
   accepted as an ASSERTION rather than escalated to an error.  This is a
   deliberate soundness hole and therefore its own verdict, never folded into
   [Proved] — a reader of `--refine-report` must be able to tell how much of a
   module's "verification" is actually a trusted assertion.  It can only ever
   replace a [Skipped _]: a [Violated] is a DECIDED failure, not an
   incompleteness to wave through, so [Trusted] must never be produced from
   one.

   [Violated] covers two shapes, both decided and both reported at the call
   site.  The original one is "the solver proved the predicate can NEVER hold"
   — a bug in the annotation.  The second, added with the call-site promotion
   (design doc §2), is "SOME input demonstrably fails": the enclosing
   function was executed on decoded arguments and observed to panic, and to
   return once the offending argument was repaired.  The two are not the same
   strength of claim, and a future report that wants to distinguish them will
   need a third verdict rather than a payload — but neither is a skip, and
   `--refine-report` must not count either as an incompleteness, which is what
   sharing the constructor buys. *)
type verdict = Proved | Violated | Trusted | Skipped of reason

(* [Precondition]: an argument checked against a callee's declared param
   refinement (or a bound expression against a `let` annotation) — [callee]
   names the callee/annotation site.  [Postcondition]: a function's own
   return value checked against its declared return refinement — [callee]
   carries the FUNCTION's own name, since there is no separate callee to
   name.  [Division]: a `cap no_panic` divisor checked non-zero by
   [Division_safety] — [callee] names the DIVISOR variable, since the
   obligation belongs to a `/` rather than to any function.

   [Division] is its own kind rather than a [Precondition] with a synthetic
   callee because both `cap verified` escalation and `--refine-report` branch
   on kind; folding it into [Precondition] would silently change what those
   two do for every module that already contains a division. *)
type kind = Precondition | Postcondition | Division

type t =
  { span : March_ast.Ast.span
  ; callee : string
  ; predicate : string
  ; verdict : verdict
  ; kind : kind
  }

let log : t list ref = ref []

(* ── Per-call-site index ───────────────────────────────────────────────────
   The ledger above answers "how many obligations of each verdict does this
   module have"; [by_span] answers "what did the checker conclude about THIS
   site".  A later pass that wants to admit a call because its precondition
   was actually discharged — rather than banning it by name — needs the second
   question, and there was no way to ask it.

   It is populated HERE, in [record], on purpose: [record] is the single point
   every verdict in this subsystem already passes through (four call sites
   today — [Refine_check]'s precondition [note], its postcondition [note], its
   match-tail postcondition, and [Division_safety]), so the index cannot go
   partially stale as those paths change, and it cannot disagree with what
   `--refine-report` prints because it holds the very same records.  Deriving
   a verdict any other way would be a second discharge path, free to drift
   from the real one.

   Keyed on the obligation's own [span], which for a precondition is the span
   [Refine_check.visit] hands [check_call] as [~span] — the CALL EXPRESSION's
   span, i.e. the [sp] of [A.EApp (_, _, sp)].  A consumer must key on the
   same thing; the callee NAME's span is a different span and would silently
   never match. *)
let by_span : (March_ast.Ast.span, t list) Hashtbl.t = Hashtbl.create 64

(* Cleared with the ledger, so the index's lifetime is exactly one module —
   [Refine_check.check_module] calls [reset] at its top.  Leaking an entry
   across modules would let a later module read a `Proved` that was never
   established for it, which is strictly worse than reading nothing. *)
let reset () = log := []; Hashtbl.reset by_span

(* Run [f] against a SCRATCH ledger+index, then put the real ones back.

   The suggestion probes ([Precond_infer]/[Postcond_infer]) work by calling
   [reset] and re-walking a HYPOTHESIS module — the user's program with a
   speculative contract spliced in — and reading the resulting counts back.
   That is fine for the ledger, which they only ever consult through
   [count_debt].  It was NOT fine for [by_span]: the printers run in the middle
   of the pipeline, so anything downstream that keys on a call site read the
   last hypothesis's verdicts as if they were the real program's.  That was
   live: `--refine-suggest-all` flipped `cap no_panic` in BOTH directions — a
   provably-unguarded `List.tail` compiled clean, and a correctly-guarded one
   errored.

   The pipeline order was fixed too (the consumers now run before the
   printers), but ordering alone is a rule nobody can see: the next consumer of
   [by_span] added after the printers would silently inherit the same bug.
   This makes the probes non-destructive instead, so the invariant is enforced
   where it is violated rather than by remote convention.

   [Hashtbl.copy] is a shallow copy, which is exactly right — the values are
   immutable [t list]s, and [record] replaces bindings rather than mutating
   them. *)
let with_scratch (f : unit -> 'a) : 'a =
  let saved_log = !log in
  let saved_index = Hashtbl.copy by_span in
  let restore () =
    log := saved_log;
    Hashtbl.reset by_span;
    Hashtbl.iter (fun k v -> Hashtbl.replace by_span k v) saved_index
  in
  match f () with
  | v -> restore (); v
  | exception e -> restore (); raise e

let record (o : t) : unit =
  log := o :: !log;
  Hashtbl.replace by_span o.span (o :: Option.value ~default:[] (Hashtbl.find_opt by_span o.span))

let all () : t list = List.rev !log

(* Every obligation recorded at [span], in the order they were recorded.  One
   call site can raise several — one per refined parameter — so this is a list,
   not an option, and a consumer must decide about ALL of them. *)
let obligations_at (span : March_ast.Ast.span) : t list =
  List.rev (Option.value ~default:[] (Hashtbl.find_opt by_span span))

(* The WEAKEST verdict recorded at [span], or [None] when no obligation was
   raised there at all.

   Weakest, never first-wins: a call whose first parameter proved and whose
   second was skipped has not been proved safe, and a consumer folding this
   the optimistic way would admit exactly the calls it must not.  [None] means
   "the checker said nothing about this site" — an unrefined call, or one the
   walk never reached — and must NOT be read as either a proof or a failure;
   it is the absence of information. *)
let verdict_at (span : March_ast.Ast.span) : verdict option =
  let rank = function
    | Violated -> 0
    | Skipped _ -> 1
    | Trusted -> 2
    | Proved -> 3
  in
  List.fold_left
    (fun acc (o : t) ->
      match acc with
      | Some v when rank v <= rank o.verdict -> acc
      | _ -> Some o.verdict)
    None (obligations_at span)

(* Slug for a verdict, mirroring [reason_name]'s role for a skip's reason.
   Exists so a consumer (and a test) can name a verdict without re-matching
   this type's constructors, which would break every time one is added. *)
let verdict_name = function
  | Proved -> "proved"
  | Violated -> "violated"
  | Trusted -> "trusted"
  | Skipped _ -> "skipped"

let reason_name = function
  | Unreflectable_predicate _ -> "unreflectable-predicate"
  | Unreflectable_subject _ -> "unreflectable-subject"
  | Sort_conflict -> "sort-conflict"
  | Float_sort_gate -> "float-sort-gate"
  | Solver_undecided -> "solver-undecided"
  (* The spelling is deliberately NOT interpolated into the slug: `--refine-report`
     groups skips by reason, and a per-spelling slug would split one cause into
     as many buckets as there are names.  The spelling belongs in the detail. *)
  | Alias_withdrawn _ -> "alias-withdrawn"
  | Unconstrained_subject _ -> "unconstrained-subject"
  | Opaque_application _ -> "opaque-application"
  | Partial_conjunct _ -> "partial-conjunct"

(* One clause of plain English per reason, for the `cap verified` error text.
   [reason_name] alone is a debug-report slug; once a reason reaches a USER it
   has to say what actually happened, and it must not over-claim — which is why
   [Unreflectable_subject] exists as its own reason at all.  The two used to be
   one: a record-typed argument whose ACTUAL could not be reflected was filed
   under "unreflectable predicate", so a user with a perfectly ordinary
   predicate would have been told to rewrite it and sent chasing the wrong
   thing.  Nothing but a debug count depended on the conflation. *)
let reason_detail = function
  | Unreflectable_predicate sub ->
    Printf.sprintf "the predicate's `%s` has no SMT translation" sub
  | Unreflectable_subject actual ->
    Printf.sprintf
      "the argument `%s` could not be translated to SMT, so no goal was built" actual
  | Sort_conflict -> "reflecting it would declare one symbol at two different sorts"
  | Float_sort_gate -> "the float wellsortedness gate rejected the formula"
  | Solver_undecided -> "the solver proved neither the predicate nor its negation"
  | Alias_withdrawn spelling ->
    Printf.sprintf
      "the guard uses `%s`, but this compilation unit also BINDS that name, so \
       the checker withdrew its built-in measure meaning and the guard proved \
       nothing"
      spelling
  | Unconstrained_subject name ->
    Printf.sprintf "no fact the checker derived constrains `%s`" name
  | Opaque_application name ->
    Printf.sprintf
      "the checker has no meaning for `%s`, so it cannot reason through it" name
  | Partial_conjunct { held; missing } ->
    Printf.sprintf "%s established here; %s not"
      (String.concat " and " (List.map (Printf.sprintf "`%s`") held))
      (String.concat " and " (List.map (Printf.sprintf "`%s`") missing))

(* Deliberately still a 3-tuple: (proved, violated, skips-by-reason).  Every
   existing caller destructures it that way, and [Trusted] does not belong in
   any of those three buckets — it is neither a proof nor a skip nor a
   violation.  Its own count is queried directly off [all ()] (see
   bin/main.ml's [print_refine_report], which keeps its own tally).

   The skip bucket is keyed on [reason_name] (a payload-free string), NOT the
   raw [reason]: [Alias_withdrawn] and [Unconstrained_subject] both carry a
   NAME in their payload, so keying on the variant itself splits one cause
   into one bucket per distinct name — exactly the bug this comment used to
   predict and dismiss as cosmetic for [Alias_withdrawn] alone.  It is not
   cosmetic for [Unconstrained_subject], the far more common cause, where it
   defeated a later task's per-bucket distribution count.  [print_refine_
   report] in bin/main.ml keeps its own separate tally and must key the same
   way, or the two can disagree. *)
let summary () =
  let proved = ref 0 and violated = ref 0 in
  let skips : (string, int) Hashtbl.t = Hashtbl.create 8 in
  List.iter
    (fun o ->
      match o.verdict with
      | Proved -> incr proved
      | Violated -> incr violated
      | Trusted -> ()
      | Skipped r ->
        let name = reason_name r in
        Hashtbl.replace skips name (1 + Option.value ~default:0 (Hashtbl.find_opt skips name)))
    !log;
  (!proved, !violated, Hashtbl.fold (fun name n acc -> (name, n) :: acc) skips [])
