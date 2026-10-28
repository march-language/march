Termination checking, phase 3: the induction hypothesis behind the certificate

Design: `specs/2026-10-26-termination-checking-design.md` §4 (all of it), §5, §6 and §8
phase 3; decisions D1-D6. Branch `claude/termination`, on top of phase 2
(`specs/progress/2026-10-27-termination-phase2.md`). The rulings of phases 0-2 stand.

D1 is the rule this phase implements: a recursive function's own contract is assumed at
its recursive calls (the induction hypothesis, IH) only behind a termination
certificate. The design's §0 scratch build, an ungated IH, "proved"
`loopy : {Int | _ < 0}`, and the call `need_pos(loopy(k))` became a false violation.

## What changed

- **`Refine_check.ih_prepare`** (new, called by the gate) decides which recursive SCCs
  may use the IH, and at which calls. It runs once per module, after the IH-free gate
  rounds have stalled, over the contracts proved so far.
  - **Demand (§9).** It considers three kinds of SCC: the SCCs of the still-pending
    refined returns; the SCC of every unit declaring an element return (top-level or
    local, not `@[assume]`); and every recursive SCC reachable from those. When no
    recursive SCC is demanded, it returns at once.
  - **A scratch walk** covers the top-level functions holding a member of an IH SCC or
    of a metric-pending SCC. It runs with a throwaway error context, under
    `Obligation.with_scratch`, and with `calls_only_walk` set, so no return is checked
    and no local is lent a return. The witness budget is 0. Every module-wide cell the
    walk can move is saved and restored:
    - `term_sites` and `term_verdicts`;
    - `annotated_acc_facts`, `ret_ctr`, `promoted_sites`, `local_elem_ret_proved`,
      `last_elem_return_proved`;
    - the witness wall budget and the solver's malformed counters.

    It discharges the phase-2 termination obligations of the demanded SCCs, and records
    which watched call spans it reached (`ih_watch` / `ih_reached`, set in `visit`'s
    `EApp` arm).
  - **Certificates** come from `Refine_term.finish` over those verdicts.
  - **An SCC is eligible** when its certificate is `structural` or `metric`, and every
    recursive SCC reachable from it (`Refine_term.reachable_sccs`) is certified too.
  - **A call span is eligible (rule (a))** when it meets all four conditions:
    - it is an intra-SCC direct or lambda edge of an eligible SCC;
    - the scratch walk reached it;
    - every `Precondition` obligation recorded at it was `Proved`;
    - if the callee has a refined parameter, at least one obligation was recorded.
  - Eligible spans go into `Refine_post.ih_spans`, with whether the edge is a self-edge.
    A group (`ih_group`) is returned for each eligible SCC with pending members.
- **The gate** (`Refine_post.gate_unverified_posts_ih`) works as follows.
  - The IH-free rounds are exactly as before (`rounds` now returns what is left).
  - Then it calls `ih` (always, so the element gate and the walk see `ih_spans`).
  - Then come the IH rounds. A group's pending members are checked **without admitting
    any of them** (`verdict`, not `check`). While they are checked, `ih_at` answers each
    member's declared contract at the group's eligible spans. All members are admitted
    iff all prove.
  - An ordinary item is retried when a name it calls was admitted. The exported
    `gate_unverified_posts` (the `.mli` entry the inference probes use) is the IH-free
    gate, unchanged.
  - `ih_at` answers only when the call also resolves, by this checker's own rule from
    the caller's module, to that member's cleared `defs` entry, compared physically.
    That makes the termination graph and the checker agree on the callee.
- **`Refine_post.call_post`**: `ih_at` at the call's span, else `post_lookup`. It
  replaces `post_lookup` in `let_call_const` (C1's let form) and `scalar_call` (a bare
  tail).
- **Rule (b)** (`scalar_nested` in `check_post`). A scalar return tail that neither
  `scalar` nor `scalar_call` reflects is rewritten:
  - each call sub-term under strict operators, or in a call's arguments, whose contract
    `call_post` answers at a scalar sort becomes a fresh `f$ret<N>` carrying the
    contract;
  - the constants are committed only if the rewritten tail then reflects.

  It applies to every proved contract, not only the IH.
