# An `Option` element return through a recursive local `fn` (O1)

Landed 2026-10-24. Closes `specs/todos/2026-10-21-refine-local-fn-option-return-unproved.md`
(moved here), row O1 of `specs/2026-10-20-refinement-suggest-lite-design.md` §0. Lifts G3-3 of
`specs/2026-10-18-element-flow-followups-design.md` ("No self-call hypothesis for a local …
Lifting this is the same structural rule plus scoping").

```march
fn fidx(xs : List(Int), pred : Int -> Bool) : Option({Int | _ >= 0}) do
  fn go(lst : List(Int), i : {Int | _ >= 0}) : Option({Int | _ >= 0}) do
    match lst do
      Nil -> None
      Cons(h, t) -> if pred(h) do Some(i) else go(t, i + 1) end
    end
  end
  go(xs, 0)
end
fn user(xs : List(Int)) : Int do
  match fidx(xs, fn y -> y > 3) do
    Some(i) -> need_nn(i)
    None -> 0
  end
end
```

Before: 3 skips (`unreflectable-subject` at `return of go`, `return of fidx`, and
`unconstrained-subject` at `need_nn(i)`). Now: every user obligation proved.

## Root cause

Not what the todo guessed. A local `fn`'s `Option` return IS checked through its
`Some(e)` tails and lent once proved (element-flow phase 3 works for any registered
container; a non-recursive `fn one(n) : Option({Int | _ >= 0})` already proved, lent through
a `match`, and a `Some(0 - 1)` tail was already a violation, measured on the base). The
find_index shape is RECURSIVE: its third tail is `go(t, i + 1)`, and a self-call of a local
carried nothing — phase 3's ruling G3-3, because `elem_ret_hyp`'s arm (`hyp_applies`)
refuses any name in `ctx.locals`. So that tail skipped, `go` was not proved, nothing was
lent, and `fidx` and the use skipped in turn. The same held for a recursive local
`keep(lst) : List({Int | _ >= 0})`.

## Fix (`lib/refinecheck/refine_check.ml`)

- `local_elem_hyp`: a local's structural self-call hypothesis, the top-level
  `elem_ret_hyp` scoped to one signature. `container_entry_of_expr`: a call whose `cbenv`
  entry IS the local's signature (physical equality, so a rebinding of the name inside the
  body is never a self-call), with some argument a structural subvariable of the matching
  parameter (`structural_subvars`, minus `ambiguous_names`), gets the declared entry — closed,
  or relational over the local's own formals and read at the call's actuals (`lend_entry`).
- `visit_local_fn`: the walk is factored into `walk errctx hyp`. For a `Single` entry the
  local could lend at all (`lendable`: closed or movable over its formals, not naming the
  enclosing function's abstract refinements), a local declaring no abstract refinement of its
  own, and a body that mentions the local's name, a GATING walk runs first: under the
  hypothesis, in `Obligation.with_scratch`, with a fresh `Err.create ()`, and with
  `strict_verified`, `unverified_hinted`, `last_elem_return_proved` and
  `local_elem_ret_proved` restored afterwards. Only if it proves the return is the recorded
  walk made under the hypothesis; otherwise the recorded walk is the pre-O1 one. This is
  `gate_elem_returns`' discipline for top-level functions, so no proof from an unproved
  hypothesis is ever recorded (the `Some(0 - 1)` control pins it: zero proved obligations
  under `return of go`).
- The induction gate (`local_elem_self`) is unchanged and applies in both walks: an unproved
  element argument at a self-call clears the local's verdict.
- Registration in `local_elem_ret_proved` uses the same `lendable` test as before (only
  factored), so what may be lent is exactly phase 3/4's rule; `None` owes nothing (no
  element to check), as before.

## Tests (group `gap-o1-local-option`, 7 cases)

RED on the R2 commit (`753e43a7e`) + this group: 2 failing, the 5 controls passing.

