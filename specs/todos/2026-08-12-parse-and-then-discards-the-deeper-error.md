# `[P2]` `Parse`: `and_then` discards the deeper error, so ordered choice reports the shallow one

- [ ] **Widen the success channel to carry `(pos, expected)`, or accept the
  regression knowingly.**

  `ROk(value, new_pos, furthest_pos)` carries the furthest offset any
  sub-parse failed at, but only as an `Int` — deliberately, so the success
  path allocates nothing. The consequence is that when a deeper failure is
  later abandoned, the *position* survives and the *expected-set* does not,
  and `and_then`'s failure path therefore keeps only the second parser's
  error.

  This was documented as a known limitation with "revisit once a real grammar
  can judge it". A real grammar has now judged it, and it produces a message
  that is worse than the hand-written parser's:

  ```
  input:  {"a":}
  hand:   unexpected character: '}'
  comb:   1:2: I was expecting `}` in the object that started at 1:1
  ```

  The user's actual mistake is a missing **value** after `:`. What happens:
  `sep_by` ends in `alt(sep_by1, pure(Nil))`; the member parser fails at the
  `}`; `sep_by1` fails; the empty alternative succeeds at the offset just
  after `{`; and the closing-brace parser then fails there. The real failure —
  "a JSON value, at offset 5" — was reachable the whole time and got dropped.

  Options:

  1. **Carry `(pos, expected)` in `ROk`** and merge it on the failure paths.
     Costs an allocation on the success path, which is the thing the design
     explicitly set out to avoid — but see the sibling todo: the success path
     is already allocating far more than this per descent, so the objection
     may be much weaker than it looked when the trade was made.
  2. Keep the `Int` and accept that ordered choice sometimes reports the
     shallow error. Defensible, but it should be a stated limitation with a
     test pinning the bad message, not an accident.

  Do this **after** the memoizing-`delay` work, since that changes the
  allocation budget option 1 is judged against.

  Evidence and full comparison table:
  `specs/progress/2026-08-12-json-combinator-ab.md`.
