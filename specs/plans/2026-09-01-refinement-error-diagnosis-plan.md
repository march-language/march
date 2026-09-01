# Diagnosing the `solver-undecided` Bucket — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single undifferentiated `solver-undecided` refinement skip
with four diagnosed causes reported per site, and promote the sub-case that can
be *proven* a real failure — by executing the enclosing function from its entry
— to a warning carrying an inferred precondition fix.

**Architecture:** Four new `Obligation.reason` variants are computed lazily at
the existing fall-through in `check_call`, reached only after the positive
discharge has already failed, so a proved obligation pays nothing.  Three are
purely syntactic over the built `Smt.vc`; one costs extra Z3 queries.  The
promotion reuses `Witness`'s existing execute-and-observe machinery
(`decode_model` / `admissible` / `call_fn`), which already exists for the
return-contract path — the new part is keeping the `Panicked` result that
`violates_post` currently discards, and requiring the model to assign the
*enclosing function's own parameters* so reachability is demonstrated rather
than assumed.

**Tech Stack:** OCaml 5.3.0, dune, Z3 via `March_refine.Solver`, Alcotest.

## Global Constraints

- Opam switch is `march`; `dune` and `opam` are on PATH. **Never** use
  `eval $(opam env ...)`.
- This worktree is nested inside the main repo, so bare `dune build` resolves
  the WRONG root. Every dune command in this plan uses `--root .`.
- No new facts are derived. Let-bound constants are still not propagated into
  the path context; match-arm exclusions are still not derived. Any task that
  finds itself improving checker *precision* has left this plan's scope.
- No false positives. A promotion that reports a failure in correct code is a
  ship-blocking bug, not a tuning parameter.
- Existing `Obligation.reason` variants keep their exact slugs
  (`unreflectable-predicate`, `unreflectable-subject`, `sort-conflict`,
  `float-sort-gate`, `solver-undecided`, `alias-withdrawn`). New slugs only.
- Hint text is hard-wrapped near 78 columns. The renderer does not reflow.
- Never `git stash` in this repo — the stash stack is shared across worktrees.
- Never `git add -A` / `git add .`. Stage files explicitly by name.
- No `Co-Authored-By` trailers.
- Per CLAUDE.md: the `specs/todos/` → `specs/progress/` move and the
  `CHANGELOG.md` entry land in the same commit as the behavior change
  (Task 9).

---

### Task 1: Three syntactic reason variants

The zero-cost half of the taxonomy: causes readable straight off the built
`Smt.vc` with no extra solver work.

**Files:**
- Modify: `lib/refinecheck/obligation.ml:10-36` (the `reason` type),
  `:180-188` (`reason_name`), `:199-206` (`reason_detail`)
- Create: `lib/refinecheck/undecided.ml` — the detection helpers
- Modify: `lib/refinecheck/dune` (add `undecided` if modules are listed
  explicitly; check first — the library may use whole-directory inclusion)
- Test: `test/test_refinecheck.ml` (append to `reason_suite`, near `:4186`)

**Interfaces:**
- Consumes: `March_refine.Smt.{term, vc, sort}` (`lib/refine/smt.ml:20-72`)
- Produces:
  - `Obligation.Unconstrained_subject of string`
  - `Obligation.Nonlinear_goal`
  - `Obligation.Opaque_application of string`
  - `Undecided.diagnose : subject_sym:string option -> Smt.vc -> Obligation.reason option`
    — returns `None` when no syntactic cause applies, so the caller falls
    through to Task 2 and then to `Solver_undecided`.

- [ ] **Step 1: Write the failing tests**

Append to `reason_suite` in `test/test_refinecheck.ml`. Each fixture pins
*which* variant fires — `skip_reasons` (`:4175`) returns the slug list.

```ocaml
    (* Nothing in scope mentions `n` at all, so no assumption constrains it.
       This is the single most common shape in the corpus and used to be
       indistinguishable from a solver that merely ran out of road.
       Mutation that fails this: return `None` from [Undecided.diagnose]'s
       unconstrained branch — the slug reverts to "solver-undecided". *)
    gated "an unconstrained subject is diagnosed, not filed solver-undecided"
      (fun () ->
        let rs =
          skip_reasons
            {|mod UD1 do
  fn take_n(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do take_n(k) end
end|}
        in
        Alcotest.(check (list string)) "unconstrained-subject"
          [ "unconstrained-subject" ] rs);

    (* CONTROL for the above: the same call with a fact about `k` in scope is
       NOT unconstrained.  Without this control the test above passes even if
       [diagnose] returns Unconstrained_subject unconditionally, which would
       mislabel every skip in the compiler. *)
    gated "a constrained-but-undecided subject is not called unconstrained"
      (fun () ->
        let rs =
          skip_reasons
            {|mod UD1b do
  fn take_n(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do
    if k > -5 do take_n(k) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "not unconstrained" false
          (List.mem "unconstrained-subject" rs));

    (* A goal multiplying two unknowns leaves LIA, where z3 is complete, for a
       fragment where it is not.  The user's predicate is fine; the checker is
       incomplete, and saying so is different advice from "guard the call". *)
    gated "a non-linear goal is diagnosed as such" (fun () ->
        let rs =
          skip_reasons
            {|mod UD2 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(a : Int, b : Int) : Int do pos(a * b) end
end|}
        in
        Alcotest.(check (list string)) "nonlinear-goal" [ "nonlinear-goal" ] rs);
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL. The first and third report `["solver-undecided"]` against
expected `["unconstrained-subject"]` / `["nonlinear-goal"]`. The second (a
control) PASSES already — that is correct and expected; it only becomes
load-bearing after Step 3.

- [ ] **Step 3: Add the reason variants**

In `lib/refinecheck/obligation.ml`, after the `Solver_undecided` line (`:15`):

```ocaml
  (* Refinements of [Solver_undecided], split out because they are four
     different pieces of advice.  The residual keeps the old constructor: a
     reason we cannot name must not be dressed up as one we can.

     Payload discipline follows [Alias_withdrawn]: the NAME rides in the
     detail, not the slug, so `--refine-report` groups all unconstrained
     subjects into one bucket instead of one bucket per variable. *)
  | Unconstrained_subject of string  (* the subject appears in no assumption *)
  | Nonlinear_goal                   (* goal leaves linear arithmetic *)
  | Opaque_application of string     (* goal names an undeclared function symbol *)
