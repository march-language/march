# Abstract refinements, phase 2: `List.filter` keeps what its predicate says

Landed 2026-10-06/07. Design: `specs/2026-09-20-abstract-refinements-design.md`
(phase 2). Plan: `specs/plans/2026-10-06-abstract-refinements-phase2-plan.md`
(PR B, tasks B0-B9). Prerequisite (PR A):
`specs/progress/2026-10-06-callback-binder-pass-sites.md`. Closes item 6 of
`specs/todos/2026-09-18-refine-element-flow-followups.md`.

## What a user sees

```march
fn sum_pos(xs : List({Int | _ > 0})) : Int do … end
sum_pos(List.filter(ys, fn y -> y > 0))      -- proved   (was parametric-source-unproved)
let zs = List.filter(ys, fn y -> y > 0)
sum_pos(zs)                                  -- proved   (was unreflectable-subject)
sum_pos(List.filter(pos, fn y -> y < 100))   -- proved when pos : List({Int | _ > 0})
sum_pos(List.filter(ys, fn y -> y >= 0))     -- skip: abstract-refinement-too-weak
```

Every demand above is an error under `cap verified` unless proved: before this
work all four were errors there, and now only the last one is.

## What landed, per task

| Task | Commit | Change |
|---|---|---|
| B1 | `feat(refinecheck): abstract-refinement obligation reasons` | `Abstract_too_weak`, `Abstract_uninstantiated` (classified like `Parametric_source_unproved`) |
| B2 | `… uninterpreted inside their definition` | `p(e)` translates to `($abs_p e)` while the declaring fn is walked (`current_abstracts`, set in `visit_fn`); `abstract_preamble` declares it last in both preamble sites; arms in `mentions_str`/`wellsorted`/`formula_wellsorted`/`resolve_sorts_exact` |
| B3 | `… locate an abstract refinement's definer and element type` | `Refine_abstract.definer_index`, `positive_base` |
| B4 | `… never read as a call-site fact` | `declared_elem_return` drops an entry applying a callee abstract refinement |
| B5 | `… instantiate … from an inline lambda at its call` | `abstract_flow` (+ `abstract_return_slot`, `record_abstract_verdict`), hooked before `demand_flow` |
| B6 | `… conjoin the input's element fact` | the single `Src_elem` source's slot is conjoined, incoming first |
| B7 | `… let-bound … re-examined at its use` | `check_elements`' variable arm consults the `lets` channel |
| B8 | `feat(stdlib): List.filter's result carries its predicate` | the signature (with the `subset` contract kept); `refine_audit` reads the slot under the enclosing fn's abstracts; baselines; conformance pair |

## Deviations from the design and plan (each found by a test going red)

1. **A type-variable element refinement was never a slot.** `refined_param_ty`
   accepts only Int/String/Bool/Float/ADT bases, so `List({a | p(_)})` produced
   *no obligation at all*. Both n5 and n6 passed vacuously until "an
   obligation exists" was asserted. Fix: `abstract_tyvar_slot` admits one only
   where its predicate applies a current abstract refinement, i.e. inside the
   declaring definition. `gate_elem_returns` reads candidates the same way
   (`has_elem_return`), and so does `refine_audit` (otherwise filter's return
   counted as 1 unenforced and broke the CI audit ratchet). The design assumed
   a type-variable base "already parses", which is true but not sufficient.
2. **`formula_wellsorted` refused every application in Bool position.**
   `$abs_p` is the first Bool-valued uninterpreted function, and the goal
   `$abs_p(h)` hit `float-sort-gate` until the gate learned it.
3. **A caller with its OWN `p` read a callee's `p(_)` as its own.** Once (1)
   holds inside a function declaring `p`, a call to another function declaring
   a `p` admitted that slot: `g(ys, k)` returning `filt(ys, fn y -> true)`
   proved `g`'s element return. B4's exclusion closes it. Test SN is red with
   the exclusion disabled. It picks `g`'s obligation out by source line, because
   it shares the label `filt(…)` with filt's own legitimately proved recursive
   tails.
4. **Instantiation is from an inline lambda only.** The design's
   "`let`-bound lambda via `cbenv`" is not possible: `cbenv` stores a
   signature, not a body. Named predicates (row n3) remain phase 3.
