# Postcondition-`let` Self-Rebinding Hole Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the refinement checker from proving impossible obligations when a `let` rebinds a name that its own postcondition-derived predicate mentions.

**Architecture:** `scope_add_binding` files a callee's return predicate under the `let`'s binder after `postcond_of` has substituted the call's actuals. The ADT arm already declines when the predicate mentions the binder (`expr_mentions`); the scalar and record arms do not. Factor that test into one helper and apply it to all three arms. No consumer changes: a self-mentioning entry is never created, so no loader can see one.

**Tech Stack:** OCaml 5.3.0, dune, Z3 via `March_refine.Solver`, Alcotest.

## Global Constraints

- Opam switch `march`; `dune`/`opam` on PATH. NEVER `eval $(opam env ...)`.
- Nested worktree: EVERY dune command needs `--root .`.
- No false proofs. A `proved` that becomes `skipped` must be a self-mentioning rebind; any other lost proof is a bug in the guard.
- Assert on the obligation LEDGER (`proved`/`skipped` counts via `Obligation.summary` or `--refine-report`), never on a boolean "has error".
- Test discipline: ONE process, foreground, `rm -rf .march/cas/vc` first, `pgrep -fl "test_|main.exe"` clean (ignore other worktrees). z3 is installed; `test_refinecheck.exe` must show `[OK]`, never `[SKIP]`. `scripts/run-tests.sh` covers refinecheck since #393.
- Never `git stash`; never `git add -A`; stage by name; no attribution trailers.
- CHANGELOG `### Fixed` bullet and the `specs/todos` to `specs/progress` move land in the final task's commit.

---

### Task 1: Guard the scalar and record arms

**Files:**
- Modify: `lib/refinecheck/refine_scope.ml:845-863` (`scope_add_binding`'s postcond arms)
- Test: `test/test_refinecheck.ml`, `post_compose_relational_suite` (registered as `"post-compose-relational"`, near line 11257)

**Interfaces:**
- Produces: `self_mentioning : A.pattern -> A.expr -> bool` in `refine_scope.ml`, used by all three postcond arms.

- [ ] **Step 1: Write the failing tests**

Append to `post_compose_relational_suite`. `skip_reasons`, `has_refine_error_d` and a ledger helper exist in the file; if there is no helper returning `(proved, skipped)` counts, add one beside `skip_reasons` (~line 4175) that resets `Obligation`, runs `check_module` on the desugared module, and folds `Obligation.all ()` into a pair.

```ocaml
    (* THE hole.  `incr`'s promise, filed under `n` after the actual `n` was
       substituted, reads `n == n + 1` once `n` is rebound: a contradiction,
       and a contradiction proves every goal.  The ledger, not a boolean,
       because the postcondition of `incr` legitimately proves and would mask
       a boolean.  Mutation that fails this: drop the guard on the scalar arm. *)
    gated "REJECT: a scalar postcond-let that rebinds a mentioned name is not a proof"
      (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod PreScalar do
  fn incr(n : Int) : {Int | _ == n + 1} do n + 1 end
  fn needs_lt(u : Int, v : {Int | _ < u}) : Int do 0 end
  fn go(n : Int, u : Int) : Int do
    let n = incr(n)
    needs_lt(u, n)
  end
end|}
        in
        Alcotest.(check (pair int int)) "1 proved (incr's own postcondition), 1 skipped"
          (1, 1) (proved, skipped));

    (* POSITIVE CONTROL: the same promise under a FRESH name keeps its fact.
       Without this the guard could be widened to "always decline" and the
       suite would stay green. *)
    gated "ACCEPT CONTROL: a postcond-let under a fresh name keeps its fact"
      (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod PreScalarOk do
  fn incr(n : Int) : {Int | _ == n + 1} do n + 1 end
  fn take_pos(v : {Int | _ > 0}) : Int do v end
  fn go(n : Int) : Int do
    if n >= 0 do
      let m = incr(n)
      take_pos(m)
    else 0 end
  end
end|}
        in
        Alcotest.(check (pair int int)) "both proved" (2, 0) (proved, skipped));
```

- [ ] **Step 2: Run to verify the first fails**

```bash
rm -rf .march/cas/vc
dune build --root . test/test_refinecheck.exe && ./_build/default/test/test_refinecheck.exe test post-compose-relational
```

Expected: the REJECT case FAILS with `(2, 0)` against `(1, 1)` (the false proof). The ACCEPT control passes already; that is its job.

- [ ] **Step 3: Factor the guard and apply it**

In `refine_scope.ml`, above `scope_add_binding`:

```ocaml
(* A postcondition-derived entry whose predicate mentions the `let`'s own
   binder denotes the PRE-binding value under the post-binding name (the
   actuals were substituted by [postcond_of] before the binding took effect).
   Filing it would collapse two values onto one SMT symbol and, for a
   relational promise like `_ == n + 1`, manufacture a contradiction that
   proves every goal.  Declining is the only sound choice: the pre-binding
   symbol has already been retired by [scope_shadow]. *)
let self_mentioning (pat : A.pattern) (pred : A.expr) : bool =
  expr_mentions (pat_binders pat) pred
```

Replace the three arms:

```ocaml
       (match postcond fname args with
        | Some (binder, pred, m)
          when scalar_sort_of_marker m <> None
               && not (self_mentioning b.A.bind_pat pred) ->
          (n.A.txt, (binder, pred, m)) :: sc
        | Some (binder, pred, Some srt)
          when is_record_sort srt
               && not (self_mentioning b.A.bind_pat pred) ->
          (n.A.txt, (binder, pred, Some srt)) :: sc
        | Some (binder, pred, Some srt)
          when Hashtbl.mem adt_ctors srt
               && not (self_mentioning b.A.bind_pat pred) ->
          (n.A.txt, (binder, pred, Some (meas_sort_prefix ^ srt))) :: sc
        | Some _ | None -> sc)
```

Rewrite the comment above the arms (currently "Deliberately on THIS arm only ...") to say the guard now covers all three and why.

- [ ] **Step 4: Run to verify both pass, then mutation-test**

Run the group. Expected: both `[OK]`. Then temporarily remove `&& not (self_mentioning ...)` from the SCALAR arm only, rebuild, confirm the REJECT case reddens and the ACCEPT control stays green; restore. Record the result in the report.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_scope.ml test/test_refinecheck.ml
git commit -m "refine: decline a self-mentioning postcond-let on the scalar and record arms too"
```

---

### Task 2: Pin the record arm

**Files:**
- Test: `test/test_refinecheck.ml`, same suite

**Interfaces:**
- Consumes: `self_mentioning` (Task 1).

- [ ] **Step 1: Write the fixture**

Adapt an existing record fixture from the suite (grep `is_record_sort` cases, or the `Config`/`port` shape in `reason_suite`):

```ocaml
    (* Record arm of the same hole.  `bump`'s promise `r.port == c.port + 1`
       under the rebound `c` is again a contradiction. *)
    gated "REJECT: a record postcond-let that rebinds a mentioned name is not a proof"
      (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod PreRecord do
  type Config = { port : Int }
  fn bump(c : Config) : {r : Config | r.port == c.port + 1} do { port: c.port + 1 } end
  fn needs_port_lt(u : Int, c : {v : Config | v.port < u}) : Int do 0 end
  fn go(c : Config, u : Int) : Int do
    let c = bump(c)
    needs_port_lt(u, c)
  end
end|}
        in
        Alcotest.(check bool) "the impossible call is not proved" true
          (skipped >= 1 || proved < 2));
