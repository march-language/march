(** Refinement checking, §14–§15: verdict state and precondition checking.

    Moved VERBATIM out of [Refine_check] (R4 of
    [specs/plans/2026-08-28-refine-check-decomposition.md]):

      §14 Verdict state and withdrawal diagnostics
      §15 check_call — precondition checking at a call site

    [check_call] is 1,361 lines and was the single largest definition in the
    compiler.  It is the heart of the pass: for each refined parameter of a
    callee, reflect the actual argument, assemble the facts in scope, and ask
    the solver whether they entail the parameter's predicate.

    Five of the pass's mutable cells live here — [strict_verified],
    [unverified_hinted], [trusted_fn], [enclosing_fn] and
    [enclosing_fn_probe] — and all five are written from §21 (the
    declaration walk), which is still in [Refine_check].  They therefore
    reach that writer through [include], as the same ref cells.
    Re-declaring any of them would leave the writer setting a ref nobody
    reads, and since they only ever RELAX or TIGHTEN reporting, an accepting
    corpus would not notice: [strict_verified] turns a skipped obligation
    into an error, and [trusted_fn] suppresses one. [enclosing_fn_probe] is
    the exception — it is test-only instrumentation with no effect on
    reporting; see its own comment.

    Verify changes here against the REJECT corpus
    (`dune build @types-check --force`), not only [scripts/refine-oracle.sh]. *)

include Refine_resolve

(* =================================================================
   §14 Verdict state and withdrawal diagnostics
   ================================================================= *)

(* ── `cap verified`: a skipped obligation becomes an error ───────────────── *)
(* March's default stance is DEFINITE FAILURE ONLY — an obligation the checker
   cannot discharge is silence, because a false positive on correct code is the
   cardinal sin here.  A module that writes `cap verified` opts INTO the
   inverse: inside it, "the checker could not verify this" is an error rather
   than silence, so the module's contracts are a guarantee instead of a
   best effort.

   Strictly OPT-IN.  This flag is false unless the decl list currently being
   walked itself contains `cap verified`, and it is saved/restored around every
   nested module by [visit_decls] — so it is scoped exactly like
   [Division_safety]'s `cap no_panic`.  Two consequences worth stating:

     - a `cap verified` module that CALLS an ordinary module does not make the
       callee's module strict; only obligations RAISED at call sites lexically
       inside the strict decl list escalate; and
     - inheritance into nested modules is deliberately NOT done.  bin/main.ml
       prepends the entire standard library as sibling `DMod` decls of the
       entry module's own decls, so an inherited flag would turn every stdlib
       module strict the moment one user module asked for verification. *)
let strict_verified = ref false

(* Whether this decl list has already been told that some contract in it went
   unverified. Scoped and restored exactly like [strict_verified].

   The default stance is "definite failure only" — an undecidable obligation
   stays silent rather than risk a false positive on correct code. That is the
   right default, but silence is indistinguishable from "checked and fine": a
   reader who never learns the checker gave up believes a contract is enforced
   when it is not, and `cap verified` (the opt-in that turns exactly this
   silence into an error) is only discoverable if you already know to look for
   it. One hint per decl list names the first such contract and points at the
   escalation — enough to be findable, not so much that a module with many
   undecidable predicates becomes a wall of text. *)
let unverified_hinted = ref false

(* Scoped exactly like [strict_verified], but to a single `fn` rather than a
   decl list: true while [visit_fn] is walking a function whose [fn_attrs]
   carry `@[trusted]`.  Consulted only by [check_call]'s [note] — see there for
   why [check_post] does not (yet) need to. *)
let trusted_fn = ref false

(* The function whose body is being walked, set and restored by [visit_fn]
   exactly as [trusted_fn] is.  A ref rather than a [call_ctx] field because
   it is not a fact channel: it never shadows, never retires on rebinding, and
   adding it to the record would touch all three construction sites in
   refine_check.ml for a value none of them varies. *)
let enclosing_fn : A.fn_def option ref = ref None

(* Test-only observation hook: when set, [visit_fn] invokes it with [fd]
   immediately after setting [enclosing_fn], so a test can sample the ref
   DURING the walk rather than only after it — the walk's own [None]
   default is otherwise indistinguishable from a ref that was never
   populated at all. Production cost is one [match] against [None]. Never
   set outside a test. *)
let enclosing_fn_probe : (A.fn_def -> unit) option ref = ref None

(* Does [e] ever APPLY the function spelled [name]?  Applications only: a bare
   mention (`let f = List.length`) is not a guard, and counting it would let an
   unrelated line decide what a call site is told. *)
let expr_applies (name : string) (e : A.expr) : bool =
  let found = ref false in
  iter_all
    (fun e ->
      match e with
      | A.EApp (A.EVar n, _, _) when n.A.txt = name -> found := true
      | _ -> ())
    e;
  !found

(* Does [e] apply [name] TO THE VARIABLE [subject], counting only a FREE
   occurrence of [subject] — one not captured by an intervening binder of the
   same name?  Stricter than [expr_applies] on purpose — see condition 3 of
   [alias_withdrawal_cause]: a guard on some OTHER list says nothing about
   this call's argument, so `List.length(zs) > 0` guarding `head(ys)` must
   not be read as a guard on `ys`.  Compared by NAME rather than
   structurally, because the same variable read at two source positions
   carries two different spans and would never compare equal.

   The FREE restriction exists because [guard_applies] below uses this in an
   ACCEPTING position: "this guard applies the withdrawn spelling to the
   subject" is evidence FOR an attribution, so a shadow-blind, discard-only
   walk (the shape [expr_mentions] above uses, built on [iter_all]) would be
   a wrong attribution here, not merely a vague one.  `if check(fn ys ->
   List.length(ys) > 0, zs) do head(ys) …` must not read as "the guard
   applies List.length to ys": the guard's `ys` is the lambda's own
   parameter, and the guard says nothing about the outer `ys` that `head`'s
   argument names.  Mirror image of the laundered-path bug fixed 2026-07-31
   (probe PE, see [expr_mentions_free] above) — same fix, one level of AST
   deeper because the thing that must stay free is the ARGUMENT reference,
   not the applied function's own name.  Modeled on [expr_mentions_free]'s
   traversal shape (sequential [EBlock] scoping, lambda/[let fn] parameter
   capture, match-arm binder capture) rather than sharing code with it: the
   two walk for different things (a free mention of a name vs. a free
   argument to an application) and a shared abstraction would be a worse
   trade than the duplication. *)
let rec expr_applies_to_free (name : string) (subject : string) (e : A.expr) : bool =
  let free = expr_applies_to_free name subject in
  let any = List.exists free in
  let binds ps = List.mem subject ps in
  let pbinds ps = List.exists (fun (p : A.param) -> p.A.param_name.A.txt = subject) ps in
  match e with
  | A.EVar _ -> false
  | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
  | A.EApp (f, args, _) ->
    (match f with
     | A.EVar n
       when n.A.txt = name
            && List.exists (function A.EVar v -> v.A.txt = subject | _ -> false) args ->
       true
     | _ -> false)
    || free f || any args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
  | A.ELam (ps, body, _) -> if pbinds ps then false else free body
  | A.EBlock (es, _) ->
    (* Sequential: a `let` (or `let fn`) rebinding [subject] shadows the REST
       of the block, but its own RHS still sees the outer [subject]. *)
    let rec go = function
      | [] -> false
      | e :: rest ->
        free e
        ||
        (match e with
         | A.ELet (b, _) when binds (pat_binders b.A.bind_pat) -> false
         | A.ELetFn (n, _, _, _, _) when n.A.txt = subject -> false
         | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) when binds (pat_binders p) -> false
         | _ -> go rest)
    in
    go es
  | A.ELet (b, _) -> free b.A.bind_expr
  | A.ELetFn (n, ps, _, body, _) ->
    if n.A.txt = subject || pbinds ps then false else free body
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
    free e1 || (if binds (pat_binders p) then false else free e2)
  | A.EMatch (subj, brs, _) ->
    free subj
    || List.exists
         (fun (br : A.branch) ->
           if binds (pat_binders br.A.branch_pat) then false
           else
             (match br.A.branch_guard with Some g -> free g | None -> false)
             || free br.A.branch_body)
         brs
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> free v) fs
  | A.ERecordUpdate (r, fs, _) -> free r || List.exists (fun (_, v) -> free v) fs
  | A.EField (r, _, _) -> free r
  | A.EIf (c, t, el, _) -> any [ c; t; el ]
  | A.ECond (arms, _) -> List.exists (fun (c, b) -> free c || free b) arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> free a || free b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> free e

