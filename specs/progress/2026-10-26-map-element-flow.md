Refinements: `Map`'s own functions carry a refined map's element facts (opaque-container source rule)

Closes `specs/progress/2026-10-21-map-element-flow-through-combinators.md` (moved from
`specs/todos/`; design `specs/2026-10-18-abstract-refinements-multi-arg-design.md` §8,
rows m10/m11). Container-gap batch, gap 2 of 4, branch `claude/refine-container-gaps`.
Files the remainder as `specs/todos/2026-10-26-map-element-flow-remainder.md`.

## Root cause

Two independent refusals, both measured:

1. `ptype Map(k, v) = HamtMap(HEntry(k, v))` hides both parameters (`HEntry` holds pairs
   in `HCollision(Int, List((k, v)))`), so `ctor_hidden_params` is `[0; 1]` and
   `Refine_param.container_paths` refused every path through a `Map` slot: `sources_of`
   answered `None`, and every demand through a `Map` function was
   `parametric-source-unproved`.
2. The functions were unannotated (`insert(m, key, val, cmp)`), so P1
   (`generic_in_inferred`) had nothing to align.

Measured with the final test file (below): with only the stdlib annotations and the
checker unchanged, 14 of the 35 cases fail; `map_values` and `singleton` already prove
(their demanded variable's only sources are a lambda's codomain or a bare parameter, no
`Map` slot), everything reading a `Map` argument's slot does not.

## Fix

**Ruling: the opaque-container source rule, as a source rule, not as `@[assume]`d
element contracts.** — An `@[assume]`d contract cannot say "the result's values are the
input's values plus `val`" without a definer, and the parametric element rule already
says exactly that when its gates hold; P2 (`parametric_safe`) checks each body, so no new
trust is added. — Cost if wrong: a false proof for an opaque type whose slot facts can be
established shallowly (see the soundness argument; no such path was found).

- `lib/refinecheck/refine_encode.ml`: a table `opaque_containers`, filled in
  `register_field_sorts_once` for a variant type declared `ptype` (`DType (Private, …)`)
  or whose every constructor is private (`opaque type`, `alwayslinear opaque type`);
  reset with `ctor_hidden_params` in `Refine_check.check_module`.
- `lib/refinecheck/refine_param.ml` `container_paths`: an opaque container's hidden
  parameters are not refused (`hidden = []` for it). Nothing else changes: P1, P2, the
  forward rule (`agreed_elem_slot`) and the demand rule (`demand_flow`) apply unchanged.
- `stdlib/map.march`: honest generic annotations, bodies unchanged:
  `get(m : Map(k, v), key : k, cmp : k -> k -> Bool)`, `get_or(…, default : v, …) : v`,
  `insert(m : Map(k, v), key : k, val : v, cmp : k -> k -> Bool)`,
  `remove(m : Map(k, v), key : k, cmp : …)`, `keys(m : Map(k, v))`,
  `values(m : Map(k, v)) : List(v)`, `map_values(m : Map(k, v), f : v -> w)`,
  `merge(a : Map(k, v), b : Map(k, v), cmp : …)`, and `singleton(key : k, val : v)`
  (parameters renamed from `k`/`v` so value and type names do not coincide; its
  `keys(_) == singleton(key)` contract is renamed with them). The `@[assume]`d key-set
  contracts are unchanged. The module header says the element facts are checked by
  parametricity, not assumed.

### Soundness argument

The parametric rule is sound for a hidden-parameter container when a slot fact on it
always means "every value of that parameter anywhere in the value" (deep). A slot fact
on an opaque container's value can only come from:
- a construction: a constructor field that hides a demanded parameter is a recorded skip
  (multi-arg phase 0, `ctor_field_params`), never a fact; a constructor with only `Param`
  / identity `Self` / `Within` fields is checked field by field, which covers every value
  of the parameter in it by induction;
- a declared parameter type: obliged at every caller;
- a proved return: its tails go through the same construction checks;
- an `@[assume]`d return: trusted and witnessed (`Map.filter`);
- the parametric rule itself: by parametricity every value of `v` in the result is a
  value of `v` in a source, so a deep fact of every source is a deep fact of the result.

