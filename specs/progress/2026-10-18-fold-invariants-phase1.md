# Accumulator invariants for fold-shaped calls, phase 1

Landed 2026-10-18. Design: `specs/2026-10-18-fold-accumulator-invariants-design.md`, phase 1
of §8 (rows f3-f15, f20 of §0). Built on element-flow phase 2 (`6fcef2c9d`), whose scalar
entry point (`Refine_check.scalar_demand`), return-tail hook (`Refine_post.tail_demand`) and
`discharge_pairs` it extends; it adds no entry point of its own.

## What a user sees

```march
need_nn(List.fold_left(ys, 0, fn (acc, _x) -> acc + 1))           -- was a skip; proved
fn h(ys : List(Int)) : {Int | _ >= 0} do
  List.fold_left(ys, 0, fn (a, x) -> if x > a do x else a end)      -- was a skip; proved
end
need_nn(List.fold_right(ys, 0, fn (_x, a) -> a + 1))              -- proved
need_nn(Enum.fold(ys, 0, fn a -> fn _x -> a + 1))                 -- proved (curried)
one_pos(Enum.reduce(pos, fn a -> fn x -> a + x))                  -- proved (container path)
need_pos(List.fold_left(pos, 1, fn (acc, x) -> acc + x))          -- proved (x's element fact too)
need_nn(List.fold_left(pos, 0, fn (acc, x) -> acc - x))           -- skip, accumulator-step-unproved
need_pos(List.fold_left(pos, 0, fn (acc, x) -> acc + x))          -- skip, accumulator-base-unproved
```

A demand `D` on the result of a call to a callee parametric in its return variable `b`
(P1/P2) is read as `b := {b | D}`: every source of `b` must meet `D` (unchanged), and a
callback source's tails are now checked ASSUMING `D` of each of its parameters whose declared
domain is exactly `b` (the design's §2 induction / free theorem). Not specific to the stdlib:
a user-written fold proves the same way.

## Code

- `lib/refinecheck/refine_check.ml`
  - `peel_lambda`: `fn a -> fn x -> body` against a chain of 2 is read as `fn (a, x) ->
    body` (exact count, distinct non-wildcard names; otherwise checked as written).
  - `invariant_params ~sg ~i ~pairs ps body` (design §3.2): the hypothesis, `Ok (ps',
    used)` or `Error why` (own refinement annotation on a receiving parameter, `let?`/`let*`
    anywhere in the body, a lambda parameter free in a demand it would assume).
  - `discharge_pairs`: `hyp_ok = invariant_callee_ok ctx g`; the `Src_cod` lambda arm
    peels, runs the existing capture guard over EVERY peeled parameter, and `lambda_ok`
    overlays the hypothesis on the outer lambda's element facts (`lambda_domain_params`,
    unchanged; peeled inner parameters get no element fact). The verdicts are classified:
    a variable with a scalar demand that some `Src_cod` callback consumes (an arrow-chain
    domain is exactly it) is an ACCUMULATOR, and its failing `Src_bare`/`Src_elem`/
    non-consuming `Src_cod` source is the base, its consuming `Src_cod` the step.
  - `erase_param_refinements`: see "Two soundness fixes" below.
  - The `` `Unproved `` payload of `demand_flow`, `scalar_demand` and `discharge_pairs`
    is now an `Obligation.reason` (was a string always wrapped as
    `Parametric_source_unproved`); `record_param_skip ~reason`.
- `lib/refinecheck/obligation.ml`: `Accumulator_base_unproved`, `Accumulator_step_unproved`
  (`accumulator-base-unproved` / `accumulator-step-unproved`, detail = payload); classified
  in `refine_call.ml`'s three exhaustive matches like `Parametric_source_unproved` (per site,
  escalated under `cap verified`).
- `lib/refinecheck/refine_call.ml`, `refine_post.ml`: the demand closure / tail hook types
  carry the reason through (`` `Unproved r -> note (Skipped r) ``).
- `lib/refinecheck/refine_param.ml`: `invariant_callee_ok` (not an adopted `impl` method,
  not `@[assume]`, not `@[trusted]`), `impl_keys`, and the P2 interface fix below.

## Two soundness fixes (pre-existing false proofs found by the controls)

