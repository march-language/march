- Record field preconditions **integrated with `main`** (String refinements,
  ADT constructor tags, the predicate-vocabulary foundation, and the two
  solver-robustness fixes), 2026-07-24. `sig_of_clause` now collects through
  `main`'s `refined_param_ty` — a record IS a registered 1-constructor ADT, so
  one predicate admits all four refinable bases; a new `is_record_sort` picks
  the record-specific path (field selectors) out of the three things
  `rparam.sort` can now name. The branch's dedicated record preamble was
  dropped: the record path seeds its sort into `main`'s `adt_sorts` and
  inherits the existing deduplication against the measure and `$Str`
  preambles, so a VC mentioning a record AND a tester AND a string declares
  each sort once. Two real defects found and fixed during the sweep:
  `term_fits_sort` was shallow, so `history: Cons(1, Nil)` (an `Int` in the
  generic `List`'s opaque `Elem` field) built a malformed VC; and z3's
  multi-line `(error …)` reply left a continuation line in the pipe that was
  read as the NEXT query's verdict, shifting every later answer by one and
  turning correct calls into reported violations. `term_fits_sort` now
  recurses into constructor arguments; `read_verdict` consumes the whole error
  s-expression. `test_refinecheck` 124 → 137, all green on a cold VC cache.