- **The three self-call hypotheses widen by span.** Each now accepts either a structural
  argument (the old rule) or an eligible self-edge span in `ih_spans`:
  - Tier 2's `ih_arg` (`refine_post.ml`);
  - `hyp_applies` (`?span`, from `container_entry_of_expr`);
  - `local_elem_hyp`'s condition.

  The definer condition of `hyp_applies` and the physical-signature test of the local
  are unchanged.
- **`check_module`** resets `ih_spans` before the gate and clears it when it returns
  (`Fun.protect`), so no other entry point sees a stale certificate.
- **`Refine_term`**: units record `u_top` (the enclosing top-level unit) and `u_ret` (the
  declared return). New helpers: `reachable_sccs` and `unit_at`.
- **`Refine_resolve.instantiate_ret`**: the body of `postcond_of_declared`'s
  resolved-callee case, factored out, with identical behaviour.
- **Docs and records:**
  - `specs/lang/refinement-types.md` gains "The induction hypothesis" under Termination;
    the Tier 2 "non-structural recursion" bullet points at it;
    `scripts/gen-lang-docs.py` was rerun.
  - CHANGELOG: a `### Added` bullet, and the phase-2 bullet's "nothing uses a proved
    metric yet" now points at it.
  - New todo `specs/todos/2026-10-27-termination-ih-gaps.md`.

## Tests (group `termination-ih`, 11 cases; the 65 of phases 0-2 still green)

The RED-first run used a stub build with no `~ih` passed to the gate and rule (b)
switched off (`stub-no-phase3`). Seven of the eleven failed. The first failing line was:

```
FAIL sum_to post
   Expected: `["proved"; "proved"]'
   Received: `["proved"; "skipped"]'
```

The soundness rows pass on the stub by construction, since they assert today's skip.
Each one was then watched RED under a perturbation of exactly the rule it guards. Each
perturbation is one edit to the shipped code, a rebuild, a run of `termination-ih`, and
a restore (`perturb.py` in the session scratchpad, not committed).

| Case | Asserts | Perturbation | First failing line |
|---|---|---|---|
| r2 / §4.3 | nested `n + sum_to(n - 1)`: post, pre and `need_nn(sum_to(k))` all proved | `stub-no-phase3`; `no-rule-b` | `FAIL sum_to post` / `Received: ["proved"; "skipped"]` |
| r1 / r3 | let forms: `_ >= 0` and `_ >= n`, `need_ge(sum_to(10))` proved | `stub-no-phase3` | `FAIL r1 sum_to` |
| r4 | `1 + len2(t)` (structural) and its caller proved | `stub-no-phase3`; `no-rule-b` | `FAIL len2` |
| c1 / c1-nested / c2 / c3 | no proved post, no violation, caller skipped | `always-grant` (every SCC certified, closure ignored) | `FAIL c1 post: some tail skipped, none violated; got proved` |
| `pre_fails` | `f(n - 2)`: skip (its termination fails too); `f(n - 1, k - 1)`, which decreases but breaks `k > 0` at k = 1: post not all proved, `need_pos(f(1, 1))` not proved | `no-pre-check` | `FAIL f(n, k) post: not every tail proved; got proved,proved` |
| `scc_atomic` | `ev`/`od`, `od` false: neither all-proved, `need_nn(ev(1))` (really `-1`) not proved; both true: both proved | `non-atomic` (members admitted one by one under the group IH) | `FAIL caller need_nn(ev(1)): … got proved` |
| `elem_widened` | `@[decreases(n)] replicate`'s `Cons(x, replicate(x, n - 1))` proved; structural `keep` proved; unannotated (metric `x`, unchanged) not all proved | `no-elem-widening`; `always-grant` (the control) | `FAIL return of replicate` |
| `local_widened` | a local `go(i - 1)` with `i : {Int \| _ >= 0}` proves its `Option` return and the caller's `need_nn`; ascending `go(i + 1)` skips | `no-local-widening`; `always-grant` (the control) | `FAIL return of go` |
| `tier2_widened` | `rep(n - 1)` proves `len(_) == n`; `rep_bad(n : Int)` (diverges at -1) skips | `no-tier2-widening`; `always-grant` | `FAIL rep` / `FAIL rep_bad: … got proved` |
| `diverges_in_scc` | `f` certified, but it calls uncertified `spin`: skip | `no-closure`; `always-grant` | `FAIL f post: … got proved,proved` |
| ledger | no `Termination` obligation recorded for an IH-only SCC | — | — |