Both type-checked under `cap verified` on `6fcef2c9d`; each is pinned by a reject fixture.

1. **An interface method's result counted as parametric** (`reject/t384`). `fn pick(o :
   Option(a), d : a) : a` returning `dflt(1)`, where the only `impl Dflt(Int)` returns -5:
   `classify_head` resolved `dflt` to the ADOPTED impl body (head-free, so "safe") and a
   non-adopted method tainted only when its signature CREATES a variable. So
   `need_pos(pick(o, 1))` and `sum_pos(mk(pos))` (with `mk` consing `dflt(1)`) were proved;
   `pick(Some(3), 1)` runs to -5 (executed). With the new rule a fold impostor `k13` that
   hands its step `dflt(1)` would have proved too (`reject/t383`). Now `iface_methods`
   records `method_returns_var` (the result mentions ANY type variable, so `t -> t`
   taints too), and an adopted impl key behind such a method is `` `Taint ``.
2. **A callback parameter's own refinement annotation was assumed** by `lambda_ok`
   (`reject/t385`): `need_pos(List.fold_left(pos, 1, fn (acc : {Int | _ > 100}, x) -> acc
   - 50))` was proved, although nothing checks that annotation (the domain is `b`) and
   `List.fold_left([5], 1, …)` is -49. `lambda_ok` now erases every refinement in a
   parameter's own annotation (any depth) unless `lambda_domain_params` gave it a fact; the
   annotation is also not read as the invariant (phase 4, open decision 1).

## Where this departs from the design