```

Extend `reason_name` (`:180`):

```ocaml
  | Unconstrained_subject _ -> "unconstrained-subject"
  | Nonlinear_goal -> "nonlinear-goal"
  | Opaque_application _ -> "opaque-application"
```

Extend `reason_detail` (`:199`):

```ocaml
  | Unconstrained_subject name ->
    Printf.sprintf "nothing in scope constrains `%s`" name
  | Nonlinear_goal ->
    "the goal multiplies or divides two unknowns, which leaves the arithmetic \
     fragment the solver decides completely"
  | Opaque_application name ->
    Printf.sprintf
      "the checker has no meaning for `%s`, so it cannot reason through it" name
```

`reason_name` and `reason_detail` are the only exhaustive matches on `reason`
in `lib/`, `bin/`, `lsp/` and `forge/` — verified by grep. `bin/main.ml`'s
`print_refine_report` keys a `Hashtbl` on the whole reason and needs no change.

- [ ] **Step 4: Write the detection helpers**

Create `lib/refinecheck/undecided.ml`:

```ocaml
(* Diagnosing WHY an obligation was not decided.

   Reached only from [Refine_call.check_call]'s fall-through, after the
   positive discharge has already failed — so nothing here is on the happy
   path and none of it costs a proved obligation anything.

   Everything in this file is syntactic over the built [Smt.vc].  The one
   diagnosis that costs solver time ([Partial_conjunct]) lives in
   [Refine_call] instead, because it needs [Refine.discharge] and the
   preamble, neither of which belongs in a pure analysis module. *)

module Smt = March_refine.Smt

(* Every symbol a term mentions, as [Const] names and [App] heads kept apart:
   a `Const` is a value the VC declares, an `App` head is a FUNCTION symbol
   that the preamble either axiomatised or did not. *)
let rec consts (t : Smt.term) : string list =
  match t with
  | Smt.Const n -> [ n ]
  | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> []
  | Smt.App (_, ts) -> List.concat_map consts ts
  | Smt.IsCtor (_, a) | Smt.Neg a | Smt.Not a -> consts a
  | Smt.MulLit (_, a) -> consts a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b)
  | Smt.FpGt (a, b) | Smt.FpGe (a, b) -> consts a @ consts b

let rec app_heads (t : Smt.term) : string list =
  match t with
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> []
  | Smt.App (f, ts) -> f :: List.concat_map app_heads ts
  | Smt.IsCtor (_, a) | Smt.Neg a | Smt.Not a -> app_heads a
  | Smt.MulLit (_, a) -> app_heads a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b)
  | Smt.FpGt (a, b) | Smt.FpGe (a, b) -> app_heads a @ app_heads b

(* [Mul] is the general (possibly non-linear) product; [MulLit] is the linear
   one and is deliberately NOT a hit.  See the constructor comments in
   lib/refine/smt.ml — the driver emits no `(set-logic)`, so z3 decides many
   [Mul] goals instantly; this is a diagnosis of a LIKELY cause, offered only
   once the solver has already declined. *)
let rec nonlinear (t : Smt.term) : bool =
  match t with
  | Smt.Mul (_, _) -> true
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> false
  | Smt.App (_, ts) -> List.exists nonlinear ts
  | Smt.IsCtor (_, a) | Smt.Neg a | Smt.Not a | Smt.MulLit (_, a) -> nonlinear a
  | Smt.Add (a, b) | Smt.Sub (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b)
  | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b)
  | Smt.FpGt (a, b) | Smt.FpGe (a, b) -> nonlinear a || nonlinear b

(* Ordered most-specific-first.  [subject_sym] is the SMT symbol the checked
   ACTUAL reflected to, or [None] when the actual is not a bare symbol (an
   arbitrary expression has no single name to report as unconstrained). *)
let diagnose ~(subject_sym : string option) (vc : Smt.vc) : Obligation.reason option =
  let declared = List.map fst vc.Smt.decls in
  let goal_heads = List.sort_uniq compare (app_heads vc.Smt.goal) in
  match List.find_opt (fun f -> not (List.mem f declared)) goal_heads with
  | Some f -> Some (Obligation.Opaque_application f)
  | None ->
    if nonlinear vc.Smt.goal then Some Obligation.Nonlinear_goal
    else
      match subject_sym with
      | Some s
        when not
               (List.exists (fun a -> List.mem s (consts a)) vc.Smt.assumptions) ->
        Some (Obligation.Unconstrained_subject s)
      | _ -> None
```

Check `lib/refinecheck/dune` for an explicit `(modules ...)` field. If present,
add `undecided`; if absent, the directory is included whole and no edit is
needed.

- [ ] **Step 5: Wire it into the fall-through**

In `lib/refinecheck/refine_call.ml`, replace the final arm at `:1919`:

```ocaml
           | _ ->
             let subject_sym =
               match List.nth_opt args rp.idx with
               | Some (A.EVar { A.txt = x; _ }) -> Some x
               | _ -> None
             in
             note
               (Obligation.Skipped
                  (match Undecided.diagnose ~subject_sym vc with
                   | Some r -> r
                   | None -> Obligation.Solver_undecided)))))
```

`vc` is already in scope at this point (bound at `:1813`).

**Note on the symbol namespace:** `subject_sym` is the SOURCE name, while
`vc.decls` may carry caller-namespaced spellings — see the `caller_scalar`
table and the caller-namespace producers around `:700-760`. If the
unconstrained test fails because the names do not match, resolve the actual
through the same namespacing the VC builder used rather than loosening the
comparison; a substring match here would silently mislabel.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS, all three new cases plus the whole pre-existing suite. Any
pre-existing `reason_suite` case that now reports a new slug instead of
`solver-undecided` is a **legitimate** change — update its expectation and say
so in the commit message. A case that changes to a *different* new slug than
you predicted is a bug in `diagnose`'s ordering, not an expectation to update.

- [ ] **Step 7: Commit**

```bash
git add lib/refinecheck/obligation.ml lib/refinecheck/undecided.ml lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: split three syntactic causes out of solver-undecided