One perturbation stayed green, and the reason is recorded rather than hidden:
- **`no-agreement`** (drop the resolution-agreement check): 0 failures. No fixture is known
  where the termination graph and the checker resolve a call differently. Phase 0
  pinned lexical resolution on both sides. The check is defence in depth, filed in the
  gaps todo.
- `no-pre-check`'s first run was also green. The original `pre_fails` (`f(n - 2)`) fails
  its *termination* obligation (`0 <= n - 2` at n = 1), so it never isolated rule (a).
  `pre_fails_k` was added; it decreases and breaks only a precondition.

### Existing fixtures that changed deliberately (§4.2: "the phase 3 progress note lists each one")

- **`demand-chains` / "C1 recursion control".** `fn f(n : {Int | _ >= 0}) : {Int | _ > 0}`
  with body `if n == 0 do 1 else f(n - 1) end` used to be `[proved; skipped]`. It
  terminates (metric `n`), so the IH proves the tail: `[proved; proved]`. The control is
  kept with `n : Int` (`f(-1)` diverges), which still gives `[proved; skipped]`.
- **`tier2-induction` / "a closed Int postcondition on a recursive function".**
  `countdown(n : Int) : {Int | _ >= 0}` has a `<= 0` exit, so it is certified. Its
  contract is now proved, and `needsneg(countdown(5))` is a **true** violation
  (`countdown(5) = 0`). The test's comment said the fixture was pinned so that "a future
  widening … cannot change it unnoticed". It now asserts the violation, plus an `== 0`
  variant that still stays silent.

No other existing test changed.

## Oracles

All ran under private `HOME`s, with `_build/default/stdlib` deleted before the baseline
and before each check. The baselines were recorded before the first edit, with the
phase-2 exe (`5a6e62350`).

- **`scripts/refine-oracle.sh check`: `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines over 552
  fixtures)`.** The design's §7 predicts an empty stdlib diff. The brief expected a
  change, so the reason was measured. A temporary counting build (not committed)
  swept all 552 fixtures and found:
  - in every fixture, the only demanded SCC is `Range.filter_list`, an element-return
    function that is already structurally proved;
  - no fixture has a pending recursive refined return;
  - rule (b) fires nowhere.

  So there are no lines to classify: 0 skip→proved, 0 new violations, 0 proved→other.
  No stdlib spot check was needed, and the `list.march` audit ratchet cannot have
  moved. No audit baseline was regenerated.
  - **The oracle is blind to this phase, and that was proved directly.** An
    `always-grant` build (every SCC certified, the callee closure ignored) also gave
    `IDENTICAL`. The corpus cannot see the IH at all, so phase 3's evidence is the
    `termination-ih` group and the two changed fixtures above, not the oracle.
- **`scripts/ir-oracle.sh check`** (`MARCH_ORACLE_EXE`, frozen phase-3 exe, run from the
  worktree root): `IR IDENTICAL across 497 programs`.
- The typechecker and parser are untouched, so there was no types-oracle run.
- **Timing** (§9, ≤ 105% for default `--check`). `--check --refine-report`, phase-2 exe
  (a detached worktree at `5a6e62350`) against the phase-3 exe, interleaved, 5 timed runs
  each after a warm-up, median, load 3.6-4.4:
  - `stdlib/list.march`: 1.196 s → 1.162 s (97.2%);
  - `stdlib/json.march`: 1.203 s → 1.163 s (96.7%).

  That is within budget; the difference is noise. Every fixture now pays one scratch
  walk of `Range.filter_list`.

## Soundness argument (for the reviewer)

The claim: an assumption the IH adds is a true fact about every value the program can
produce at that point. And no IH is given to a function that may not return on the input
in question.

1. **Partial correctness.** March is call-by-value with strict `&&`/`||` (F11). The
   claim "f(x) returns v ⇒ post(x, v), for every x meeting f's precondition" can be
   proved by induction on the depth of the computation. Each recursive call in f's body
   is a strictly shallower computation, so assuming the post at a call is sound **for
   proofs** provided the call's argument meets f's precondition. Rule (a)'s precondition
   half gives exactly that: every precondition obligation at the call was *proved* in
   the scratch walk. (`pre_fails_k` is the case where dropping that half proves a false
   contract.)
