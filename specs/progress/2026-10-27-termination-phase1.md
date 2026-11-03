Termination checking, phase 1: structural certificates over SCCs, strict positivity, the SCC measure gate

Design: `specs/2026-10-26-termination-checking-design.md` §8 phase 1, §3.3, §3.6 and §6
(the `@[measure]` row). Branch `claude/termination`, on top of phase 0
(`specs/progress/2026-10-27-termination-phase0.md`).

The certificate is REPORT-ONLY, per D2. It raises no warning by default, and nothing feeds the
induction hypothesis (phase 3). Its one consumer with a verdict is the `@[measure]` gate.

## What changed

- **`Refine_term.certify`** (`lib/refinecheck/refine_term.ml`) certifies each SCC
  `structural` or `unproved:<reason>`.
  - A self-recursive SCC is certified when some parameter position `i` exists such that every
    intra-SCC call's argument `i` is a bare variable in `structural_subvars` of the caller's
    own parameter `i`. That set is computed over the clause the call sits in, by-name and
    with its fixpoint (F6). So arithmetic, nullary constructors, `List.nth` and the
    parameter itself never count.
  - A mutual SCC is certified when every member gets a position, and all those positions hold
    one **type family**: the same ADT, or ADTs defined in terms of each other. The head
    constructor is the annotated one, or else the typechecker's, so a merged multi-head
    `__arg0` works. See the ruling below on why this is not literally "the same ADT". Every edge `f -> g` must also pass, at `g`'s position, a
    `structural_subvars` variable of `f`'s position. The assignment search is capped at 4096
    steps, and running out of budget means unproved.
  - Lambda edges are checked like direct ones. Any intra-SCC reference edge gives
    `unproved:reference`.
- **Strict positivity** (`nonpositive_types`) runs over every `type` declaration at any
  `mod` depth.
  - `T` is non-positive when a type mutually reachable with `T` (or `T` itself) has a field
    with, to the left of an arrow, a type that reaches `T`.
  - A generic type's parameter that occurs on the left of an arrow (or is passed on to such a
    parameter, to a fixpoint) makes its arguments left positions.
  - A unit calling a function value (a callee bound as a variable, or any non-name callee)
    whose type, from the `type_map`, mentions a type that reaches a non-positive one gets
    `unproved:non-positive`, and so does its SCC. When no type was recorded and some
    non-positive type exists, the unit is assumed tainted.
  - A non-recursive unit with such a call is listed in the report (class F, shape `value`).
- **The `@[measure]` gate** (`refine_check.ml`, beside `measure_gate_errors`): a measure whose
  unit is recursive and uncertified, or that calls a non-positive function value, gets
  `invalid_measure` with the self-call rule's own wording ("is not structurally recursive
  (…)"). The self-call rule is kept, and the message is added only if that rule did not
  already add it, so the union is never weaker than before. The graph is built lazily, only
  when there is a measure to gate.
- **`--termination-report`** gains a `cert=` column, a `certificate: N structural, M unproved`
  line, and the non-positive non-recursive rows.
- **Docs and specs:**
  - `specs/lang/refinement-types.md` gains a new subsection, "The structural certificate", and
    the measure soundness gate bullet now names the cycle rule. Docs were regenerated.
  - CHANGELOG: a `### Changed` bullet.
  - New todo `specs/todos/2026-10-27-termination-structural-certificate-gaps.md`.

## Tests (group `termination-structural`, 22 cases; phase 0's 17 still green)

Every phase-1 RED-table row is covered, with each certificate rule's REJECT control:

