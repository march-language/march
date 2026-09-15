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