2. **Why termination as well (D1, §4.4).** A proved post is also assumed when
   *refuting* at call sites. A function that never returns has every post vacuously
   true (c1-c3), and a caller would then get a fabricated witness. The IH is the only
   way a post on a diverging path can be proved (without it, the recursive call's
   value is unconstrained). So the IH is granted only to a certified SCC:
   - a `structural` certificate decreases a well-founded sub-term order (phase 1);
   - a `metric` certificate decreases a lexicographic order on naturals, with every
     intra-SCC edge obliged (phase 2).

   `trusted` (an obligation accepted under `@[trusted]`) and every `unproved:*` give
   nothing.
3. **Callees.** A certified SCC terminates *modulo its callees*. The IH is withheld if
   any recursive SCC reachable from it is uncertified (`diverges_in_scc`). A
   non-recursive callee terminates iff its own callees do; induction over the SCC DAG
   makes "every reachable recursive SCC certified" mean "terminates, except through
   function values, builtins and externs". Function values are "terminating modulo
   function-valued inputs" (§5, not claimed); builtins and externs are trusted
   (decision 10). Builtins and externs are not graph units, so they never appear as
   reachable SCCs.
4. **The termination proofs themselves use only proved facts.** The scratch walk runs
   after the IH-free rounds, so `defs` holds only proved contracts. It runs with
   `calls_only_walk` set, so no structural, element or local self-hypothesis is active
   in it (`elem_ret_hyp` is set only for an element demand, which is off, and the local
   O1 scratch walk does not run). A callee's proved post may be used in a metric query.
   By (1) it is a true partial-correctness fact. If that callee could diverge, (3)
   withholds the IH from every SCC reaching it anyway.
5. **Atomic admission.** A group's members are checked with no member admitted, so a
   member's contract reaches a sibling only through `ih_at`, at eligible spans. All are
   admitted iff all prove: strong induction on the shared metric needs the hypothesis
   of every member. A false member would otherwise lend a false contract
   (`scc_atomic`: `ev(1) = -1` "proved" `>= 0` under `non-atomic`).
6. **Self-only widenings.** Tier 2, the element return and the local return assume
   only the function's own contract, at its own self-edges. That is induction on the
   certified metric restricted to self-calls. A mutual member's value at those sites is
   unconstrained, which is weaker and still sound. The widening reads only
   `ih_spans = true`, that is, self-edges of an eligible SCC that passed rule (a).
7. **Callee identity.** `ih_at` is keyed by call span (the graph's edge) and answers only
   when the checker's own resolution, from the caller's module, reaches that member's
   `defs` entry physically. A name resolved differently by the two can therefore never
   lend one function's contract to another's call. The self-only widenings check the
   same identity as before: the name, no local or callback shadowing, and for a local,
   the physical signature.
8. **Rule (b).** A nested call's value is a fresh constant constrained by a contract
   `call_post` answers (proved, or the IH at an eligible span). Every call under the
   descended operators is evaluated whenever the tail's value exists (strict operators,
   and `smt_of` has no conditional). Each occurrence is its own constant. The
   rewrite runs only after both older translations failed, and commits its constants
   only on success, so no query that reflected before changes.
9. **Scope.** `ih_spans` lives exactly as long as one `check_module` (reset, then
   `Fun.protect`). `ih_at` lives for one group check. The inference probes call the
   IH-free gate.
10. **The walk after admission.** An admitted contract is in `defs`, so the reporting
    walk's re-check reads it at every self-call. That re-derives a contract the gate
    already proved, so it adds no unproved assumption. An unadmitted one is absent, and
    stays the old skip.

## Rulings

- **Ruling: the certificate is decided by a scratch walk before the gate's IH rounds,
  rather than in the reporting walk.**
  - Why: the reporting walk runs after the gate, but the gate needs the certificate.
    The scratch walk is the same `visit`, so the termination obligations get the same
    path, scope and `let` facts as in phase 2. It is restricted to the demanded
    functions, and it checks calls only.
  - Cost if wrong: a precondition that only an IH-proved contract can discharge is not
    seen (gaps todo, "one certification per module"). That loses proofs, never adds
    one.
- **Ruling: rule (a) is per call span, and "proved" means `Proved`.** `Trusted` does not
  count, and a refined callee with no recorded obligation does not either.
  - Why: §4.2. A call the walk never reached (an arm guard) has no checked precondition.
    A `Trusted` verdict is an assertion, not a proof.
  - Cost if wrong: `Range.filter_list`'s abstract-refined `f` files no obligation, so its
    self-call is not eligible. It proves structurally anyway (gaps todo).
