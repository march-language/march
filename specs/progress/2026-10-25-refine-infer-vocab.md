# Inference vocabulary: the refinement shapes the checker gained in October

Branch `claude/refine-infer-vocab`, base `bf49708ec` (main with #1016, #1020-#1025).
`march --refine-infer` / `forge refine --infer` (design
`specs/2026-10-20-refinement-suggest-lite-design.md`) learns the shapes the checker
proves since October: relational scalar returns (G1), two-argument abstract
refinements, relational element refinements, and `Map`/`Deque` element and abstract
slots. The real checker stays the only judge: every new candidate goes through the same
oracle (`lib/refinecheck/infer_oracle.ml`).

## 1. Relational scalar returns (G1)

`Infer_vocab.rel_returns`: for an `Int`/`Float` return, candidates `_ OP x` over a
parameter `x` of the return's own sort, read off the body's tails (through blocks,
`if` and `match` arms), never the cross product of parameters and operators:

| Tail | Candidates |
|---|---|
| `x` | `_ >= x`, `_ <= x`, `_ == x` |
| `x + c` (literal `c > 0`) | `_ > x`, `_ >= x`, `_ == x + c` |
| `x - c` (literal `c > 0`) | `_ < x`, `_ <= x`, `_ == x - c` |
| `x + y`, `x - y` (both parameters) | `_ == x + y`, `_ == x - y` |

Inequalities come first, then equalities, at most 4 per slot. They are Body-sourced and
have their own allowance on top of the 12-candidate cap.

**Bug found and fixed: the implication order never ordered a relational candidate.**
`Infer_vocab.implies` asks the checker whether `c1 ⇒ c2` by passing a parameter refined
by `c1` to one demanding `c2`. The scope names (`x`) were declared AFTER the subject
parameter, and a refinement may only name an earlier parameter: the subject was then
`unconstrained-subject`, so every relational implication was "not proved". Relational
candidates were therefore incomparable and ordered by text, which put `_ == x + 1`
(`'='` sorts before `'>'`) ahead of the weaker `_ > x`. The scope now comes first, and
the subject parameter has a name no user parameter can clash with (`__infer_imp_v__`).

Tests (`test/test_refinecheck.ml`, group `infer-vocab-oct`, rows 0-4). RED on the base
(lib reverted, test file kept): `inc` proposed `[]` (expected `{Int | _ > x}`); the
vocabulary for `x + 1` was `_ > 0; _ != 0; _ >= 0; _ <= 0; _ < 0`; `add` proposed `[]`
(expected `{Int | _ == x + y}`); the apply case wrote nothing. The control (`dec(x) =
x - 1` into `need_pos(dec(n))`, nothing proposed) passed before and after. With the
candidates but before the order fix, `inc` proposed `{Int | _ == x + 1}`.

## 4. `Map` / `Deque` element slots

`Infer_slot` gives a container of several type arguments one slot per argument
(`Arg (i, p)`, JSON `return/elem.0`, `return/elem.1`); a one-argument container keeps
`Elem` (`return/elem`), so every existing slot name and test is unchanged. The walker,
the renderer and the installer (`steps`/`refine_at`) know the new step; the Body source
treats an `Arg` slot as an element slot (its binder is a lambda parameter).
`Map(k, v)` is a registered container, and `Map.filter` lends its entry fact
(2026-10-24), so a wrapper is proposed `Map(String, {Int | _ > 0})` (value slot) or
`Map({Int | _ > 0}, String)` (key slot).

`Deque.Deque(a)` element slots needed nothing: since #1022 (qualified container types)
the one-argument path already proposes `Deque.Deque({Int | _ > 0})` on the base. That
row is pinned, not RED.

Tests (`infer-vocab-oct` rows 5-9, through the real driver so the whole stdlib is
loaded). RED on the base: `pos_vals` and `pos_keys` proposed `[]`, and the apply case
wrote nothing. Controls: a wrapper returning its input unchanged proposes nothing
(passed before and after); the Deque pin passed before and after.

## 2. Two-argument abstract refinements (K6)

`Infer_slot.k6_callback_vars` accepts a curried `keep : k -> v -> Bool` (distinct type
variables) as well as `f : a -> Bool`. `k6_returns` then offers, for a registered
two-argument container whose arguments are exactly `k, v` in order, `T(k[p], v[p])`
(the multi-arg sugar, phase 3). One-argument callbacks now also cover every registered
one-argument container (`Deque.Deque(a[p])`), not only `List`/`Option`. The graft parses
the re-spelled signature as before and then runs `Refine_abstract.expand_markers_fn` on
it, because `check_module` expands the occurrence sugar in a pre-pass the inference
never sees. TRUE and USEFUL are the existing K6 judgment (`k6_verdict`).

**Bug found and fixed: every K6 apply reverted (exit 3).** `Refine_infer.run`'s
`install` marked an accepted proposal's element return as proved in
`Refine_param.elem_ret_proved` only for a non-`Param` path; a K6 slot IS a parameter
path (the callback), so its arm was unreachable. The final prediction then read the
definer's own recursive calls and its callers as `abstract-refinement-uninstantiated`
("`filt`'s own body is not proved"): for a rediscovered one-argument `filter`, "predicted
3 skipped, got 0", every edit reverted. Main has this bug (reproduced with the base
compiler: `user skips 1 -> 3`, "if applied: 3 skipped"); the K6 unit tests never applied
a proposal. The K6 install now marks the table.

