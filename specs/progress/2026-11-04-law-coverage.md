# Law coverage and law strength (2026-11-04)

Design: `specs/2026-11-04-law-coverage-design.md`. Plan: `specs/plans/2026-11-04-law-coverage-plan.md`.

## What landed

- **`march --check --law-coverage FILE`** (`lib/refinecheck/law_coverage.ml`): one block per module
  of the file, listing its pure (reflected) functions as uncovered (public / private), unproved
  only, or covered, with the laws; higher-order (`Specialised`) functions apart and out of the
  count; impl methods under their impl when the interface declares laws, covered
  `<law> (via <Iface>)` (through the generated `__law_<m>__<tag>` copies). A law covers what its
  theorem calls (an AST walk, resolved through the lemma's module scopes); calls in its proof
  do not count. `--law-coverage-json`: one object per function on stdout.
- **`--law-strength`** (`lib/refinecheck/law_strength.ml`): up to 20 single-site edits per covered
  function (return a parameter, swap call arguments or constructor fields, change an Int
  literal, swap two match arms' results, drop the recursive call, change a comparison), each
  judged in the witness interpreter on the parity net's inputs: dropped when it changes no
  result, killed when a covering law is false on some input, surviving when every law holds,
  undecided otherwise. Each covering law is first run on the unedited function; only a law that
  holds there judges, and an edit survives only when every such law still holds on at least as
  many inputs (an edit that loops or fails where the original returned is undecided, not a
  survivor). Budget `MARCH_LAW_STRENGTH_MS` (5000) per function.
- **`forge audit --laws [--strength]`** (`forge/lib/cmd_audit.ml`): one check of a generated entry
  that `use`s every module of the package's `lib/` and `src/` files (both on the lib path), run
  with `--law-coverage-all`, so every law of the package is loaded and every module's block
  counts them all; no `forge.caps.lock`; exits 0 unless the check fails.
- `--law-coverage` lists the entry file's functions only; `--law-coverage-all` every user file
  the check loaded, each named by its own module path.
- `--reflect-report`'s row computation is split out (`reflect_rows` in `bin/main.ml`) and shared.

## Rulings made while building (my calls)

- An edit "typechecks" when each pair of sites it exchanges has one type in the checked module's
  type map (`ed_same_type`); arm swaps whose results name their own pattern's variables are not
  generated. Re-typechecking the edited module measured ~0.8 s per edit (both the full check and
  the cached-stdlib-environment check), so a 20-edit function would take 16 s against a 5 s
  budget. An ill-typed edit the pairs miss most likely fails at run time (undecided or killed).
- The logic's `len` is bound in the interpreter for law evaluation (`Lemma_test.test_lemma
  ~with_len:true`, strength only); `--lemma-test` still leaves length laws "not-tested" (filed:
  `specs/todos/2026-11-04-lemma-test-len-unbound.md`).
- "Strength: not run (no input generator)" is pinned by unit tests: every reflected function
  whose parameters lack a generator also has laws the checker cannot admit (opaque sorts; a
  base-case-free datatype crashes z3), so no integration fixture reaches it.
- The plan's "rev_rev keeps the identity edit" fixture is impossible (rev_rev's proof needs
  rev_cat, which kills it); the same property is tested with `neg(neg(n)) == n`.

## On the stdlib

`march --check --law-coverage --law-strength` on a stdlib file as the entry (11.7 s for
`list.march`, 1.9 s each for `option.march` and `result.march`):

```
law coverage: List: 3 of 11 pure functions have a law (1 more only by unproved laws)
law coverage: Option: 0 of 6 pure functions have a law
law coverage: Result: 0 of 5 pure functions have a law
```

Uncovered in `List`: `head_opt`, `tail_opt`, `nth_opt`, `length`, `is_empty`, `sum_int`,
`product_int`. Checking a stdlib file as the entry file reports `invalid_lemma` (3) and
`lemma_unproved` (4) with or without the new flags (the stdlib is also loaded as the
stdlib), so `reverse` shows "unproved only" there although `len_reverse` is admitted in user
programs; the counts undercount `List` accordingly. `reverse_onto` reaches the 5 s budget
(`partial (budget), 1 of 3 edits judged`); with `MARCH_LAW_STRENGTH_MS=60000` it reads
`0 of 1 edits survive (1 undecided)`: the undecided edit swaps `reverse_onto`'s arguments,
which loops. (Before the final review's fix, that loop was misread as a survivor.) `append`
(`0 of 2`) and `drop` (`0 of 7`) have no surviving edit.
