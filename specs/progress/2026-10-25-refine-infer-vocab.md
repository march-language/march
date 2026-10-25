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
