# Accumulator invariants for fold-shaped calls, phase 2

Landed 2026-10-18. Design: `specs/2026-10-18-fold-accumulator-invariants-design.md`, phase 2
of §8 (rows f1, f2, f17 of §0). Built on `9beb7a5e8` (phase 1 and its named-callback
precondition fix, element-flow phases 0-3).

## The rows, measured on the base first

| Row | Program | `9beb7a5e8` | Now |
|---|---|---|---|
| f2 | `need_nn(List.fold_left(nn, 0, fn (acc, x) -> acc + x))` | **proved** (phase 1 + element-flow phase 1's `x` fact) | proved, pinned |
| f1 | `need_pos(List.fold_left(pos, 1, fn (acc, x) -> acc * x))` | **proved** on z3 4.16 | proved on z3 4.16, pinned tolerantly (below) |
| f1 control | `_ >= 0` elements into `_ > 0` | skip, `accumulator-step-unproved` | unchanged, pinned |
| — | `need_pos(Enum.fold(pos, 1, fn a -> fn x -> a + x))` (curried, element fact on the inner `x`) | skip, `accumulator-step-unproved` | **proved** |
| f17 | `sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))` | skip, `unreflectable-subject` | **proved** |

So the scalar half of phase 2 had already landed with phase 1 (its progress note says so for
the positive sum); what was missing was the CONTAINER accumulator and the curried inner
parameter's element fact.

## What a user sees

```march
sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))                    -- proved
sum_pos(List.fold_right(pos, Nil, fn (x, acc) -> Cons(x, acc)))                  -- proved
sum_pos(Enum.fold(pos, Nil, fn acc -> fn x -> Cons(x, acc)))                     -- proved
fn keep_pos(ys : List(Int)) : List({Int | _ > 0}) do
  List.fold_left(ys, [1], fn (acc, x) -> if x > 0 do Cons(x, acc) else acc end)  -- proved
end
sum_pos(List.fold_left(ys, Nil, fn (acc, x) -> Cons(x, acc)))   -- skip, accumulator-step-unproved
sum_pos(List.fold_left(pos, [0], fn (acc, x) -> Cons(x, acc)))  -- skip, accumulator-base-unproved
need_pos(Enum.fold(pos, 1, fn a -> fn x -> a + x))              -- proved (was a step skip)
```

## Code (`lib/refinecheck/refine_check.ml`)

- `demand_flow`: a declared return that is a BARE type variable `b` (not a container `TyCon`)
  now pairs the whole container demand with it, `[(b, Container (container, slots))]` (design
  §3.1's last row). The call sits in a container position, so the typechecker instantiated
  `b` to that container. Same P1/P2 gate (`parametric_ok`, with its own "not parametric in its
  return type" detail) and the same `discharge_pairs`. Before, the arm answered `` `Na `` and
  `check_elements` recorded `unreflectable-subject`. Not fold-specific: `sum_pos(pick(c, pos,
  [3]))` with `pick(c, x : b, y : b) : b` proves through its two bare sources.
- `invariant_params` now also hypothesises a CONTAINER demand: a callback parameter whose
  arrow-chain domain is exactly a container-demanded variable is returned as a container-env
  entry `(name, (c, slots))` (the new middle component of its `Ok`), which `lambda_ok` adds
  to `ce'` after the parameters are bound. Same soundness argument (§2.2: every `b` the
  callee hands the step is one it already held) and the same guards, the shadowing guard
  extended to every slot predicate (`elem_entry_mentions`; a slot's binder is its element,
  never a lambda parameter, so nothing is exempt).
- `lambda_domain_params ?peeled`: a curried lambda read as one (`peel_lambda`) gives every
  peeled parameter its arrow-chain position's element fact, guards (G2-1..3) over all of them.
  `lambda_ok` passes the peeled list; before, inner parameters were erased. Used only inside
  the demand discharge: the ordinary walk of a curried lambda's body is unchanged (its inner
  parameter still gets no fact there; stated in the reference).
- `discharge_pairs`' `accumulator` classification counts a container-demanded variable that
  a callback consumes, so a failing source is reported as `accumulator-base-unproved` /
  `accumulator-step-unproved` rather than `parametric-source-unproved`.

## Tests

`test/test_refinecheck.ml`, group `fold-invariants-2` (30 cases, ledger triples, reasons and
detail text; the prelude is fold-invariants-1's local fold shapes plus `sum_pos`, `sum_lt`, a
pair type and `need_p4`). On `9beb7a5e8` (the final test file built against the base library
in a detached worktree) **25 of 30 were RED**: 13 proof rows `(0, 0, 1)` instead of `(1, 0, 0)`
(the curried element fact; f17 with `Nil`, `[]`, a refined base and a guarded step,
`fold_right`, curried, a return tail, a relational `_ < n` demand with a refined capture; the
nested fold and its inner-shadowing twin; the two-variable control; the unmarked twin of the
`@[trusted]` row; `pick`), f17 under `cap verified` rejected, six controls with
`unreflectable-subject` instead of the accumulator reason (unrefined element, violating
element, `[0 - x]`, base `[0]`, unrefined base list, nested inner step), the impostor with
`unreflectable-subject` instead of `parametric-source-unproved`, and four guard rows by their
detail (container own-annotation, accumulator spelled like the demand's name, the
two-variable container shadow, `let?`). GREEN on both, as pins: f2, f1, the f1 zero-capable
control, the curried unrefined-elements control, the curried own-annotation guard.

**f1 and CI's z3.** The design (§4.2) asks f1's assertion to pin the verdict CI's z3 4.8.12
returns. Only z3 4.16.0 is installed here, and nothing in the repo runs 4.8.12 locally, so it
was NOT probed. The test pins what is true on either solver: never violated, one obligation,
and if it is a skip its reason is `nonlinear-goal` / `solver-undecided`. f1 is kept out of the
`cap verified` conformance fixture for the same reason. Tighten the assertion once CI's verdict
is seen.

Perturbations (each applied, built, the fold groups plus `named-callback-preconds`,
`elemflow-scalar-demand`, `elemflow-multiparam` and `demand-flow` run, restored, rebuilt):

| Perturbation | Goes red |
|---|---|
| bare-`TyVar` arm of `demand_flow` off (`` `Na ``) | every container row (proofs, controls' reasons, guard details, impostor reason, `pick`): 22 of 30; the two P(b, c) rows (a `TyCon` return) stay green, correctly |
| container hypothesis never given | exactly the 12 container proof rows (f17 ×7, `cap verified`, nested ×2, the two-variable control, the unmarked `@[trusted]` twin) |
| container shadowing guard off | the two-variable shadow row, `(1, 0, 0)`: a FALSE proof, executed: `pf4([1], [n + 1], fn (k, n) -> if n > 0 do k else [1] end, [1])` with `n = -5` returns a `c` whose head is `-4` against `List({Int \| _ > 0})` |
| peeled element facts off | the curried scalar proof and curried f17 |
| `accumulator` classification scalar-only again | the six controls' reasons (now `parametric-source-unproved`) |
| own-annotation `Error` off for container targets | that row's detail only (the erasure still withholds the annotation; belt-and-braces as in phase 1) |
| P1 forced true in the bare-`TyVar` arm | the `kc` impostor, `(1, 0, 0)` (`kc` cons'es `-1` onto its accumulator; `march --check` also rejects `kc` as `annotated_tyvar_fixed`, so the refinement gate is pinned on its own, as in phase 1) |

No new guard was needed beyond phase 1's: the container hypothesis reuses them. The `let?` and
own-annotation guards are pinned for the container path too.

Conformance: `accept/t420_refine_fold_container_accumulator` (`List.fold_left` with `[]`,
`List.fold_right`, curried `Enum.fold` building a list and summing with the inner element fact,
a return tail, the f2 sum, under `cap verified`; REJECTED on `9beb7a5e8`: four
`unreflectable-subject` and one `accumulator-step-unproved`), `reject/t421` (unrefined
element; reason pinned) and `reject/t422` (base `[0]`; reason pinned), both rejected on the
base too as `unreflectable-subject`. The corpus is 478/478 (200 accept, 278 reject).

## Verification

- `test_refinecheck.exe -e` in one run (private `HOME`, VC cache cleared once): 1267 tests,
  all pass, 517 s (`audit-baseline` and `z3-well-formed` included; no audit baseline moved).
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh` (private `HOME`): 478 passed, 0 failed.
- `scripts/refine-oracle.sh`: baseline from a detached `9beb7a5e8` worktree at the same
  directory depth (stdlib re-staged in both), check here: **identical**, 8663 lines over 549
  fixtures. Blind to this change: no `test/native` or `stdlib` file puts an element demand on a
  call whose declared return is a bare type variable, or checks a curried step against a
  demand; the group and the conformance trio are what see it.
- `stdlib/list.march` `--check --refine-report`: byte-identical to the base (35 proved, 0
  violated, 1 skipped for user code); the CI ratchet does not move.
- Timing, `--check --refine-report stdlib/list.march`, private `HOME`s, VC caches cleared once,
  five interleaved A/B rounds, load average 15-17: base median 1.116 s, this change 1.121 s
  (+0.4%, within the 110% budget); the first (cold) pair 1.234 / 1.251 s. The group runs in
  ~0.1 s.

## Left open

- f1's verdict on CI's z3 4.8.12 (above).
- A step tail naming something bound inside the step (`match acc do Cons(h, _) -> Cons(h,
  acc) … end`) is not checked (`lambda_tail_rebinds`, pre-existing for every lambda tail), so
  such a fold is a step skip; stated in the reference.
- A `let`-bound fold result used later (f11) carries nothing, as before.
- §7's out-of-scope items, filed now as the design asks:
  `specs/todos/2026-10-18-refine-fold-indexed-invariants.md`,
  `specs/todos/2026-10-18-refine-fold-tuple-record-accumulators.md`,
  `specs/todos/2026-10-18-refine-fold-list-b-callback-domain.md` (hand-written accumulator
  recursion was filed with phase 1; the annotated accumulator is phase 4; `impl`/`interface`
  dispatch stays unchecked generally; inferring an invariant is never planned).
- Phases 3 (stdlib fold signatures) and 4 (the annotated accumulator).

Todos touched: the accumulator half of item 2 of
`specs/todos/2026-09-18-refine-element-flow-followups.md` is closed; the `fold_left` bullet of
`specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md` is dropped (its
`Map.filter` bullet stays open).
