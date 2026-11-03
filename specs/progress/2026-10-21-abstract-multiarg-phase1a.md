Refinements: the element entry becomes a record with relations, inert (`rels = []`) (multi-arg design phase 1a)

Phase 1a of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§2.1-§2.3, §9
"Phase 1"). A type migration with no observable effect: no diagnostic, ledger line or audit
line changes. Phase 1b gives the relations meaning.

## What changed

`lib/refinecheck/refine_scope.ml`: the element entry is now R1's record.

```ocaml
type elem = Refined of (string * A.expr * string option) | Container of entry
and entry = { cont : string; slots : elem option list; rels : rel list }
and rel = { rel_args : (int * string * string option) list; rel_pred : A.expr }
type contenv = (string * entry) list
```

The old `Container of string * elem option list` and the `(string * elem option list)` pair
that every reader destructured are gone. The compiler listed every reader, and each one was
migrated: `refine_scope.ml` (`elem_entry_mentions`, `elem_refinement`, `ret_elems`),
`refine_param.ml` (`entry_is_closed`) and about 25 sites in `refine_check.ml`. Every constructed
entry has `rels = []`, through `entry_of_slots`. A one-line `1b:` comment marks each site where
phase 1b has to act: `elem_refinement` (sibling binders become rels), `agreed_elem_slot` /
`parametric_return` (the rel-carrying rule), the `ECon` arm (rel obligations, the `Within`
rule), `demand_flow` (the shared-source rule), the `match` facts (path facts, the `Within`
remap), `lend_entry` and `instantiate_entry`.

New helpers:
- `entry_of_slots`, `normalize_entry` and `entry_meet` in `refine_scope.ml`, with
  `conj_refined` (one binder, the incoming fact first, capture-avoiding `$r` renaming).
  `normalize_entry` implements I1-I3 in full, so 1b can rely on it. It is the identity on a
  rel-free entry.
- `entry_is_closed` (`refine_param.ml`) and `entry_mentions`, `elem_entry_mentions` and
  `entry_movable` (`refine_check.ml`, `refine_scope.ml`) now also scan rels: a rel's own
  binders are exempt, like a slot's binder.
- `entry_implies cx errctx ~span ~callee ~subject ~have ~want` (`refine_check.ml`). This is
  the subtyping arm of `check_elements`, moved out word for word, and the arm now calls it.
  Same queries, same ledger triples. The arm used `check_elements`' `sc`, which is the `sc` of
  the `cx` it already received from `cx_of`, so `cx.sc` is the same value.
- `instantiate_entry` moves a rel only when it mentions nothing but its own binders; otherwise
  it is `Stuck`, i.e. `Error`. On the want side that is a recorded skip, never a silent drop.
  `lend_entry` lends slot by slot, so rels are not lent, which is sound on the have side.
- `agreed_elem_slot`'s agreement key includes a nested entry's rels. With `rels = []` the key
  strings are byte-identical.

`refine_check.mli` now exposes `elem` / `entry` / `rel`, `normalize_entry` and `entry_meet`
for the unit tests (a new "Element entries" section).

## Tests

New group `element-entries` in `test/test_refinecheck.ml`, registered before `z3-well-formed`.
It has 10 pure unit tests on hand-built entries:
- normalize: the identity on a rel-free entry;
- I1: a one-slot rel folds into its slot, incoming first;
- I1: a one-slot rel fills an empty slot;
- I1: a `true` rel drops;
- a two-slot rel stays a rel;
- folding avoids capturing an outer name spelled like the slot binder (`$r`);
- I2: a one-slot rel on a nested-container slot drops;
- `entry_meet`: slots pairwise, incoming first, binder aligned;
- `entry_meet`: rels concatenated and normalised;
- `entry_meet`: nested containers meet slot by slot.

RED, before the implementation (the group written first, against base `fa70709af`):
`Error: Unbound type constructor "RC.entry"` (`test/test_refinecheck.ml`, `show_entry`).
RED, behaviourally: with `normalize_entry` forced to the identity, 6 of the 10 fail
(`6 failures! … 10 tests run.`). For example, `FAIL folded / Expected:
"Assoc(-, {y | ((y > 0) && (y < 10))})" / Received: "Assoc(-, {y | (y > 0)}) rel[1:z | (z < 10)]"`.
GREEN after: `Test Successful … 10 tests run.`

## Equivalence evidence

- `scripts/refine-oracle.sh` (it sets up its own private HOME). The baseline was taken at
  `fa70709af` before any edit: 549 fixtures, 8726 report lines. After the migration:
  `REFINEMENT DIAGNOSTICS IDENTICAL (8726 lines over 549 fixtures)`.
- The oracle was shown to go RED. A first throwaway perturbation, a changed skip-detail string
  in `entry_implies`, stayed IDENTICAL: the report prints skip reasons, not detail text, so
  that perturbation proved nothing. A second throwaway perturbation made the refined-vs-refined
  arm return `true` without a query. The result was `DIAGNOSTICS CHANGED — 2220 differing lines`
  (for example, `native_actor_call_canonical: by kind: 158 precondition` became `131
  precondition`). I reverted it (cmp against the saved file), rebuilt, and checked again:
  IDENTICAL.
- The refine audit baselines (`test/refine_audit/*.baseline`, compared by the `audit-baseline`
  group inside the refinecheck suite) were not regenerated and still pass. `git status` shows
  them unchanged.
- `scripts/run-tests.sh refinecheck`: base `fa70709af` gives `Test Successful … 1379 tests run.`
  After the migration: `Test Successful … 1389 tests run.` The difference is the 10 new
  tests. z3 was on PATH; 0 `[SKIP]` in either run.
- `scripts/run-tests.sh compiler` (the stdlib ratchet): `Test Successful … 1451 tests run. All
  suites passed.`
- `dune build --root .`: exit 0, with no OCaml warning or error lines.

## Rulings

- Ruling: `entry_of_slots`, `normalize_entry` and `entry_meet` live in `refine_scope.ml`, not
  `refine_param.ml` as §2.3 says. Why: `elem_refinement` (in `refine_scope.ml`, earlier in the
  include chain) constructs entries and 1b's `normalize_entry` must run there. Cost if wrong:
  none; moving them later is a cut-and-paste.
- Ruling: `entry_implies` takes `errctx ~span ~callee ~subject` besides `cx ~have ~want`. Why:
  the arm it replaces records skips against the error context and names the subject in skip
  text; `cx` does not carry them. Cost if wrong: a signature change in 1b.
- Ruling: `entry_meet` on entries that do not line up (another container, another slot count,
  a scalar slot against a nested one) keeps the first (incoming) side. Why: it is a have-side
  conjunction, and losing an assumption is sound. Cost if wrong: a lost fact, never a false
  proof.
- Ruling: when folding a one-slot rel (or meeting two slots) whose predicate names the slot's
  binder as an outer name, both sides are renamed to the first unused `$r`, `$r1`, … Why:
  renaming the rel's binder onto the slot's would capture it. The names are deterministic, with
  no counter, as the determinism oracle requires. Cost if wrong: a rendering difference in that
  (today unreachable) case.
- Ruling: `refine_check.mli` exposes the entry types and two helpers for the unit tests. Why:
  the mli hides everything not used outside the module, and §9 asks for unit tests of these
  functions. Cost if wrong: two more names in the interface.
