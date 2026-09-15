# `[P3]` `Array` contract follow-ups from #460

Filed 2026-09-15. Three gaps left by the `Array.get`/`set`/`pop` bounds
contracts (`specs/progress/2026-09-13-array-bounds-contracts.md`):

- the violation message and its suggested guard spell the private measure
  `pvec_length(v)`, which user code cannot write;
- `Array.get(v, -1)`'s counterexample reads `(e.g. negate = 0)`, because the
  witness treats the head of `negate(1)` as a variable;
- `Array.from_list`, `empty`, `push`, `set` and `map` carry no length
  postcondition, so `Array.get(Array.from_list([1, 2, 3]), 7)` is skipped
  rather than reported.

Design: `specs/2026-09-15-refinement-remaining-designs.md` §A.

## Landed 2026-09-15

### Diagnostics

- `Refine_encode.display_measures` rewrites `pvec_length(` to
  `Array.length(` in finished message text, at an identifier boundary and only
  while `array_length_is_stdlib` holds (the same gate as the alias). Applied at
  the call-site violation message and its argument label, the unverified hint
  (including a `Partial_conjunct`'s held/missing split), the `cap verified`
  error and the "propagates a requirement" warning in `refine_call.ml`. The
  ledger's `Obligation.predicate` keeps the raw spelling, so the audit
  baselines and `--refine-report` identities do not move.
- `Witness.free_vars` no longer treats the head of `EApp (EVar _, …)` as a
  variable; `-1` is `negate(1)`, which produced `(e.g. negate = 0)`. A closed
  argument (no free variables) now gets no example at all: the message already
  quotes the literal. A symbolic argument still gets its validated example
  (`(e.g. i = -1)`).

### Length postconditions (`stdlib/array.march`)

| Function | Postcondition | Status |
|---|---|---|
| `empty()` | `pvec_length(_) == 0` | proved (bare constructor) |
| `push(v, elem)` | `pvec_length(_) == pvec_length(v) + 1` | `@[assume]` — body skipped `unreflectable-subject` (tail-full branch through `push_leaf`'s tuple) |
| `set(v, idx, val)` | `pvec_length(_) == pvec_length(v)` | `@[assume]` — body skipped `unreflectable-subject` (tail/trie `if`) |
| `map(v, f)` | `pvec_length(_) == pvec_length(v)` | `@[assume]` — not attempted (through `to_list`/`from_list`) |
| `from_list(xs)` | `pvec_length(_) == len(xs)` | `@[assume]` — not attempted (accumulator `go` over `push`) |

`pop` returns a tuple; tuple-component postconditions are outside the
fragment, so it has none.

Each assumed contract has a runtime witness in
`test/stdlib/test_array.march` ("assumed length contracts (runtime
witnesses)"), at 0, 1, 2, 31, 32, 33, 63, 64, 65, 1023, 1024, 1025, 1057
elements and over random lists. Changing `push`'s trie-branch count to
`n + 2` turns the witnesses (and three existing tests) red.

What composes: a relation over a parameter or a guarded value reaches a
`let`-bound result (`if Array.length(v) > 2 do let p = Array.push(v, x)
Array.get(p, 3)` proves; index 4 does not), and `from_list`/`empty` facts
reach a literal index. What does not: two chained `let`-bound calls
(`push` of a `push` of `empty()`), where the checker does not carry one call's
assumed postcondition into the next call's reflection. Documented in
`specs/lang/refinement-types.md` and `docs/refinement-types.md`.

### Tests

`test/test_refinecheck.ml` group `array-contract-followups` (7 cases):
message text, symbolic-index example, hint split, `display_measures` gate and
boundary, `from_list` literal index (7 and 3 violated, 2 proved, guarded
`List.length` proved), `push`/`set`/`map` let-bound relations (each with a
not-proved twin), `empty()` index violated. RED evidence: `display_measures`
forced to identity fails 3; restoring `free_vars`'s head and the closed-arg
example fails the message test; stripping the five postconditions fails the 3
postcondition tests.