(* ── Attributing a skip to a withdrawn alias ───────────────────────────────
   A withdrawn alias is only ONE of the reasons an obligation can go
   undischarged, and a wrong attribution is worse than a vague one: it sends
   the author to rename a binding that had nothing to do with their problem,
   and it hides the real cause.  So this is deliberately conjunctive — all
   four conditions, or we keep the honest general message:

   1. the reason is [Solver_undecided] or its syntactic refinement
      [Unconstrained_subject] (see [Undecided.diagnose]).  A withdrawal
      cannot cause any other skip: it removes an ASSUMPTION, so the VC is
      still built, still well-sorted, and still reaches the solver — it just
      arrives without the fact that would have discharged it, which is
      exactly what [Unconstrained_subject] also names from the syntax alone.
      An unreflectable predicate or a sort conflict failed strictly earlier,
      for reasons the alias cannot touch — and neither does
      [Opaque_application], which describes the GOAL's own shape, not the
      assumption set a withdrawal thins.  Where both could describe the same
      skip, the withdrawal wins: it names a decision made elsewhere in the
      unit, which is more actionable than "nothing constrains it".
   2. the predicate actually mentions the measure the alias routes to.  A
      withdrawn `len` alias is irrelevant to `{Int | _ != 0}`.
   3. a POSITIVE path condition applies the withdrawn spelling TO THIS
      OBLIGATION'S OWN SUBJECT.  Each half of that is load-bearing, and the
      first version of this test had neither:

        - "to this subject", because `if List.length(zs) > 0 do head(ys) …`
          is not a guard on `ys`.  Delete the competing binding and that
          program is STILL undischarged — which is the proof that the
          withdrawal was not the cause.  Blaming it sends the author to rename
          something irrelevant, while the general message's "guard the call"
          is the correct advice.
        - "positive", because in `if List.length(ys) > 0 do 0 else head(ys) end`
          the guard does not fail to prove the predicate — it DISPROVES it.
          With the binding removed that program reports a real refinement
          violation, so "the guard proved nothing" would dress a genuine bug in
          the user's code up as a story about a nested module.  We cannot
          report the violation ourselves (the alias is withdrawn, so nothing
          reflects either way), but we can decline to misdescribe it.

      Without this conjunct the attribution would also fire on every unguarded
      call in a module that merely CONTAINS a competing definition — the
      relabel-everything failure this fix must not become.
   4. the withdrawn spelling measures the same KIND of thing as the subject:
      `List.length` for a list subject, `String.byte_size` /
      `string_byte_length` for a String one.  All three route to the single
      name `len`, so condition 2 cannot separate them on its own, and a
      withdrawn `List.length` was being blamed for an undischarged
      `{String | len(_) > 0}` — naming a list definition that could not
      possibly have mattered.

   Condition 3 accepts the guard in two spellings, and only two.  DIRECT: the
   condition itself applies the withdrawn spelling to the subject.  LAUNDERED
   through exactly one `let`: the condition mentions a name that [lets] maps
   to an application, and THAT application applies the withdrawn spelling to
   the subject — `let n = List.length(ys)` then `if n > 0` is the same author
   intent, stopped by the same withdrawal, so it earns the same sentence.
   The laundered check runs [expr_applies_to_free] against the recorded RHS with
   the obligation's own subject, never against the let-bound name: `let n =
   List.length(zs)` guarding a call about `ys` fails it exactly as the direct
   `if List.length(zs) > 0` does.  [lets] is shadow-disciplined by [visit]
   (see [launder]), so a rebinding of either the laundering name or the
   collection between the `let` and the guard has already retired the entry
   before this function ever sees it.

   Note the asymmetry with the gates themselves: THEY resolve doubt by
   suppressing (silence is safe).  This resolves doubt by staying general,
   because the thing being chosen here is a sentence, and an over-confident
   sentence is a lie.  The cost is coverage: a guard laundered through a CHAIN
   of locals (`let a = List.length(ys)` then `let n = a`), applied to a
   non-variable actual, or established in a caller, falls back to the general
   message.  That is the right trade — this reason exists to explain one
   specific confusion, not to claim every skip. *)
(* ── Condition 5: the guard, read as a fact, must ENTAIL the predicate ─────
   Condition 3 (below, [guard_applies]) only asks whether the guard applies
   the withdrawn spelling to this obligation's own subject — not whether it
   would have PROVED the goal.  `List.length(ys) >= 0` applies the spelling
   to `ys` exactly as `List.length(ys) > 0` does, but it is a tautology over
   a non-negative measure: it entails nothing about the goal `len(ys) > 0`,
   so that call is skipped with or without the withdrawal.  Blaming the
   withdrawal there sends the author to fix an import that was never the
   cause — the harm this conjunct exists to prevent.

   The check is a small syntactic interval-entailment over `==`/`!=`/`<`/
   `<=`/`>`/`>=` against an integer literal, modeled on
   [Division_safety.path_proves_nonzero]'s `dual`/`flip`/`proves` shape
   (extended there to boolean connectives): normalise both sides to `X op n`
   with `X` the measure application (or, laundered, the name it was bound
   to), read each as a half-open/closed interval of integers, and ask
   whether the guard's interval is a SUBSET of the predicate's.  `!=` is not
   convex — no single interval represents "everything but n" — so it never
   entails anything here; that is a missed proof, not a wrong one.

   Where the shapes do not match this pattern at all (anything but a single
   comparison against a literal on one side), entailment is UNDECIDED, and
   per the fail-closed stance of this whole function, undecided means "do
   not blame the withdrawal" — a generic `solver-undecided` message is a
   smaller error than sending the author to fix an unrelated import. *)
let alias_withdrawal_cause ~(pred : A.expr) ~(subject : A.expr option)
    ~(subject_is_str : bool) ~(path : (A.expr * bool) list) ~(lets : launder)
    (r : Obligation.reason) : withdrawal option =
  match (r, subject) with
  | (Obligation.Solver_undecided | Obligation.Unconstrained_subject _), Some (A.EVar sn) ->
    let guard_applies (w : withdrawal) (cond : A.expr) : bool =
      (* FREE occurrence only, on both the direct condition and the laundered
         RHS: this is an ACCEPTING position, so a shadow-blind, discard-only
         walk would be the wrong tool on either path — a lambda parameter in
         the guard that merely collides with the subject's own name must not
         read as evidence (review 2026-07-31, probe PE, and its mirror image
         on the direct path). *)
      expr_applies_to_free w.wd_spelling sn.A.txt cond
      || List.exists
           (fun (m, rhs) ->
             expr_mentions_free m cond && expr_applies_to_free w.wd_spelling sn.A.txt rhs)
           lets
    in
    (* `a op b` <=> `b (flipped op) a` — used to normalise to `X op n`.  (No
       `dual`/negation step is needed here, unlike
       [Division_safety.path_proves_nonzero]: the caller below already
       filters to a POSITIVE path entry before [guard_discharges] runs — see
       condition 3's own "NEGATED guard" tests — so [cond] is always a fact
       read at face value, never one that needs de-negating first.) *)
    let flip = function
      | "<" -> ">" | ">" -> "<" | "<=" -> ">=" | ">=" -> "<="
      | op -> op (* == and != are symmetric *)
    in
    (* `X op n`, read as a closed-or-half-open integer interval.  [None] for
       either bound means unbounded on that side; [None] for the whole thing
       means "not a convex interval" (only `!=`). *)
    let interval_of op n : (int option * int option) option =
      match op with
      | ">"  -> Some (Some (n + 1), None)
      | ">=" -> Some (Some n, None)
      | "<"  -> Some (None, Some (n - 1))
      | "<=" -> Some (None, Some n)
      | "==" -> Some (Some n, Some n)
      | _ -> None
    in
    let interval_subset (lo1, hi1) (lo2, hi2) =
      let lo_ok =
        match lo2 with
        | None -> true
        | Some l2 -> (match lo1 with Some l1 -> l1 >= l2 | None -> false)
      in
      let hi_ok =
        match hi2 with
        | None -> true
        | Some h2 -> (match hi1 with Some h1 -> h1 <= h2 | None -> false)
      in
      lo_ok && hi_ok
    in
    (* Is [e] the predicate's own measure application (`len(_)`, `len(xs)`,
       …)?  Any application of the withdrawn measure name suffices — a
       parameter predicate has exactly one subject to measure. *)
    let is_measured_pred (w : withdrawal) (e : A.expr) : bool =
      match e with A.EApp (A.EVar n, _, _) -> n.A.txt = w.wd_measure | _ -> false
    in
    (* Read [pred] itself as `measure(subject) op n`.  Computed once per
       withdrawal candidate — [pred] does not vary with [cond]. *)
    let atomic_cmp (is_subject : A.expr -> bool) (e : A.expr) : (string * int) option =
      match e with
      | A.EApp (A.EVar op0, [ a; b ], _)
        when List.mem op0.A.txt [ "=="; "!="; "<"; "<="; ">"; ">=" ] -> (
        match b with
        | A.ELit (A.LitInt n, _) when is_subject a -> Some (op0.A.txt, n)
        | _ -> (
          match a with
          | A.ELit (A.LitInt n, _) when is_subject b -> Some (flip op0.A.txt, n)
          | _ -> None))
      | _ -> None
    in
    (* Does some subterm of [e] compare the withdrawn measure applied to the
       FREE subject against a literal, in a way that ENTAILS `(op2, n2)`
       (already known to be [pred]'s own comparison)?  Mirrors
       [expr_applies_to_free]'s shadow-respecting descent — same cases, same
       shadowing rules for the SUBJECT name (`sn`) — because this is asking
       the same question ("does the withdrawn spelling apply to the free
       subject somewhere in here") plus one more thing: not just THAT it
       applies, but WHAT the surrounding comparison says.  A guard buried
       inside an opaque call (`check(fn q -> List.length(ys) > 0, zs)`) still
       has a genuine, entailing comparison at that free position — nesting
       inside a call this pass cannot otherwise reason about must not by
       itself defeat entailment, or a case [guard_applies] already accepted
       ("a FREE occurrence … still attributes") would regress.  A lambda
       parameter that collides with the SUBJECT's name still closes off
       descent into that lambda's body, exactly as [expr_applies_to_free]
       already does — that is the discipline probe PE pinned, and this walk
       must not reopen it.

       [is_subject] reads a SECOND name channel besides the subject —
       [lets], the laundering table — and that channel needs its own
       shadow discipline: `let n = List.length(ys); if n >= 0 && any_pos(zs,
       fn n -> n > 0) do head(ys) …` must not read the LAMBDA's own `n` as
       the laundered length just because the string "n" is a laundering key
       somewhere in scope.  [shadowed] carries every name any binder passed
       on the way down has rebound (lambda/`let`/`let fn`/`let?`/match-arm),
       independent of whether that name happens to be the subject; a
       laundering lookup that hits a shadowed name is retired exactly as a
       path fact would be (see [path_shadow]) rather than trusted. *)
    let rec exists_discharging (w : withdrawal) (op2, n2) ~(shadowed : string list)
        (e : A.expr) : bool =
      let recur ?(bind = []) e = exists_discharging w (op2, n2) ~shadowed:(bind @ shadowed) e in
      let any ?(bind = []) es = List.exists (recur ~bind) es in
      let binds ps = List.mem sn.A.txt ps in
      let pbinds ps = List.exists (fun (p : A.param) -> p.A.param_name.A.txt = sn.A.txt) ps in
      let param_names ps = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
      let is_subject e =
        match e with
        | A.EApp (A.EVar n, args, _) ->
          n.A.txt = w.wd_spelling
          && List.exists (function A.EVar v -> v.A.txt = sn.A.txt | _ -> false) args
        | A.EVar { A.txt = m; _ } when not (List.mem m shadowed) -> (
          match List.assoc_opt m lets with
          | Some (A.EApp (A.EVar n, args, _)) ->
            n.A.txt = w.wd_spelling
            && List.exists (function A.EVar v -> v.A.txt = sn.A.txt | _ -> false) args
          | _ -> false)
        | _ -> false
      in
      let cmp_here =
        match atomic_cmp is_subject e with
        | Some (op1, n1) -> (
          match (interval_of op1 n1, interval_of op2 n2) with
          | Some i1, Some i2 -> interval_subset i1 i2
          | _ -> false)
        | None -> false
      in
      cmp_here
      ||
      match e with
      | A.EVar _ -> false
      | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
      | A.EApp (f, args, _) -> recur f || any args
      | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
      | A.ELam (ps, body, _) -> if pbinds ps then false else recur ~bind:(param_names ps) body
      | A.EBlock (es, _) ->
        (* Sequential, like [expr_applies_to_free]'s own [EBlock] case: a
           `let` (or `let fn`/`let?`) rebinding the SUBJECT shadows the rest
           of the block exactly as there (the [binds]/[sn.A.txt] checks
           below, unchanged); a `let` rebinding a LAUNDERING key instead
           retires that key from [is_subject]'s lookup for the rest of the
           block, via [shadowed], without discarding the whole branch — the
           subject itself may still be free elsewhere. *)
        let rec go (shadowed : string list) = function
          | [] -> false
          | e :: rest ->
            exists_discharging w (op2, n2) ~shadowed e
            ||
            (match e with
             | A.ELet (b, _) when binds (pat_binders b.A.bind_pat) -> false
             | A.ELetFn (n, _, _, _, _) when n.A.txt = sn.A.txt -> false
             | (A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _)) when binds (pat_binders p) -> false
             | A.ELet (b, _) -> go (pat_binders b.A.bind_pat @ shadowed) rest
             | A.ELetFn (n, _, _, _, _) -> go (n.A.txt :: shadowed) rest
             | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) -> go (pat_binders p @ shadowed) rest
             | _ -> go shadowed rest)
        in
        go shadowed es
      | A.ELet (b, _) -> recur b.A.bind_expr
      | A.ELetFn (n, ps, _, body, _) ->
        if n.A.txt = sn.A.txt || pbinds ps then false
        else recur ~bind:(n.A.txt :: param_names ps) body
      | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
        recur e1 || (if binds (pat_binders p) then false else recur ~bind:(pat_binders p) e2)
      | A.EMatch (subj, brs, _) ->
        recur subj
        || List.exists
             (fun (br : A.branch) ->
               let bs = pat_binders br.A.branch_pat in
               if binds bs then false
               else
                 (match br.A.branch_guard with Some g -> recur ~bind:bs g | None -> false)
                 || recur ~bind:bs br.A.branch_body)
             brs
      | A.ERecord (fs, _) -> List.exists (fun (_, v) -> recur v) fs
      | A.ERecordUpdate (r, fs, _) -> recur r || List.exists (fun (_, v) -> recur v) fs
      | A.EField (r, _, _) -> recur r
      | A.EIf (c, t, el, _) -> any [ c; t; el ]
      | A.ECond (arms, _) -> List.exists (fun (c, b) -> recur c || recur b) arms
      | A.EPipe (a, b, _) | A.ESend (a, b, _) -> recur a || recur b
      | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
      | A.EDbg (Some e, _) -> recur e
    in
    (* Does the guard fact [cond] — already known to apply [w]'s spelling to
       this subject, and already filtered to a POSITIVE path entry by the
       caller below — actually ENTAIL [pred]?  The laundered spelling (`if n
       > 0 …` after `let n = List.length(ys)`) is handled by substituting the
       laundering name's bound expression in wherever [cond] free-mentions
       it, one hop only — mirroring [guard_applies]'s own laundered arm. *)
    let guard_discharges (w : withdrawal) (cond : A.expr) : bool =
      match atomic_cmp (is_measured_pred w) pred with
      | None -> false
      | Some (op2, n2) ->
        exists_discharging w (op2, n2) ~shadowed:[] cond
        || List.exists
             (fun (m, rhs) ->
               expr_mentions_free m cond && exists_discharging w (op2, n2) ~shadowed:[] rhs)
             lets
    in
    List.find_opt
      (fun w ->
        w.wd_str = subject_is_str
        && expr_applies w.wd_measure pred
        && List.exists
             (fun (cond, negated) ->
               (not negated) && guard_applies w cond && guard_discharges w cond)
             path)
      !withdrawals
  (* A non-variable actual (`head(f(xs))`) carries no name a guard could be
     matched against, so we cannot show the guard was about THIS value. *)
  | _ -> None

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
(* What the refined value being checked IS, for diagnostics only.  `Argument` is
   a real call's actual; `Bound_expr` is the right-hand side of an annotated
   `let`, which reaches this function through a SYNTHESIZED one-parameter
   [fn_sig] (see [check_let_annotation]).  The obligation itself is identical —
   "does this expression satisfy this predicate" — but "argument does not
   satisfy precondition" reads as nonsense at a `let`, where the author called
   nothing, so the two user-facing messages branch on this. *)
type check_subject =
  | Argument
  | Bound_expr

(* Span of an expression, for pointing a diagnostic at ONE argument instead of
   the whole call. [refinecheck] does not depend on [march_typecheck], so this
   mirrors its [span_of_expr] rather than importing it; only the forms that can
   appear in argument position need to be precise, and anything unlisted falls
   back to the caller-supplied call span (never a dummy, which would render as
   a phantom location at line 0). *)
let arg_span (fallback : A.span) : A.expr -> A.span = function
  | A.ELit (_, sp) | A.EApp (_, _, sp) | A.ECon (_, _, sp)
  | A.ETuple (_, sp) | A.ERecord (_, sp) | A.EField (_, _, sp)
  | A.EIf (_, _, _, sp) | A.EPipe (_, _, sp) | A.EAnnot (_, _, sp)
  | A.EBlock (_, sp) | A.EMatch (_, _, sp) | A.ELam (_, _, sp)
  | A.EAtom (_, _, sp) -> sp
  | A.EVar name -> name.A.span
  | _ -> fallback

(* =================================================================
   §15 check_call — precondition checking at a call site
   ================================================================= *)

(* The environment [check_call] discharges an obligation IN, as opposed to the
   obligation itself.  Every field is threaded unchanged through the whole of
   [visit]'s walk of one call node, so bundling them stops a twelve-parameter
   signature from having to be re-read at each of the three call sites — and
   gives each thread a place to say what it is, which is the documentation
   this function has never had.

   The four things that differ per obligation stay explicit parameters:
   [~span] / [~callee] (which call), [sg] / [args] (its signature and actuals)
   and [rp] (which refined parameter of it), plus [?subject] / [?verdict_out],
   which only the `let`-annotation caller sets. *)
type call_ctx = {
  root : string;
      (* Project root — passed to [Refine.discharge] so the SMT bridge can
         place its scratch files and resolve solver configuration. *)
  errctx : Err.ctx;
      (* Diagnostic sink.  [check_call] is a REPORTING site: every exit path
         records an outcome through [note], and violations are emitted here. *)
  postcond :
    string -> A.expr list -> (string * A.expr * string option) option;
      (* Return refinement of a callee, by name and actuals — how a nested
         call's postcondition becomes a premise for this one.  Always
         [postcond_of ctx defs] at every call site; it is a parameter rather
         than a direct call because [rctx]/[defs] are not in scope here. *)
  path : (A.expr * bool) list;
      (* Path facts: the guards (and their polarity) reaching this call site.
         One of the two fact channels — see the shadowing discipline note in
         §10: a name rebound in between must retire from BOTH this and
         [sc], or a stale fact proves a goal about a different value. *)
  lets : launder;
      (* Laundering `let`s: bindings whose RHS lets a guard about one name be
         re-attributed to another.  Retires on rebinding of either the key or
         any name its RHS mentions. *)
  sc : scope;
      (* The other fact channel: refined locals and parameters in scope, name
         -> (binder, predicate, sort). *)
  re : recenv;
      (* Record-typed variables in scope, name -> SMT sort name, so a
         predicate's `v.field` projections can be resolved through that
         sort's selectors. *)
}

let check_call (cx : call_ctx) ~span ~(callee : string) ?(subject = Argument)
    ?(verdict_out : Obligation.verdict option ref option)
    (sg : fn_sig) (args : A.expr list) (rp : rparam) : unit =
  (* Destructured to the names the body has always used: this is a signature
     change, not a rewrite of 1,361 lines. *)
  let { root; errctx; postcond; path; lets; sc; re } = cx in
  let subject_noun = match subject with Argument -> "argument" | Bound_expr -> "bound expression" in
  let obligation_noun =
    match subject with Argument -> "precondition" | Bound_expr -> "type annotation"
  in
  let name_pos = List.mapi (fun i n -> (n, i)) sg.param_names in
  (* A CALLER-scope name whose declared type is a record (see [recenv]).  Such a
     name is declared into the record's datatype sort by [path_resolve_field];
     every other producer must therefore refuse to declare it `Int`, or the VC
     declares one symbol at two sorts and z3 answers with an `(error …)` that
     desynchronises the shared `z3 -in` channel — silently disabling refinement
     checking for the rest of the compilation. *)
  let is_recvar name = List.mem_assoc name re in
  let actual_of_name name =
    match List.assoc_opt name name_pos with
    | Some i -> List.nth_opt args i
    | None -> None
  in
  (* Is the callee parameter called [name] declared String? *)
  let str_pos = List.mapi (fun i b -> (i, b)) sg.param_str in
  let name_is_str name =
    match List.assoc_opt name name_pos with
    | Some i -> (match List.assoc_opt i str_pos with Some b -> b | None -> false)
    | None -> false
  in
  (* The SCALAR sort a callee parameter (and hence the actual passed to it)
     lives at.  `Int` unless the callee declared it `Bool`. *)
  let scalar_at_idx i =
    match List.nth_opt sg.param_scalar i with Some s -> s | None -> Smt.SInt
  in
  let scalar_of_name name =
    match List.assoc_opt name name_pos with Some i -> scalar_at_idx i | None -> Smt.SInt
  in
  (* The refined value's own scalar sort, read from its refinement's base type.
     [rp.sort] and [sg.param_scalar] are computed from the same declared type,
     so they agree; this spelling also covers a synthesized callback sig. *)
  let self_scalar = scalar_sort_or_int rp.sort in
  (* Every exit below records an outcome.  All but one of them are silent to the
     USER by design (the definite-failure stance: only a predicate that can
     never hold is reported); silent to the LEDGER is what this fixes, so a
     contract that checks nothing is distinguishable from one that passes.
     Recording is observation-only — it must never alter control flow. *)
  let note verdict =
    (* Re-attribute BEFORE recording, not just in the error text: the ledger is
       what `--refine-report` prints, and a ledger that disagrees with the
       diagnostic is a second thing to be confused by. *)
    let verdict, cause =
      match verdict with
      | Obligation.Skipped r ->
        (* The obligation's own SUBJECT — the actual passed at [rp.idx].  Read
           here rather than taken from the enclosing [self_actual] because
           [note] is in scope before that binding, and because a missing
           argument must simply mean "no attribution". *)
        (match
           alias_withdrawal_cause ~pred:rp.pred
             ~subject:(List.nth_opt args rp.idx)
             ~subject_is_str:(rp_is_str rp) ~path ~lets r
         with
         | Some w -> (Obligation.Skipped (Obligation.Alias_withdrawn w.wd_spelling), w.wd_span)
         | None -> (verdict, None))
      | _ -> (verdict, None)
    in
    (* `@[trusted]` accepts a SKIP as an assertion, recorded as its own verdict
       rather than escalated — see [trusted_fn].  This must run before the
       verdict is recorded (not just before the escalation match below), or
       the ledger would say `Skipped` while the diagnostic behaved as if it
       were `Trusted`.  A [Violated] is deliberately untouched: it never
       reaches this branch because it is not a [Skipped _] to begin with — a
       predicate the solver proved can never hold is a bug in the annotation,
       not an incompleteness `@[trusted]` may wave through. *)
    let verdict =
      match verdict with
      | Obligation.Skipped _ when !trusted_fn -> Obligation.Trusted
      | _ -> verdict
    in
    Obligation.record
      { Obligation.span; callee; predicate = pred_str rp.pred; verdict
      ; kind = Obligation.Precondition };
    Option.iter (fun r -> r := Some verdict) verdict_out;
    (* …except inside a `cap verified` module, where a skip is the very thing
       the user asked to be told about (see [strict_verified]).  `Proved` and
       `Violated` are unaffected: the latter already reported itself.  A
       [Skipped] that was just turned into [Trusted] above no longer matches
       here, which is how `@[trusted]` suppresses the escalation. *)
    match verdict with
    | Obligation.Skipped r when !strict_verified ->
      (* The remedy depends on the reason.  The generic advice below is worse
         than useless for a withdrawn alias — "guard the call" is what the
         author already did — so that case gets its own note, naming the
         binding to rename and, when we found it, where it is. *)
      let remedy =
        match r with
        | Obligation.Alias_withdrawn spelling ->
          let where =
            match cause with
            | Some (sp : A.span) when sp.A.file <> "" ->
              Printf.sprintf " (%s:%d)" sp.A.file sp.A.start_line
            | Some (sp : A.span) -> Printf.sprintf " (line %d)" sp.A.start_line
            | None -> ""
          in
          Printf.sprintf
            "note: at least one binding of `%s` in this compilation unit%s \
             withdrew the alias for the WHOLE unit, including this call — the \
             gate is unit-global and syntactic, so it does not matter whether \
             that binding could ever win here.  There may be others: renaming \
             or moving every one of them out of this unit restores the alias, \
             and restating the fact as a refinement avoids the guard entirely"
            spelling where
        | _ ->
          (match subject with
           | Argument ->
             "note: guard the call or strengthen what is known here, rewrite \
              the predicate into the fragment the checker supports, or remove \
              `cap verified` from this module — it asks for every obligation \
              to be discharged"
           | Bound_expr ->
             "note: bind an expression the checker can see satisfies this \
              annotation, weaken the annotation, or remove `cap verified` from \
              this module — it asks for every obligation to be discharged")
      in
      Err.error errctx ~span
        (Printf.sprintf
           "`cap verified` module: cannot verify %s `%s` on `%s` (%s: %s)\n%s"
           obligation_noun (pred_str rp.pred) callee (Obligation.reason_name r)
           (Obligation.reason_detail r) remedy)
    (* Outside `cap verified`, a skip stays non-fatal. A DIAGNOSED cause is
       specific and actionable, so it reports at every call site; the residual
       reasons keep the once-per-module throttle, whose rationale — "advice
       repeated per call site would be worse than silence" — is about a
       message that says the same thing everywhere. "Nothing in scope
       constrains `n`" and "`_ >= 0` held here, `_ < len(xs)` did not" are
       different facts about different calls, so suppressing the second
       because the first already printed is a bug, not the throttle working.
       A withdrawn alias is excluded from both halves: it has its own
       dedicated explanation and is not the checker running out of road. *)
    | Obligation.Skipped r
      when (not !strict_verified)
           && (match r with
               | Obligation.Alias_withdrawn _ -> false
               | Obligation.Unconstrained_subject _
               | Obligation.Opaque_application _
               | Obligation.Partial_conjunct _ -> true
               | Obligation.Solver_undecided
               | Obligation.Unreflectable_predicate
               | Obligation.Unreflectable_subject
               | Obligation.Sort_conflict
               | Obligation.Float_sort_gate -> not !unverified_hinted) ->
      (match r with
       | Obligation.Solver_undecided
       | Obligation.Unreflectable_predicate
       | Obligation.Unreflectable_subject
       | Obligation.Sort_conflict
       | Obligation.Float_sort_gate -> unverified_hinted := true
       | Obligation.Unconstrained_subject _
       | Obligation.Opaque_application _
       | Obligation.Partial_conjunct _
       | Obligation.Alias_withdrawn _ -> ());
      let body =
        match r with
        | Obligation.Unconstrained_subject _
        | Obligation.Opaque_application _
        | Obligation.Partial_conjunct _ ->
          Printf.sprintf "%s `%s` on `%s` was NOT verified here.\n%s"
            obligation_noun (pred_str rp.pred) callee (Obligation.reason_detail r)
        | Obligation.Solver_undecided
        | Obligation.Unreflectable_predicate
        | Obligation.Unreflectable_subject
        | Obligation.Sort_conflict
        | Obligation.Float_sort_gate
        | Obligation.Alias_withdrawn _ ->
          (* Hard-wrapped near 78 columns. The renderer does not reflow, so a
             single long line is left to the terminal to break wherever it
             happens to run out of width — mid-token, and differently in every
             window. *)
          Printf.sprintf
            "%s `%s` on `%s` was NOT verified here.\n\
             reason: %s — %s\n\
             note: March reports only definite failures, so a contract it \
             cannot decide\n\
             is accepted in silence. Add `cap verified` to this module to make \
             every\n\
             unverifiable obligation an error instead; `--refine-report` lists \
             them all."
            obligation_noun (pred_str rp.pred) callee
            (Obligation.reason_name r) (Obligation.reason_detail r)
      in
      Err.hint errctx ~span body
    | _ -> ()
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    (* Assumptions the ENCODER emits about its own representation — a
       well-formedness axiom true of every value at a sort, not a fact
       derived from anything the user wrote (a path guard, a declared
       refinement, a callee's proven postcondition).  `len$x >= 0` is the
       running example: [measure_of_var] asserts it unconditionally as a
       side effect of reflecting `len(_)` even when there is NO guard at
       all, so `vc.assumptions` always mentions the subject's measure
       symbol — which made [Undecided.diagnose]'s "nothing constrains it"
       check trivially, permanently false for every `len`-measured subject.
       [user_assume] mirrors [assume] but omits exactly these: every
       `assume := … :: !assume` site in this function pushes to BOTH unless
       it is one of the three well-formedness sites marked [push_structural]
       below (the measure-application non-negativity axiom, at its three
       emission points).  [diagnose] is handed a VC built from
       [user_assume]'s content, run through the identical wellsortedness/
       float-rewrite pipeline as [assume] — never the raw list, and never a
       shape-based filter over [assume] itself, which would silently drop a
       genuine user guard that happens to look like `len(xs) >= 0`. *)
    let user_assume = ref [] in
    let push_user (t : Smt.term) : unit =
      assume := t :: !assume;
      user_assume := t :: !user_assume
    in
    let push_user_list (ts : Smt.term list) : unit =
      assume := ts @ !assume;
      user_assume := ts @ !user_assume
    in
    (* A well-formedness axiom about the encoder's OWN representation — see
       [user_assume]'s comment.  Marked at its emission site, where the
       encoder knows what it is emitting, rather than pattern-matched by
       shape later: that would risk swallowing a genuine user fact that
       happens to have the same shape (an explicit `len(xs) >= 0` guard,
       say), and it would rot silently the moment the encoder started
       emitting a differently-shaped axiom. *)
    let push_structural (t : Smt.term) : unit = assume := t :: !assume in
    (* ── Caller-scope scalar sorts ─────────────────────────────────────────
       A path condition mentions CALLER variables and reflects each to
       `Const name`; so does an argument that IS that variable.  The two must
       agree on a sort, or the VC declares one symbol twice and z3 rejects it.
       The only names whose sort this call pins are the ones it passes to a
       parameter of known scalar sort, so those are recorded here and consulted
       by every caller-namespace producer.  A name not listed keeps the
       pre-existing default, `Int`. *)
    let caller_scalar : (string, Smt.sort) Hashtbl.t = Hashtbl.create 4 in
    List.iteri
      (fun i a ->
        match a with
        | A.EVar { A.txt = x; _ } ->
          let s = scalar_at_idx i in
          if s <> Smt.SInt then Hashtbl.replace caller_scalar x s
        | _ -> ())
      args;
    let caller_scalar_of name =
      match Hashtbl.find_opt caller_scalar name with Some s -> s | None -> Smt.SInt
    in
    (* Attach the (expensive) datatype/quantifier preamble ONLY to VCs that
       actually reference an axiomatised measure; a plain Int/Bool VC pays no
       axiom cost.  Set when [resolve_measure] reflects an axiom measure. *)
    let uses_axiom = ref false in
    (* ADT sorts a constructor tester ranged over; their datatype declarations
       are attached to this VC's preamble. *)
    let adt_sorts = ref [] in
    (* ── Per-VC string state ────────────────────────────────────────────────
       [str_names] records every constant declared into the `Str` sort, so a
       later reflection of the same March variable agrees on its sort and
       [resolve_measure_app] can tell a string term from a list term.
       [str_lit_tbl] maps each DISTINCT literal to its constant, so the same
       literal reflects to the same symbol and distinct literals are asserted
       distinct.  [uses_string] decides whether this VC gets the string
       preamble — the same "attach only when actually used" discipline the
       measure preamble follows. *)
    let str_lit_tbl : (string, string) Hashtbl.t = Hashtbl.create 4 in
    let str_names : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let uses_string = ref false in
    let declare_str_const c =
      if not (Hashtbl.mem str_names c) then begin
        Hashtbl.replace str_names c ();
        uses_string := true;
        decls := (c, Smt.SData str_sort) :: !decls
      end
    in
    (* A string literal's constant, minted on first sight.  Literal text is NOT
       embedded in the symbol (arbitrary text is not a legal SMT-LIB symbol); an
       index is used instead.  Two facts are asserted: the pinned length, and
       distinctness from every literal already seen.

       LENGTH IS IN BYTES.  March's `string_length` builtin is `String.length`
       in the interpreter and an alias for `march_string_byte_length` in native
       codegen, so bytes is not a conservative guess, it is what that builtin
       means.  OCaml's [String.length] over the already-unescaped literal is
       exactly that.

       March DOES have a codepoint-length primitive — `String.codepoint_count`,
       which returns 1 for "é" where every byte-length spelling returns 2.  It
       is simply not what `$strlen` denotes, and must never be aliased to it;
       see [measure_alias].  (An earlier revision of this comment claimed the
       language had no such primitive.  It does, and reasoning from that claim
       is how a codepoint count nearly got equated with a byte count.) *)
    let str_lit_const (s : string) : Smt.term option =
      if not (string_len_available ()) then None
      else
        match Hashtbl.find_opt str_lit_tbl s with
        | Some c -> Some (Smt.Const c)
        | None ->
          let c = Printf.sprintf "$str%d" (Hashtbl.length str_lit_tbl) in
          Hashtbl.replace str_lit_tbl s c;
          declare_str_const c;
          push_structural
            (Smt.Eq (Smt.App (strlen_fn, [ Smt.Const c ]), Smt.IntLit (String.length s)));
          Hashtbl.iter
            (fun s' c' ->
              if s' <> s then push_structural (Smt.Ne (Smt.Const c, Smt.Const c')))
            str_lit_tbl;
          Some (Smt.Const c)
    in
    (* Reflect a STRING-typed actual.  Side effects (declarations, assumptions)
       must happen once per key, hence the memo table.  A refined string local
       carries its own predicate in as an assumption — that is what makes
       `fn f(s : {String | len(_) > 0}) … nonempty(s)` provable rather than
       merely unprovable-and-skipped. *)
    let str_reflected : (string, Smt.term option) Hashtbl.t = Hashtbl.create 4 in
    let reflect_str (key : string) (e : A.expr) : Smt.term option =
      match Hashtbl.find_opt str_reflected key with
      | Some cached -> cached
      | None ->
        let result =
          if not (string_len_available ()) then None
          else
            match e with
            | A.ELit (A.LitString s, _) -> str_lit_const s
            | A.EVar { A.txt = x; _ } ->
              declare_str_const x;
              let xc = Smt.Const x in
              (match List.assoc_opt x sc with
               | Some (b, q, Some srt) when srt = str_sort ->
                 let rv n = if n = b || n = "_" then Some xc else None in
                 let rm m n =
                   if m = "len" && (n = b || n = "_") then Some (Smt.App (strlen_fn, [ xc ]))
                   else None
                 in
                 (match smt_of ~resolve_var:rv ~resolve_measure:rm
                          ~resolve_str_lit:str_lit_const q with
                  | Some qa -> push_user qa
                  | None -> ())
               | _ -> ());
              Some xc
            (* Any other string-producing expression (a concatenation, a call)
               is opaque to this encoding — skip rather than guess. *)
            | _ -> None
        in
        Hashtbl.replace str_reflected key result;
        result
    in
    let absorb = function
      | Some (t, d, a) -> decls := d @ !decls; push_user_list a; Some t
      | None -> None
    in
    (* `a.rem` appearing as an ACTUAL argument.  Deliberately the same
       construction [path_resolve_field] uses below for `a.rem` in a PATH
       CONDITION — the record's SMT selector applied to `Const a` — because the
       guard and the goal only meet if both sides land on the identical term.
       The declaration is RETURNED (via [reflect_scalar]'s decls channel and
       [absorb]) rather than pushed straight onto [decls], so a field read that
       never makes it into the goal contributes no stray declaration.
       A receiver outside [recenv] (no known record sort) stays None: the
       obligation is skipped exactly as before, never guessed. *)
    let arg_resolve_field varname fname =
      match List.assoc_opt varname re with
      | None -> None
      | Some sort_name ->
        (match make_field_resolver varname sort_name (Smt.Const varname)
                 varname fname with
         | None -> None
         | Some t ->
           if not (List.mem sort_name !adt_sorts) then
             adt_sorts := sort_name :: !adt_sorts;
           Some (t, [ (varname, Smt.SData sort_name) ]))
    in
    (* Reflection must be stable per binder within one [check_call]: two
       syntactic occurrences of the same binder (or the same cross-argument
       parameter name) in a predicate denote the same value, so they must
       resolve to the same SMT constant.  [reflect_scalar]'s call-argument
       branch mints a *fresh* constant on every invocation (via [ret_ctr]),
       so without memoizing here a predicate like [_ != 4] combined with
       [n > 3 && n < 5] would bind each `_`/`n` occurrence to a different
       constant and lose the contradiction between them.  Caching the
       reflection (not just its absorption) fixes that; re-[absorb]ing an
       identical reflection is harmless (decls are deduplicated before the
       VC is built, and a repeated assumption is the same term). *)
    let reflect_cache
      : (string, (Smt.term * (string * Smt.sort) list * Smt.term list) option) Hashtbl.t =
      Hashtbl.create 8
    in
    let reflect_cached key compute =
      match Hashtbl.find_opt reflect_cache key with
      | Some cached -> cached
      | None ->
        let result = compute () in
        Hashtbl.add reflect_cache key result;
        result
    in
    (* ── The record-refined-parameter path ──────────────────────────────────
       A record actual is NOT a scalar: it must become a datatype term so the
       predicate's `v.field` projections select from it.  We recognise exactly
       two shapes and SKIP everything else:

         - a record literal `{ port: 0 }`  -> the constructor applied to its
           field terms, reordered into declaration order.  If ANY field is
           itself unreflectable — or reflects to a term that would not be
           WELL-SORTED at that field's declared sort — the whole record
           reflects to None: a partial or ill-sorted reflection would either
           assert facts about fields we cannot see, or build a VC z3 answers
           with an `(error …)`.
         - a variable holding a record-refined local/param -> an opaque
           datatype constant carrying that local's own predicate as an
           assumption, which is what lets a refinement forward through a call.

       An unrefined record variable, a call, a field access, … all yield None
       and the call is skipped — the definite-failure stance.

       Note this path deliberately keeps the SAME two-discharge decision
       procedure as the Int path (report only when ¬goal is Verified).  It does
       NOT use check_post's report-on-SAT branch, so a record fact that merely
       fails to establish the callee's precondition stays silent. *)
    let scalar_arg e = absorb (reflect_scalar ~postcond sc e) in
    (* A stand-in for a record field we cannot reflect (see
       [reflect_record_literal]).  Fresh per occurrence, declared at the field's
       DECLARED sort, and given NO assumption — so it denotes an arbitrary value
       and the call-site's "report only when ¬goal is Verified" rule can never
       conclude anything from it.  Its only job is to keep the VC well-sorted so
       the record's CHECKABLE fields survive a sibling we cannot see. *)
    let opaque_ctr = ref 0 in
    let opaque_field (s : Smt.sort) : Smt.term =
      incr opaque_ctr;
      let nm = Printf.sprintf "fld$op%d" !opaque_ctr in
      decls := (nm, s) :: !decls;
      Smt.Const nm
    in
    let record_self sort_name : Smt.term option =
      match self_actual with
      | A.ERecord (fields, _) ->
        reflect_record_literal ~opaque:opaque_field sort_name fields scalar_arg
      | A.EVar { A.txt = x; _ } ->
        (match List.assoc_opt x sc with
         | Some (b, q, Some s) when s = sort_name ->
           let c = Smt.Const x in
           decls := (x, Smt.SData sort_name) :: !decls;
           (* The carried predicate must resolve `b.field` against the SAME
              term the goal projects from, or the assumption constrains a
              different value than the one being checked. *)
           let rv n = if n = b || n = "_" then Some c else None in
           let rf = make_field_resolver b sort_name c in
           (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                    ~resolve_field:rf q with
            | Some qa -> push_user qa
            (* Untranslatable predicate: the constant stays unconstrained, so
               neither the goal nor its negation can be proven and the call is
               skipped.  Sound, just weaker. *)
            | None -> ());
           Some c
         (* An UNREFINED record variable of the right type ([recenv]).  It
            reflects to an opaque constant carrying NO predicate: on its own
            that proves nothing in either direction, so the call is still
            skipped unless the PATH context — a `if c.port >= 1` guard,
            reflected onto this very constant by [path_resolve_field] — settles
            it.  Before this the whole call was skipped, so a guarded call could
            never discharge and a guard that made the call a DEFINITE failure
            was never reported. *)
         | _ ->
           (match List.assoc_opt x re with
            | Some s when s = sort_name ->
              decls := (x, Smt.SData sort_name) :: !decls;
              Some (Smt.Const x)
            | _ -> None))
      (* A direct CALL returning a record, whose callee has a PROVEN
         postcondition at this very record sort.  Records are a subset of the
         ADT sorts, so the Int postcondition path ([reflect_scalar]) and the
         variant path ([reflect_dt]) both already carried their return
         refinements to call sites; only the record shape was dropped here, so
         `needLow(mk())` was silently skipped while the identically-shaped Int
         version was caught.

         The result becomes a FRESH constant — never a name borrowed from the
         caller, so it cannot collide with a symbol declared at another sort —
         carrying the instantiated postcondition as an assumption.

         Two guards keep this from guessing.  The sort equality test: a
         postcondition about some OTHER record says nothing about this one and
         asserting it here would be ill-sorted.  And [gate_unverified_posts]
         has already cleared [ret] on every signature whose postcondition the
         DEFINITION side did not prove, so anything [postcond] returns is a
         fact rather than a trusted contract. *)
      | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) -> (
        match postcond fname cargs with
        | Some (b, q, Some srt) when srt = sort_name ->
          incr ret_ctr;
          let nm = Printf.sprintf "%s$rec%d" fname !ret_ctr in
          let c = Smt.Const nm in
          decls := (nm, Smt.SData sort_name) :: !decls;
          (* [q] is already in the CALLER's namespace ([postcond_of] substituted
             the actuals).  Its binder — and its `b.field` projections — must
             resolve against the SAME term the goal projects from. *)
          let rv n = if n = b || n = "_" then Some c else None in
          let rf = make_field_resolver b sort_name c in
          (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                   ~resolve_field:rf q with
           | Some qa -> push_user qa
           (* Untranslatable predicate: the constant stays unconstrained, so
              neither the goal nor its negation is provable and the call is
              simply skipped. *)
           | None -> ());
          Some c
        | _ -> None)
      | _ -> None
    in
    (* [`Other] = every non-record subject — Int, String and variant ADT — each
       handled by its own resolver below, unchanged.
       [`Skip]   = a RECORD parameter whose actual we cannot reflect; the goal
                   is not even built, so the call is silently skipped. *)
    let mode =
      match rp.sort with
      | Some sort_name when is_record_sort sort_name ->
        (match record_self sort_name with
         | None -> `Skip
         | Some t ->
           (* Seed the ADT preamble so this VC gets the record's
              `declare-datatypes`.  Sharing main's [adt_sorts] machinery (rather
              than emitting a separate record preamble) is what keeps a VC that
              mentions a record AND a tester AND a string free of duplicate sort
              declarations, which z3 rejects inside one push. *)
           if not (List.mem sort_name !adt_sorts) then adt_sorts := sort_name :: !adt_sorts;
           `Record (sort_name, t))
      | _ -> `Other
    in
    (* Resolve a scalar variable IN THE PREDICATE, i.e. in the CALLEE's
       namespace: the refined binder (`_` or its declared name) denotes this
       call's actual argument, and another parameter's name denotes that
       parameter's actual.  Path conditions live in the CALLER's namespace and
       must NOT come through here — see [path_resolve_var]. *)
    let is_self name = name = rp.binder || name = "_" in
    (* The SMT symbol standing for the refined value in MEASURE position.
       Both spellings of the binder — the anonymous `_` of `{Tree | size(_) < 0}`
       and the named `v` of `{v : Tree | size(v) < 0}` — denote the same value,
       so both must reflect to one canonical symbol.  Emitting the binder's
       source name instead was wrong twice over:

         - `_` is a RESERVED SMT-LIB token (it heads indexed identifiers such
           as `(_ is Ctor)`), so `(declare-const _ M_Tree)` made z3 answer
           `(error …)`.  The predicate was therefore never decided — and `_` is
           the DOCUMENTED idiom, so the spelling the docs teach silently
           checked nothing while the named spelling worked.  Worse, a malformed
           VC on the shared `z3 -in` channel is not merely a missed check.
         - a named binder that collides with a caller-scope Int variable would
           put one symbol at two sorts, the same hazard [is_recvar] guards.

       `$self` cannot collide with a March identifier. *)
    (* The Int symbol standing for `m(x)` where [x] is a March NAME — the one
       channel through which a non-axiomatised measure over a variable is
       reflected, on the goal side and (via [load_scope_measure_facts] below) on
       the assumption side.  Memoized per `(m, x)` so BOTH sides name the symbol
       exactly once: z3 rejects a duplicate `declare-const` as a hard error, and
       a malformed VC comes back `Unknown`, i.e. an ordinary-looking SKIP with no
       signal that anything went wrong.  (This VC builder does deduplicate
       [decls] by (name, sort) pair before rendering, so an identical second
       declaration would in fact have survived; the memo does not rely on that,
       and it additionally keeps the `>= 0` assumption from being asserted
       twice.) *)
    let measure_var_cache : (string, Smt.term option) Hashtbl.t = Hashtbl.create 8 in
    let measure_of_var m x =
      let nm = m ^ "$" ^ x in
      match Hashtbl.find_opt measure_var_cache nm with
      | Some cached -> cached
      | None ->
        let c = Smt.Const nm in
        decls := (nm, Smt.SInt) :: !decls;
        (* `len` is known non-negative; user measures get no axiom in v1 (sound;
           guarded uses still discharge via the path context). *)
        if is_nonneg_measure m then push_structural (Smt.Ge (c, Smt.IntLit 0));
        let r = Some c in
        Hashtbl.replace measure_var_cache nm r;
        r
    in
    (* ── Caller-namespace resolvers for a caller-scope refinement's OWN
       predicate ─────────────────────────────────────────────────────────────
       Passed to [reflect_scalar] so a promise mentioning a sibling parameter
       survives instead of being discarded whole (see its header).  The name is
       a CALLER variable and denotes ITSELF, exactly as [path_resolve_var]
       treats a name in a path condition — the same discipline, and for the same
       reason: routing it through the goal-side resolvers would silently
       re-point it at a callee actual whenever the two happen to share an
       identifier.

       The two sort guards are not optional.  A `Str`-sorted or record-sorted
       name re-declared here at `Int` puts one symbol at two sorts, which makes
       z3 emit an error line — and a malformed VC on the shared `z3 -in` channel
       desynchronises it and silently switches refinement checking off for the
       rest of the compilation.  Returning [None] instead drops the sub-term and
       with it the fact, which only loses a proof. *)
    let foreign_var name =
      if Hashtbl.mem str_names name then None
      else if is_recvar name then None
      else Some (Smt.Const name, (name, caller_scalar_of name))
    in
    (* Route measures through the SAME memo the goal side uses, so a promise
       about `len(xs)` and a goal about `len(xs)` land on the one `len$xs`
       symbol.  Two independently-declared constants would be two unrelated
       integers and the fact would connect to nothing — a skip that looks
       exactly like a proof from outside. *)
    let foreign_measure m name = measure_of_var m name in
    let self_dt_sym = "$self" in
    let self_is_str = rp_is_str rp in
    (* The SMT symbol the subject ("_"/[rp.binder]) actually reflects to in
       THIS goal — populated by [mark_self] wherever [resolve_var] or
       [resolve_measure] resolves a self reference to a term with a stable
       top-level symbol (a bare [Const], or a single-arg [App] wrapping one,
       e.g. the `$strlen` wrapper).  Deliberately NOT the source argument's
       own spelling: a measure-typed subject (`len(_) > 0`) reflects to
       `Const "len$x"`, never `Const "x"` (see [measure_of_var]) — the
       UNCONSTRAINED CHECK has to compare against this, or it cannot work at
       all (it would search the assumptions for a symbol the goal itself
       never uses, and call a genuinely-guarded subject "unconstrained").

       [self_source_name] is the OTHER half, for the MESSAGE rather than the
       check: what the user actually typed, e.g. `"ys"`.  These are
       deliberately two different strings carried separately — printing
       [self_symbol] in `reason_detail` leaked `len$ys` into user-facing
       text (round 3 of this task's review): a symbol that appears nowhere
       in the user's program, which sends them looking for something that
       does not exist.  [self_source_name] is computed once, statically,
       from [self_actual] — not tracked dynamically like [self_symbol],
       because the source spelling does not depend on which reflection
       branch fired, only on whether the actual is a bare variable at all;
       an actual that is not (a call, a field access, a literal) has no
       single name to show the user, so this stays [None] and
       [Undecided.diagnose] must not report [Unconstrained_subject] without
       one — see its own comment. *)
    let self_symbol : string option ref = ref None in
    let self_source_name : string option =
      match self_actual with A.EVar { A.txt = x; _ } -> Some x | _ -> None
    in
    let mark_self (name : string) (t : Smt.term option) : Smt.term option =
      if is_self name then
        (match t with
         | Some (Smt.Const c) -> self_symbol := Some c
         | Some (Smt.App (_, [ Smt.Const c ])) -> self_symbol := Some c
         | _ -> ());
      t
    in
    let resolve_var name =
      (* A String-typed subject reflects into the `Str` sort, never `Int`.  The
         choice is driven by a DECLARED type (the refinement's own base type for
         the binder, the callee's parameter type otherwise), never inferred from
         the actual — so an unknown stays unknown instead of being guessed. *)
      match mode with
      (* The refined value is a record: it stands for the datatype term, not
         for anything [reflect_scalar] could produce.  Records and strings are
         disjoint sorts, so this cannot shadow the String path. *)
      | `Record (_, t) when is_self name -> mark_self name (Some t)
      | _ ->
      if is_self name && self_is_str then
        mark_self name (reflect_str "$self" self_actual)
      else if (not (is_self name)) && name_is_str name then
        (match actual_of_name name with Some a -> reflect_str name a | None -> None)
      else if is_self name then
        mark_self name
          (absorb
             (reflect_cached "$self" (fun () ->
                  reflect_scalar ~postcond ~foreign_var ~foreign_measure
                    ~foreign_field:arg_resolve_field
                    ~sort:self_scalar sc self_actual)))
      else
        match actual_of_name name with
        | Some a ->
          absorb
            (reflect_cached name (fun () ->
                 reflect_scalar ~postcond ~foreign_var ~foreign_measure
                   ~foreign_field:arg_resolve_field
                   ~sort:(scalar_of_name name) sc a))
        | None ->
          (* a caller-scope variable from the path context *)
          if Hashtbl.mem str_names name then Some (Smt.Const name)
          (* …unless it is a caller-scope RECORD, which lives at a datatype sort.
             Declaring it `Int` here would put one symbol at two sorts; dropping
             the sub-term instead just loses a fact (silence). *)
          else if is_recvar name then None
          else begin
            decls := (name, caller_scalar_of name) :: !decls;
            Some (Smt.Const name)
          end
    in
    (* ── A caller-scope refined ADT parameter's own promise ──────────────────
       `fn outer(ys : {List(Int) | len(_) > 0}) … inner(ys)`: the goal for the
       inner call is `len$ys > 0`, and until this existed nothing said anything
       about `len$ys`, so the VC was satisfiable both ways and the call was
       SKIPPED — while the identically-shaped `Int` version composed, because
       [reflect_scalar]'s `EVar` arm consults [sc] for scalar sorts and there is
       no scalar sort for a list.

       So: when the actual is a bare name carrying a MEASURE-ONLY scope entry
       ([meas_sort_prefix]), reflect that entry's own predicate as an assumption.
       Three restrictions keep this from guessing:

         - the predicate's measures must apply to the entry's OWN refined value.
           That value has THREE spellings, all of which denote it and all of
           which must resolve identically: the anonymous `_`, the annotation's
           declared binder `v` (`{v : List(Int) | len(v) > 0}`), and the
           parameter's OWN name `ys` (`{List(Int) | len(ys) > 0}`).  A measure
           over any OTHER name is a different value; returning None there drops
           the whole predicate rather than mis-attributing it.

           Accepting only the first two (as this did until 2026-07-29) is the
           same spelling-class bug the GOAL side carried until 2026-07-27, in
           this same file: the third spelling silently composed nothing, so
           `fn outer(ys : {List(Int) | len(ys) > 0}) do inner(ys) end` stayed
           `1 proved, 1 skipped` while the other two spellings proved both
           calls.  A skip emits no diagnostic, so renaming a binder into the
           parameter's own name silently unwired composition.  All three
           spellings are now pinned by tests in BOTH directions (the positive
           case AND a weaker `len(ys) >= 0` control that must still skip).
         - the fact must be phrased over the SAME symbol the goal side uses for
           this value, which differs by measure class:
             · a NON-axiomatised measure (list `len`, a plain user measure) is a
               bare uninterpreted Int, `m$x`, via the memoized [measure_of_var];
             · an AXIOMATISED `@[measure]` ranges over the datatype itself, so
               the fact is `(m x)` with `x` declared at the measure's ADT sort —
               the same term the goal side builds when it reflects the actual
               `EVar x` through [reflect_dt].  That form only MEANS anything if
               the quantified-axiom preamble is attached to this VC, so it sets
               the very [uses_axiom] ref that gates it (defined once for the
               whole VC above; a second, disconnected flag would leave the
               assumption in the VC with nothing to interpret it).
         - [resolve_var] is `None` throughout: the binder denotes a LIST, not a
           scalar, so any predicate that mentions a variable OUTSIDE a measure
           is dropped entirely.  No approximation.  A measure over some other
           name IS translated — see [rm]'s non-self branch below — but only to
           the term the goal side builds for that same name.

       Sound direction: this only ADDS a hypothesis that the caller's own
       signature already promises about this very value, over the same symbol.
       It is loaded at most once per name per VC (the [done] table), so the
       assumption list cannot grow with the number of occurrences.

       Shadowing is handled upstream and not here: [scope_shadow] retires the
       name from [sc] at every binding construct, so after `let ys = tail(ys)`
       the lookup simply finds nothing and no fact is loaded.  Its SECOND
       trigger covers the relational case: an entry whose predicate MENTIONS a
       rebound name is retired too, so `let r = push(t, 5)` followed by a rebind
       of `t` drops `r`'s promise rather than re-reading `t` at its new value. *)
    let scope_facts_loaded : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let load_scope_measure_facts (x : string) : unit =
      if not (Hashtbl.mem scope_facts_loaded x) then begin
        Hashtbl.replace scope_facts_loaded x ();
        match List.assoc_opt x sc with
        | Some (b, q, Some s) when is_meas_sort s ->
          let rv _ = None in
          (* All three spellings of the refined value — `_`, the declared binder
             [b], and the scope entry's own name [x] — denote it.  See the note
             above; the goal side's [is_self]/[actual_of_name] pair already
             accepts the same three. *)
          let is_self_spelling n = n = b || n = "_" || n = x in
          (* ── A RELATIONAL carried predicate's OTHER names ───────────────────
             `fn push(t, x) : {Tree | size(_) == size(t) + 1}` stored against
             `let r = push(t, 5)` arrives here as `size(_) == size(t) + 1`,
             ALREADY in the caller's namespace ([postcond_of] substituted the
             actuals simultaneously, or abandoned propagation entirely).  So a
             non-self name denotes ITSELF, a caller-scope value — the same
             discipline [foreign_var]/[foreign_measure] apply to a refined
             parameter's own promise, and for the same reason: routing it
             through the GOAL-side resolvers would silently re-point it at a
             callee actual whenever a caller variable and a callee parameter
             happen to share a spelling.

             Refusing it outright (as this did until 2026-08-04) drops the
             sub-term, and [smt_of] then drops the WHOLE predicate: no
             assumption, VC satisfiable both ways, call silently skipped.  That
             is what made the motivating repro `needs_bigger(t, r)` report
             `1 proved, 1 skipped` with no diagnostic.

             What is emitted must be the term the GOAL side builds for the same
             name, or the fact connects to nothing and the skip merely looks
             like a proof:
               · axiomatised `@[measure]`: `(m n)` with `n` declared at the
                 measure's ADT sort — exactly what [reflect_dt]'s `EVar` arm
                 produces for this actual (goal side, [resolve_measure]), and
                 what its caller-scope fallback produces when the name is not a
                 callee parameter at all;
               · everything else: the memoized `m$n` from [measure_of_var],
                 which is literally the same call the goal side makes.
             A FRESH constant here would be the `{List(a) | len(_) > 0}` bug
             again — trivially satisfiable, hence a contract that enforces
             nothing while appearing to work.  The REJECT CONTROL test (a
             demand for a SMALLER tree, which `push` never provides) is what
             distinguishes the two.

             Shadowing needs nothing here: [scope_shadow] retires an entry both
             when its own name is rebound AND when its predicate MENTIONS a
             rebound name ([expr_mentions]), so a `t` rebound between the `let`
             and the call removes the whole entry rather than re-pointing this
             `Const t` at the new binding.  That second trigger already exists
             precisely because a promise may mention another name.

             Fail-closed: the sort guards (a `Str` name, a record name, a name
             already pinned to a non-Int scalar sort) drop the sub-term — and
             with it the whole fact — for a name this VC already knows at some
             other sort.  They are a cheap FIRST filter, not the invariant: what
             actually guarantees a one-symbol-two-sorts VC never reaches z3 (a
             single error line there desynchronises the shared `z3 -in` channel
             and silently switches refinement checking off for the rest of the
             compilation) is the [sort_conflict decls] gate further down, which
             sees the finished declaration list.  Losing a fact only loses a
             proof. *)
          let rm m' n =
            if not (is_self_spelling n) then
              if Hashtbl.mem str_names n || is_recvar n
                 || caller_scalar_of n <> Smt.SInt
              then None
              else if is_axiom_measure m' then begin
                let adt = Hashtbl.find axiom_measures m' in
                uses_axiom := true;
                decls := (n, Smt.SData adt) :: !decls;
                Some (Smt.App (m', [ Smt.Const n ]))
              end
              else measure_of_var m' n
            else if is_axiom_measure m' then begin
              (* Gate the quantified-axiom preamble on the SHARED per-VC ref, so
                 `(m x)` here and `(m x)` in the goal are interpreted by the same
                 axioms.  Both this and the goal side declare `x` at the sort; the
                 VC builder deduplicates [decls] by (name, sort), and the
                 per-name [scope_facts_loaded] memo keeps a repeated occurrence
                 of the same name from re-loading the fact at all. *)
              let adt = Hashtbl.find axiom_measures m' in
              uses_axiom := true;
              decls := (x, Smt.SData adt) :: !decls;
              Some (Smt.App (m', [ Smt.Const x ]))
            end
            else measure_of_var m' x
          in
          (match smt_of ~resolve_var:rv ~resolve_measure:rm q with
           | Some qa -> push_user qa
           | None -> ())
        | _ -> ()
      end
    in
    (* ── A caller-scope refined ADT parameter's own CONSTRUCTOR-TAG promise ───
       The tester analogue of [load_scope_measure_facts], and the same gap:

         fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
         fn outer(p : {Option(Int) | is_Some(_)}) : Int do inner(p) end

       The goal for `inner(p)` is `((_ is Some) p)`, and [reflect_dt]'s `EVar`
       arm declares `p` as a FRESH, UNCONSTRAINED datatype constant — so the VC
       was satisfiable both ways and the call was SKIPPED, silently, while the
       measure-shaped version of the very same composition proved.  `outer`'s
       own signature already promises exactly this tag about exactly this value,
       so the fact is available; nothing was consulting [sc] for it.

       What fires, and only this:

         - the actual is a bare name [x] carrying a MEASURE-ONLY scope entry
           ([meas_sort_prefix] — the marker [refined_scope_ty] gives every
           registered non-record ADT, `Option` included);
         - that entry's predicate is EXACTLY a bare tester application over the
           entry's OWN refined value — no conjunction, no negation, no other
           subject.  All THREE spellings of that value are accepted: the
           anonymous `_`, the annotation's declared binder [b], and the
           parameter's own name [x].  Missing one of the three is the spelling
           class that has shipped broken three times in this file (twice on the
           measure side, once on the goal side); a skip emits no diagnostic, so
           the omission is invisible until someone renames a binder;
         - the tester's constructor is the SAME constructor this goal tests, and
           belongs to the SAME datatype sort [adt].  A DIFFERENT constructor is
           deliberately not loaded: `is_None(_)` composing into a callee that
           wants `is_Some(_)` would be sound to assume (and would turn the call
           into a reported violation, since the two are exclusive), but it is a
           strictly wider claim than "the caller already promised the goal", and
           a missed report costs nothing here while a wrong one is the failure
           this subsystem exists to prevent.

       The fact is phrased over `Const x` at sort [adt] — the very term
       [reflect_dt]'s `EVar` arm builds for this actual on the GOAL side — so
       assumption and goal meet on one symbol.  Both sides also emit the same
       `(x, SData adt)` declaration; the VC builder deduplicates [decls] by
       (name, sort) before rendering, and the per-(name, ctor) memo below keeps
       a repeated occurrence from re-asserting the assumption.

       Sound direction: this only ADDS a hypothesis the caller's own signature
       already states about this very value.  Shadowing is handled upstream by
       [scope_shadow], which retires the name from [sc] at every binding
       construct, so after `let p = None` or a `match` arm binding `p` the
       lookup finds nothing and no fact is loaded. *)
    let tester_facts_loaded : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let load_scope_tester_facts (adt : string) (goal_ctor : string) (x : string) : unit =
      let key = x ^ "|" ^ adt ^ "|" ^ goal_ctor in
      if not (Hashtbl.mem tester_facts_loaded key) then begin
        Hashtbl.replace tester_facts_loaded key ();
        match List.assoc_opt x sc with
        | Some (b, q, Some s) when is_meas_sort s -> (
          match q with
          | A.EApp (A.EVar { A.txt = t; _ }, [ A.EVar { A.txt = n; _ } ], _)
            when n = b || n = "_" || n = x -> (
            match ctor_of_tester t with
            | Some ctor when ctor = goal_ctor && sort_of_ctor ctor = Some adt ->
              decls := (x, Smt.SData adt) :: !decls;
              if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
              push_user (Smt.IsCtor (ctor, Smt.Const x))
            | _ -> ())
          | _ -> ())
        | _ -> ()
      end
    in
    (* Reflect a value into the SMT datatype term an axiomatised measure ranges
       over: a constructor application becomes (ctor …) (so the recursion axioms
       fire); a variable becomes a fresh datatype constant. *)
    let dt_counter = ref 0 in
    let rec reflect_dt adt e =
      match e with
      | A.ECon (ctor, args, _)
        when (match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor.A.txt cs | None -> false) ->
        let sorts = try Hashtbl.find ctor_field_sorts ctor.A.txt with Not_found -> [] in
        if List.length args <> List.length sorts then None
        else
          List.fold_right2
            (fun a s acc ->
              match reflect_field a s, acc with Some t, Some ts -> Some (t :: ts) | _ -> None)
            args sorts (Some [])
          |> Option.map (fun ts -> Smt.App (ctor.A.txt, ts))
      | A.EVar { A.txt = x; _ } -> decls := (x, Smt.SData adt) :: !decls; Some (Smt.Const x)
      (* ── Tier 2 propagation ────────────────────────────────────────────────
         A CALL returning a value at this very datatype sort, whose callee has a
         PROVEN postcondition (an unproven one has already been cleared by
         [gate_unverified_posts]).  It becomes a fresh opaque constant of the
         sort, carrying the instantiated postcondition as an assumption — the
         datatype analogue of [reflect_scalar]'s call branch.
         The sort equality test is load-bearing: a postcondition about a value
         of some OTHER datatype says nothing about this one, and asserting it
         about this constant would be ill-sorted. *)
      | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) -> (
        match postcond fname cargs with
        | Some (b, q, Some srt) when srt = adt ->
          incr ret_ctr;
          let nm = Printf.sprintf "%s$dt%d" fname !ret_ctr in
          let c = Smt.Const nm in
          decls := (nm, Smt.SData adt) :: !decls;
          (* [q] is already in the CALLER's namespace (postcond_of substituted
             the actuals), so every remaining variable denotes itself.  A
             measure over the binder applies to [c]; a measure over any other
             term is reflected at the measure's own ADT sort. *)
          let rv n = if n = b || n = "_" then Some c else None in
          let rm m x =
            if not (is_axiom_measure m) then None
            else begin
              uses_axiom := true;
              if x = b || x = "_" then Some (Smt.App (m, [ c ]))
              else
                let a = Hashtbl.find axiom_measures m in
                Option.map
                  (fun t -> Smt.App (m, [ t ]))
                  (reflect_dt a (A.EVar { A.txt = x; A.span }))
            end
          in
          let rma m arg_term =
            if not (is_axiom_measure m) then None
            else
              match concrete_measure_app m arg_term with
              | Some n -> Some (Smt.IntLit n)
              | None -> uses_axiom := true; Some (Smt.App (m, [ arg_term ]))
          in
          (match smt_of ~resolve_var:rv ~resolve_measure:rm ~resolve_measure_app:rma q with
           | Some qa -> push_user qa
           (* Untranslatable predicate: the constant stays unconstrained, which
              proves nothing in either direction — the call is simply skipped. *)
           | None -> ());
          Some c
        | _ -> None)
      | _ -> None
    and reflect_field a = function
      | Smt.SData sub when sub <> "Elem" -> reflect_dt sub a
      | sort ->
        (* element / Int field: irrelevant to a structural measure -> fresh const *)
        incr dt_counter;
        let nm = Printf.sprintf "_e%d" !dt_counter in
        decls := (nm, sort) :: !decls;
        Some (Smt.Const nm)
    in
    (* A constructor tester, in the predicate or in a path condition.  Its
       subject is reflected into the datatype sort the constructor belongs to:
       the refined binder (`_` or its name) stands for THIS call's actual
       argument, another parameter's name for that parameter's actual, and
       anything else — a caller-scope variable, a constructor literal — for
       itself.  [reflect_dt] turns a literal into `(Ctor …)` (so the tester
       decides concretely) and a variable into an opaque datatype constant (so
       an unconstrained value stays unknown and we keep silent). *)
    let resolve_tester ctor arg =
      match sort_of_ctor ctor with
      | None -> None
      | Some adt ->
        let subject =
          match arg with
          | A.EVar { A.txt = x; _ } when x = rp.binder || x = "_" -> self_actual
          | A.EVar { A.txt = x; _ } ->
            (match actual_of_name x with Some a -> a | None -> arg)
          | _ -> arg
        in
        (* The subject is a bare caller-scope name: load whatever the CALLER's
           own signature promises about its TAG first, so the promise and the
           goal meet on the one `Const x` symbol [reflect_dt] is about to
           build for it.  Mirrors the measure side's load-before-reflect. *)
        (match subject with
         | A.EVar { A.txt = x; _ } -> load_scope_tester_facts adt ctor x
         | _ -> ());
        (match reflect_dt adt subject with
         | Some t ->
           if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
           Some (Smt.IsCtor (ctor, t))
         | None -> None)
    in
    let resolve_measure m name =
      (* `len` OVERLOAD RESOLUTION.  The string meaning is taken only when the
         subject's DECLARED base type is String — the refinement's own base type
         for the binder, the callee's parameter type for a cross-argument name.
         Everything else falls through to the existing list handling unchanged,
         so list `len` keeps its meaning exactly. *)
      if m = "len" && string_len_available ()
         && ((is_self name && self_is_str) || ((not (is_self name)) && name_is_str name))
      then
        let key = if is_self name then "$self" else name in
        let actual = if is_self name then Some self_actual else actual_of_name name in
        mark_self name
          (match actual with
           | Some a -> Option.map (fun t -> Smt.App (strlen_fn, [ t ])) (reflect_str key a)
           | None -> None)
      else if is_axiom_measure m then (
        uses_axiom := true;
        let adt = Hashtbl.find axiom_measures m in
        (* BOTH spellings resolve against the SAME actual argument, exactly as
           the non-axiomatised branch below does — the anonymous `_`, the named
           binder and (for a cross-argument name) that parameter's own name all
           denote the value being passed.

           Until this, the self spellings routed to an UNCONSTRAINED datatype
           constant [self_dt_sym] instead, discarding [self_actual].  So
           `{Tree | size(_) > 0}` was decided only by `size`'s own axioms about
           an arbitrary tree — satisfiable both ways — and every call was
           SKIPPED, including `inner(Node(Leaf, 5, Leaf))` (provable: the
           recursion axioms compute 1) and `inner(Leaf)` (a real violation:
           they compute 0).  A contract in that shape enforced nothing at all,
           silently, while the same measure over ANOTHER parameter's name
           (`{Int | _ < size(t)}`) worked, because that path already reflected
           the actual.

           Reflecting the actual is also what lets the CALLER's own promise meet
           this goal: for `EVar x` [reflect_dt] yields `Const x` at the ADT sort,
           the same term [load_scope_measure_facts] phrases its assumption over.
           Hence the load below, before reflecting.

           The fallback keeps the previous behaviour where there is nothing to
           reflect (an actual that is neither a variable, a constructor literal,
           nor a call with a proven postcondition): an unconstrained constant,
           i.e. SAT, i.e. a skip. *)
        let actual = if is_self name then Some self_actual else actual_of_name name in
        match actual with
        | None ->
          decls := (name, Smt.SData adt) :: !decls;
          Some (Smt.App (m, [ Smt.Const name ]))
        | Some a ->
          (match a with A.EVar { A.txt = x; _ } -> load_scope_measure_facts x | _ -> ());
          mark_self name
            (match reflect_dt adt a with
             | Some t -> Some (Smt.App (m, [ t ]))
             | None ->
               if is_self name then begin
                 decls := (self_dt_sym, Smt.SData adt) :: !decls;
                 Some (Smt.App (m, [ Smt.Const self_dt_sym ]))
               end
               else None))
      else
        (* A measure with no axioms (a user measure, or list `len`).  All three
           spellings of the refined value — the anonymous `_`, the named binder
           `v`, and the parameter's own name `xs` — denote the SAME value, so all
           three must resolve against the SAME actual argument.  Routing `_`/`v`
           to a fresh constant instead (as this did until 2026-07-27) made
           `{List(a) | len(_) > 0}` and `{v : List(a) | len(v) > 0}` reflect to
           an unconstrained non-negative integer: satisfiable, hence never a
           definite failure, hence SILENT.  The contract parsed, typechecked and
           checked nothing, while the third spelling worked — so a stdlib author
           following the documented `_` idiom got no enforcement at all, and
           renaming a parameter silently unenforced a working contract. *)
        let actual = if is_self name then Some self_actual else actual_of_name name in
        match actual with
        | Some a ->
          mark_self name
            (match (if m = "len" then list_len a else None) with
             | Some n -> Some (Smt.IntLit n)
             | None -> (
                 match a with
                 (* The actual is a bare name.  Load whatever the CALLER's own
                    signature promises about its measures first, so the promise
                    and the goal meet on the one memoized `m$x` symbol. *)
                 | A.EVar { A.txt = x; _ } ->
                   load_scope_measure_facts x;
                   measure_of_var m x
                 (* A non-variable, non-literal actual (a call, a field…): no
                    symbol to share with the caller's facts.  For the binder
                    spellings keep the fresh non-negative constant — it is what
                    the two spellings resolved to before, and it stays SAT, so
                    the outcome is silence either way. *)
                 | _ when is_self name -> measure_of_var m self_dt_sym
                 | _ -> None))
        | None -> measure_of_var m name (* a caller-scope variable *)
    in
    (* [resolve_field] turns the predicate's `v.port` into the record's SMT
       selector applied to the term standing for the refined value.  Only the
       record path installs one; every other path keeps [smt_of]'s default
       (which returns None, dropping any field-bearing predicate). *)
    let resolve_field =
      match mode with
      | `Record (sort_name, t) -> make_field_resolver rp.binder sort_name t
      | `Other | `Skip -> fun _ _ -> None
    in
    (* A measure applied to a non-variable term — `len(v.history)` where
       `v.history` is a field selector.  Mirrors check_post: evaluate
       concretely when we can (a concrete answer needs no quantified axioms,
       which is what keeps Z3 from returning `unknown`), otherwise fall back
       to a symbolic constant, or to the axiomatised application. *)
    let mapp_ctr = ref 0 in
    (* Memoized per (measure, term): two occurrences of `len(v.history)` in one
       predicate denote the same value and must share a constant, or a
       contradiction between them is lost. *)
    let mapp_cache : (string, Smt.term option) Hashtbl.t = Hashtbl.create 8 in
    let resolve_measure_app_record m arg_term =
      let key = m ^ "|" ^ Smt.render arg_term in
      match Hashtbl.find_opt mapp_cache key with
      | Some cached -> cached
      | None ->
        let result =
          if m = "len" then
            match concrete_len arg_term with
            | Some n -> Some (Smt.IntLit n)
            | None ->
              incr mapp_ctr;
              let nm = Printf.sprintf "len$app%d" !mapp_ctr in
              decls := (nm, Smt.SInt) :: !decls;
              push_structural (Smt.Ge (Smt.Const nm, Smt.IntLit 0));
              Some (Smt.Const nm)
          else if is_axiom_measure m then
            match concrete_measure_app m arg_term with
            | Some n -> Some (Smt.IntLit n)
            | None ->
              (* No concrete answer: use the axiomatised application, which
                 makes this VC need the quantified-axiom preamble. *)
              uses_axiom := true;
              Some (Smt.App (m, [ arg_term ]))
          else begin
            incr mapp_ctr;
            let nm = Printf.sprintf "%s$app%d" m !mapp_ctr in
            decls := (nm, Smt.SInt) :: !decls;
            if is_nonneg_measure m then push_structural (Smt.Ge (Smt.Const nm, Smt.IntLit 0));
            Some (Smt.Const nm)
          end
        in
        Hashtbl.add mapp_cache key result;
        result
    in
    (* `len(<expr>)` where the expression itself reflected to a term.  Two
       disjoint meanings, tried in order:
         - STRING: the term is one of OUR declared `Str` constants (e.g. an
           inline `len("abc")`) — main's rule, unchanged;
         - RECORD: the term is a field selector such as `len(v.history)` —
           evaluated concretely when possible, otherwise a symbolic constant or
           the axiomatised application.
       They cannot both match one term (a `Str` constant is never a selector),
       so the order is arbitrary and neither changes the other's behaviour. *)
    let resolve_measure_app m arg =
      match m, arg with
      | "len", Smt.Const c when string_len_available () && Hashtbl.mem str_names c ->
        Some (Smt.App (strlen_fn, [ arg ]))
      | _ ->
        (match mode with
         | `Record _ -> resolve_measure_app_record m arg
         | `Other | `Skip -> None)
    in
    (* Pre-reflect a String binder before the path conditions are translated, so
       a caller variable mentioned by a guard is already known to be `Str`-sorted
       and both occurrences agree on a sort. *)
    if self_is_str then ignore (resolve_var rp.binder);
    (* ── Caller-namespace resolvers, for the PATH CONTEXT only ─────────────
       A path condition was collected at the call site, so every name in it is
       a CALLER variable and denotes itself.  Routing it through the predicate
       resolvers above (which consult [rp.binder] and [actual_of_name]) would
       silently re-point it at the callee's actuals whenever the caller happens
       to use the same identifier as a callee parameter or as the refinement's
       named binder — reporting `y = None` from a fact about an unrelated
       caller `o`.  A caller variable therefore always reflects to `Const name`
       — the very term [reflect_scalar]/[reflect_dt] give an `EVar` actual, so
       when the argument really IS that variable the two sides still meet on
       the same SMT symbol and the narrowing keeps working. *)
    let path_resolve_var name =
      (* A name already declared into the `Str` sort denotes ITSELF at that
         sort.  [reflect_scalar] would unconditionally declare it `Int`, and a
         VC declaring one symbol at two sorts makes z3 emit an error line — the
         failure mode that desynchronises the shared `z3 -in` channel and
         silently switches refinement checking off for the rest of the
         compilation.  So the string sort wins here, exactly as it does in
         [resolve_var]'s caller-scope fallback. *)
      if Hashtbl.mem str_names name then Some (Smt.Const name)
      (* Same rule for a caller-scope RECORD: it is declared at its datatype
         sort by [path_resolve_field], so it must never also be reflected as a
         scalar.  Returning None drops the sub-term — and with it the whole
         condition — which only loses a fact. *)
      else if is_recvar name then None
      else
        absorb
          (reflect_cached ("$path$" ^ name) (fun () ->
               reflect_scalar ~postcond ~sort:(caller_scalar_of name) sc
                 (A.EVar { A.txt = name; A.span })))
    in
    (* `c.port` in a PATH CONDITION.  The name is a CALLER variable, so it
       denotes itself: the record's SMT selector applied to `Const c` — the very
       term [record_self] gives a record actual that IS that variable, so a
       guard and the goal meet on one constant.  A name outside [recenv] yields
       None and the condition is dropped (sound, just weaker). *)
    let path_resolve_field varname fname =
      match List.assoc_opt varname re with
      | None -> None
      | Some sort_name ->
        let c = Smt.Const varname in
        (match make_field_resolver varname sort_name c varname fname with
         | None -> None
         | Some t ->
           decls := (varname, Smt.SData sort_name) :: !decls;
           if not (List.mem sort_name !adt_sorts) then adt_sorts := sort_name :: !adt_sorts;
           Some t)
    in
    let path_resolve_measure m name =
      if is_axiom_measure m then (
        uses_axiom := true;
        let adt = Hashtbl.find axiom_measures m in
        decls := (name, Smt.SData adt) :: !decls;
        Some (Smt.App (m, [ Smt.Const name ])))
      (* `len` over a name ALREADY declared into the `Str` sort is the string
         length, i.e. the same `($strlen name)` the predicate side produces —
         and the caller's `name` is the very constant it produced it over (the
         binder is pre-reflected just above, before path translation, exactly so
         that this holds).  Without this the two sides split: the predicate says
         `($strlen t)` while the guard said `len$t`, an unrelated Int constant,
         and no string guard could ever discharge a string obligation.
         [path_resolve_var] applies the identical `str_names` rule to plain
         occurrences, so this keeps measure and variable positions at one sort.

         Unreachable from source until the byte-length aliases existed — March
         has no callable `len`, so a guard could not mention this measure. *)
      else if m = "len" && string_len_available () && Hashtbl.mem str_names name then
        Some (Smt.App (strlen_fn, [ Smt.Const name ]))
      else measure_of_var m name
    in
    let path_resolve_tester ctor arg =
      (* A tag test on a LIST is a statement about its length, and saying it that
         way is what connects a `match` arm to a `len` contract:

           match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end

         The `_` arm carries `not is_Nil(xs)` (pushed by the arm-order exclusion
         in [visit]), and `mean`'s precondition is about `len(xs)`.  Routed
         through the datatype encoding below those are two unrelated facts — a
         tester over an opaque datatype constant, and an integer — so the arm
         proved nothing and every safe-wrapper in the stdlib carried permanent
         unprovable debt.  Translating the tester onto the SAME memoized `len$x`
         symbol the goal uses closes the gap with no datatype declaration and no
         quantified axiom:

           is_Nil(xs)   <->  len(xs) = 0
           is_Cons(xs)  <->  len(xs) > 0

         Both are exact for lists, and `len >= 0` is already asserted by
         [measure_of_var], so `not (len$xs = 0)` gives z3 `len$xs > 0` directly.

         Gated on the constructor belonging to the BUILT-IN List sort: a user
         ADT is free to have its own `Nil`, and a `len` claim about that would be
         invented rather than derived. *)
      let list_sort = adt_sort_name "List" in
      match arg, sort_of_ctor ctor with
      | A.EVar { A.txt = x; _ }, Some adt
        when adt = list_sort && (ctor = "Nil" || ctor = "Cons") ->
        (match measure_of_var "len" x with
         | Some len_x ->
           Some
             (if ctor = "Nil" then Smt.Eq (len_x, Smt.IntLit 0)
              else Smt.Gt (len_x, Smt.IntLit 0))
         | None -> None)
      | _ ->
      match sort_of_ctor ctor with
      | None -> None
      | Some adt ->
        (match reflect_dt adt arg with
         | Some t ->
           if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
           Some (Smt.IsCtor (ctor, t))
         | None -> None)
    in
    (* Translate the path conditions into assumptions (dropping any that fall
       outside the supported fragment — sound, just weaker).  Names resolve in
       the CALLER's namespace; string literals still reflect to this VC's `Str`
       constants so a guard mentioning one lines up with the predicate. *)
    List.iter
      (fun (cond, negated) ->
        match
          smt_of ~resolve_var:path_resolve_var ~resolve_measure:path_resolve_measure
            ~resolve_field:path_resolve_field
            ~resolve_measure_app ~resolve_tester:path_resolve_tester
            ~resolve_str_lit:str_lit_const cond
        with
        | Some t -> push_user (if negated then Smt.Not t else t)
        | None -> ())
      path;
    (* [`Skip]: a record parameter whose actual could not be reflected — build
       no goal at all, so neither discharge runs and the call is passed over. *)
    (match
       (match mode with
        | `Skip -> None
        | `Other | `Record _ ->
          smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app
            ~resolve_tester ~resolve_str_lit:str_lit_const rp.pred)
     with
     | None ->
       (* Two different causes reach this arm and they must not be conflated:
          `Skip` means the SUBJECT (a record actual) did not reflect, while the
          other modes mean the PREDICATE itself did not.  The distinction was
          cosmetic while it only fed a debug count; `cap verified` puts the
          reason in front of a user, and telling someone their perfectly
          reflectable predicate is unreflectable sends them after the wrong
          thing. *)
       note
         (Obligation.Skipped
            (match mode with
             | `Skip -> Obligation.Unreflectable_subject
             | `Other | `Record _ -> Obligation.Unreflectable_predicate))
     | Some goal when not (wellsorted (Hashtbl.mem str_names) goal) ->
       note (Obligation.Skipped Obligation.Sort_conflict)
     | Some goal ->
       (* de-duplicate decls (a symbol may be requested twice) *)
       let decls =
         List.fold_left
           (fun acc d -> if List.mem d acc then acc else d :: acc)
           [] !decls
       in
       (* A symbol declared into the `Str` sort must NOT also be declared `Int`
          by some other reflection path: z3 rejects the duplicate, and a single
          error line desynchronises the shared `z3 -in` channel, silently
          disabling refinement checking for the remainder of the compilation.
          Every producer is supposed to consult [str_names] first; this is the
          one place that can guarantee it, so it is enforced here as well.  Any
          term that still refers to such a symbol as an Int is ill-sorted and
          is dropped by [wellsorted] below. *)
       let decls =
         List.filter
           (fun (n, s) -> not (s = Smt.SInt && Hashtbl.mem str_names n))
           decls
       in
       if sort_conflict decls then note (Obligation.Skipped Obligation.Sort_conflict)
       else
       (* Drop ill-sorted assumptions.  Weakening the hypothesis set can only
          make BOTH discharges harder, so this can only turn a report into a
          skip — never the reverse. *)
       let assumptions = List.filter (wellsorted (Hashtbl.mem str_names)) !assume in
       (* Now the declarations are final, so which symbols are floats is known:
          rewrite every ordinary comparison over two floats into its IEEE form,
          then drop anything that still mixes a float with an Int. *)
       let sort_of n = List.assoc_opt n decls in
       let is_float n = sort_of n = Some Smt.SFloat in
       let goal = fp_rewrite is_float goal in
       if not (float_wellsorted is_float goal && formula_wellsorted sort_of goal) then
         note (Obligation.Skipped Obligation.Float_sort_gate)
       else
       let assumptions =
         List.filter_map
           (fun a ->
             let a = fp_rewrite is_float a in
             if float_wellsorted is_float a && formula_wellsorted sort_of a then Some a
             else None)
           assumptions
       in
       let vc = { Smt.decls; assumptions; goal } in
       (* [user_assumptions]: the SAME two-step filter (sort-wellsortedness,
          then float-rewrite-and-wellsortedness) applied to [user_assume]
          instead of [assume] — i.e. every USER-derived assumption that
          survived exactly the same gates the real [vc.assumptions] did,
          minus the encoder's own well-formedness axioms (see
          [user_assume]'s comment above).  This is what [Undecided.diagnose]
          gets handed for its "nothing constrains it" check, so a `len$x >=
          0` axiom the CHECKER emitted can never make a genuinely-unguarded
          subject look constrained, while a real user guard of the exact
          same shape (`if List.length(xs) >= 0 do …`, however redundant)
          still counts — it was pushed at the path-condition site, not the
          measure's well-formedness site, so it lands in [user_assume]
          regardless of what it looks like. *)
       let user_assumptions =
         List.filter_map
           (fun a ->
             let a = fp_rewrite is_float a in
             if float_wellsorted is_float a && formula_wellsorted sort_of a then Some a
             else None)
           (List.filter (wellsorted (Hashtbl.mem str_names)) !user_assume)
       in
       (* Attach the (expensive) axiom preamble only when an axiomatised
          measure was reflected, the datatype declarations only when a
          constructor tester was, and the `$Str` sort only when a string was.
          When measure and ADT both fire, the measure preamble already declares
          `Elem` and its own covered sorts, so the ADT half must not redeclare
          them — z3 rejects a duplicate sort inside one push, and one such
          error line desynchronises the shared solver channel.  The string
          preamble declares only `$Str`/`$strlen`, names no other preamble can
          produce, so it composes with either or both unconditionally.

          A RECORD subject seeds its sort into [adt_sorts] (see [mode]), so it
          rides this same path and inherits the same deduplication — which is
          what makes a VC mentioning a record AND a tester AND a string emit
          each sort exactly once. *)
       let preamble =
         let m = if !uses_axiom then !measure_preamble else "" in
         let a =
           if !adt_sorts = [] then ""
           else
             adt_vc_preamble
               ~skip:(fun s -> m <> "" && Hashtbl.mem measure_preamble_sorts s)
               ~skip_elem:(m <> "") !adt_sorts
         in
         let s = if !uses_string then string_preamble else "" in
         let ma = match m, a with "", x | x, "" -> x | x, y -> x ^ "\n" ^ y in
         match ma, s with "", x | x, "" -> x | x, y -> x ^ "\n" ^ y
       in
       (* Report a violation ONLY when the precondition can *never* hold under
          the assumptions (a definite failure).  If it merely *might* fail
          (e.g. a symbolic, unknown length), that is unprovable either way and
          we stay silent — no false positives.

          - discharge(goal=G) Verified  => G always holds        => pass
          - else discharge(goal=¬G) Verified => G never holds     => violation
          - otherwise (G depends on unknowns / solver unsure)     => skip *)
       (match Refine.discharge ~root ~preamble vc with
        | Refine.Verified -> note Obligation.Proved
        | first ->
          (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             note Obligation.Violated;
             (* Name the parameter and callee rather than saying "argument".
                On a call with several arguments, "argument does not satisfy
                `_ != 0`" leaves the reader to work out WHICH one, and the
                predicate's binder is usually the anonymous `_`, so the message
                alone does not identify it. *)
             let param_label =
               match subject, List.nth_opt sg.param_names rp.idx with
               | Argument, Some pname when pname <> "" ->
                 Printf.sprintf "argument `%s` of `%s`" pname callee
               | Argument, _ -> Printf.sprintf "argument %d of `%s`" (rp.idx + 1) callee
               | Bound_expr, _ -> subject_noun
             in
             (* Point at the offending argument itself. The call span covers the
                whole expression, which on a multi-argument call underlines
                everything and singles out nothing. *)
             let labels =
               match subject, List.nth_opt args rp.idx with
               | Argument, Some a ->
                 let sp = arg_span span a in
                 if sp = span then []
                 else
                   [{ Err.lbl_span = sp;
                      Err.lbl_message =
                        Printf.sprintf "this argument must satisfy `%s`"
                          (pred_str rp.pred) }]
               | _ -> []
             in
             (* The inline example: prefer a witness-validated, shrunk,
                source-syntax assignment over the raw model rendering —
                fall back to the raw one whenever anything in the pipeline
                (an undecodable sort, an unevaluable path fact) refuses. *)
             let cx_str =
               let fallback () = format_cx (model_of first) in
               match subject, List.nth_opt args rp.idx with
               | Argument, Some arg ->
                 (match
                    Witness.confirm_precond ~sc ~path ~pred:rp.pred
                      ~binder:rp.binder ~arg ~model:(model_of first)
                  with
                  | Some entries ->
                    (match Witness.render_entries entries with
                     | Some s -> Printf.sprintf " (e.g. %s)" s
                     | None -> fallback ())
                  | None -> fallback ())
               | _ -> fallback ()
             in
             Err.report errctx
               { Err.severity = Err.Error; span;
                 message = Printf.sprintf
                   "refinement violation: %s does not satisfy %s `%s`%s\n%s"
                   param_label obligation_noun (pred_str rp.pred)
                   cx_str
                   (match subject with
                    | Argument ->
                      Printf.sprintf
                        "note: guard the call (e.g. `if %s do …`) or pass a value known to \
                         satisfy it"
                        (pred_str rp.pred)
                    | Bound_expr ->
                      "note: a refined annotation on a `let` is CHECKED against the \
                       expression it annotates, not assumed — bind a value that satisfies \
                       it, or weaken the annotation");
                 labels; notes = []; code = None; fix = None }
           | _ ->
             (* [!self_symbol] is what the CHECK runs against — see
                [mark_self]'s comment above [resolve_var].  [self_source_name]
                is what the MESSAGE prints — see its own comment.  Two
                different strings, on purpose: printing the symbol
                (`len$ys`) instead of the source name (`ys`) was round 3's
                review finding — a symbol that appears nowhere in the user's
                program, sent them looking for something that does not
                exist.

                [vc_for_diagnose], NOT [vc]: the unconstrained check must see
                only USER-derived assumptions, never the encoder's own
                well-formedness axioms about its own representation — see
                [user_assumptions]'s comment above.  [Refine.discharge]
                already ran against the real [vc] (full assumption set,
                correctly) before this arm is ever reached; only the
                DIAGNOSIS, not the proof attempt, uses the narrowed one. *)
             let vc_for_diagnose = { vc with Smt.assumptions = user_assumptions } in
             (* Before filing a skip: try to PROMOTE this to a demonstrated
                failure.  A model consistent with everything the checker knows
                may still describe an unreachable state — the assumption set is
                an over-approximation, and the missing fact is by definition
                not in it (`List.last`'s `t = Nil` is the worked example).  So
                this does not TRUST the model: it uses it to propose arguments
                for the ENCLOSING function, runs that function from its entry,
                and promotes only on an observed panic that repairing the
                subject removes.  Reachability is demonstrated, never assumed.

                [Bound_expr] is excluded: there is no callee whose requirement
                the enclosing function could be propagating, so the sentence
                below would not be true of it. *)
             let promoted =
               match subject, !enclosing_fn, model_of first with
               | Argument, Some fd, (_ :: _ as model) ->
                 (match List.nth_opt args rp.idx with
                  | Some arg ->
                    Option.map
                      (fun r -> (fd, r))
                      (Witness.confirm_precond_reachable ~fn:fd ~pred:rp.pred
                         ~binder:rp.binder ~arg ~model)
                  | None -> None)
               | _ -> None
             in
             (match promoted with
              | Some (fd, (wargs, panic_msg)) ->
                (* The ledger records a DECIDED verdict, not a skip: a failure
                   that was executed and observed is not an incompleteness, and
                   `--refine-report` must not count it as one.  [note]'s
                   `@[trusted]` and `cap verified` branches both key on
                   [Skipped], so a promotion flows through neither — the
                   severity choice below is the only report, made exactly
                   once. *)
                note Obligation.Violated;
                (* Rendered in source syntax: the reader has to be able to
                   paste the call back into their program. *)
                let call =
                  match Witness.render_call fd.A.fn_name.A.txt wargs with
                  | Some c -> c
                  | None -> "this call"
                in
                (* What is DEMONSTRATED is that the enclosing function panics
                   on an input violating the callee's requirement, and that
                   repairing that input removes the panic — NOT that the callee
                   raised the panic.  [Eval_error] carries no identity, so that
                   stronger claim is not available; do not reword this into
                   "the call to `%s` panics".  Hard-wrapped near 78 columns:
                   the renderer does not reflow. *)
                let text =
                  Printf.sprintf
                    "`%s` propagates a requirement it doesn't declare.\n\n\
                     `%s` requires  %s\n\
                     but %s panics — \"%s\""
                    fd.A.fn_name.A.txt callee (pred_str rp.pred) call panic_msg
                in
                (* Warning by default: "propagates an undeclared requirement"
                   is a design choice a user is allowed to make, and nearly
                   every unrefined wrapper around a panicking function is in
                   that category.  `cap verified` is the established opt-in for
                   turning unverifiable obligations into errors. *)
                if !strict_verified then Err.error errctx ~span text
                else Err.warning errctx ~span text
              | None ->
               (* [Partial_conjunct]: the goal is a top-level conjunction and the
                  whole-goal discharge above failed both ways.  Flatten the
                  goal's `&&` spine, pair each SMT conjunct with the source
                  fragment it came from, and discharge each SEPARATELY against
                  the FULL assumption set — [vc], the same one the whole-goal
                  proof attempt above used, not [vc_for_diagnose]'s narrowed
                  one, since this is a real proof attempt per conjunct, not a
                  diagnosis.  Only meaningful when the two spines line up in
                  length: if reflection reassociated or dropped a conjunct the
                  pairing is wrong, and quoting the user a fragment that does
                  not correspond to the conjunct tested is worse than the vague
                  message. *)
               let rec spine = function
                 | Smt.And (a, b) -> spine a @ spine b
                 | t -> [ t ]
               in
               let rec pred_spine (e : A.expr) =
                 match e with
                 | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) ->
                   pred_spine a @ pred_spine b
                 | e -> [ e ]
               in
               let goal_parts = spine goal and pred_parts = pred_spine rp.pred in
               let partial =
                 if List.length goal_parts < 2
                    || List.length goal_parts <> List.length pred_parts
                 then None
                 else
                   let judged =
                     List.map2
                       (fun g p ->
                         let holds =
                           Refine.discharge ~root ~preamble { vc with Smt.goal = g }
                           = Refine.Verified
                         in
                         (holds, pred_str p))
                       goal_parts pred_parts
                   in
                   let held = List.filter_map (fun (h, s) -> if h then Some s else None) judged
                   and missing =
                     List.filter_map (fun (h, s) -> if h then None else Some s) judged
                   in
                   (* Every conjunct failing is not "partial" — it is whatever
                      the syntactic diagnosis says. *)
                   if held = [] || missing = [] then None
                   else Some (Obligation.Partial_conjunct { held; missing })
               in
               note
                 (Obligation.Skipped
                    (match partial with
                     | Some r -> r
                     | None ->
                       (match
                          Undecided.diagnose ~subject_sym:!self_symbol
                            ~subject_name:self_source_name vc_for_diagnose
                        with
                        | Some r -> r
                        | None -> Obligation.Solver_undecided)))))))

