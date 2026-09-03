# A postcondition-derived `let` entry whose predicate mentions the `let`'s own binder (filed 2026-08-04, landed 2026-09-02)

**Shape.** `scope_add_binding`'s `postcond` arm (`lib/refinecheck/refine_check.ml`)
files the callee's return refinement under the `let`'s binder. `postcond_of` has
already substituted the call's **actuals**, so a name in the stored predicate
denotes the value **before** the binding. When the `let` rebinds a name the
predicate mentions, the pre-binding value and the post-binding value collide onto
one SMT symbol, because the fact loaders accept the entry's **own name** as a
spelling of the promised value (`is_self_spelling n = n = b || n = "_" || n = x`
in `load_scope_measure_facts`; the same `n = x` spelling in
`load_scope_tester_facts`). That spelling is correct for a refined **parameter**
entry — there the two really are the same value — and wrong for a
postcondition-derived `let` entry.

The collision does not merely lose precision. It produces a **contradictory
assumption**, and a contradiction discharges every goal, so the VC is vacuously
valid and an impossible obligation is reported **proved**. That is a false proof,
the one outcome this subsystem exists to prevent.

`scope_shadow` already applies exactly the right test (`expr_mentions`) to
**pre-existing** entries at every binding construct; what is missing is applying
it to the **newly created** entry's own predicate.

**Closed already (do not re-report).** The measure/ADT arm — the one marked with
`meas_sort_prefix` — was fixed on 2026-08-04 (`d3b961a1`) by guarding it with
`not (expr_mentions (pat_binders b.A.bind_pat) pred)`. Pinned by
`post-compose-relational` case 3.

Its two repros and their measured ledgers are inlined below so this file stands
on its own; all runs cleared `.march/cas/artifacts-v2` and `.march/cas/vc`
first, and ran the compiler in place at `_build/default/bin/main.exe` (stdlib
resolution is exe-relative, so a copy elsewhere measures nothing).

**(a) The relational repro** — the shape that made the hole reachable, and the
regression that prompted the guard:

```march
fn push2(t : Tree, u : Tree) : {Tree | size(_) > size(t) + size(u)} do
  Node(t, 1, u)
end
fn needs_smaller(before : Tree, after : {Tree | size(_) < size(before)}) : Int do 0 end
fn go(t : Tree, u : Tree, w : Tree) : Int do
  let t = push2(t, u)     -- REBINDS `t`, which the promise mentions
  needs_smaller(w, t)     -- demands size(t) < size(w) for an ARBITRARY w
end
```

| build | ledger (user code) |
|---|---|
| `273b4ef2` (before the relational widening) | `1 proved, 0 violated, 1 skipped` (solver-undecided) |
| `ad72f67f` (widening, no guard) | `2 proved, 0 violated, **0 skipped**` — the impossible goal PROVED |
| `d3b961a1` (guard) | `1 proved, 0 violated, 1 skipped` (solver-undecided) |

The emitted VC under `ad72f67f` was
`assume (> (size t) (+ (size t) (size u)))` — i.e. `0 > size(u)`, false under
the `size >= 0` axiom — against `goal (< (size t) (size w))`. A contradictory
hypothesis discharges every goal, so the VC was vacuously valid.

**(b) The ADT repro** — the same collision, reachable on the parent commit,
i.e. it predates the relational widening and was closed as a side effect of the
guard (same arm):

```march
fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do Node(t, x, Leaf) end
fn needs_smaller(before : Tree, after : {Tree | size(_) < size(before)}) : Int do 0 end
fn go(t : Tree, u : Tree) : Int do
  let t = push(t, 5)
  needs_smaller(u, t)     -- demands size(t) < size(u) for an ARBITRARY u
end
```

| build | ledger (user code) |
|---|---|
| `273b4ef2` | `2 proved, 0 violated, **0 skipped**` — impossible goal PROVED |
| `d3b961a1` | `1 proved, 0 violated, 1 skipped` (solver-undecided) |

Here the assumption collapses to `(= (size t) (+ (size t) 1))`.

