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