| Case | Asserts | Watched RED by |
|---|---|---|
| t7 `len2` | `structural` | the `always-structural` stub could not show this; it is the positive control |
| `nil_not_smaller` | `1 + f(Nil)`: `unproved:no-structural-arg`; the stack pass still names `f` "structurally recursive" | `always-structural` → `Received: "structural"` |
| `copy_shadow` | a genuinely diverging `copy(t, Cons(0, xs))`, where `t` is ys's tail and also xs's: `unproved` | `no-fixpoint` (a by-name set with no shadow discipline) → `FAIL copy certificate … Received: "structural"` |
| `mutual_nat` | `even`/`odd` on `Nat`, annotated and as multi-head clauses: `structural` | positive control |
| `mutual_two_adts` | `tsize`/`csize` on `Tree`/`List(Tree)` (different families): `unproved:not-same-family` | `no-same-adt` (any type accepted) → `FAIL tsize certificate … Received: "structural"` |
| `mutual_family` | `tsize`/`fsize` on `RTree`/`RForest` (one family): `structural` | positive control; the existing `mutual-mc` group is its RED (below) |
| `mutual_nullary` | an edge passing `Z`: `unproved` | `always-structural` |
| t11 | `apply2(h, x)` inside `h`: `unproved:reference` | `no-reference-rule` → `Received: "unproved:no-structural-arg"` |
| t11b, lambda-diverges | a lambda edge with an unrelated argument (`walk([1])` loops through a callback): `unproved` | `no-lambda-edges` → `FAIL walk certificate … Received: "<no row>"` |
| lambda control | the same lambda edge on a component: `structural` | positive control |
| t9b `grow`, t1, t4 | `unproved` (no Int heuristic) | `always-structural` |
| t11c omega | `nonpositive_types = [Fix]`; `w` is `unproved:non-positive` | `no-positivity` → `FAIL w certificate … Received: "<no row>"` |
| positivity control | `T(Int -> Int)`: no non-positive type, `u` has no row | positive control |
| mutual and generic non-positive | `A`/`B` via `MkA(B -> Int)`; `F(Box(F))` with `Box(a) = Box(a -> Int)` | `no-positivity` |
| structural + non-positive | `r` recursing on `t` while calling `g : Fix -> Int`: `unproved:non-positive` | `no-positivity` → `Received: "structural"` |
| c4 | mutual measures `ma(Z) -> mb(Z) -> ma(Z) + 1`: two `invalid_measure` errors, both with the structural wording | before the gate change: `FAIL two invalid_measure errors  Expected: 2  Received: 0` |
| c4 control | a structural mutual measure pair: no error | positive control |
| c5 | `bad(n)`: exactly the one message it had before (no duplicate) | — |
| report | `cert=` column and `certificate:` line | — |

The perturbations were run by `perturb.py` (in the session scratchpad, not committed): each one
edits `refine_term.ml`, rebuilds, runs `termination*` and restores the file. The c4 row fails in
every perturbed build, because the gate change was not yet applied when they ran.

## The sweep (stdlib and test/native, deduplicated by declaration site)

| | stdlib | test/native |
|---|---|---|
| recursive units | 763 | 523 |
| class A (syntactic structural, phase 0) | 466 | 74 |
| certified structural | **435** | **67** |
| `unproved:no-structural-arg` | 283 | 455 |
| `unproved:not-same-family` | 43 | 1 |
| `unproved:reference` | 2 | 0 |
| `unproved:non-positive` | 0 | 0 |

No unit outside class A is certified. 31 stdlib and 7 native class-A units are not:
- 23 stdlib units are mutual cycles through a `List` of children, which the type-family rule excludes;
- 8 stdlib and 7 native units are mostly tuple-scrutinee multi-head functions
  (`match (xs, ys) do (Cons(a, ar), Cons(b, br)) -> f(ar, br)`), which `structural_subvars` does not follow.

Both groups are filed in `2026-10-27-termination-structural-certificate-gaps.md`. Neither
affects a verdict before phase 3. No stdlib or native type is non-positive.

## Rulings

- **Ruling: a mutual SCC is certified over one TYPE FAMILY, not literally one ADT
  (§3.3 says "the same ADT across mutual members").**
  - Why: the spec's rule is wrong against the code. With the literal rule, the existing group
    `mutual-mc` went RED: `FAIL no error  Expected: false  Received: true` in "mutually-recursive
    measures: index 0 is in bounds". The `tsize`/`fsize` measures over the mutually-recursive
    `RTree`/`RForest`, an M-c feature that has always been accepted, became `invalid_measure`.
    A strict pattern component has a smaller constructor depth than the value it came from,
    whichever type of the family it has, and March values are finite (F11). So "types defined
    in terms of each other" is sound. It is also the rule for mutual inductive types in
    Coq/Agda.
  - The REJECT control was moved to a pair of types that are *not* one family, a `Tree`
    through `List(Tree)`.
  - Cost if wrong: none for soundness under the size argument. The narrower spec rule would
    have rejected a shipped, tested measure.

- **Ruling: the measure gate keeps the self-call rule and adds the SCC certificate,
  rather than replacing one with the other (§6 says "replaced").**
  - Why: the union can only reject more, so no measure that is rejected today is newly accepted. The
    message text is unchanged, and it is emitted once.
  - Cost if wrong: none for soundness. A measure the certificate accepts but the old rule
    rejects (a two-parameter measure recursing structurally) stays rejected. That is
    today's behaviour, and the shape gate requires one parameter anyway.
