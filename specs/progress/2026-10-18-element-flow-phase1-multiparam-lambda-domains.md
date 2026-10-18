# Domain facts for multi-parameter lambdas (element-flow follow-ups, phase 1)

Landed 2026-10-18. Design: `specs/2026-10-18-element-flow-followups-design.md`, §4 and
phase 1 of §8 (rows m1-m7 of §0.2). Closes item 2 of
`specs/todos/2026-09-18-refine-element-flow-followups.md`. Built on phase 0
(`specs/progress/2026-10-18-relational-element-refinement-scope.md`, `6769313ef`).

## What a user sees

```march
fn d(xs : List({Int | _ > 0}), ys : List({Int | _ > 0})) : Int do
  sum_pos(List.zip_with(xs, ys, fn (x, y) -> x + y))             -- was a skip; proved
end
List.zip_with(xs, ys, fn (x, y) -> need_pos(x) + need_pos(y))    -- was 2 skips; 2 proved
List.fold_left(xs, 0, fn (acc, x) -> acc + need_pos(x))          -- was a skip; proved
List.sort_by(xs, fn (a, b) -> need_pos(a) < need_pos(b))         -- was 2 skips; proved
List.fold_left(xs, 1, fn (acc, x) -> need_pos(acc) + x)          -- still a skip (acc gets nothing)
```

Each parameter `pj` of a lambda passed where the callee's parameter is
`d1 -> … -> dk -> r` assumes the element fact of `dj` when `dj` is a bare type
variable whose every source is an element agreeing on one refinement (the 2026-09-18
rule, applied position by position).

## Code

`lib/refinecheck/refine_check.ml`, nothing else in the library:

- `lambda_domain_facts ctx defs cb ce g sg args i : (int * q) list` (design §4.2): the
  arrow-chain positions of parameter `i` whose domain is a bare type variable with an
  agreed scalar slot (`agreed_elem_slot`, unchanged). Independent of the lambda's shape,
  for the sibling's curried-lambda peeling. Not exported in an `.mli` (the module has
  none for it); the sibling can use it from inside `refine_check.ml`.
- `lambda_domain_params` now maps every parameter of the lambda onto its position's
  fact, with the guards below. Its two consumers (`visit`'s `EApp` arm for body
  obligations, `demand_flow`'s `lambda_ok` for tail obligations) are unchanged.

Guards, as the design's §4.3, with the calls made where it left room:

| Guard | Implemented as |
|---|---|
| G2-1 arity | A one-parameter lambda takes position 0 of a chain of any length (the pre-phase-1 rule, kept byte-for-byte so `fn a -> fn b -> …` keeps its outer fact). A lambda of `k >= 2` parameters needs a chain of exactly `k`. Nested `ELam`s are not peeled. |
| G2-2 own annotation | Any parameter whose annotation contains a refinement anywhere (`ty_has_refinement`) declines the whole lambda. A fact replaces only an unannotated or `TyCon` annotation, as before. |
| G2-3 capture | Position `j` is not given `qj` when `qj` mentions ANY of the lambda's parameter names, except `qj`'s binder when the binder is `pj`'s own name (the old one-parameter exemption). Other positions are unaffected. |
| G2-4 accumulator | Inherited from `agreed_elem_slot`: `fold_left`'s `b` has a bare and a codomain source, so `acc` never gets a fact. |
| G2-5 repeated variable | Free: each position asks for its own variable, so `a -> a -> Bool` gives both. |
| G2-6 non-variable domain | That position gets nothing. |

## Where this departs from the design

- **G2-1, one parameter.** The design says "parameter count = arrow-chain length". Applied
  to one-parameter lambdas it would have *removed* today's fact for `fn a -> fn b -> …`
  against `a -> b -> c` (the outer `a` is exactly position 0, which is sound). Kept the
  shipped rule for `k = 1`; the equality applies from `k = 2`.
- **G2-2, "carrying its own `TyRefine`".** Read as "an annotation with a refinement anywhere
  in it" (`x : List({Int | _ > 0})` included), because `visit_lambda ~assume:true` assumes
  every annotation, including an element entry. For a one-parameter lambda this declines one
  shape the old rule accepted (a `TyCon` with an inner refinement at a scalar-fact position,
  which the typechecker would reject anyway). More conservative, no corpus change.
- **G2-3 covers siblings, not just the parameter itself.** The design's row is "a `qj` that
  mentions any of the lambda's parameter names declines". Implemented per position (only the
  capturing position loses its fact). The binder exemption is narrowed to the receiving
  parameter's own name, so a sibling spelled like the binder also declines.
- **A sibling capture is only sometimes a live false proof.** With the guard disabled,
  `fn (n, y) -> if n < 0 do need_neg(y) else 0 end` over `y`'s `_ < n` (the caller's `n`)
  proves (false: `f(5, [3], [0 - 1])`); the `(y, n)` order does not, because binding `n`
  after `y` already drops `y`'s fact. Both orders are pinned; the reject fixture uses the
  live one.

## Tests

`test/test_refinecheck.ml`, group `elemflow-multiparam` (13 cases, 21 ledger-triple
assertions plus one skip-reason assertion; never exit codes). On the unfixed library
(`6769313ef`, the group run with every assertion made non-fatal):

