`[P2]` A record whose only refinements are element slots is never obliged

Found 2026-10-18 while designing the element-flow follow-ups
(`specs/2026-10-18-element-flow-followups-design.md` §0.5, probes `p4v`/`p4w`),
re-confirmed after its phase 0 landed. A record type whose fields carry element
refinements but no SCALAR refinement (`type Box = { n : Int, xs : List({Int | _ >
0}) }`) files **zero** obligations at a construction: `{ n: 10, xs: [0 - 5] }`
type-checks, `--refine-report` counts nothing (not even a skip), and `cap verified`
compiles it. Give one field a scalar refinement (`n : {Int | _ > 0}`) and the same
`[0 - 5]` is a violation, so the element check itself works; the record is just
never registered. `collect_ctor_sigs` (`lib/refinecheck/refine_scope.ml`) only
registers a record whose fields have a scalar refinement and has no counterpart
of `has_elem_param` (which covers functions only). Fix direction: register a
record (and a variant constructor) whose fields carry any element refinement, so
`check_field_elements` runs; it already turns a slot naming another field into a
recorded skip.

```march
mod P4v do
  type Box = { n : Int, xs : List({Int | _ > 0}) }
  fn go() : Box do
    { n: 10, xs: [0 - 5] }     -- 0 obligations today; should be violated
  end
end
```

## Fixed 2026-10-29 (branch `claude/record-element-slot-obligations`)

### What changed

- `Refine_scope.collect_ctor_sigs` registers a record, actor state or variant
  constructor when a field has a scalar refinement **or** a container field has
  an element refinement (`has_elem_param`). An element-only signature has an
  empty `refined`, so `field_facts` (the reader-side assumption) adds nothing
  for it: registration only adds obligations. Record literals and
  `{ r with … }` updates then reach `check_field_elements`, which already
  existed and already turned a slot naming a sibling field into a recorded skip.