5. **The too-weak detail names the lambda and the demand, without a witness
   value.**
6. **The let-bound result goes through the `lets` channel**, which
   re-examines the bound call at the use, rather than through `contenv`. The
   channel's retirement rule therefore now guards a verdict, not only a sentence;
   its comment says so. It is conservative: rebinding the *input* also
   retires the record (test NLI).

§3.5, a negative occurrence (`p` in a parameter's element slot), was found
silently UNCHECKED when probed after the first round (2026-10-07: zero
obligations, even for `need([0, 1], fn y -> y > 0)`), because a call site sees
no slot for a callee's `{a | p(_)}`. Fixed in this PR: `abstract_param_entry`
instantiates `p` at the call and `check_arg_elements` runs ordinary element
subtyping against it (tried before `elem_refinement`, which would read a
same-named caller `p`); an opaque callback is an `uninstantiated` skip. Tests
§3.5 call side (refined input / literals / literal 0 violated / unrefined
skip / opaque uninstantiated; red without the path) and definition side
(`pass` returning `xs` proves `List({a | p(_)})`). `abstract_slot_of_ty` and
`instantiate_abstract` are now shared with `abstract_flow`.

**Pressure test before phase 3 (2026-10-07) found two more, fixed here:**
(a) the §3.5 demand defaulted to the Int sort, so a CORRECT
`need(ss, fn s -> String.byte_size(s) > 0)` with `ss : List({String | len(_) > 0})`
was a false *violation* (witness `len($elem) = 0`). The sort now comes from
the argument's typechecked element type (`elem_marker_of_arg`), and an
unknown sort declines (`uninstantiated`). String literals now prove, and
`["a", ""]` is a genuine violation. (b) A lambda whose body calls a function
(`fn y -> is_pos(y)`) was reported `too-weak`, because the call is not
reflected where the predicate is assumed, so the assumption silently dropped.
It is now `uninstantiated`, naming the call. Both have tests that were red
first.

## Tests (`test_refinecheck`, group `abstract-phase2`)

| Case | Covers |
|---|---|
| slugs | B1 |
| n5 / n6 | definition side proves; returning the input has an obligation that neither proves nor violates |
| definer_index / positive_base | B3 |
| SN | a callee's `p(_)` is not the caller's `p` (red without B4) |
| n, n2, n4, capture, NB, cap verified | B5: proved / too-weak / uninstantiated (opaque, capturing, unproved callee) / `cap verified` both ways |
| n1, n1 control | B6 |
| let-bound, rebind name, rebind input | B7 |

Also: the phase-1 inert case is renamed (it is now the n4+n6 shape), and the
conformance pair `accept/t308`, `reject/t309` runs over the real `List.filter`.

## Verification

- `scripts/run-tests.sh` (full): all passing. compiler 1367, eval 288, codegen 673, stdlib 894, stdlib_march 76, test_jit 33, lsp 379 + 5 + 37 + 10 + 7, refinecheck 1000.
- `scripts/run-tests.sh stdlib stdlib_march`: 894 + 76 tests, all passing.
- `specs/lang/types/check_types.sh`: 430/430.
- `scripts/refine-oracle.sh check` against the PR-A baseline: 1880 lines,
  **every** count line `+3 proved` / `+3 precondition` (filter's three tails),
  and 2 lines that are `list.march` warning snippets shifted 5 lines by the new
  docstring. No skip, violated or trusted count moved in any program.
- Audit baselines regenerated: every line `+3 enforced`; `list.march`'s own 14 → 17; 0 unenforced.
- CI ratchet (`stdlib/list.march`, user + stdlib): 58 proved, 0 violated, 33 trusted, **37 skipped** (limit 42).
- Ecosystem: `--check --refine-report` over all 77 `conduit`/`depot` lib
  files, PR-A compiler vs this branch: **byte-identical** (exit codes and
  reports; their 46 non-zero exits are the same under both).
- Cold `--check --stdlib-source stdlib/list.march`, interleaved A/B, 5 runs
  each at load 8.5-9: PR A 1.13-1.16 s, this branch 1.10-1.12 s. No
  regression; the budget was 110%.
- VC cache: t308, t308 (warm), t309 → 0, 0, 1. The cache key is the full
  query text, so the second lambda does not inherit the first's verdict.