That last step rests on P2 (`parametric_safe`) being right that the body cannot create a
`v`. **Correction (2026-10-26 soundness review):** it was not. `compute_safety` classified
only call heads (`f(…)`) and treated every local name as harmless, so a value-creating
function used as a VALUE (`let g = dflt`, `{g: dflt}`, `apply1(dflt, 1)`,
`Map.map_values(m, dflt_of)`) was missed, and this rule then proved
`need_vals(sneak(m, 1))` for a `sneak` that inserts `dflt(1) = -5` (run: prints `-5`).
The same hole already gave a false proof on main without any `Map` involved
(`Cons(apply1(dflt, 1), xs)` into a `List({Int | _ > 0})`). Fixed in its own commit by
classifying every name a body references
(`specs/progress/2026-10-26-refine-p2-value-references.md`); the opaque rule here is
unchanged.

`ptype` constructors are **not** private in practice: `Map.HamtMap(Map.HLeaf(…))` from
another module typechecks (measured). The argument above does not rely on visibility,
and two tests pin that such a construction never becomes a proved source.

**Ruling: restrict the rule to opaque types** (`ptype` / `opaque type`) although the
argument above would cover any hidden-parameter type. — The design (§8) names opaque
containers, a user `type Wrap(k, v) = Wrap(List((k, v)))` is the h1 shape phase 0 was
written for, and the restriction keeps the change minimal while another builder edits
`lib/refinecheck`. — Cost if wrong: a lost proof for a user hidden-shape `type` (pinned
as a skip by a control).

**Ruling: a too-weak declared map is a violation through these functions.** —
`need_vals(Map.remove(m, "a", cmp))` with `m : Map(String, {Int | _ >= 0})` now reports
`refinement violation … (e.g. (elem) = 0)`, exactly what `list_pos(List.reverse(xs))`
with `xs : List({Int | _ >= 0})` reports (measured side by side): the forward rule
carries the declared slot and the subtyping query refutes it. — Cost if wrong: a
consistent existing judgement, not a new one; no corpus or sampled program hits it.

**Ruling: `Map.empty()` stays a non-source.** — It has no parameter, so P1 has no
witness for `k`/`v`; making a variable no parameter mentions "vacuously generic" is a
P1 change with its own soundness question (filed). — Cost: `Map.insert(Map.empty(), "a",
3, cmp)` into a positive demand is a skip (pinned).

## Tests

New group `map-flow` in `test/test_refinecheck.ml` (35 cases) on the batch's
`container_gap_harness` (the REAL `stdlib/list.march`, `option.march`, `map.march`).

RED: the final test file built against `lib/refinecheck` and `stdlib/map.march` reverted
to the merge base (`git checkout` of the four files, rebuilt):
`16 failures! in 0.554s. 35 tests run.` The failing 16 are every accept row: m10, a
refined value, the name-capture row, a key demand, a chained insert, `get` (and through a
`match`), `get_or`, `remove`, `merge`, `map_values`, `values`, `singleton`, the `ptype`
user control, the too-weak-violation row and the `cap verified` m10 row. Typical lines:

```
m10:  Expected `[("proved", "")]'  Received `[("skipped", "parametric-source-unproved")]'
get:  Expected `[("proved", "")]'  Received `[]'   (the call-labelled subtyping obligation did not exist)
```

With only the stdlib annotations (checker reverted): 14 failures (`map_values` and
`singleton` pass, as explained above). GREEN: `Test Successful … 35 tests run.`

| Accept | Control (skip / error, never a violation unless stated) |
|---|---|
| m10 `Map.insert(m, "b", 5, …)` proved | m11 `… "b", 0 …` skip; insert into an unrefined map skip; `cap verified` m11 is an error |
| insert of a refined parameter | — |
| name capture: caller params `val : Map(…)`, `m : {Int \| _ > 0}`, `key` | the same with `m : Int`: skip |
| key demand through insert | key `0` into a positive-key map: skip |
| insert chained twice | a relation through insert: `parametric-source-unproved` (relations are never carried, phase 1b ruling) |
| `get` (labelled `Map.get(…)`), and through `match … Some(v) -> need_pos(v)` | unrefined map: skip |
| `get_or` with a positive default | default `0`: skip |
| `remove`, `merge`, `values` | unrefined map / one unrefined side: skip |
| `map_values(m, fn v -> v * v + 1)` | `fn v -> v * v`: skip |
| `singleton("a", 3)` | `singleton("a", 0)`: skip |
| a user `ptype PWrap(k, v) = PWrap(List((k, v)))` through an identity | the same as plain `type`: `parametric-source-unproved`; a `ptype` function failing P1 (`PBox([(1, 0 - 5)])` returned as `PBox(v)`) carries nothing |
| `cap verified` m10: no error | soundness: `Map.insert(Map.HamtMap(Map.HLeaf(0, "z", 0 - 5)), …)` and the same through an unproved `fn mkm() : Map(String, {Int \| _ > 0})` are not proved |
| — | `insert(Map.empty(), …)` pinned skip (lost proof) |
| — | too-weak `Map(String, {Int \| _ >= 0})` through `remove` is a violation, as `List.reverse` |

`abstract-map`'s "m10 control: Map.insert carries no element fact (out of scope)" is
flipped to "m10: … proved".

**Runtime witnesses** (`test/stdlib/test_map.march`, describe "element flow through
Map's functions (runtime witnesses)", four `Check.all` properties over random
`List((Int, Int))`): `insert`'s values are in `values(m) ∪ {x}` and keys in `keys(m) ∪
{k}`; `get`'s `Some(v)` is a value of `m`, `get_or`'s result a value or the default;
`remove`/`values`/`merge` values (and `merge` keys) come from the inputs; `map_values`'
values are `f` of input values and `singleton(x, x)` has values `[x]`. These facts are
checked by parametricity, so no generic perturbation of a body can break them. Two
perturbations show the properties are not vacuous:
- stdlib: `map_values`' `HLeaf(h, k, f(v))` changed to `f(f(v))`, restaged: `FAIL: "…
  map_values: every value is f of an input value; …" counterexample: ([(0, 0)], 0)` (and
  the existing unit test and doctest), `3/2431 tests failed`;
- oracle: the insert property's allowed set weakened to `values(m)` (without `x`):
  `FAIL: "… insert: values come from the map or the inserted value; …" counterexample:
  ([], (0, 0))`, `1/2431 tests failed`.
Both restored (`grep -c 'f(f(v))'` = 0): `=== 1 file, 2431 tests passed ===`.

## Verification

- **Refine oracle.** A new baseline was taken after merging main (#1028) into the
  branch, with gap 1 committed and gap 2 not applied: 552 fixtures, 8738 lines. After:
  `DIAGNOSTICS CHANGED — 6 differing lines`, all `stdlib_map` source excerpts whose
  line numbers moved by 8 (the new header comment): `295 → 303`, `303 → 311`,
  `340 → 348`. No verdict, count or summary line moved in any fixture: no stdlib or
  `test/native` program puts a refined demand on a `Map` function's result. The new
  proofs are seen by the test group, not the corpus.
- **Real programs.** Every file in `examples/`, `test/native/` and `test/stdlib/` that
  calls `Map.insert/get/remove/merge/map_values/values/singleton/get_or/keys` (15 files;
  `examples/` has none) was swept with `--check --refine-report --refine-report-sites`:
  no user obligation, violation or skip anywhere except `test_map.march`'s two
  pre-existing `List.head` skips. `test_cluster_node` and `test_linear_map` print
  typecheck errors under plain `--check` (`missing_impl` for `Eq` and a `cap_ceiling`),
  unrelated to refinement and from the test harness's own conventions.
- `stdlib/list.march` ratchet (`--check --stdlib-source --refine-report`): user + stdlib
  110 proved, 35 trusted, **36 skipped** (ceiling 42).
- Refine audit baselines: unchanged (the annotations are unrefined, so no new site).
- `scripts/run-tests.sh refinecheck compiler stdlib_march` (z3 on PATH, after merging
  main): `All suites passed.` refinecheck 1784 tests (audit-baseline unchanged),
  run_compiler 1453 (the stdlib ratchet), test_stdlib_march 81.
- `scripts/check-docs.sh`: `doc-lint passed`.