Unconstrained subject, non-linear goal and opaque application are readable
straight off the built VC. Solver_undecided survives as the honest residual."
```

(Add `lib/refinecheck/dune` to the `git add` if Step 4 required editing it.)

---

### Task 2: `Partial_conjunct` — say which half is missing

The one diagnosis that costs solver time, and the highest-value one: the
`List.nth` shape, where half the bounds contract is established and the reader
is told nothing about which half.

**Files:**
- Modify: `lib/refinecheck/obligation.ml` (one variant, one `reason_name`
  arm, one `reason_detail` arm)
- Modify: `lib/refinecheck/refine_call.ml` (the fall-through from Task 1)
- Test: `test/test_refinecheck.ml` (`reason_suite`)

**Interfaces:**
- Consumes: `Undecided.diagnose` from Task 1; `Refine.discharge ~root ~preamble`
  and the `preamble` bound at `refine_call.ml:1839`
- Produces: `Obligation.Partial_conjunct of { held : string list; missing : string list }`
  — rendered predicate fragments, source syntax, in goal order

- [ ] **Step 1: Write the failing test**

```ocaml
    (* Half a bounds contract is established.  "the solver proved neither the
       predicate nor its negation" is true and useless; naming the surviving
       conjunct is the whole difference between advice and noise.
       Mutation that fails this: drop the per-conjunct discharge and return
       Unconstrained_subject — `i` IS constrained here, by the guard. *)
    gated "a partially established conjunction names the missing half"
      (fun () ->
        let rs =
          skip_reasons
            {|mod UD3 do
  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do 0 end
  fn go(xs : List(Int), i : Int) : Int do
    if i >= 0 do at(xs, i) else 0 end
  end
end|}
        in
        Alcotest.(check (list string)) "partial-conjunct" [ "partial-conjunct" ] rs);
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL, reporting `["solver-undecided"]` (the goal's `len(xs)` App head
IS declared by the measure preamble, so Task 1's `Opaque_application` correctly
does not fire, and `i` IS constrained by the guard so `Unconstrained_subject`
correctly does not fire).

- [ ] **Step 3: Add the variant**

`lib/refinecheck/obligation.ml`, alongside Task 1's variants:

```ocaml
  (* Payload is rendered SOURCE syntax, not SMT: it goes straight into user
     text.  Both lists are kept because "`i >= 0` holds" and "`i < len(xs)`
     does not" are both load-bearing — the first tells the reader their guard
     worked and stops them rewriting it. *)
  | Partial_conjunct of { held : string list; missing : string list }
```

```ocaml
  | Partial_conjunct _ -> "partial-conjunct"
```

```ocaml
  | Partial_conjunct { held; missing } ->
    Printf.sprintf "%s established here; %s not"
      (String.concat " and " (List.map (Printf.sprintf "`%s`") held))
      (String.concat " and " (List.map (Printf.sprintf "`%s`") missing))
```

- [ ] **Step 4: Split and discharge per conjunct**

In `refine_call.ml`'s fall-through, BEFORE calling `Undecided.diagnose` (this
diagnosis is more specific than all three syntactic ones):

```ocaml
             (* Flatten the goal's top-level `&&` spine, and pair each SMT
                conjunct with the source fragment it came from so the message
                can quote the user's own syntax.  A non-conjunction flattens
                to a single element and is skipped below. *)
             let rec spine = function
               | Smt.And (a, b) -> spine a @ spine b
               | t -> [ t ]
             in
             let rec pred_spine (e : A.expr) =
               match e with
               | A.EBinop ({ A.txt = "&&"; _ }, a, b) -> pred_spine a @ pred_spine b
               | e -> [ e ]
             in
             let goal_parts = spine goal and pred_parts = pred_spine rp.pred in
             let partial =
               (* Only meaningful when the two spines line up: if reflection
                  reassociated or dropped anything the pairing is wrong, and a
                  wrong quote is worse than a vague message. *)
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
                 and missing = List.filter_map (fun (h, s) -> if h then None else Some s) judged in
                 (* Every conjunct failing is not "partial" — it is whatever
                    the syntactic diagnosis says.  All holding is impossible
                    here (the whole goal failed), but guard it anyway rather
                    than emit an empty `missing`. *)
                 if held = [] || missing = [] then None
                 else Some (Obligation.Partial_conjunct { held; missing })
             in
```

Then make the reason selection prefer it:

```ocaml
             note
               (Obligation.Skipped
                  (match partial with
                   | Some r -> r
                   | None ->
                     (match Undecided.diagnose ~subject_sym vc with
                      | Some r -> r
                      | None -> Obligation.Solver_undecided)))
```

Confirm `pred_str` and the AST spelling of `&&` against the file before
compiling — `A.EBinop`'s operator representation is what the parser produces,
and `pred_str` is already used at `:1904` for user-facing text.

- [ ] **Step 5: Run to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS. Also confirm Task 1's three cases still report their own slugs
— `partial` is tried first and must not swallow them.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/obligation.ml lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: diagnose partially established conjunctions

Discharges each top-level conjunct separately when the whole goal failed, so
a half-established bounds contract names the surviving half."
```

---

### Task 3: Report diagnosed causes per site

The diagnosis is worthless while the hint is throttled to once per module —
`stdlib/list.march`'s five user-code skips currently produce one hint, for
whichever fired first.

**Files:**
- Modify: `lib/refinecheck/refine_call.ml:681-701` (the hint branch)
- Modify: `test/test_refinecheck.ml:209-219` (the existing throttle test)
- Test: `test/test_refinecheck.ml` (new cases beside it)

**Interfaces:**
- Consumes: `Obligation.reason` including all four new variants
- Produces: no new API; changes emission volume only

- [ ] **Step 1: Update the existing throttle test and add its counterpart**

The case at `:210` ("the unverified hint is emitted at most once per module")
uses `take_n(k)` with `k : Int` unconstrained — which is now
`Unconstrained_subject`, and must report at every site. Rewrite it as a PAIR,
so both halves of the new rule are pinned:

```ocaml
    (* A DIAGNOSED cause is specific and actionable, so it reports at every
       site.  The throttle exists to stop a vague message repeating; it must
       not also suppress three different pieces of real advice. *)
    gated "a diagnosed cause is reported at every site" (fun () ->
        let hints =
          refine_hints
            (decl
               "  fn f(k : Int) : Int do take_n(k) end\n\
               \  fn g(k : Int) : Int do take_n(k) end\n\
               \  fn h(k : Int) : Int do take_n(k) end") in
        Alcotest.(check int) "one hint per site" 3
          (List.length
             (List.filter (fun h -> contains h "was NOT verified here") hints)));

    (* …and the residual keeps the throttle, because repeating "the solver
       proved neither" three times is exactly the noise it was added for.
       This fixture must produce a BARE solver-undecided; if the taxonomy ever
       learns to diagnose it, this test starts failing and the right fix is a
       new fixture, not deleting the throttle. *)
    gated "the residual solver-undecided hint stays once per module" (fun () ->
        let src =
          {|mod UD4 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn f(a : Int, b : Int) : Int do if a > b do pos(a - b) else 1 end end
  fn g(a : Int, b : Int) : Int do if a > b do pos(a - b) else 1 end end
end|}
        in
        Alcotest.(check (list string)) "the fixture is a bare residual"
          [ "solver-undecided"; "solver-undecided" ] (skip_reasons src);
        Alcotest.(check int) "exactly one hint" 1
          (List.length
             (List.filter (fun h -> contains h "was NOT verified here")
                (refine_hints src))));