| # | Case | RED on base | Now |
|---|---|---|---|
| 0 | find_index shape: `return of go`, the two `go(…)` tails, everything | `return of go`: Expected `[("proved", ""); ("proved", "")]`, Received `[("proved", ""); ("skipped", "unreflectable-subject")]` | all proved, `need_nn` proved |
| 1 | `Some(0 - 1)` tail | control | violated, 0 proved under `return of go`, nothing lent |
| 2 | `Some(h)` (unproved) | control | skip, not lent |
| 3 | non-structural `go(lst, i + 1)` | control | self-call tail skips, not lent |
| 4 | self-call with an unproved element argument (`go(t, Cons(h, acc))`) | control | self-call tail skips (gate), `keep` not proved |
| 5 | recursive local `keep(lst) : List({Int \| _ >= 0})` | `return of keep`: Expected three proved, Received `[proved; skipped unreflectable-subject; skipped unreflectable-subject]` | all proved, lent at `sum_nn(keep(xs))` |
| 6 | `let go = fn …` rebinding inside the body | control | not proved |

(Case 0's assertion was relabelled after the fix to the recorded subjects — the proved
self-call tail and `fidx`'s tail are recorded under `go(…)` — and still fails on the base,
where the self-call tail is a `return of go` skip.)

Edited existing tests, deliberately: `elemflow-local-fn` "a recursive local: no self-call
hypothesis, lends nothing (G3-3)" now asserts that `keep(t)` proves and `keep(ys)` is lent
(the lifted ruling); `infer-elements` "O1: … rejected as not-true" now asserts the
`_ >= 0` element return of `fidx` is proposed.

`scripts/run-tests.sh refinecheck` on this commit before the `infer-elements` edit: 1608
tests, the only failure that case; after the edit that group passes. The whole suite is
green on the branch tip (1616 tests, see the Deque note).

## Oracle

Baseline from the unmodified base (8742 lines, 551 fixtures), private `HOME`:
`REFINEMENT DIAGNOSTICS IDENTICAL (8742 lines over 551 fixtures)`. No corpus fixture has a
recursive local with a declared element return, so nothing could move.

Proving the oracle can go red, on this binary: (1) declining every CLOSED lambda reading in
`instantiate_abstract` left the oracle IDENTICAL — the corpus has no arity-1 abstract
refinement instantiated from a lambda under a demand, so R2's code path is not covered by
the corpus at all (only by the tests); (2) declining every BY-NAME instantiation in the same
function gave `DIAGNOSTICS CHANGED — 1662 differing lines` (e.g.
`native_actor_call_canonical: skipped (abstract-refinement-uninstantiated): 15`). Source
restored and `cmp`-checked, binary rebuilt. `stdlib/list.march` ratchet: 37 skipped,
unchanged.

## Rulings

- Ruling: the local hypothesis is GATED by a scratch walk, not trusted from the same walk's
  final verdict — a proof recorded under a hypothesis the walk then refutes would be a
  false `proved` line in the ledger — cost if wrong: a second walk of a recursive local's
  body (only for a local whose body mentions its own name and whose entry is lendable).
- Ruling: a self-call is identified by the PHYSICAL `cbenv` signature, never by name —
  a `let go = …` inside the body, or a sibling local of the same spelling, is a different
  binding — cost if wrong: none (a lost proof at worst).
- Ruling: a local declaring its own abstract refinement gets no hypothesis — the top-level
  rule needs `definers` (the callback received unchanged), which a local's `cbenv` does not
  record in the same way — cost if wrong: such locals stay skips.
- Ruling: scalar preconditions at a self-call are not part of the gate, exactly as for a
  top-level function (measured: `go(t, k, i + k)` top-level and `lgo(t, i + k)` local both
  prove their return with the precondition `i + k >= 0` a `solver-undecided` skip, which is
  reported, and an error under `cap verified`) — cost if wrong: the same modular trust a
  top-level function's return already gets.
- Ruling: only a `Single` entry gets the hypothesis; a tuple return keeps phase C's
  check-but-lend-nothing rule — cost if wrong: a recursive local returning a tuple stays a
  skip.
