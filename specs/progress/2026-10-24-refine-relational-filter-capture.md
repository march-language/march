# A relational element return built by `List.filter` with a captured bound (R2)

Landed 2026-10-24. Closes `specs/todos/2026-10-21-refine-relational-filter-return-unproved.md`
(moved here), row R2 of `specs/2026-10-20-refinement-suggest-lite-design.md` §0.

```march
fn small(xs : List(Int), n : Int) : List({Int | _ < n}) do List.filter(xs, fn y -> y < n) end
fn go(ys : List(Int)) : Int do sum_lt10(small(ys, 10)) end
```

Before: 2 skips (`abstract-refinement-uninstantiated` at `return of small`,
`unreflectable-subject` at the call). Now: 2 proved.

## Root cause

`Refine_check.instantiate_abstract`'s `of_lambda` required the lambda's reading `q` to be
`Closed` over its own parameter (`classify_pred y [] r = Closed`, the C1 rule of leftovers
phase A, inherited from the 2026-09-20 design's "capture-free" decline). `y < n` mentions
`n`, so `p` was never instantiated, `small`'s return was unproved, and phase 4's relational
lending (which would have read `_ < n` at `small(ys, 10)`) never got an entry to lend.

## Fix (`lib/refinecheck/refine_check.ml` only)

- `instantiate_abstract ?stable`: the names `q` mentions besides its binder
  (`pred_value_names`) are admitted when each is written FREE in the lambda itself
  (`Refine_scope.expr_mentions_free`, so a name the reader introduces is not a capture) and
  `stable` holds of it. Default `stable = fun _ -> false`, the old rule. The reading must
  then be `Closed`/`Relational` over those names (`classify_pred y caps r <> Unusable`).
  A decline names the captured variable ("captures `limit`, which is not a local binding of
  this call") when that is why; otherwise the old text.
- `stable_local ctx n = List.mem n ctx.locals`: a name some enclosing binder binds
  (parameter, `let`, `let?`, lambda parameter, local `fn`, arm binder). Passed at both
  call sites, `abstract_flow` (a demand on the result) and `abstract_param_entry` (a
  parameter-slot demand).
- `abstract_flow`'s scratch implication query runs under `~goal_scope_facts` exactly when
  the reading captures, so `$elem : {y < k}` loads `k`'s scope fact (`k <= 10`). A closed
  reading keeps the pre-R2 query (no oracle line moved).
- The produced entry keeps the captured names free. It is relational over the caller's
  scope, like a lent `List({Int | _ < n})`. Nothing substitutes into `q`: an arity-1 slot
  is closed over its binder (`abstract_slot_of_ty`), so no callee formal is in it (the C4
  lesson is satisfied by construction, and tested). The n-ary path
  (`instantiate_abstract_n`) is untouched and still declines a capture.

Why a captured name stays meaningful wherever the fact is read:
- at the call itself (`abstract_flow`, `abstract_param_entry`): the lambda is lexically at
  the call, so its free `n` is the call site's `n`;
- through a `let`-bound lambda (`local_lambda_of lets`) or a `let`-bound call re-read at its
  use (`check_elements`' `lets` arm): the `lets` channel retires an entry when ANY name its
  RHS mentions is rebound (`launder_shadow`, over-approximate `expr_mentions`), so a
  rebinding between the lambda and the use leaves nothing to read;
- at a definer's return: a return demand naming a rebound parameter is already declined
  before the abstract route (`let n = 5` before the tail gives `unreflectable-subject`).

## Tests (group `gap-r2-capture`, 10 cases)

RED on the base (`1686cb24d` + only this test group), 7 failing, the 3 controls passing:

| # | Case | RED on base | Now |
|---|---|---|---|
| 0 | R2: `return of small` / `small(ys, 10)` | `[("skipped", "abstract-refinement-uninstantiated")]` | proved / proved |
| 1 | too-weak `fn y -> y <= n` | `[("skipped", "abstract-refinement-uninstantiated")]` | `solver-undecided` (n unconstrained), call not proved |
| 2 | caller `k : {Int \| _ <= 10}` / `<= 11` | `[uninstantiated]` | proved / `abstract-refinement-too-weak` |
| 3 | definer `let n = 5` before the filter | control (passes) | not proved |
| 4 | `let f = fn y -> y < k; let k = 5` | control | `abstract-refinement-uninstantiated` |
| 5 | `let ys = filter(…k…); let k = 5; sum_lt10(ys)`; unrebound control | `unrebound`: `[uninstantiated]` | not proved / proved |
| 6 | collision: `keep(ys, 0, fn y -> y < n)`, caller `n <= 1000` / `keep(ys, 1000, …)`, `n <= 10` | `[uninstantiated]` | too-weak / proved |
| 7 | helper collision `lt(n, y)` called `lt(y, n)` / `lt(n, y)` | `[uninstantiated]` | proved / too-weak |
| 8 | a `let` inside the lambda introducing `k` | control | not proved |
| 9 | module-level `limit`, named in the detail | `names \`limit\``: false (old text) | uninstantiated, names `limit` |

Edited existing tests, deliberately (each pinned the old decline on an UNCONSTRAINED capture,
which now instantiates and is a skip for the honest reason):
`abstract-phase2` "a capturing lambda is uninstantiated" → `solver-undecided`;
`abstract-phase3` "a let-bound lambda that captures is uninstantiated" → `solver-undecided`;
`abstract-leftovers-a` A8 (`fn y -> gt(y, k)`, `k : Int`) → `solver-undecided`, plus a new
`k : {Int | _ >= 0}` row that proves; `infer-elements` "R2: … rejected as not-true" → the
`_ < n` return is now proposed. The two leftovers-A tests of a `let`-bound lambda capturing
a name and CALLED inside the body are unchanged (still declined by `inline_bool_body`).

`scripts/run-tests.sh refinecheck`: green, 1601 tests.

## Oracle

`scripts/refine-oracle.sh`, private `HOME`, baseline from a build of the unmodified base:
`REFINEMENT DIAGNOSTICS IDENTICAL (8742 lines over 551 fixtures)`. No corpus fixture passes
a capturing lambda to an arity-1 abstract refinement under a demand, so nothing could move.
(A first baseline was taken while a test build ran in the same tree; it was torn, 7865
lines, and 1017 diagnostic-rendering lines differed with no refinement-report line among
them. It was discarded and retaken with nothing else running. The oracle's ability to go
red is shown in the O1 note.) `stdlib/list.march` ratchet: 37 skipped, unchanged (ceiling 42).

## Rulings

- Ruling: "stable" is `List.mem n ctx.locals` — every enclosing binder, including lambda
  parameters and arm binders — because March has no mutable binding and a binder's value
  is fixed for the closure's lifetime — cost if wrong: a capture of a binder that is not
  the one in scope at the use; the channels above retire every rebinding, so this would
  need a reading surviving a rebinding, which none does.
- Ruling: a module-level name (`let limit = 5` at top level) is declined although
  immutable — it is not in `ctx.locals`, and a fact over a global constant is read in the
  scope translation as a free caller name with no fact — cost if wrong: a lost proof only.
- Ruling: a capture must be FREE in the lambda as written, not only in the reading — so a
  name the reader introduces (a `let` inside the body, an inlined helper's internals) can
  never be taken for the caller's — cost if wrong: a lost proof only.
- Ruling: `~goal_scope_facts` only when the reading captures — so the closed case's query,
  and every existing verdict, is byte-identical — cost if wrong: a closed reading against a
  relational demand misses a scope fact it could have used (as before R2).
- Ruling: a definer's too-weak capturing lambda is `solver-undecided`, not too-weak —
  phase 4's free-name rule (an unconstrained caller name blocks the definite-failure
  shortcut) applies unchanged — cost if wrong: a less specific skip reason.
- Ruling: the rebound-capture decline is reported in the words of the channel that drops
  it (`f` "has no proved … return", the use "not known to satisfy it"), not by naming the
  captured variable — the retired entry is gone by the time the call is read, and keeping
  it to name the variable would mean keeping a stale binding around — cost if wrong: a
  vaguer message.
- Ruling: the n-ary path (`instantiate_abstract_n`) keeps its capture decline — its return
  entry names callee formals that `instantiate_entry` substitutes after the abstract
  application, which is exactly where a caller capture named like a formal would be
  captured (C4) — cost if wrong: n-ary filters with a captured bound stay skips.
