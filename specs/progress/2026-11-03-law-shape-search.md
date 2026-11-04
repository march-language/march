# Search by a law's shape (2026-11-03)

The rest of idea 4 in `specs/todos/2026-11-02-lemma-uses-beyond-refinement.md`.

`forge search --law Q` (`Search.search_laws`): when `Q` parses as a call or an operator
application (`shape_of_query`), it is also a pattern over each lemma's theorem, re-parsed
from its text (`has_shape`).

- A one-letter callee (`f`, `g`, `h`) matches any function name, the same one each time.
- Any other identifier matches any subterm, the same one each time (compared span-free by
  `canon`).
- Longer callee names match by last segment (`reverse` matches `List.reverse`), and
  constructors, literals and operators match themselves.
- `==` and `!=` match either way round.
- A query matches a whole theorem or one of its `&&` conjuncts.

Ranked after a text match (1.0) and before a "calls this function" match (0.9). The index
is unchanged: shapes are matched against the stored theorem text at query time.

Test: `test/test_search.ml` group `lemmas`, "--law with a shape": an involution, `==`
swapped, a right identity, a named callee, a non-match, and a variable that must be the
same subterm twice.
