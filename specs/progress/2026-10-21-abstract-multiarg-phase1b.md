Refinements: relational element refinements (multi-arg design phase 1b)

Phase 1b of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§1.3, §1.4's
concrete-relation warning, §2.2-§2.6, §9 "Phase 1 / 1b"). Phase 1a (`d053b4bdb`,
`specs/progress/2026-10-21-abstract-multiarg-phase1a.md`) built the entry record inertly;
this phase gives `rels` a meaning.

## Before / after

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
fn need_pos(_a : Assoc(Int, {Int | _ > 0})) : Int do 0 end
fn need_arel(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end
fn need_gt(k : Int, v : {Int | _ > k}) : Int do k + v end
```

| Row | Program | Before (`d053b4bdb`) | After |
|---|---|---|---|
| r1 | `need_arel(ACons(1, 2, ANil))` | skip (`y > x` named a free `x`) | proved (one obligation for the relation) |
| r2 | `need_arel(ACons(5, 2, ANil))` | skip | violation: "the entry (5, 2) passed to `need_arel` does not satisfy precondition `y > x`" |
| r3 | `a : Assoc({x : Int \| x > 0}, {y : Int \| y > x})` into `need_pos` | skip, solver-undecided (the 2026-10-18 design measured a false violation, `x = -1`) | proved (projection) |
| r4 | `a` (r3's) into `Assoc({a : Int \| true}, {b : Int \| b > a})` | skip | proved |
| r4' | `a` (r3's) into `need_arel` | skip | proved |
| r5 | `match a do ACons(k, v, _) -> need_gt(k, v)` | skip, solver-undecided | proved (path fact `v > k`) |
| r6 | `Assoc({x \| true}, {y \| y >= x})` into `need_arel` | skip | violation, "e.g. x = 0, y = 0" |
| proj_insufficient | `Assoc({x \| true}, {y \| y > x})` into `need_pos` | skip | violation, "e.g. x = -1, y = 0" |

## What changed

- `lib/refinecheck/refine_scope.ml`: `elem_refinement` is now `elem_app`, which reads one
  container application. Inside one application, a slot predicate sees every sibling slot's
  binder, in any order, and a sibling binder shadows a value parameter of the same name. Each
  top-level conjunct of slot `i`'s predicate that names a sibling goes into one `rel` over `i` and
  those siblings. The other conjuncts stay slot `i`'s fact; a slot left with none is empty, and its
  sort marker is kept in the rel. The entry is built through `normalize_entry`. A rel is kept only
  if it is well formed; otherwise it is dropped and an issue says why:
  - W2: no related slot's base is a container type (`{xs : List(Int) | true}`);
  - W4: `entry_shaped` holds;
  - a sibling binder name is not spelled on two other slots;
  - a nested container slot naming one of this application's binders (`Assoc({x : Int | true},
    List({y : Int | y > x}))`, across nesting levels) is dropped.

  `relation_issues t` (one application) feeds the declaration warning, and
  `relation_issues_deep` feeds the audit. `render_model_entry` renders `$elem_<j>_<binder>` as
  `<binder> = v`.
- `lib/refinecheck/refine_encode.ml`: `entry_shaped ~name_of c s`, beside `ctor_param_fields`.
  Every constructor must hold the same number (0 or 1) of `Param j` fields for each related `j`,
  hold no related value in a hiding field (`ctor_field_params`), and hold related values in a
  `Within` field only if that field holds all of them and no `Param` field holds any (then the
  nested container must be entry-shaped, recursively). An opaque container (no `Param`/`Within`
  field anywhere: `Map`) is entry-shaped vacuously. Phase 0 had already added `ctor_field_params`;
  it is reused, not duplicated.
- `lib/refinecheck/refine_check.ml`:
  - `warn_predicate_ty`'s `TyCon` arm warns `refinement_unchecked` ("This relation is not checked:
    …") at the predicate of every dropped rel. There is no new error code.
  - `entry_implies`: with no rels on either side, the pre-1b arm is unchanged. Otherwise (§2.4),
    each slot the have side informs (a refined have slot, or a have rel mentioning it) gets one
    deterministic constant `$elem_<j>[_<binder>]` carrying that fact (`true` at its sort for a
    rel-only slot). The have rels at those constants are path facts. Each refined want slot and
    each want rel is one `check_call ~subject:Element_domain` goal, with one ledger entry each. A
    want rel's goal uses a signature whose parameters are the rel's binders, so the ledger shows
    `y > x`. A goal over an uninformed slot is a recorded skip, never a drop. An unknown sort
    declines with a recorded skip.
  - `check_elements`, `ECon` arm (§2.5): for each want rel, a constructor with exactly one `Param`
    field per related slot owes one obligation on a synthetic signature (parameters named by the
    rel's binders, the `_`-spelled one last). The violation label is "the entry (f1, f2) passed to
    `callee`" (new `?entry_label` on `check_call`). A constructor with none of the slots owes
    nothing. A `Within` field holding every related slot (and no `Param` field holding one) passes
    the rel, remapped, into the nested entry. Any other shape is a recorded skip. Phase 0's
    hidden-field skip now also counts a slot that only a rel demands.
  - `match` facts: each scrutinee rel all of whose slots are bound by `PatVar`s at `Param` fields
    of this constructor occurrence becomes a path fact over those binders. A binder with no slot
    fact gets a `true` scope entry so it has its sort, and a rel naming another binder of the
    pattern (capture) gives nothing. A `Within` binder's nested entry carries the remapped rels
    that its field holds whole.
  - `demand_flow`: a demanded rel through a call, at any nesting level of the return, is always
    `Unproved` (`parametric-source-unproved`). It reads "a relation between `k` and `v` cannot be
    traced through separate sources" when the sources differ, and "… is not preserved through `g`:
    a function parametric in them may pair the components of different entries" for one common
    source. See the rulings.
  - `lend_entry` keeps rels that mention only their own binders. `instantiate_entry` substitutes
    a rel that is relational over the formals like a slot, its binders first renamed `$s<j>`.
    `parametric_return` carries no rel (ruling).
- `lib/refinecheck/refine_audit.ml`: a dropped rel's site is `Inert_warned` (the warning fires at
  it). A kept rel is one site and goes through the existing `Type_arg` rule.
- Sites with no code change: `container_entry_of_expr` and the self-call hypothesis carry the
  entry whole, so the hypothesis carries the declared rels. `declared_elem_return` lends a closed
  entry whole. `cont_add_param` / `cont_add_binding`, the `lets` re-examination and
  `check_pass_site_elements` go through `check_elements`. `cap verified` escalation happens
  through `record_elem_skip` / `record_param_skip` / `check_call`.

## Tests

New group `relational-elements` in `test/test_refinecheck.ml` (27 cases). It is registered after
`element-entries`. RED was measured by running the final test file in a worktree of the base
`d053b4bdb`: `23 failures! … 27 tests run.` The four that pass there are controls by design. Each
RED line below is from that run (Expected → Received):

| Case | RED on base |
|---|---|
| r1 literal entry proved | `["proved"]` → `["skipped"]` |
| r2 violation naming both fields | `need_arel: violated` `true` → `false` |
| r3 projection | `["proved"]` → `["skipped"]` |
| r4 alpha-renamed relational demand | `["proved"]` → `["skipped"]` |
| r4' same-name spelling | `["proved"]` → `["skipped"]` |
| r5 match binders | `["proved"]` → `["skipped"]` |
| r5 control: binders of two entries | passes on base (control) |
| r6 weaker relation is a violation | `true` → `false` |
| proj_insufficient | `true` → `false` |
| two_not_entry_shaped (`K(k) \| V(v)`): warned, not assumed, not owed | `warned` `true` → `false` |
| two_not_entry_shaped (Within, `MX(k, List(v))`) | `warned` `true` → `false` |
| nested_slot_rel (`{xs : List(Int) \| true}`) | `warned` `true` → `false` |
| nested_slot_rel (inner slot names an outer binder) | `warned` `true` → `false` |
| rel_through_reverse: not carried (ruling; `shift`) | passes on base (soundness control) |
| rel_two_sources | `[("skipped", "parametric-source-unproved")]` → `[("skipped", "unreflectable-subject")]` |
| sibling_shadows_param | `need_pos: violated` `true` → `false` |
| unary_rel_is_slot | passes on base (I1 control: ledger identical to the plain unary form) |
| relation through a `Within` field | `proved` `true` → `false` |
| annotated `let` | `["proved"]` → `["skipped"]` |
| proved / violated relational return | `return of mk_bad: violated` `true` → `false` |
| recursive `bump` (self-call hypothesis + path fact) | `["proved"; "proved"; "proved"]` → `["proved"; "proved"; "skipped"]` |
| a conjunct naming no sibling stays the slot's fact | `["proved"; "proved"]` → `["proved"; "skipped"]` |
| single-source demand names the cause | `not preserved through `shift`` `true` → `false` |
| pass site: a lambda owes the relation per tail | `proved` `true` → `false` |
| audit: kept rel Enforced, dropped rel Inert_warned | `["Inert_warned"]` → `["Enforced"]` |
| `cap verified`: r1, r3, r5 leave nothing unverified | `[]` → three `cannot verify` errors |
| `cap verified` control: unrefined source is an error | passes on base (control) |

`determinism` is not a unit test. See Verification.

Conformance: `specs/lang/types/accept/t453_relational_element_refinement.march` (r1, r3, r5 under
`cap verified`) and `reject/t454_relational_element_violated.march` (r2). On the base compiler t453
is rejected (exit 1, three `cannot verify` errors) and t454 is accepted (exit 0). After the change:
0 and 1. `specs/lang/types/INDEX.md`: rows and counts (490 = 205 accept + 285 reject).
`specs/lang/types/check_types.sh`: `490 passed, 0 failed`. Neither file is a `test/native`
fixture, so no refine-audit baseline is involved.

## Verification

- `scripts/refine-oracle.sh`: the baseline was taken at `d053b4bdb` before any edit (549
  fixtures, 8726 lines, the same as phase 1a's). After: `REFINEMENT DIAGNOSTICS IDENTICAL (8726
  lines over 549 fixtures)`. The corpus (`test/native`, `stdlib`) has no sibling-binder relation,
  so nothing may move, and nothing did. No new warning either, because the report includes
  diagnostics.
- The oracle was shown to go RED. Perturbation 1 routed every entry pair through the new
  relational arm of `entry_implies` (guard forced false). The result was IDENTICAL, which shows
  that arm agrees with the old one on every rel-free entry pair of the corpus, but proves nothing
  about the oracle. Perturbation 2 kept that and made the arm's goal `true` without a query:
  `DIAGNOSTICS CHANGED — 2220 differing lines` (`native_actor_call_canonical: … 129 proved` became
  `102 proved`). The file was restored from a saved copy (`cmp` clean) and rebuilt.
- Refine audit baselines (`test/refine_audit/*.baseline`, group `audit-baseline`): not
  regenerated, and they still pass.
- `./_build/default/test/test_refinecheck.exe -e` (VC cache cleared, z3 on PATH, 0 SKIP), run
  before the last four cases were added: `Test Successful … 1412 tests run.` (1389 + 23).
- Full `scripts/run-tests.sh`: `All suites passed.`, exit 0. refinecheck: `Test Successful … 1416
  tests run.` (1389 + 27); compiler: `1451 tests run.`
- Determinism: `scripts/determinism-oracle.sh --self-test` was RED as required, and `--corpus
  small` gave `DETERMINISTIC across 29 programs × 4 conditions`. That corpus has no relation, so
  a ledger check was added. `--check --refine-report --refine-report-sites` over t453, t454 and
  the r/rv probe programs, under a cold then warm private `HOME` and two working directories,
  printed byte-identical output (293 lines, 4 violations) in all 4 conditions.
- Budget (§10): cold `--check --stdlib-source --refine-report stdlib/list.march` (artifacts and VC
  cache cleared, fresh `HOME` every run), 5 interleaved A/B runs, base = a worktree of
  `d053b4bdb`. Base runs: 1.446, 1.388, 1.394, 1.369, 1.386 s (median 1.388). This phase: 1.380,
  1.372, 1.368, 1.378, 1.390 s (median 1.378). That is 99.3% of base, within the 110% budget.
  Load average was 17.5 at the start and 15.1 at the end (other sessions). The report is
  byte-identical between the two (`user + stdlib`: 105 proved, 33 trusted, 37 skipped; ratchet
  unchanged).
- `scripts/check-docs.sh`: exit 0 (Check C: types 490 = 205 + 285).

## Rulings

- Ruling: a relation does NOT ride through `parametric_return`, and a demanded relation through a
  call is never discharged by `demand_flow`. This reverses the design's §2.5 rows and its
  `rel_through_reverse` test. Why: parametricity in `k` and `v` preserves each slot's facts, but
  not a joint relation. `shift(a : Assoc(k, v)) : Assoc(k, v)`, returning `ACons(k1, v2, …)` from
  two cells, is parametric (P1/P2 hold), has one source and maps slot-for-slot, yet
  `shift(ACons(5, 6, ACons(0, 1, ANil)))` has the entry `(5, 1)`. The design's rule would have
  proved `need_arel` of it, and of `shift(a)` for a relational `a`. The test
  `rel_through_reverse` pins that neither a reverse nor `shift` carries the relation. A nested
  container carried whole as a type variable's value (`List(a)` with `a := Assoc(…)`) keeps its
  rels, because that value is never taken apart. Cost if wrong: lost proofs through generic
  reverse/map-like callees; phase 2's abstract relation (`Assoc(k[p], v[p])` proved on the
  definition side) is the sound way to carry one.
- Ruling: a slot predicate is split into top-level conjuncts. Only the conjuncts that name a
  sibling go into the rel; the rest stay the slot's fact. Why: it keeps one-slot facts as slot
  facts (I1's intent) and keeps the existing single-slot path for them. Cost if wrong: none for
  soundness (`a && b` either way).
- Ruling: entry shape (W4) also refuses a related value in a hiding field, and a `Within` field
  holding only some of the related slots or sitting beside a `Param` field holding another.
  It accepts an opaque container (no `Param`/`Within` field) vacuously, as the design says for
  `Map`. Why: those are the shapes where a value is in no entry (leftovers phase E's rule: never
  pair a `Within` field with a direct field). Cost if wrong: a warning on a container whose
  relation could have been modelled.
- Ruling: W2 is checked on the slot's declared base (`is_container_type`), and a nested slot that
  names an outer binder is dropped with the same warning. Why: the design's "nested slot rel" row,
  and §8's "across nesting levels" exclusion; dropped means never assumed and never owed. Cost if
  wrong: lost checking of a (previously misread) shape.
- Ruling: the sort of an entry constant comes from the have slot, a have rel, a want rel or the
  want slot (I3 markers). `elem_markers_of_arg` was not added. Why: in phase 1 every informed or
  demanded slot has a marker (a rel exists only over slots `refined_param_ty` read). The decline
  path exists and is a recorded skip. Cost if wrong: a skip where the typechecker knew the sort,
  never an Int default.
- Ruling: entry constants are named `$elem_<j>_<binder>` (want binder first, else have's) and
  rendered `<binder> = v`, so counterexamples read `x = -1, y = 0` as the design shows. Why:
  `$`-prefixed names cannot capture a program name, and the name is a pure function of the two
  entries (deterministic). Cost if wrong: a rendering difference.
- Ruling: a rel obligation's synthetic signature names its parameters by the rel's binders, not
  `$r0 … $r(n-1)`. Why: the ledger and the violation then show the relation as written (`y > x`);
  parameter names are positional in `check_call`. Cost if wrong: none (the binders are distinct).
- Ruling: a want slot spelled `{x : Int | true}` over a slot the have side says nothing about is
  still today's skip. Why: unchanged pre-1b behaviour for a refined want slot. Cost if wrong: an
  extra skip on such demands.

## Not done

- `elem_markers_of_arg` (see the rulings).
- The design's `rel_through_reverse` "keeps the relation" outcome is replaced by the soundness
  control above, and nothing was filed. Phase 2's abstract relations are the route.