```

The `UD4` fixture is a hypothesis about what z3 declines to decide. Run
`skip_reasons` on it FIRST (Step 2 shows both assertions); if it reports
`partial-conjunct` or proves outright, replace it with a fixture that genuinely
lands in the residual rather than weakening the assertion. The first assertion
exists precisely so this cannot pass for the wrong reason.

- [ ] **Step 2: Run to verify the new expectations fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: the "every site" case FAILS with 1 against expected 3. The residual
case's first assertion tells you whether `UD4` is the fixture you need before
you touch any source.

- [ ] **Step 3: Throttle only the residual**

In `refine_call.ml`, the branch at `:681`. Today's guard is
`(not !strict_verified) && (not !unverified_hinted) && (r is not Alias_withdrawn)`.
Replace the throttle term with a per-reason decision:

```ocaml
    (* Per-site for a DIAGNOSED cause, once-per-module for the residual.
       The throttle's rationale — "advice repeated per call site would be
       worse than silence" — is about a message that says the same thing
       everywhere.  `nothing in scope constrains n` and "`i >= 0` holds but
       `i < len(xs)` does not" are different facts about different calls, and
       suppressing the second because the first already printed is a bug. *)
    | Obligation.Skipped r
      when (not !strict_verified)
           && (match r with
               | Obligation.Alias_withdrawn _ -> false
               | Obligation.Unconstrained_subject _
               | Obligation.Nonlinear_goal
               | Obligation.Opaque_application _
               | Obligation.Partial_conjunct _ -> true
               | _ -> not !unverified_hinted) ->
      (match r with
       | Obligation.Solver_undecided
       | Obligation.Unreflectable_predicate
       | Obligation.Unreflectable_subject
       | Obligation.Sort_conflict
       | Obligation.Float_sort_gate -> unverified_hinted := true
       | _ -> ());
```

Note the `match` is written with every constructor named and **no wildcard on
the diagnosed side** — the same discipline as `visit_decl`'s decl walk. A new
reason added later must be classified deliberately, not defaulted.

Then split the message body. The diagnosed variants get the specific text and
drop the `cap verified` boilerplate paragraph, which is module-level advice
that does not bear repeating per site:

```ocaml
      let body =
        match r with
        | Obligation.Unconstrained_subject _
        | Obligation.Nonlinear_goal
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
          (* Byte-for-byte today's text: reason slug, reason_detail, and the
             cap-verified paragraph, hard-wrapped near 78 columns.  Move the
             existing Printf.sprintf from :688-701 here unchanged — retyping it
             is how a wording change sneaks in and breaks @types-check, which
             pins diagnostic TEXT and runs only in CI. *)
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
```

Keep the existing hard wrap near 78 columns; the renderer does not reflow.

- [ ] **Step 4: Run to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS. The `decl`-based fixtures elsewhere in the suite that assert on
hint COUNTS may move; each one that does is a legitimate change from this
task's rule and its expectation should be updated with a one-line comment
saying which side of the rule it lands on.

- [ ] **Step 5: Check the message end-to-end by eye**

```bash
dune build --root . bin/main.exe
printf 'mod M do\n  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do 0 end\n  fn go(xs : List(Int), i : Int) : Int do\n    if i >= 0 do at(xs, i) else 0 end\n  end\nend\n' > /tmp/ud-de2bdc.march
./_build/default/bin/main.exe --check /tmp/ud-de2bdc.march
```

Expected: a hint naming which conjunct held and which did not, wrapped within
78 columns, with no `cap verified` paragraph.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: report diagnosed skip causes at every call site

The once-per-module throttle exists to stop a vague message repeating; it now
applies only to the residual reasons, not to the four diagnosed ones."
```

---

### Task 4: Plumb the enclosing function to the call site

`call_ctx` carries no enclosing-function identity, and the promotion in Task 6
cannot demonstrate reachability without one.

**Files:**
- Modify: `lib/refinecheck/refine_call.ml:66-72` (module-level refs),
  `:10-25` (the header note listing them)
- Modify: `lib/refinecheck/refine_check.ml:886-906` (`visit_fn`)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Produces: `Refine_call.enclosing_fn : March_ast.Ast.fn_def option ref` —
  the function whose body is currently being walked, or `None` outside one.

- [ ] **Step 1: Write the failing test**

The ref is internal, so pin it through an observable: a promotion cannot fire
without it, and Task 6 depends on it. Add a direct unit assertion now so the
plumbing is testable on its own:

```ocaml
    (* The enclosing function must be restored on the way out, or a sibling
       decl inherits a stale identity and the promotion in Task 6 executes the
       WRONG function.  Save/restore mirrors [trusted_fn]. *)
    gated "enclosing_fn is None outside any function body" (fun () ->
        ignore (has_refine_error_d
          {|mod EF1 do
  fn take_n(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do take_n(k) end
end|});
        Alcotest.(check bool) "restored to None after the walk" true
          (!March_refinecheck.Refine_call.enclosing_fn = None));
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL to COMPILE — `enclosing_fn` is unbound. That is the correct
failure for this step.

- [ ] **Step 3: Add the ref**

`lib/refinecheck/refine_call.ml`, beside `trusted_fn` at `:72`:

```ocaml
(* The function whose body is being walked, set and restored by [visit_fn]
   exactly as [trusted_fn] is.  A ref rather than a [call_ctx] field because
   it is not a fact channel: it never shadows, never retires on rebinding, and
   adding it to the record would touch all three construction sites in
   refine_check.ml for a value none of them varies. *)