Tests (`infer-vocab-oct` rows 10-16). RED on the base: the `Assoc` `filt` proposed `None`
(expected `k -> v -> Bool[p]` / `Assoc(k[p], v[p])`); the apply case wrote nothing;
`dfilt` over `Deque.Deque(a)` proposed `[]`. After the candidates and before the install
fix, the `Assoc` apply exited 3 ("predicted 3 skipped / 0 violated, got 0 skipped"); the
one-argument apply row exits 3 on the base compiler. Controls: a1-bad (the body returns
its input) is not proposed; a caller with no demand gets nothing for `filt`; a `Map(k, v)`
combinator passing its callback to `Map.filter` is not proposed, because the checker does
not prove the hand-annotated version either (`abstract-refinement-uninstantiated` at its
own return; filed as `specs/todos/2026-10-25-refine-map-filter-two-arg-passthrough.md`).

## 3. Relational element refinements (Demand-driven only)

`Infer_slot.rel_slots` / `rel_demands`, `Infer_oracle.best_whole`, `Refine_infer`'s
`try_rel`. A root (parameter or return) whose type is a registered container of several
arguments, none refined, is a K5 slot. Its candidates come from the Demand source alone:
- for a return, every call `g(…, f(…), …)` in the unit;
- for a parameter `x`, every call `g(…, x, …)` in the function's body.

When `g`'s parameter at that position has a relational type (a slot predicate naming a
sibling binder) whose refinement-free spelling is the slot's own type, that type is the
candidate, written whole. A return is judged as an element return (TRUE through the
element-return gate, USEFUL at a caller). A parameter is judged as a precondition
(closes a body site, no caller violation, satisfiable, not vacuous). Returns run in the
F-phase after K6, parameters in the D-phase. The budget is 12 probes per root. JSON
`kind` is `element-return` / `element-param`, and `slot` is the root (`return`,
`param a`).

Proposed: `mk(n : Int) : Assoc({x : Int | true}, {y : Int | y > x})` for `ACons(n, n +
1, ANil)` under `need_arel(mk(n))`, and `f(a : Assoc({x : Int | true}, {y : Int | y >
x}))` for `f(a) = need_arel(a)`.