- **Ruling: "may diverge" is inferred upward for the IH. An SCC reaching any uncertified
  recursive SCC gets no IH (§3.7's "no IH for an SCC whose proof crosses into one").**
  - Why: phase 4's `@[diverges]` does not exist yet. An uncertified recursive SCC is
    exactly what it will mark, so `diverges_in_scc` is tested with one.
  - Cost if wrong: an SCC that calls an unannotated, uncertified helper loses its IH.
    The only cost is conservatism.
- **Ruling: `trusted` certificates license no IH.**
  - Why: a termination obligation accepted under `@[trusted]` was not proved, and D1 asks
    for a certificate.
  - Cost if wrong: an `@[assume]`d or `@[trusted]` recursive function's callers lose
    nothing, since an `@[assume]`d contract is assumed anyway.
- **Ruling: termination obligations filed only for the IH are not recorded in the
  ledger.** The reporting walk discharges only phase 2's demand (`@[decreases]`,
  `--termination-report`).
  - Why: D2 keeps termination report-only. `cap verified`'s "escalate the termination
    obligations a proof relied on" is vacuous here, because the IH is granted only
    when they are *proved*, so none that a proof relied on can be unproved. Recording
    them would change `--refine-report`'s `by kind:` line for every module with a
    certified recursive contract, with no new verdict.
  - Cost if wrong: `--refine-report` does not show the termination lemmas behind an
    IH proof. `--termination-report` does.
- **Ruling: the gate's IH rounds run only after the IH-free rounds stall.**
  - Why: a contract that proves without the IH is admitted exactly as before, so no
    verdict that phase 2 reached depends on the new machinery.
  - Cost if wrong: none for soundness; one extra round of checks for an SCC that needs
    the IH.
- **Ruling: rule (b) applies to every proved contract, not only to IH calls, and only
  to a scalar return tail.**
  - Why: §4.2 phrases it on `!post_lookup`. A nested call with a proved contract is the
    same fact as a bare or `let`-bound one (`scalar_call`). Path conditions, record and
    list tails were left alone to keep the change small.
  - Cost if wrong: none for soundness (argument 8); the remaining positions are filed.
- **Ruling: the Tier 2, element and local widenings stay self-call only; the tuple
  element hypothesis is not widened.**
  - Why: §4.2 widens "argument is a structural subvariable" at each site. Each of those
    hypotheses is a self-call hypothesis, so the widening keeps that shape. Mutual
    admission exists only in the scalar gate, where §4.2's atomic rule is built.
  - Cost if wrong: mutual datatype or element contracts, and tuple returns, still skip
    (gaps todo).
- **Ruling: the exported `gate_unverified_posts` stays IH-free.**
  - Why: its other callers (`precond_infer`, `postcond_infer`, `infer_oracle`) run it
    outside `check_module`, with no certificate in hand. The `.mli` is unchanged.
  - Cost if wrong: an inference probe may miss a proposal that needs the IH. It still
    runs the real `check_module` to verify a proposal, and that does have the IH.
- **Ruling: the two existing fixtures above change deliberately.** Both now terminate
  provably, and one is a true violation that the old silence hid. §4.2 anticipates
  this, and each keeps a diverging control.

## Suites

- `termination-ih` 11/11; all 76 `termination-*` cases; `demand-chains`, `tier2-induction` and
  `gap-o1-local-option` green.
- The full `scripts/run-tests.sh` ran at load average 3.5-4.5 and printed `All suites
  passed`: 13 suites, 6128 tests. Among them:
  - `march-refinecheck`: 1890;
  - `march-compiler`: 1459;
  - `march-codegen`: 720;
  - `march-stdlib`: 899;
  - `errors`: 299.
- Suite time, `scripts/run-tests.sh refinecheck` at load ~4: the phase-2 tree took 844 s
  for 1879 tests, and this branch took 895 s for 1890. Most of the difference is the 11
  new cases (`termination-ih` alone is about 13-26 s).
- `scripts/check-docs.sh`: passed.

## Not done

- Everything in `specs/todos/2026-10-27-termination-ih-gaps.md`.
- Phase 4 (`@[diverges]`, `cap total`, handlers, LSP actions) and phase 5 (inference).