let enclosing_fn : A.fn_def option ref = ref None
```

Update the header note at `:15` to list four module-level refs rather than
three.

- [ ] **Step 4: Set and restore it**

`lib/refinecheck/refine_check.ml`, in `visit_fn`, extending the existing
`Fun.protect` at `:903` rather than adding a second one:

```ocaml
  let saved_trusted = !trusted_fn in
  let saved_enclosing = !enclosing_fn in
  trusted_fn := is_trusted;
  enclosing_fn := Some fd;
  Fun.protect
    ~finally:(fun () ->
      trusted_fn := saved_trusted;
      enclosing_fn := saved_enclosing)
    (fun () ->
```

Note `visit_fn` takes `?(assume_params = true)` and is called with
`assume_params:false` for `impl` methods whose contract could not be adopted
(`:875-885`). `fd` there is the ORIGINAL definition, which is the right value
to execute — the stripping affects what may be assumed, not what the function
is.

- [ ] **Step 5: Run to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_call.ml lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "refine: track the enclosing function during the decl walk

Scoped save/restore in visit_fn, mirroring trusted_fn. Needed to demonstrate
reachability for call-site witness promotion."
```

---

### Task 5: `Witness.confirm_precond_reachable`

The soundness core. **Read `specs/2026-09-01-refinement-error-diagnosis-design.md`
§2 before writing any code in this task** — the obvious implementation (reuse
`confirm_precond`) is unsound, and the reason is subtle.

`confirm_precond`'s `ok` (`witness.ml:837`) validates a candidate against the
*recorded* path facts. When the reason for undecidedness is a missing fact,
that fact is by definition not recorded, so a candidate violating it passes.
`stdlib/list.march:128` is the counterexample: `t = Nil` satisfies every
recorded fact in `last`'s `Cons(_, t)` arm, and the arm exclusion that rules it
out is exactly what the checker never derived.

The gate is to execute the **enclosing function from its entry** and observe an
actual panic. Reachability is then demonstrated, not assumed.

**Files:**
- Modify: `lib/refinecheck/witness.ml` (new function after `violates_post`,
  `:557-566`)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Consumes: `Witness.{decode_model, admissible, annotated_params, call_fn,
  shrink, render_entries}`, `exec_result = Ret | Panicked of string | Unconfirmable`
- Produces:
  `Witness.confirm_precond_reachable : fn:March_ast.Ast.fn_def -> model:(string * string) list -> ((string * V.value) list * string) option`
  — the shrunk argument assignment for `fn`'s own parameters, paired with the
  panic message, or `None`.

- [ ] **Step 1: Write the failing tests — the negative one first**

**This is the most important test in the plan.** It asserts SILENCE, and an
accept-only fixture cannot distinguish "correctly declining" from "promotion
path is dead".

```ocaml
    (* THE false-positive guard.  `List.last`'s recursive call is safe because
       the previous arm rules out the singleton — a fact the checker does not
       derive, so the model happily assigns `t = Nil`.  Confirming that model
       against RECORDED path facts "proves" a failure in correct code.
       Executing `last` from its entry cannot: `t` is a match binder, not a
       parameter, and `last`'s own contract excludes every `xs` that would
       reach the call with `t = Nil`.

       Asserts SILENCE.  An accept-only fixture here passes whether the gate
       declines correctly or the whole promotion path is dead. *)
    gated "a safe recursive call is not promoted (List.last shape)" (fun () ->
        let src =
          {|mod W1 do
  fn last(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil          -> 0
    Cons(x, Nil) -> x
    Cons(_, t)   -> last(t)
    end
  end
end|}
        in
        Alcotest.(check int) "no warnings" 0
          (List.length (refine_warnings src));
        Alcotest.(check bool) "no errors" false (has_refine_error_d src));

    (* The positive: an unrefined parameter passed straight into a refined one.
       `go([])` is a real, reachable panic and the model assigns `ys` — a
       PARAMETER of the enclosing function — so execution can demonstrate it. *)
    gated "an unconstrained parameter reaching a panic is promoted" (fun () ->
        let src =
          {|mod W2 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil        -> panic("empty")
    Cons(h, _) -> h
    end
  end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}
        in
        Alcotest.(check int) "exactly one warning" 1
          (List.length (refine_warnings src));
        Alcotest.(check bool) "and it is not an error by default" false
          (has_refine_error_d src));
```

Two more, pinning the DECLINE paths. Both assert silence, for the same reason
`W1` does: a promotion path that declines for the wrong reason is
indistinguishable from one that declines for the right one unless the fixtures
separate them.

```ocaml
    (* An effectful enclosing function cannot be executed under the veto, so
       no panic can be observed and nothing is promoted.  Without this the
       veto could be removed and every test above would still pass. *)
    gated "an effectful enclosing function is not promoted" (fun () ->
        let src =
          {|mod W5 do
  needs IO.Console
  fn head(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil        -> panic("empty")
    Cons(h, _) -> h
    end
  end
  fn go(ys : List(Int)) : Int do
    print("side effect")
    head(ys)
  end
end|}
        in
        Alcotest.(check int) "no warnings" 0 (List.length (refine_warnings src)));

    (* A subject that is a LET-BOUND temporary rather than a parameter: the
       model assigns `n`, which `decode_model` cannot map onto `go`'s own
       parameters, so there is nothing admissible to execute.  This is the
       same mechanism that makes the List.last shape decline, exercised
       without recursion so a failure here localises. *)
    gated "a let-bound subject is not promoted" (fun () ->
        let src =
          {|mod W6 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do
    let n = k - k
    pos(n)
  end
end|}
        in
        Alcotest.(check int) "no warnings" 0 (List.length (refine_warnings src)));
```

`refine_warnings` does not exist yet. Add it beside `refine_hints` (`:111`),
identical but filtering `Warning`:

```ocaml
let refine_warnings src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx
    (March_desugar.Desugar.desugar_module (parse src));
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Warning
      then Some d.March_errors.Errors.message else None)
    ctx.March_errors.Errors.diagnostics
```

- [ ] **Step 2: Run to verify they fail correctly**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: the `W1` negative case PASSES already (nothing is promoted yet — it
is a regression guard, and it must stay green through Tasks 5 and 6). The `W2`
positive case FAILS with 0 warnings against expected 1. **If `W1` ever goes red
in a later task, stop and fix the gate — do not adjust the fixture.**

- [ ] **Step 3: Implement the reachable confirmation**

In `lib/refinecheck/witness.ml`, after `violates_post` (`:566`):

```ocaml
(* Confirm a call-site precondition failure by DEMONSTRATING reachability:
   run the enclosing function on arguments the model assigns to its own
   parameters and observe an actual panic.

   Contrast [confirm_precond], which evaluates the predicate under an
   assignment validated against the RECORDED path facts.  That is sound where
   the solver already settled the verdict, and unsound here: the undecided
   bucket is populated precisely by MISSING facts, and a missing fact is not
   in [path] to be checked against.  See the design doc §2.

   Three things must hold and none is assumed:
     - the model assigns the enclosing function's own PARAMETERS (a match
       binder or a let-bound temporary is not one, which is what makes the
       List.last shape decline),
     - those arguments are admissible under the function's OWN refinements
       (else we would blame a caller for an input the function never promised
       to accept), and
     - executing it actually panics. *)
let confirm_precond_reachable ~(fn : A.fn_def) ~(model : (string * string) list)
    : ((string * V.value) list * string) option =
  match fn.A.fn_clauses with
  | [ clause ] ->
    (match annotated_params clause.A.fc_params with
     | None -> None
     | Some params ->
       (match decode_model ~params model with
        | None -> None
        | Some args ->
          if not (admissible ~params args) then None
          else
            let panic_of cand =
              match call_fn ~name:fn.A.fn_name.A.txt ~args:(List.map snd cand) with
              | Panicked msg -> Some msg
              | Ret _ | Unconfirmable -> None
            in
            (match panic_of args with
             | None -> None
             | Some _ ->
               (* Shrink with the same oracle, then re-read the panic from the
                  shrunk candidate: a smaller input may panic in a different
                  place, and quoting the original message beside the shrunk
                  arguments would be a lie. *)
               let run cand =
                 if admissible ~params cand then
                   Option.map (fun _ -> V.VUnit) (panic_of cand)
                 else None
               in
               let shrunk, _ = shrink ~run args V.VUnit in
               Option.map (fun msg -> (shrunk, msg)) (panic_of shrunk))))
  (* A multi-head function is several clauses after desugar; executing it is
     still well defined, but which clause the panic came from is not, and the
     message would have to guess.  Decline rather than guess. *)
  | _ -> None
```

Check the field names `fn_clauses` / `fc_params` / `fn_name` against
`lib/ast/ast.ml` before compiling — `visit_fn` at `refine_check.ml:909`
iterates `c.A.fc_params`, which confirms the inner spelling.

`decode_model` (`:210`) takes `~params` and the model; confirm its exact
signature and whether it needs the `len_fact` helper threaded for list-typed
parameters. `zero_value` fills don't-cares, and `admissible` is what rejects
the ones the contract excludes.

- [ ] **Step 4: Run to verify `W1` is still green**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: `W1` PASSES (still nothing promoted — Task 6 does the wiring), the
whole suite green. `W2` still fails; that is Task 6.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/witness.ml test/test_refinecheck.ml
git commit -m "witness: confirm call-site failures by executing the enclosing fn

Reachability is demonstrated rather than assumed: the model must assign the
enclosing function's own parameters, they must be admissible under its own
refinements, and execution must actually panic. confirm_precond validates
against recorded path facts, which is unsound in the undecided bucket where
the missing fact is by definition unrecorded."
```

---

### Task 6: Wire the promotion

**Files:**
- Modify: `lib/refinecheck/refine_call.ml` (the fall-through, and the
  `strict_verified` escalation branch at `:660-676`)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Consumes: `Witness.confirm_precond_reachable` (Task 5),
  `Refine_call.enclosing_fn` (Task 4), `Undecided.diagnose` (Task 1),
  `Refine.discharge`'s `Sat` model accessor (`model_of first`, already used
  at `:1888`)

- [ ] **Step 1: Add the `cap verified` escalation test**

The `W2` case from Task 5 pins the default `Warning`. Add its strict
counterpart:

```ocaml
    (* Warning by default because "propagates an undeclared requirement" is a
       design choice a user may make; Error under `cap verified`, which is the
       established opt-in for turning unverifiable obligations into errors.
       Both halves are pinned: a promotion that is always an error would break
       every unrefined wrapper around a panicking stdlib function. *)
    gated "a promoted failure escalates to an error under cap verified"
      (fun () ->
        Alcotest.(check bool) "error under cap verified" true
          (has_refine_error_d
             {|mod W3 do
  cap verified
  fn head(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil        -> panic("empty")
    Cons(h, _) -> h
    end
  end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}));
```

Confirm `cap verified`'s exact surface spelling from an existing fixture in
the suite (`grep -n 'cap verified' test/test_refinecheck.ml`) rather than
trusting this snippet.

- [ ] **Step 2: Run to verify `W2` and `W3` fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: both FAIL. `W1` still green.

- [ ] **Step 3: Attempt promotion before filing a skip**

In `refine_call.ml`'s fall-through, before the `note (Obligation.Skipped …)`
from Tasks 1–2:

```ocaml
             (* A model consistent with everything the checker knows may still
                describe an unreachable state — the assumption set is an
                over-approximation.  So this does not TRUST the model: it uses
                it to propose arguments for the enclosing function and then
                runs that function to see what really happens. *)
             let promoted =
               match !enclosing_fn, model_of first with
               | Some fd, Some model ->
                 Witness.confirm_precond_reachable ~fn:fd ~model
               | _ -> None
             in
             match promoted with
             | Some (args, panic_msg) ->
               note Obligation.Violated;
               let call = Witness.render_call fd.A.fn_name.A.txt args in
               let text =
                 Printf.sprintf
                   "`%s` propagates a requirement it doesn't declare.\n\n\
                    `%s` requires  %s\n\
                    but %s panics — \"%s\""
                   fd.A.fn_name.A.txt callee (pred_str rp.pred)
                   (match call with Some c -> c | None -> "this call")
                   panic_msg
               in
               if !strict_verified then Err.error errctx ~span text
               else Err.warning errctx ~span text
             | None ->
               (* The Task 1 + Task 2 selection, unchanged: partial-conjunct
                  first, then the syntactic diagnoses, then the residual. *)
               note
                 (Obligation.Skipped
                    (match partial with
                     | Some r -> r
                     | None ->
                       (match Undecided.diagnose ~subject_sym vc with
                        | Some r -> r
                        | None -> Obligation.Solver_undecided)))
```

`model_of` is already defined and used at `:1888`; confirm whether it returns
an option or a list and adapt the pattern. `Witness.render_call` (`:408`) is
the existing renderer for `f(args)` in source syntax and returns an option.

Note `note Obligation.Violated` — the ledger records a *decided* verdict, not a
skip. That is deliberate: `--refine-report` must not count a demonstrated
failure as an incompleteness. Verify against `Obligation`'s doc comment at
`:38-47` that `Violated` is right here — it states `Trusted` must never be
produced from a `Violated`, which this respects.

- [ ] **Step 4: Check the `cap verified` branch does not double-report**

The escalation branch at `:660` turns `Skipped` into an error under
`strict_verified`. A promotion notes `Violated`, not `Skipped`, so it should
not also flow through there. Confirm by running `W3` and asserting **one**
diagnostic, not two:

```ocaml
    (* A promotion notes [Violated], not [Skipped], so it must not ALSO flow
       through the `cap verified` escalation at :660 and report twice.  A
       boolean cannot tell "reported once" from "reported twice", which is why
       this counts. *)
    gated "a promoted failure under cap verified reports exactly once"
      (fun () ->
        Alcotest.(check int) "one diagnostic, not a doubled report" 1
          (refine_error_count
             {|mod W3b do
  cap verified
  fn head(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil        -> panic("empty")
    Cons(h, _) -> h
    end
  end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}));
```

`refine_error_count` is the suite's existing error-counting helper — the header
comment at `test/test_refinecheck.ml:58` explains why a boolean is insufficient
("cannot tell 'both violations found' from 'one found, one silently lost'").
Grep for its actual name near `refine_hints` (`:111`) and use that; do not add
a second one.

- [ ] **Step 5: Run to verify all three pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: `W1` green (silence), `W2` green (one warning, no error), `W3` green
(one error). If `W1` went red, **stop**: the gate is unsound and no amount of
fixture adjustment fixes that.

- [ ] **Step 6: Check the real `List.last` — the fixture is a model, not the thing**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2 .march/cas/vc
./_build/default/bin/main.exe --check stdlib/list.march
```

Expected: no warning or error at `stdlib/list.march:128`. The `W1` fixture is a
hand-written approximation; this is the actual code that motivated the gate.

- [ ] **Step 7: Commit**

```bash
git add lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: promote reachability-confirmed call-site panics

Warning by default, error under cap verified. A model is used to propose
arguments for the enclosing function, never trusted as a verdict; only an
observed panic promotes."
```

---

### Task 7: Attach the inferred precondition as a fix

**Files:**
- Modify: `lib/refinecheck/refine_call.ml` (the promotion branch from Task 6)
- Read first: `lib/refinecheck/precond_infer.ml:1-33` (the module's contract
  and cost model), and its `status` type
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Consumes: `Precond_infer`'s entry point and `status` type — read the `.ml`
  for the exact signature; it needs the target function plus a pruned decl tree
  and runs `Refine_check.check_module` once beforehand
- Produces: no new API; populates the `Err` diagnostic's `fix` field

- [ ] **Step 1: Write the failing test**

```ocaml
    (* The message should end in the signature to write, not the panic to
       fear.  precond_infer is assume-and-recheck against the real checker,
       so a suggestion is correct by construction; it is affordable here
       precisely because promotion is rare. *)
    gated "a promoted failure suggests the precondition to declare" (fun () ->
        let ws =
          refine_warnings
            {|mod W4 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil        -> panic("empty")
    Cons(h, _) -> h
    end
  end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}
        in
        Alcotest.(check bool) "names the refinement to add" true
          (List.exists (fun w -> contains w "len(_) > 0" && contains w "ys") ws));
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL — the warning quotes the panic but suggests no signature.

- [ ] **Step 3: Collect promoted sites during the walk, suggest AFTER it**

**Do not call `Precond_infer.suggest` from inside `check_call`.** Its body is
`Ob.with_scratch @@ fun () -> …` (`precond_infer.ml:534-541`), which resets the
obligation ledger *and* the per-call-site index, and each probe re-enters
`Refine_check.check_module` on a pruned decl tree. Calling that mid-walk would
clobber the ledger the walk is populating and re-enter the module-level refs
(`strict_verified`, `trusted_fn`, `unverified_hinted`, and Task 4's
`enclosing_fn`) underneath their own save/restore frames. The module's own
header comment flags the ledger half of this hazard explicitly.

Instead, make the promotion branch record its site and emit the Task 6 message
unchanged, then run suggestion as a post-pass once the walk is over:

```ocaml
(* Promoted sites, drained by [check_module]'s epilogue.  Deferred rather than
   suggested inline because [Precond_infer.suggest] re-enters
   [Refine_check.check_module] under [Ob.with_scratch] — mid-walk that would
   reset the ledger this walk is filling and re-enter every module-level ref
   beneath its own save/restore frame. *)
let promoted_sites : (A.span * string) list ref = ref []
```

In the epilogue of `Refine_check.check_module`, after the decl walk completes,
drain it and upgrade each diagnostic in place:

```ocaml
  List.iter
    (fun (span, fn_name) ->
      let results =
        Precond_infer.suggest ~root ~is_user ~target:fn_name m
      in
      match results with
      | r :: _ ->
        (match r.Precond_infer.status with
         (* Only a proposal the checker itself verified discharges the debt is
            worth printing.  [Partial] leaves debt behind and would advertise a
            signature that does not fix the reported problem; the rest are not
            suggestions at all. *)
         | Precond_infer.Solved -> attach_fix ~span r.Precond_infer.suggestions
         | Precond_infer.Partial
         | Precond_infer.No_debt
         | Precond_infer.No_candidate
         | Precond_infer.Budget_exhausted
         | Precond_infer.Not_found -> ())
      | [] -> ())
    (List.rev !promoted_sites);
  promoted_sites := []
```

Every `status` constructor is named with no wildcard, deliberately: the type's
own comment explains that `Budget_exhausted` exists precisely so "nothing fits"
and "I stopped looking" are not conflated, and a wildcard would re-conflate
them here.

Read `Precond_infer.t` (the record `infer_fn` returns, `:403`) for the field
carrying the rendered suggestion, and the exact `suggest` labelled arguments —
`?root`, `?budget`, `~is_user`, `~target`, and the module. `~is_user` is a
span predicate; `check_module` already has whatever it uses to distinguish user
code from stdlib for `--refine-report`'s "user code" tally, so reuse that rather
than inventing a second notion.

Appending to the message on success:

```ocaml
                 Printf.sprintf
                   "%s\n\nhelp: declare what `%s` actually needs —\n        %s\n\
                    `forge fix` can apply this."
                   text fn_name rendered_signature
```

Populate `Err`'s `fix` field as well as the text. Follow the shape the
capability errors use — the `needs IO.Console` error in the design doc ends
"`forge fix` can apply this" and carries a machine-readable fix; a message that
advertises `forge fix` without one is worse than a message that does not.

- [ ] **Step 4: Guard the cost**

Confirm the added wall time is confined to promotion:

```bash
rm -rf .march/cas/artifacts-v2 .march/cas/vc
printf 'mod M do\n  fn f(x : Int) : Int do x + 1 end\nend\n' > /tmp/triv-de2bdc.march
time ./_build/default/bin/main.exe --check /tmp/triv-de2bdc.march
```

Expected: within noise of the pre-change compiler. #383 recorded 1.08s → 1.17s
and that budget is not infinite. If a trivial program got slower, `precond_infer`
is being reached off the promotion path.

- [ ] **Step 5: Run to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: suggest the missing precondition on a promoted failure

precond_infer runs only on promotion, where its cost is affordable, so the
message ends in the signature to write."
```

---

### Task 8: Measure

Numbers, not impressions. Both are deliverables; the second is a stop-ship
gate.

**Files:**
- Create: `specs/2026-09-01-refinement-error-diagnosis-measurements.md`

- [ ] **Step 1: Record the bucket distribution**

Run over the full corpus, not the six-module sample. Clear both caches first —
a warm `artifacts-v2` short-circuits before `--refine-report` prints anything,
producing an empty result that looks like "no skips".

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2 .march/cas/vc
for f in stdlib/*.march test/native/*.march; do
  ./_build/default/bin/main.exe --check --refine-report "$f" 2>&1
done | grep -oE "skipped \([a-z-]+\): [0-9]+" | sort | uniq -c | sort -rn
```

Record the table. Compare against the pre-change baseline (run the same
command on a build of `origin/main`). **If `solver-undecided` is still the
largest bucket, the taxonomy is wrong** — report that rather than shipping it,
and the four variants need revisiting before Task 9.

- [ ] **Step 2: Count and hand-audit every promotion**

```bash
for f in stdlib/*.march test/native/*.march; do
  ./_build/default/bin/main.exe --check "$f" 2>&1 \
    | grep -B2 -A6 "propagates a requirement it doesn't declare" \
    | sed "s|^|$f: |"
done | tee /tmp/promotions-de2bdc.txt
wc -l /tmp/promotions-de2bdc.txt
```

Read **every** promotion individually and record in the measurements file
whether each is a genuine latent panic. This number should be small. **If it is
large, the reachability gate is wrong — stop rather than ship.** A single false
positive here is a ship blocker, not a tuning parameter.

- [ ] **Step 3: Commit the measurements**

```bash
git add specs/2026-09-01-refinement-error-diagnosis-measurements.md
git commit -m "specs: bucket distribution and promotion audit for the undecided split"
```

---

### Task 9: Oracle, full suite, and the record

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]`)
- Move: `specs/todos/2026-09-01-refinement-solver-undecided-diagnosis.md` →
  `specs/progress/` (`git mv`)

- [ ] **Step 1: Prove the oracle RED-capable before trusting any GREEN**

`refine-oracle` will legitimately move here, so it is not a pass/fail gate —
but an oracle that cannot go red proves nothing either way, and two of the
three oracle scripts shipped broken. Perturb a verdict deliberately, confirm
red, revert.

```bash
mkdir -p /tmp/refine-base-de2bdc
scripts/refine-oracle.sh baseline /tmp/refine-base-de2bdc
# perturb: e.g. make check_call note Proved unconditionally at one site
dune build --root . bin/main.exe
scripts/refine-oracle.sh check /tmp/refine-base-de2bdc   # MUST be RED
git checkout lib/refinecheck/refine_call.ml && dune build --root . bin/main.exe
```

Baseline from `origin/main`, not from this branch — see the CLAUDE.md note on
`git merge origin/main` vs a stale `main` ref. `/tmp` is shared across
worktrees, hence the `-de2bdc` suffix. The script runs under a private `HOME`
already; do not override it.

- [ ] **Step 2: Diff and justify every moved line**

```bash
scripts/refine-oracle.sh check /tmp/refine-base-de2bdc
```

Classify each moved line as exactly one of: **expected text change** (a
diagnosed hint replacing the canned paragraph), **expected regroup** (a
`--refine-report` slug moving from `solver-undecided` to a new bucket), or
**intended promotion** (audited in Task 8). Record the counts in the
measurements file. **Any line fitting none of the three is a bug** — fix it
rather than widening a category.

- [ ] **Step 3: Full suite**

```bash
scripts/run-tests.sh
```

All suites, not `-q`: the 24 `Slow` tests are excluded by `-q` and this change
touches the interpreter's builtin guard indirectly through `Witness`.

- [ ] **Step 4: The CI-only checks**

`scripts/run-tests.sh` runs alcotest binaries only; `@types-check` and
`@grammar-check` are dune rules it never reaches, and they assert diagnostic
TEXT — which this change rewrites. Without `--force` the check exits 0 with a
zero-byte log, so assert on the log, never the exit code.

```bash
dune build --root . @types-check --force 2>&1 | tee /tmp/types-check-de2bdc.log
wc -c /tmp/types-check-de2bdc.log   # MUST be non-zero, or the check was vacuous
```

- [ ] **Step 5: CHANGELOG and specs**

Add under `## [Unreleased]`:

```markdown
### Changed
- Refinement obligations the checker cannot discharge now report *why*:
  an unconstrained subject, a partially established conjunction (naming which
  half holds), a non-linear goal, or an opaque application, instead of a single
  `solver-undecided` message. Diagnosed causes report at every call site;
  the undiagnosable residual keeps its once-per-module hint.

### Added
- A call-site precondition failure that can be *demonstrated* — by running the
  enclosing function on arguments the solver's model assigns to its own
  parameters and observing a real panic — is now reported as a warning
  (an error under `cap verified`), with the precondition to declare suggested
  by `precond_infer`.
```

```bash
git mv specs/todos/2026-09-01-refinement-solver-undecided-diagnosis.md specs/progress/
```

Append landed/deviation notes to the moved file in the style of
`specs/progress/2026-08-30-counterexample-surfacing.md` — including any
deviation from this plan and from the design doc, and the Task 8 numbers.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md specs/progress/2026-09-01-refinement-solver-undecided-diagnosis.md specs/2026-09-01-refinement-error-diagnosis-measurements.md
git commit -m "docs: changelog and progress record for the undecided-bucket split"
```