```

- [ ] **Step 2: Establish the pre-fix behaviour honestly**

Temporarily remove the record arm's guard, rebuild, run the case. If it goes RED, the record arm was live and this fixture is a true regression guard; say so. If it stays GREEN, the record shape does not reach the collision through any loader today; keep the fixture anyway (the hole is structural) and state in the report that it is a forward guard, not a reproduction. Restore the guard.

- [ ] **Step 3: Run, commit**

```bash
git add test/test_refinecheck.ml
git commit -m "test(refinecheck): pin the record arm of the postcond-let guard"
```

---

### Task 3: Oracle, suite, record

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]`, `### Fixed`)
- Move: `specs/todos/2026-08-04-postcond-let-self-rebinding-holes.md` to `specs/progress/`
- Modify: `specs/2026-09-02-postcond-let-self-rebinding-design.md` (status line)

- [ ] **Step 1: Oracle with RED proof**

Build the baseline compiler at the branch's merge-base with `origin/main` in a temporary worktree under the session scratchpad (NOT `/tmp`), run `scripts/refine-oracle.sh baseline <scratchpad>/refine-base`, then in this worktree perturb one verdict (e.g. note `Proved` unconditionally at one site), build, run `check`, confirm RED, revert, rebuild. Then run `check` on the real tree. Every moved line must be a `proved` becoming `skipped` at a self-mentioning rebind; list each. Anything else is a bug. Remove the temporary worktree.

- [ ] **Step 2: Full suite and CI-only checks**

```bash
scripts/run-tests.sh
dune build --root . @types-check --force 2>&1 | tee <scratchpad>/types.log; wc -c <scratchpad>/types.log
dune build --root . @grammar-check --force
scripts/check-docs.sh
```

Log sizes must be non-zero.

- [ ] **Step 3: Record**

CHANGELOG `### Fixed`: "A `let` whose right-hand side is a call with a refined return type, and which rebinds a name that return refinement mentions, no longer proves impossible obligations. The scalar and record cases of a hole closed for ADTs on 2026-08-04 are now closed the same way." `git mv` the todo to `specs/progress/` and append: what shipped, the corpus `proved` counts before and after, the oracle classification, and whether the record arm reproduced (Task 2 Step 2). Set the design's status line to landed.

```bash
git add CHANGELOG.md specs/progress/2026-08-04-postcond-let-self-rebinding-holes.md specs/2026-09-02-postcond-let-self-rebinding-design.md
git commit -m "docs: record the postcond-let guard on all three arms"
```