| Case | Before | After |
|---|---|---|
| m1 `sum_pos(zipw(xs, ys, fn (x, y) -> x + y))` | (0, 0, 1) | (1, 0, 0) |
| m2 `fn (x, y) -> x - y` | (0, 0, 1) parametric-source-unproved | same (never a violation) |
| m3 `need_pos(x) + need_pos(y)` | (0, 0, 2) | (2, 0, 0) |
| m4 `foldl(xs, 0, fn (acc, x) -> acc + need_pos(x))` | (0, 0, 1) | (1, 0, 0) |
| m5 `need_pos(acc) + x` (boundary) | (0, 0, 1) | same |
| m5′ `need_pos(acc) + need_pos(x)` | (0, 0, 2) | (1, 0, 1) |
| m6 `sortb(xs, fn (a, b) -> need_pos(a) < need_pos(b))` | (1, 0, 2) | (3, 0, 0) |
| m7 `mapl(xs, fn x -> need_pos(x))` | (1, 0, 0) | same |
| refined + unrefined list, `need_pos(x) + need_pos(y)` | (0, 0, 2) | (1, 0, 1) |
| `pick(xs, 5, fn (p, q) -> …)`, `a` also a bare source | (0, 0, 2) | same |
| G2-2 `fn (x : {Int \| _ > 100}, y)` | (0, 0, 2) | same |
| G2-2 control `fn (x : Int, y)` | (0, 0, 2) | (2, 0, 0) |
| G2-3 `fn (n, y) -> need_neg(n)` (self) | (0, 0, 1) | same |
| G2-3 sibling, both orders | (0, 0, 1) | same |
| G2-3 the uncaptured position `fn (y, n) -> need_neg(n)` | (0, 0, 1) | (1, 0, 0) |
| G2-3 control, fresh name under `n <= 0` | (0, 0, 1) | (1, 0, 0) |
| a violating step `need_pos(0 - 1)` | (0, 1, 0) | same |
| `fn (x, y) -> need_neg(x)` with `x > 0` | (0, 0, 1) | (0, 1, 0), the one-parameter verdict |
| G2-1 `fn (x, y) -> fn w -> need_pos(y)` at a three-domain chain | (0, 0, 1) | same |

Perturbations (each run against the whole group, non-fatal, then restored):

- multi-parameter arm off (`k <> 1` declines): exactly the ten "Before ≠ After" rows go
  red, nothing else.
- G2-2 off: only "G2-2 `fn (x : {Int | _ > 100}, y)`" goes red, as (2, 0, 0), a false
  proof of `need_big(x)` from the unchecked annotation.
- G2-3 widened back to the old self-only test: only the `(n, y)` sibling case goes red,
  (1, 0, 0), a false proof. The same perturbation built into the CLI makes
  `reject/t342` type-check.
- G2-1 relaxed to "chain at least `k`": only the G2-1 case goes red, (1, 0, 0).

Conformance: `specs/lang/types/accept/t340_refine_multiparam_lambda_domain_facts` (stdlib
`zip_with`, `fold_left`, `sort_by` under `cap verified`; rejected on `6769313ef` with
"cannot verify element refinement `_ > 0` on `sum_pos`", 7/0/0 now),
`reject/t341_refine_fold_accumulator_no_domain_fact` (the boundary) and
`reject/t342_refine_multiparam_domain_fact_sibling_capture` (G2-3). Both rejects are
rejected on the base as well; they pin the guards, not a fixed bug. The corpus is 453/453
(192 accept, 261 reject). The two rejects are new to the march-lean oracle.

## Verification

- `test_refinecheck.exe -e`, private `HOME`, `.march/cas/vc` cleared once: 1073 tests, all
  pass, 0 skipped (z3 4.16.0), 484 s. `audit-baseline` included: no baseline moved.
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh`: 453 passed, 0 failed.
- `scripts/refine-oracle.sh`: baseline from a detached `6769313ef` worktree, check on this
  change, both under the script's private `HOME`, the staged `_build/default/stdlib` set
  aside: **identical**, 7786 lines over 549 fixtures. The oracle is blind to this rule (no
  `test/native` or `stdlib` fixture passes a multi-parameter lambda over an element-refined
  container): the "arm off" perturbation reproduces the base's verdicts exactly, so it
  would be identical too. The evidence is the group and the corpus files.
- `stdlib/list.march`'s `--check --refine-report`: byte-identical to the base
  (21 proved, 0 violated, 1 skipped for user code).
- Timing, `--check --refine-report stdlib/list.march`, private `HOME`, VC cache cleared
  before the first of three runs, two rounds each, load average ~10: base medians
  1.146 / 1.185 s, this change 1.112 / 1.123 s. Within the design's 5% budget (noise).

## Left open

- Peeling a curried lambda (`fn a -> fn x -> …`) for an inner parameter's fact, and a
  container domain fact for a parameter typed `List(a)` (design §7), both unfiled beyond the
  design.
- The accumulator invariant: `specs/2026-10-18-fold-accumulator-invariants-design.md`.
- Phases 2-4 of the design (items 1, 3, 4 of the todo).