- **Ruling: strict positivity lives in `Refine_term`, not beside `check_nonregular_types`
  in the typechecker (§3.6).**
  - Why: it is report-only in phase 1 and feeds only the termination pass. Placing it in
    `typecheck.ml` would make it a typechecker change, with a types-oracle obligation and a
    diagnostic nobody asked for.
  - Cost if wrong: if a later phase wants a positivity *diagnostic*, the function moves; it
    is self-contained.
- **Ruling: positivity enters phase 1 (the spec schedules it for phase 2).**
  - Why: the brief asked for it, and a structural certificate that ignores a non-positive
    function-value call would certify a member of an omega-style loop. Gating the certificate
    on positivity now means phase 3 can trust it unchanged.
  - Cost if wrong: none; it only withholds certificates.
- **Ruling: types are compared by their last dotted segment** (`M.Fix` = `Fix`), for ADT
  sameness and for taint.
  - Why: declarations are bare and uses may be qualified.
  - Cost if wrong: two distinct same-named types merge. For positivity, merging only adds
    non-positive types (safe). For ADT sameness, two different types named alike could
    count as "same". That stays sound by the size argument in the gaps todo (a strict
    component decreases constructor depth whatever its type); it only matters as a
    narrower-than-intended rule.
- **Ruling: a function-value call with no recorded type counts as tainted only when some
  non-positive type exists.**
  - Why: with no non-positive type declared, no type can mention one. That keeps the
    untyped test harness and the measure gate (which can run without a `type_map`) exact,
    without assuming every closure is dangerous.
  - Cost if wrong: a non-positive type defined outside `decls` (not possible: the driver
    passes the stdlib-prepended module).
- **Ruling: the termination pass trusts calls to builtins, externs and constructors**, which are not
  nodes of the graph (§3.6, decision 10). They are not yet counted as `trusted` in the
  report; that count is a phase 2 addition alongside `Obligation.Termination`.

## Oracles

- `scripts/refine-oracle.sh check` (baseline recorded before any edit, same `_build`):
  `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines over 552 fixtures)`. The RED table
  expected changes only on fixtures with mutual measures; there are none in the corpus.
- The oracle was proved able to go red: a build whose `uncertified` answers `true` for every
  measure. That run gave `DIAGNOSTICS CHANGED — 18 differing lines`, for example
  `+stdlib_array: @[measure] \`pvec_length\` is not structurally recursive (…) [invalid_measure]`.
- `scripts/ir-oracle.sh check` against the pristine-`c918d14ca` baseline (frozen exe):
  `IR IDENTICAL across 497 programs`. The check runs in the baseline's own directory, because
  the `.ll` embeds the fixture's absolute path; a copy of the baseline in another directory
  changes every hash.
- The typechecker is untouched, so there was no types-oracle run.
- Timing (§9, ≤ 105% for default `--check`): within budget. The A/B runs were interleaved, five each, with medians taken, using the
  frozen pristine `c918d14ca` exe against the final exe at load average 6-14:
  - `--check --refine-report stdlib/list.march`: 1.277 s → 1.322 s (103.5%);
  - `stdlib/json.march`: 1.308 s → 1.331 s (101.7%).

  The graph is built only when a module has a measure, and the stdlib always has one.
- **Apparatus trap, recorded so it is not mistaken for a regression.** One `refine-oracle`
  check reported `DIAGNOSTICS CHANGED — 1017 differing lines`, all of them
  `stdlib_internal` / `trusted_linear_reserved` errors on stdlib fixtures. The cause was a
  `_build/default/stdlib` directory (137 files, two of them stale) that appeared at 15:05
  during the session. With it present, `main.exe` resolves its stdlib exe-relatively to that
  copy, so `stdlib/*.march` no longer counts as the shipped stdlib. Removing the directory and
  re-running gave `IDENTICAL`; the code was unchanged between the two runs. This is the
  `project_build_stdlib_missing_copies` trap.

## Suites

Full `scripts/run-tests.sh` (load average 5-14): `All suites passed`. The counts were 13 suites and
6083 tests, including `march-refinecheck` (1854 tests; the 40 `termination-*` cases among
them), `march-compiler` (1453) and `errors` (296).

The literal same-ADT rule had turned `mutual-mc` red, as recorded in the ruling above. That
was the only failure seen during the work, and the final build has no failures.