- **f5 (relational `{Int | _ >= lo}` at a return) is declined, not proved.** The scalar
  hook answers `` `Na `` for a non-closed demand, at calls and return tails alike, so the
  fold rule is never reached; f5 keeps its `unreflectable-subject` skip, pinned. Filed:
  `specs/todos/2026-10-18-refine-relational-scalar-demand.md`. f10 (the shadowing relational
  contract) is therefore also untouched: still violated with today's witness, pinned.
- **s9 / f1-f2-like steps prove in phase 1.** The design put "needs `x > 0` from (a)" in
  phase 2; (a) has landed, so `need_pos(List.fold_left(pos, 1, fn (acc, x) -> acc + x))`
  proves now. Two `elemflow-scalar-demand` assertions that pinned the old boundary were
  updated (s9, and `fn (k, x) -> k` under a caller `k > 0`, both now (1, 0, 0), both true).
  Peeled (curried) inner parameters still get no element fact.
- **No witness in the step detail.** The design's "`acc = 0, x = 1` gives `-1`" is not
  rendered: `scalar_ok` returns only a verdict. The detail names the half, the argument, the
  initial value (rendered) and, for a decline, the reason.
- **`@[trusted]`, `@[assume]` and adopted `impl` callees get no hypothesis** (the task's
  call; the design's gates are P1/P2 only). Their bodies are parametric in the tests, so
  these are policy, not false proofs: the plain discharge still runs.
- **Reason classification is per variable** (an accumulator is a scalar-demanded variable
  some callback consumes), only where `hyp_ok`; a non-consuming callback source of an
  accumulator (`g : Int -> b`) counts as a base.
- **Guards that are belt-and-braces** (each kept, each pinned, but no live false proof was
  found without it): the own-annotation `Error` (the replacement already skips a refined
  annotation; perturbing the guard changes only the detail), the `let?`/`let*` decline (a
  step returning a scalar `b` cannot contain an escaping `let?`; the fixture's is inside a
  nested lambda, and the perturbation turns it proved, correctly), and the distinct-names
  peel condition (sequential shadowing already gives the inner binder its own fact).

## Tests

`test/test_refinecheck.ml`, group `fold-invariants-1` (32 cases, ledger triples, reasons and
detail text). On `6fcef2c9d` (the final test file copied into a detached worktree of the
base, built against the base library) 24 of the 32 cases were RED: every proof row (f3, f4,
f4′ caller, s9, f9, f12, f13, f14, `acc : Int`, the guarded step, f20, the VC-cache pair,
the two-variable control, the unmarked twin of the `@[trusted]` row), every control's
reason or detail (f6, f7, f8, reduce step/base, the base-callback row), the own-annotation
guard as a (1, 0, 0) FALSE proof, the other three guard rows by their detail, and the
interface impostor row, whose `pick` assertion was a (1, 0, 0) FALSE proof. Green on both,
as pins: f10 violated, f5 declined, the repeated-name peel, the constant / fabricated-`b` /
`from_json` / unannotated-`f` / tuple impostors (P1 or `sources_of` blocks them; the
perturbations below show which).

Perturbations (each applied, built, the group run, restored and rebuilt):

| Perturbation | Goes red |
|---|---|
| `invariant_params` never hypothesises | exactly the proof rows (f3, f4, f4′, s9, f9, f12, f13, f14, `acc : Int`, guarded step, f20, VC pair, two-variable control, unmarked twin) plus the decline-detail rows (the decline path is bypassed) and the two updated `elemflow-scalar-demand` assertions |
| own-annotation erase off (`lambda_ok` keeps `ps0`) | the annotation guard row, (1, 0, 0): the false proof of `reject/t385` |
| own-annotation `Error` off | that row's detail only |
| `let?` guard off | the `let?` row, (1, 0, 0) (not a false proof, see above) |
| capture guard over the outer parameters only | the inner curried shadow row, (1, 0, 0): `cr` returns `Some(999)` for `n = 101` |
| hypothesis shadow guard off | the two-variable shadow row, (1, 0, 0): `pf2` builds `P(0 - 4, 5)` |
| peel off | f13, f14, the inner-shadow detail |
| peel distinct-names off | nothing (see above) |
| P1 forced true | the constant, fabricated-`b` and unannotated-`f` impostors, (1, 0, 0) each |
| P2 forced true | the interface impostor fold, (1, 0, 0) |
| adopted-impl taint off / `method_returns_var` back to `method_creates` | the interface impostor fold / its `t -> t` assertion, (1, 0, 0) |
| `invariant_callee_ok` always true | the `@[trusted]` row, (1, 0, 0) |

Conformance: `accept/t380_refine_fold_accumulator_invariant` (stdlib `List.fold_left`,
`fold_right`, `Enum.fold`, `Enum.reduce`, a return tail, a capture, a user fold under `cap
verified`; rejected on `6fcef2c9d`), `reject/t381` (f6, reason pinned), `reject/t382` (f7,
reason pinned), `reject/t383` (the interface impostor fold; rejected on the base too, it
pins the gate), `reject/t384` and `reject/t385` (the two fixes; both ACCEPTED on the base).
The corpus is 468/468 (196 accept, 272 reject).

## Verification

- `test_refinecheck.exe -e`, private `HOME`, VC cache cleared once, run in three parts by
  group (the foreground limit): 426 + 328 + 418 = 1172 tests, all pass, 0 failed
  (`z3-well-formed` and `audit-baseline` included: no audit baseline moved).
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh` (private `HOME`): 468 passed, 0 failed.
- `scripts/refine-oracle.sh`: baseline from a detached `6fcef2c9d` worktree at the same
  directory depth, check on this branch, staged `_build/default/stdlib` set aside:
  **identical**, 7786 lines over 549 fixtures. Blind to this change (no corpus fixture puts
  a demand on a fold or calls an interface method returning a type variable from a
  parametric body); shown live by a perturbation (a reason slug renamed), which diffs.
- `stdlib/list.march` `--check --refine-report`: byte-identical to the base (21 proved, 0
  violated, 1 skipped for user code); the CI ratchet does not move.
- Timing, `--check --refine-report stdlib/list.march`, private `HOME`, VC caches cleared
  once, five interleaved A/B rounds, load average 7-10: base median 1.115 s, this change
  1.123 s (+0.7%, within the 110% budget); the first (cold) pair 1.368 / 1.527 s. The group
  runs in ~0.2 s.

## Left open

- f5 / relational scalar demands: `specs/todos/2026-10-18-refine-relational-scalar-demand.md`.
- f19, hand-written scalar accumulator recursion:
  `specs/todos/2026-10-18-refine-scalar-accumulator-recursion.md`.
- Phases 2-4 of the design (container accumulators f17, element facts for peeled curried
  parameters, stdlib fold signatures, the annotated accumulator). §7's other out-of-scope
  todos are filed at phase 2 as the design says.

## Review follow-up: a named step's preconditions (second commit, same day)