## Still open

### 1. The scalar arm (`scalar_sort_of_marker m <> None`)

Reaches the same collision through `reflect_scalar`'s `foreign_var` channel
rather than `load_scope_measure_facts`, so it is older and broader than the
measure path. Reproduced as **`2 proved, 0 violated, 0 skipped`** on
`273b4ef2` **and** on `ad72f67f` (the impossible `needs_lt` goal is proved):

```march
mod PreScalar do
  fn incr(n : Int) : {Int | _ == n + 1} do n + 1 end
  fn needs_lt(u : Int, v : {Int | _ < u}) : Int do 0 end
  fn go(n : Int, u : Int) : Int do
    let n = incr(n)
    needs_lt(u, n)        -- demands n < u for an ARBITRARY u; proved
  end
  fn main() : Int do go(1, 1) end
end
```

The assumption becomes `n == n + 1`, i.e. `false`.

### 2. The record arm (`is_record_sort srt`)

Same producer, same missing test; not reproduced, by inspection only.

### 3. `load_scope_tester_facts`

**NO REPRO HAS BEEN CONSTRUCTED FOR THIS ARM. This entry is a code-reading
observation only — treat it as a lead, not a known bug.**

What IS verified: `load_scope_tester_facts` (the tester analogue of
`load_scope_measure_facts`, in `lib/refinecheck/refine_check.ml` — search for
the bare-tester `A.EApp` arm) accepts the identical
`n = b || n = "_" || n = x` guard, so it reads the entry's own name
as a spelling of the promised value in exactly the way that made arms 1–2
unsound.

What is NOT verified: that this is reachable. The obvious sketch —

```march
fn keep(o : Option(Int)) : {Option(Int) | is_Some(o)} do o end
...
let o = keep(o)
```

— was run both with and without the guard and gives `0 proved, 1 skipped`
either way, so it does **not** demonstrate the hole; something upstream already
declines it. A real reproduction still has to be built before anyone concludes
there is a defect here.

Note also that, unlike the measure and scalar cases, a bare tester cannot
express a contradiction on its own, so if the arm IS reachable the expected
symptom is a **wrong tag attribution** rather than a vacuous VC. Do not go
looking for a `0 skipped` ledger as the tell.

## Suggested fix

Hoist the guard so it covers all three `postcond` sub-arms — the property is
"a substituted postcondition that mentions this binding's own binder is not
usable at this name", which is arm-independent — then decide separately whether
`is_self_spelling`'s `n = x` clause should be dropped for
postcondition-derived entries generally (it is only sound for parameter
entries). Any change here needs a **paired reject control per arm**: an
accept-only witness cannot distinguish a working contract from one that proves
things vacuously, which is exactly how this survived.

Every measurement this file relies on is inlined above; there is no external
evidence document to chase.

Design for closing the remaining arms: `specs/2026-09-02-postcond-let-self-rebinding-design.md` (2026-09-02).


## Landed 2026-09-02

All three `postcond` sub-arms of `scope_add_binding` now carry the guard the
ADT arm had carried alone since 2026-08-04. The "Still open" section above is
history: items 1 (scalar) and 2 (record) are closed; item 3
(`load_scope_tester_facts`) is untouched and still has no reproduction, so it
remains a code-reading lead rather than a known bug.

Design: `specs/2026-09-02-postcond-let-self-rebinding-design.md`.
Plan: `specs/plans/2026-09-02-postcond-let-self-rebinding-plan.md`.

### What shipped

`lib/refinecheck/refine_scope.ml`. The test was factored into one helper,
`self_mentioning pat pred` (`:776`, defined as
`expr_mentions (pat_binders pat) pred`, both helpers pre-existing), placed
just above `scope_add_binding`, and applied as
`&& not (self_mentioning b.A.bind_pat pred)` to the scalar arm (`:866`), the
record arm (`:869`) and the ADT arm (`:873`). One helper rather than three
copies is the point: the next arm added to this match cannot forget the guard
by copying a neighbour that does not have it. The long comment above the
match was rewritten to say the guard covers all three arms and that the
scalar and record arms carry the identical latent hole, instead of describing
them as future work.

