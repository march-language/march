- Record field **preconditions**: a refinement over a record's fields
  (`{v : Config | v.port >= 1}`) is now checked on parameters at every call
  site, closing the half that return-type record refinements already covered.
  `rparam` carries the record's SMT sort, `sig_of_clause` collects record
  params through `refined_scope_ty`, and `check_call` reflects a record actual
  (a literal, with fields reordered by name to the declaration order; or a
  variable carrying a record-refined local's own predicate) and passes the
  existing `make_field_resolver` plus the record datatype preamble to
  `smt_of`. Definite-failure stance preserved: the record path uses the same
  two-discharge procedure as the Int path, NOT `check_post`'s report-on-SAT
  branch, so a weaker forwarded refinement is skipped while a contradictory
  one is caught; an unrefined record, an unknown field value, or any field
  that cannot be placed at its declared sort skips the whole call.
  Also fixed a pre-existing solver-poisoning bug found while sweeping: a
  non-`Int` record field bound to a variable built a sort-mismatched VC, and
  Z3's error desynchronised the shared `z3 -in` channel, silently disabling
  refinement checking for the rest of the compilation (a `take_n(-3)` two
  functions later went unreported). `reflect_record_literal` is now
  sort-checked against `ctor_field_sorts`; this also closes the same hole on
  the return side. `test_refinecheck` 86 → 97, all green on a cold VC cache.