An independent review of `32a847506` found no false proof introduced by the rule, but one
pre-existing one beside it (also on `6fcef2c9d`), runtime-confirmed: `discharge_pairs`'
named-callable arm (`Src_cod` passed as a bare `EVar f`) took `f`'s declared return
refinement as the source's result without checking that what the callee hands `f` meets
`f`'s own parameter refinements, and a type-variable domain has no pass-site obligation.

```march
fn dec2(a : {Int | _ > 100}, _x : Int) : {Int | _ > 0} do a - 50 end
need_pos(List.fold_left(ys, 1, dec2))     -- was PROVED; go([5]) is -49
fn g(_a : Int, x : {Int | _ > 0}) : {Int | _ > 0} do x end
need_pos(List.fold_left(ys, 1, g))        -- was PROVED; go([0 - 5]) is -5
```

Fix (`named_preconds`, inside `discharge_pairs`, used by both the scalar `` `S `` and the
container `` `C `` named-callable arms): a named callable with refined parameters
contributes its return only when its arity matches the callee's arrow chain and every
refined parameter is CLOSED and implied, at its position, by what the callee guarantees
there: the demand of a demanded variable (the invariant hypothesis, `hyp_ok` only; the same
induction step a lambda parameter takes) or the agreed element refinement of the position's
variable (`lambda_domain_facts`). Each implication is one `scalar_ok` query over a fresh
`$p` carrying the fact. Anything else declines; the skip's detail names the precondition
("the precondition `_ > 100` of `dec2` on `a` is not known to hold of what
`List.fold_left` passes it"). Phase A's helper-inlining rule
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseA.md`) is the same stance:
a helper's contract only where its refined parameters are proved at the call.

Other routes checked: `List.map(ys, dbl)` with a named `dbl(x : {Int | _ > 0})` and a caller's
callback parameter `k : ({x : Int | x > 100}) -> {Int | _ > 0}` passed on to `map` went
through the same arm and were proved too (both fixed, both pinned). A single-parameter named
callable passed at a type-variable domain IS obliged at the pass site
(`ap(n, dec)`, `Option.map(o, dec)` report a violation), so the scalar codomain pass site and
`check_pass_site_elements` do not have this hole for one parameter. They do for TWO or more:
`pass_site_obligation` returns `None` for a multi-parameter callable, so
`List.fold_left(ys, 1, dec2)` with no demand on its result files no obligation at all under
`cap verified`. No false proof follows from it any more (the demand route is fixed), but the
contract is unenforced: filed as
`specs/todos/2026-10-18-multi-param-callable-domain-unobliged.md`, not fixed here (it obliges
new stdlib call sites and needs its own sweep). `Option.unwrap_or_else(o, mk)` takes a
zero-parameter `mk`, so it has no precondition to miss.

Tests: group `named-callback-preconds` (8 cases, the demanding call's verdict and reason
only, since the named functions' own return obligations prove either way). On `32a847506`
five were RED, each a (proved) false proof: p10, p11, `map` over an unrefined list, the
callback parameter passed on, and `dec2` with the base `200` (the demand `_ > 0` does not
give `_ > 100`). Green on both: a named step with no refined parameter, `keep(a : {Int | _
> 0})` discharged by the demand, `g` over a refined list. Perturbations: `named_preconds`
always `Ok` turns exactly the five red; the demand route removed (element facts only) turns
exactly "the accumulator demand discharges the step's precondition" red.

Conformance: `reject/t386_refine_named_step_accumulator_precondition` (p10) and
`reject/t387_refine_named_step_element_precondition` (p11), both ACCEPTED under `cap
verified` on `32a847506`; `accept/t388_refine_named_step_precondition_discharged` (the three
controls with the stdlib `List.fold_left`). The corpus is 471/471 (197 accept, 274 reject).

Verification: `test_refinecheck.exe -e` (private `HOME`, VC cache cleared once, three parts):
426 + 328 + 426 = 1180 tests, all pass; `scripts/run-tests.sh -q compiler` 1348 pass;
`check_types.sh` 471/471; `refine-oracle.sh` baseline at `32a847506` (detached worktree,
same depth), check here, staged stdlib set aside: identical, 7786 lines over 549 fixtures
(blind to it, as before); `scripts/check-docs.sh` passes.