**Bug found (introduced by item 4 on this branch, fixed here).** With per-argument slots,
the House predicate `true` (from the relation's free slot `{x : Int | true}`) became a
candidate. `Assoc({Int | true}, Int)` (and, once `true` was filtered,
`Assoc({Int | _ != 0}, Int)`) was then proposed for both `mk` and `f`. A relational
demand on a call whose subject the checker cannot read is recorded as one skip: the goal
`true` of the relation's free slot. Giving that slot any refinement creates an entry,
which closes the `true` goal, and the relation then appears at the same call as a new
skip (net 0, admissible). Two guards:
- `Infer_vocab.admissible_text`: a candidate must mention `_`.
- `Infer_oracle.diff`, the diff every verdict reads: a closed `true` goal at a call that
  gains an unsettled obligation does not count.

The whole relation still closes the goal, because nothing new is left unsettled at that
call.

Tests (`infer-vocab-oct` rows 14-18). RED on the item-2 commit: `mk` and `f` each
proposed `Assoc({Int | true}, Int)`, the relation was never proposed, the violating
caller was not refused, and the apply case wrote nothing. Controls:
- `mk` with body `ACons(n, n, ANil)` gets nothing;
- `f` with a caller passing `ACons(5, 2, ANil)` is refused `caller-violation`.

Ruling: only the Demand-driven case. A `bump`-shaped function, `Assoc(Int, Int) ->
Assoc(Int, Int)` keeping `y > x`, needs the relation on the parameter AND the return at
once. A joint probe would need a K6-like two-edit proposal and its own admissibility
(caller burden plus return TRUE). It is not done: `test/native` has no two-slot
container type with a relation at all (grep), so the case is rare. Filed:
`specs/todos/2026-10-25-refine-infer-joint-relational-param-return.md`. Cost if wrong:
`bump`-shaped contracts are not found; the user writes both annotations.

## 5. Fold accumulators (K7)

Checked first, as the brief asks: K7 did NOT cover the annotated-accumulator shapes the
checker proves (`specs/progress/2026-10-18-fold-invariants-phase4.md`). Each of these was
proved hand-annotated (`--check --refine-report`: 2 or 3 proved, 0 skipped) and got
nothing stripped (`--refine-infer`: 0 proposed):
- a parameter initial value (`List.fold_left(ys, n, fn (acc, _x) -> …)`, `n : {Int | _ > 0}`);
- a `fold_right` step, whose accumulator is the SECOND lambda parameter (`fn (_x, acc)`);
- a negated literal (`0 - 1`, with `need_neg`).

The cause: v1 read the base type only from an Int literal argument, and only looked at
the first lambda parameter.

`Infer_slot.k7_slots` now:
- takes the accumulator at whichever callback domain is the callee's return variable `b`
  (exactly one), when the lambda's parameter count equals the chain's;
- reads the base from the initial value. That may be an Int or Float literal, a
  difference of two literals of one sort, or a parameter of the enclosing function
  declared `Int`/`Float` (refined or not).

The annotation text uses that base (`{Float | …}` for a Float accumulator). Curried steps
(`Enum.fold`'s `fn acc -> fn x -> …`) stay out, because the checker declines their
outer lambda too.

Tests (`infer-vocab-oct` rows 19-24). RED on the item-3 commit: the parameter-init,
`fold_right` and `0 - 1` rows proposed `[]`, and the `fold_right` apply wrote nothing.
Controls, unchanged before and after:
- a parameter init with a breaking step (`acc - 1`) proposes nothing;
- an unrefined parameter init (`n : Int`, base unproved) proposes nothing.

## Cost: what the first re-measure showed, and the three fixes

The first `test/native` run of the branch (items 1-5, ungated) accepted nothing new and
cost more than main:

| Run | median | p90 | aggregate |
|---|---|---|---|
| main | 1.38× | 1.83× | 1.73× |
| branch, items 1-5 only | 1.39× | 4.86× | 2.17× |

The increase came in quanta of about 8 s per file (up to +47 s on
`node_send_loopback.march`), with the same probe count. A `--refine-infer-kinds` bisection
put all of it in K5, and the causes were:

1. **`rel_demands` walked every body in the unit**, the stdlib included, with a function
   lookup per call. This ran for every two-argument-container root, and every
   `Result(a, e)` return is one. It now collects the unit's functions with a relational
   parameter first (one pass over signatures). That set is usually empty, and then no
   body is walked. This fix alone removed the regression.
2. **The per-argument slots are demand-gated** (`Refine_infer.try_slot`). An `Arg` return
   slot is tried only when a function that calls it has an unsettled obligation
   (`Infer_vocab.caller_has_skip`, spans first, bodies last). An `Arg` parameter slot
   needs a skip in its own body. The relational returns (item 1) use the same caller gate
   in place of "has an in-unit caller".
3. **The implication order is applied lazily** (`Infer_oracle.best_for_slot ~order:true`).
   Candidates are probed in mining order (Demand, House, Body, Fixed). Only the
   candidates that tie for the best score are put in implication order, weakest first, to
   break the tie. Since the order fix in item 1, relational pairs are real solver queries,
   so ordering a slot's whole list up front had become the expensive part.

Ruling: lazy ordering picks the same candidate as ordering everything first, except in
two cases:
- a third, non-admissible candidate would have changed the relative order of two tied
  ones through transitivity;
- the global budget runs out mid-slot, which now drops the lowest-RANK candidates
  instead of the strongest.

Why: the order exists only to break ties among admissible candidates, and with
relational queries it cost more than all the probes. Cost if wrong: on a tie involving
such a transitive chain, a stronger candidate could be proposed where a weaker one was;
both are proved.

## Evaluation over `test/native` (417 files)

The protocol is the evaluation note's. Each file gets a cold `--check` and a cold
`--check --refine-infer-json`, each in a fresh cwd and `HOME`, 4 files in parallel, with
z3 on `PATH`. The stdlib is the worktree's (`MARCH_STDLIB`). The compilers are copies of
`_build/default/bin/main.exe`: main at `bf49708ec`, and this branch at `e21defcfb`. Main
was measured twice:
- once while the refine-oracle baseline ran beside it (load 8-10);
- once alone, right before the branch's final run (load 3-8).

Both main runs gave identical counts and ratios within 0.01. The table uses the second
run. Raw outputs are kept outside the repo.

| Metric | pre-#1020 baseline (2026-10-21/23 notes) | main `bf49708ec` | this branch |
|---|---|---|---|
| Files that check | 416 / 416 | 417 / 417 | 417 / 417 |
| User skips before → after | 13 → 13 | 13 → 13 (5 files) | 13 → 13 |
| Violations before → after | 0 → 0 | 0 → 0 | 0 → 0 |
| Accepted, by kind | 1 precondition (`set_n` `n : {Int \| _ <= j}`, vacuous) | **0** | **0** |
| Refused | 11 (2026-10-21) / 6 (2026-10-23) caller-violation | 0 | 0 |
| Rejected: not-true / vacuous-branch | 3683 (2026-10-21) / 0 | 3625 / 5 | 3666 / 5 |
| not-true detail: return / element return / accumulator | 3099 / 391 / 193 | 3049 / 383 / 193 | 3060 / 381 / 225 |
| Notes: scc-unsupported / vocabulary-truncated | 16 / 2 | 16 / 2 | 16 / 2 |
| Probes | 11 778 | 11 467 | 11 474 |
| Infer ÷ check, median / p90 / aggregate | 1.38× / 1.69× / 1.49× (2026-10-23) | 1.38× / 1.83× / 1.73× | 1.38× / 1.81× / 1.74× |
| Max ratio | 23.7× | 15.1× (`nativearr_fold_sum_fusion`) | 15.9× (same file) |
| Prediction mismatches | 0 of 1 | 0 (nothing to apply) | 0 (nothing to apply) |

Main versus the pre-#1020 baseline: the one accepted proposal is gone. `set_n`'s
`n <= j` is now `vacuous-branch` (2026-10-23). There are 5 `vacuous-branch` rejections
in all, in `array_trie_drop_leak_probe` and `float_generic_field_abi`. The aggregate ratio is higher (1.49× → 1.73×). The median is
unchanged, so the growth is in the tail, and it was there before this branch.

This branch versus main: **nothing new is accepted on `test/native`.**
- The 13 user skips there are not of the shapes this branch adds. They are in 5 files,
  and no caller of a relational, Map, Deque or two-argument
  combinator is involved.
- The new candidates that were probed were all rejected `not-true`:
  - 25 return candidates: relational `_ >= acc`/`_ == n`, and fixed signs on `unwrap`
    that the `true` filter un-truncated;
  - 32 accumulator candidates on the new accumulator slots: `Float` and parameter
    initial values, and `fold_right` steps (`_ > 0.0`, `_ < 0`, and similar).
- 16 `true` candidates (always useless) are no longer probed.

Cost is at main's: median 1.38×, p90 1.81×, aggregate 1.74× against 1.73×. Before the cost
fixes above it was p90 4.86×.

The shapes this branch adds are proposed, and re-check as predicted, on the unit and
apply fixtures (`infer-vocab-oct`). Every applied fixture re-checks exactly as predicted:
the item 1, 2, 3, 4 and 5 apply rows and the one-argument K6 row.

### Newly accepted proposals

On `test/native`: none. On the fixtures, each is a contract a caller in the fixture
needs, and the checker proves it. Judgment on each:
- `inc(x : Int) : {Int | _ > x}`: real. It is the weakest relational return that closes
  `need_pos(inc(n))`, and it is preferred over `_ == x + 1`.
- `add(x, y) : {Int | _ == x + y}`: real, but exact: it restates the body. `_ > x` is not
  a candidate here, because the tail `x + y` has no literal offset, so the equality is
  the only relational fact offered.
- `filt : k -> v -> Bool[p]` / `Assoc(k[p], v[p])`: real. It is the multi-arg `filt`
  contract.
- `dfilt : a -> Bool[p]` / `Deque.Deque(a[p])`: real.
- `pos_vals : Map(String, {Int | _ > 0})` and `pos_keys : Map({Int | _ > 0}, String)`:
  real.
- `mk : Assoc({x : Int | true}, {y : Int | y > x})`: real.
- `f(a : Assoc({x : Int | true}, {y : Int | y > x}))`: real. It is a precondition the
  body needs, and a violating caller refuses it.
- `fn (acc : {Int | _ > 0}, _x)` with a parameter init, `fn (_x, acc : {Int | _ > 0})`
  in `fold_right`, and `fn (acc : {Int | _ < 0}, _x)` with `0 - 1`: real invariants.

Vacuous or odd, all found and stopped before the final run: `Assoc({Int | true}, Int)`
and `Assoc({Int | _ != 0}, Int)` (item 3), both from the per-argument slots of item 4.

## Verification

- `scripts/run-tests.sh refinecheck` (z3 on `PATH`): `Test Successful … 1685 tests run`,
  "All suites passed". `infer-vocab-oct` has 28 cases, every one watched failing on the
  commit before its item, or a control or pin that passed before and after.
- `scripts/refine-oracle.sh` (private `HOME`): **IDENTICAL**, 8750 lines over 552
  fixtures, against a baseline of `lib/refinecheck` at `origin/main` in the same `_build`.
  The first baseline (7873 lines, taken before any edit) could not be compared. A
  `scripts/run-tests.sh` run in between staged `_build/default/stdlib`. That moved 1017
  lines of non-refinement stdlib diagnostics (`stdlib_internal`, `cap_needs`) and **no**
  refinement line, the same staging effect as in the demand-chains note. Plain `--check`
  never runs the inference modules, so the oracle cannot see this branch's code; it pins
  only that nothing else moved.
- `scripts/check-docs.sh`: `doc-lint passed`, with the generated chapters matching.
- Full `scripts/run-tests.sh`: "All suites passed", exit 0 (load 4-5).

## Rulings

- Ruling: relational return candidates come from the body's tails only (`x`, `x ± c`,
  `x ± y`), at most 4, inequalities first — why: the full family (5 operators × every
  same-sort parameter) is mostly not TRUE and each probe walks the callers — cost if
  wrong: a relational return whose tail is not one of these shapes (`max`-like `if`
  tails are covered, `2 * x` is not) is not found.
- Ruling: the relational returns have their own allowance on top of the 12-candidate cap
  — why: never displace a candidate main already probed — cost if wrong: up to 4 more
  probes per return slot that has a caller with an unsettled obligation.
- Ruling: the implication probe declares the scope parameters before the subject — why: a
  refinement may only name an earlier parameter; otherwise every relational implication
  was unprovable — cost if wrong: none found; non-relational queries do not mention the
  scope.
- Ruling: K6's one-argument returns extend to every registered one-argument container,
  and two-argument callbacks to registered two-argument containers whose arguments are
  exactly `k, v` in order — why: the checker's W4 (`entry_shaped`) and the oracle decide
  the rest — cost if wrong: a few wasted probes on a container whose sugar the checker
  rejects (the graft then fails or the oracle rejects).
- Ruling: the K6 install marks the element return proved — why: the oracle proved it
  (`k6_verdict` is the element-return gate), and without it every applied K6 proposal
  failed its re-check — cost if wrong: none; the same mark was already intended (the
  unreachable `|| K6` arm).
- Ruling: relational element refinements are Demand-driven only, one root at a time —
  why: the only candidate that can be USEFUL is the type a caller demands; a joint
  parameter+return probe (`bump`) needs new admissibility rules — cost if wrong: `bump`
  shapes are not found (todo filed).
- Ruling: a candidate must mention `_`, and a closed `true` goal at a call that gains an
  unsettled obligation does not count — why: both made vacuous proposals look useful —
  cost if wrong: a slot whose only demand is a bare `true` gets nothing, which is right.
- Ruling: per-argument (`Arg`) slots and relational returns are demand-gated; other slots
  are not — why: keep this branch's cost at main's without changing which existing
  candidates are probed — cost if wrong: an `Arg` slot whose caller's skip lies in a
  function that calls it only through a qualified name not matched by `fn_calls`'s bare
  name is not tried.
- Ruling: K7 reads the accumulator's base from literals, a literal difference, or an
  `Int`/`Float` parameter; not from arbitrary expressions — why: the base must be known
  without the type map, and these are the shapes the checker's rule documents — cost if
  wrong: a fold whose initial value is a call or a field is not tried.
- Ruling: `Deque.Deque` element slots needed nothing (already proposed since #1022) — the
  row is pinned, not RED.

## Not done (todos filed)

- `specs/todos/2026-10-25-refine-map-filter-two-arg-passthrough.md`: the checker does not
  prove a `Map(k, v)` combinator that passes its two-argument callback to `Map.filter`, so
  inference correctly does not propose it.
- `specs/todos/2026-10-25-refine-infer-joint-relational-param-return.md`: the joint
  parameter+return relation (`bump`).