- `visit`'s `ECon` arm: a registered VARIANT constructor now also runs
  `check_field_elements` over its positional arguments (`$0`, `$1`, …, as
  `ctor_sig_of_fields` names them). Before, it ran only the scalar
  `check_call`, so `W([0 - 5])` for `type W = W(List({Int | _ > 0}))` was
  unchecked even with a scalar sibling argument. An open slot in a positional
  argument (a free name, `W(List({Int | _ < n}))`) is a recorded skip with its
  own detail ("…argument N of the constructor names a variable it does not
  bind"), not the record wording "names another field".
- **Sibling hole, same class (actor messages).** `collect_handler_sigs` had the
  same `refined <> []` filter, and the handler body assumed a parameter's
  element refinement through `cont_of_fnparams` regardless. So
  `on Push(xs : List({Int | _ > 0}))` proved `need(h)` for `h` taken out of
  `xs` while `Push([0 - 1])` filed nothing: assume-without-check. Now an
  element-only message is registered, its construction runs
  `check_arg_elements` (read at the construction's arguments, exactly as a
  call), and an UNENFORCED message (a clashing name) no longer gives its body
  the element facts (`strip_params_refinements` only strips an outermost
  refinement, so the contenv is withheld instead).
- **Actor state literal with a shared shape.** `check_state_literal` (the
  actor's own `init` / handler-tail check) only ran the scalar fields. A
  state literal whose field set another record shares names no constructor
  through `by_fields`, so its element slots were obliged by nothing. It now
  runs `check_field_elements` too, but only when `by_fields` does not already
  resolve the literal to this actor (otherwise `visit`'s `ERecord` arm checks
  it and the obligation would be filed twice; pinned by the "unique: one
  violation" assertion).
- `Refine_audit.classify`: `Variant_arg` and `Actor_handler_param` join the
  `Type_arg` → `Enforced` rule (and its relation-issue twin), since those
  element slots are now obliged. Both audit baselines are unchanged (the
  corpus baseline is empty; the holes baseline has only `tuple_element`).

### Tests: `element-only-ctor` suite in `test/test_refinecheck.ml`

RED on the unfixed lib (`git checkout -- lib`, test exe rebuilt), first failing
assertion of each case, then GREEN (14/14) with the fix:

| # | case | RED (unfixed) |
|---|------|---------------|
| 0 | P4v verbatim: violated, about `_ > 0` | `ASSERT P4v: a violated obligation on Box about "_ > 0" []` (line 16784) |
| 1 | good Box `[1, 2]`: proved | `ASSERT good Box: a proved obligation … []` (16784) |
| 2 | `{ b with xs: [0 - 1] }`: violated | `ASSERT update: a violated obligation … []` (16784) |
| 3 | variant `W([0 - 5])` violated, `W([1, 2])` proved, open slot skipped | `ASSERT W bad: a violated obligation on W … []` (16784) |
| 4 | `Option` and `List(List(…))` fields, bad violated / good proved | `ASSERT Option bad: … []` (16784) |
| 5 | `Map(String, {Int \| _ > 0})` field (stdlib map.march loaded) | `ASSERT Map bad: skipped on M about "can fail it" []` (16895) |
| 6 | element-only slot naming field `n`: skip "names another field" | `ASSERT sibling: a skipped obligation … []` (16784) |
| 7 | `cap verified`: bad construction is an error; good one is not | `ASSERT an error naming the element refinement []` (16920) |
| 8 | actor message `Push([0 - 1])` violated, `Push([3])` proved | `ASSERT Push bad: a violated obligation on Push … []` (16784) |
| 9 | actor state literal, shape shared by `Other` / unique: one violation each | `ASSERT clash: one violation []` (16950) |
| 10 | clashing `Push` in two actors: body's `need(h)` not proved | `ASSERT need obligations exist, none proved [need proved _ > 0; need proved _ > 0]` |
| 11 | audit: variant arg element slot Enforced | `ASSERT disposition` Expected `"Enforced"`, Received `"Unenforced"` |
| 12 | audit: handler param element slot Enforced | same |
| 13 | audit: element-only record field slot Enforced (control, unchanged) | passed unfixed (the audit already claimed it; the claim was false) |

Every assertion checks a verdict plus its predicate or skip detail, never an
exit code. The unfixed CLI gave `0 proved, 0 violated, 0 trusted, 0 skipped`
(user code) for every one of these programs, including the good controls.

**Map ruling.** A bad `Map` value through `Map.singleton("a", 0 - 1)` is a
recorded skip ("argument 2 of `Map.singleton` can fail it for some input"),
not a violation: the generic-call element-flow rule decides that, not this
fix. Under `cap verified` it is an error. The good case proves.

### Oracles and suite

- **refine-oracle** (baseline taken before the first edit, 7914 lines over 553
  fixtures). Red-capability proof: the first check ran with a temporary
  `test/native/zz_oracle_perturb.march` (the P4v program) added; it reported
  `DIAGNOSTICS CHANGED — 24 differing lines`, every one tagged
  `native_zz_oracle_perturb` (its new `1 violated` report and the error
  text), and no line from any other fixture. The fixture was then deleted and
  the final check, on the final compiler (including the handler and
  actor-state changes), reported `REFINEMENT DIAGNOSTICS IDENTICAL (7914 lines
  over 553 fixtures)`. So no stdlib module or test/native fixture builds an
  element-only record, variant or message the checker now obliges
  differently: no new violation, no finding to report.
- **ir-oracle**: `IR IDENTICAL across 498 programs` (baseline on the unfixed
  compiler). Caveat: the compiler binary was rebuilt once while the check was
  running (for the actor-state change, a `lib/refinecheck` edit that cannot
  reach emitted IR); the check was not re-run afterwards.
- **`scripts/run-tests.sh`** (full): all suites passed, 6217 tests; the only
  skips are Linux-only cases (static_link, cap_sandbox_runtime) and one
  cross-compile case without a sysroot. The golden error corpus (`errors`,
  300 cases) passed without `UPDATE_ERRORS`.
- **`scripts/check-docs.sh`**: passed (Check F confirms the regenerated
  `docs/refinement-types.md`).

### Rulings

- Registration widened rather than a second table: one `by_ctor` keeps the
  existing fail-closed clash rule for element-only constructors too.
- The handler-message and actor-state-literal holes were fixed here, not
  filed, because they are the same missing-registration / missing-element
  check and the fixes mirror the record path exactly.