Nothing else moved. No provenance tag was added to `scope` (the design's
first non-goal), `scope_add_param` and the annotated-`let` arm are unchanged,
and `is_self_spelling`'s `n = x` clause is still there, since no self-mentioning
postcondition entry is ever created now, so no consumer can see one.

Commits: `ebdebca6` (guard plus the scalar REJECT and its ACCEPT control),
`4c1b090e` (the record-arm fixture).

### Tests

`test/test_refinecheck.ml`, suite `post-compose-relational`. A new
`ledger_counts : string -> int * int` helper (next to `skip_reasons`) resets
`Obligation`, runs the checker on a desugared module and folds the ledger
into `(proved, skipped)`, so the assertions are on obligation counts rather
than on a boolean "did it error", which cannot tell a real proof from a
vacuous one.

- REJECT, scalar arm: the `PreScalar` reproduction inlined above goes from
  `2 proved, 0 skipped` to `1 proved, 1 skipped`. `incr`'s own postcondition
  still proves; the impossible `needs_lt` call is now undecided.
- ACCEPT control: a postcondition-`let` under a fresh name keeps its fact,
  `2 proved, 0 skipped`. Without this, widening the guard to "always decline"
  would pass the suite.
- REJECT, record arm: the `PreRecord` fixture, asserted the same way.
- Mutation: removing the guard from the scalar arm alone reddens the scalar
  REJECT case (it returns `(2, 0)`, a false proof) and leaves the ACCEPT
  control and the pre-existing ADT case green.

Full `./_build/default/test/test_refinecheck.exe -e`: 600 tests, 0 failures
(this exe is z3-gated and, before #393, was not reached by
`scripts/run-tests.sh`).

### Task 2 outcome: the record arm is a forward guard, not a live repro

Stated plainly because it is easy to misread the record fixture as a
reproduction: **no loader reaches the collision for a record subject today.**
Removing the record arm's guard and rerunning the `PreRecord` fixture gives a
bit-identical ledger, `0 proved, 2 skipped`, with and without the guard; the
case is `[OK]` either way. The two obligations are skipped rather than falsely
proved, so nothing is being fixed there right now. The fixture is kept as a
forward guard on a structural hole: the arm has the same shape as the scalar
one, the scalar one demonstrably *is* reachable, and a future loader change
could make the record path reachable the same way. Anyone who deletes the
record arm's guard on the grounds that "no test fails" should read this
paragraph first.

### Oracle: proven RED, then an empty diff

`scripts/refine-oracle.sh` over 299 fixtures (`test/native/*.march` plus
`stdlib/*.march`), baseline built from this plan's start commit `f47b25a3` in
a throwaway worktree. Note the baseline is NOT the merge-base with
`origin/main`: this branch stacks on an unmerged PR whose own diagnostic
changes would otherwise swamp the diff.

- Baseline manifest: 6567 report lines, 5450 `proved` and 18496 `skipped`
  summed over the per-fixture ledgers.
- RED proof, run first: forcing the call-site precondition verdict to
  `Proved` unconditionally in `refine_call.ml` collapses the manifest to 5088
  lines with 2113 differing lines and 20967 `proved`. The oracle detects a
  verdict change on this corpus. The perturbation was reverted and the
  compiler rebuilt before the real run.
- Real check: `REFINEMENT DIAGNOSTICS IDENTICAL (6567 lines over 299
  fixtures)`. Corpus `proved` before and after are both 5450.

The classification the design asked for is therefore empty: zero lines moved,
so there are zero `proved`-to-`skipped` transitions to enumerate and zero
lines of any other kind to explain. The corpus contains no `let` that rebinds
a name its own call's return refinement mentions. That is the expected shape
for a soundness guard whose only effect is to withhold a fact at a construct
the corpus does not use, and after a proven-RED oracle it is a real result
rather than a vacuous one.
