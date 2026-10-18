# Relational element refinements: one namespace (element-flow follow-ups, phase 0)

Landed 2026-10-18. Design: `specs/2026-10-18-element-flow-followups-design.md`, §1 and
phase 0 of §8 (rows z1-z5 of §0.5). A soundness fix; nothing new is proved.

## What a user sees

```march
fn need_lt(xs : List({Int | _ < n}), n : Int) : Int do 0 end

fn go(ys : List({Int | _ < 60})) : Int do
  let n = 1000
  need_lt(ys, 10)           -- was PROVED (read as `_ < 1000`); now violated
end
need_lt(ys5, 200)           -- ys5 : List({Int | _ < 5}); was a false VIOLATION; now proved
need_lt([5], 10)            -- was solver-undecided; now proved ([50] is violated)

fn below(n : Int) : List({Int | _ < n}) do
  let n = 100
  [50]                      -- was PROVED against the local n; now a recorded skip
end
```

An element slot that names a parameter is in the namespace of the declaration it came
from. Before this, it was read in whatever scope it landed in, never substituted, never
retired, never checked for capture. `entry_is_closed` kept such an entry from being a
*fact* at a call site, but nothing kept it from being a *demand*, a *stored fact* or a
*lambda's domain fact*, and under `cap verified` each of the shapes below compiled a
broken contract.

## The bugs, before and after

Ledger triples are (proved, violated, skipped) for the user code, from the
`elemflow-namespace` group of `test/test_refinecheck.ml`. "Before" was measured by running
that group, unchanged, against the unfixed library (a detached worktree at `75bca856d`
with only the test file copied in, every assertion made non-fatal so each one reports).

| Row | Shape | Before | After | Fix |
|---|---|---|---|---|
| z1 | `need_lt(ys, 10)`, `ys < 60`, caller `let n = 1000` | (1, 0, 0) **false proof** | (0, 1, 0) | `check_arg_elements` reads the slot through `instantiate_entry ~mode:`Any` at the call's actuals |
| z1′ | same, caller parameter `n` and `if n > 1000` | (1, 0, 0) **false proof** | (0, 1, 0) | same |
| z1″ | `need_lt(ys, 200)`, `ys < 5` | (0, 1, 0) false violation (witness `n = 0`) | (1, 0, 0) | same |
| z1‴ | `need_lt([5], 10)` / `need_lt([50], 10)` | (0, 0, 1) / (0, 0, 1) | (1, 0, 0) / (0, 1, 0) | same |
| extra | `need_lt(ys, n - 1)` with `ys : List({Int \| _ < n})` | (1, 0, 0) **false proof** | (0, 1, 0) | same |
| extra | `need_lt(ys, k)` with `k : {Int \| _ >= 60}`, `ys < 60` | (0, 1, 0) false violation | (1, 0, 0) | same, plus `check_call ~goal_scope_facts` (below) |
| extra | named binder `{x : Int \| x < n}` called with an actual `x` | (0, 1, 0) false violation | (1, 0, 0) | binder renamed to `_` before the substitution |
| z2 | `below(n)` with `let n = 100; [50]` | (1, 0, 0) **false proof** | (0, 0, 1), "under an inner binding that rebinds `n`" | `visit_fn` builds the tail list with `tails_bound`; a tail whose `bound` list holds a name the entry mentions is a recorded skip, never checked in-walk or in the fallback |
| z2 (match) | `Cons(n, _) -> [n - 1]` under `List({Int \| _ < n})` | (1, 0, 0) **false proof** | (0, 0, 1) | same |
| z3 | `xs : _ < n`, `let n = 0`, `need_neg(h)` | (1, 0, 0) **false proof** | (0, 0, 1) | `cont_shadow` retires an entry whose slot predicates mention a rebound name, like `scope_shadow` |
| z4 | `List.map(xs, fn n -> need_neg(n))` | (1, 0, 0) **false proof** | (0, 0, 1) | `lambda_domain_params` declines a fact that mentions the lambda's own parameter |
| z5 | `need_lt(map(ys, fn n -> n - 1), 10)` | (1, 0, 0) **false proof** | (0, 0, 1), parametric-source-unproved | z1's substitution makes the demand `_ < 10` |
| z5′ | `need_lt(map(ys, fn n -> n - 1), n)` (caller `n`) | (1, 0, 0) **false proof** | (0, 0, 1), "shadows a name the demanded refinement mentions" | `demand_flow`'s capture guard on a `Src_cod` lambda |
| field | `{ k: 1, n: 10, xs: [500] }` under `if n > 1000`, field slot `_ < n` | (2, 0, 0) **false proof** | (1, 0, 1), "names another field" | `check_field_elements`: a non-closed slot is a recorded skip (design §1.2's call) |
| codomain | `hof(10, fn y -> [50])` under `if n > 100`, `g : (Int) -> List({Int \| _ < n})` | (1, 0, 0) **false proof** | (0, 0, 1) | `check_pass_site_elements`: a non-closed expected codomain is a recorded skip (design §1.2's call) |
| lambda tail | `sum_pos(map(ys, fn y -> let k = 0 - 5; k))`, caller `k > 0` | (1, 0, 0) **false proof** | (0, 0, 1) | not in the design, see below |
| lambda tail | `hof(fn y -> let k = 0 - 5; [k])` against `List({Int \| _ > 0})` | (1, 0, 0) **false proof** | (0, 0, 1) | same |

Controls that kept their verdicts on both sides: z2's definition side (`[n - 1, n - 2]`
proves, `[n - 1, n]` is violated at `n`, `let m = n - 1; [m]` proves), z3/z4/z5's
controls (the same programs with no rebinding or a fresh name), a guarded
`n <= 0` with `xs : List({Int | _ < n})` proving `need_neg(h)` and the `map` domain
fact, a lambda tail under an inner `let` it does not mention, and the closed record field
and codomain slots (still checked, still violated).

## Code

- `Refine_check.instantiate_entry ~mode ~formals ~args` (design §1.1): `Closed` slots pass
  unchanged (byte-identical to the old path); `Relational ps` needs a positional actual for
  every `ps` and substitutes them simultaneously after renaming a named binder to `_`;
  `Unusable` (a name that is not a parameter) and a missing actual are `Error why`, a
  recorded skip naming the parameter. `` `Stable `` (variables, literals,
  `let_equality_rhs` shapes only) is implemented for phase 4 and unused here.
- `Refine_scope.elem_entry_mentions` / mention-based `cont_shadow`, and two
  simultaneous-binding helpers, `cont_add_params` and `cont_of_fnparams`. A parameter
  list binds at once, so `fn f(xs : List({Int | _ < n}), n : Int)` must keep `xs`'s
  entry when it reaches `n`; folding the mention-based `cont_add_param` would have
  dropped it. The lambda and local-`fn` sites now also shadow the outer env by
  mention (they shadowed by key only, the z3 bug in a lambda).
- `Refine_call.check_call ?goal_scope_facts`. A substituted demand mentions caller names
  (`_ < k`), and `check_call` loaded scope facts only for names in the path and the
  actuals, so `need_lt(ys, k)` with `k : {Int | _ >= 60}` came back a definite
  violation with `k` unconstrained. With the flag, a goal name that is neither the subject
  nor a parameter of the signature carries its scope fact the same way a guard's name
  does. Only the element sites pass it (`check_elements`' literal and subtyping arms,
  `demand_flow`'s `scalar_ok`): a scalar contract's goal is in the callee's namespace,
  where reading such a name as the caller's would widen the same bug class.
- `Refine_check.lambda_tail_rebinds` (see the next section).

## Where this departs from the design

- **The lambda-tail twin of z2 (not in the design).** `demand_flow`'s `lambda_ok` and
  `check_pass_site_elements` check every lambda tail in the env at the LAMBDA, so a tail
  that mentions a name bound on the way down (an inner `let`, a `match` arm, a local
  `fn`) read the caller's binding of that name. This is a false proof with a CLOSED
  demand too, found while fixing z2. The conservative call: such a tail is not checked
  (`` `U `` in `demand_flow`, a recorded skip at the pass site). A tail that does not
  mention the inner binding is checked as before. The scalar codomain pass site
  (`fn y -> let k = 0 - 5; k` against `(Int) -> {Int | _ > 0}`) was already correct, a
  violation.
- **The z5 capture guard rarely fires on z5 itself.** After z1's substitution z5's demand is
  `_ < 10`, with no `n` left to capture, so z5 becomes the ordinary parametric skip. The
  guard is pinned by z5′, where the actual is the caller's `n`.
- **`check_pass_site_elements`' lambda arm needs no capture guard**: a non-closed
  codomain is now a skip before any lambda is looked at, so the entry it checks mentions
  no name.
- **Design §1.2's `check_field_elements` and codomain rows were described as "a skip where
  there was silence".** They were live false proofs under a guard (the `field` and
  `codomain` rows above); unguarded they were solver-undecided skips.
- **`entry_is_closed` decides "non-closed"** for the field and codomain skips. It also
  declines a slot naming a module-level name that is not a parameter. That is
  conservative and costs nothing the corpus has.

## Tests

- `test/test_refinecheck.ml`, group `elemflow-namespace` (12 cases, ledger triples, skip
  reasons and detail text, never exit codes). Every case listed above as "Before" was RED
  on the unfixed library: 24 of the group's 38 assertions failed there, and all 38 pass
  now.
- Conformance pair: `specs/lang/types/accept/t325_refine_relational_element_namespace`
  (all PROVED under `cap verified`; it was rejected before, by the false violations of
  `need_lt(ys, 200)` and `need_lt(ys, k)` and the undecided `need_lt([5], 10)`) and one
  reject per false proof, `reject/t326`-`t330` (z1-z5), each of which type-checked before.
  The corpus is 450/450 (191 accept, 259 reject). The reject fixtures are new to the
  march-lean oracle (`.github/workflows/march-lean-dispatch.yml`).

## Verification

- `test_refinecheck.exe -e` under a private `HOME` with `.march/cas/vc` cleared once:
  1041 tests, all pass, 0 skipped (z3 4.16.0).
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `specs/lang/types/check_types.sh`: 450 passed, 0 failed.
- `scripts/refine-oracle.sh` baseline on `75bca856d`, check on this change, both under the
  script's private `HOME`: **identical**, 7786 lines over 549 fixtures. The oracle is
  **blind** to this change, not evidence for it: a deliberate perturbation (every
  `Closed` slot in `instantiate_entry` made an `Error`, so every element-parameter demand
  became a skip) was also identical, because no `test/native` or `stdlib` fixture passes an
  argument to an element-refined parameter. The evidence is the test group and the corpus
  pair above.
- Timing, `--check --refine-report` of `stdlib/list.march` against each build's own
  staged stdlib, private `HOME`, VC cache cleared before the first of three runs, two
  rounds each, load average ~8-11: base medians 1.14 / 1.15 s, this change 1.13 / 1.12 s.
  Within noise, as the design's 2% budget expects (no new solver work).

## Left open

- A record whose only refinements are element slots is never obliged:
  `specs/todos/2026-10-18-record-element-slot-refinements-unchecked.md`.
- Phases 1-4 of the design (multi-parameter domain facts, the scalar demand entry point,
  local `fn` container returns, relational element returns as call-site facts) are
  untouched; `specs/todos/2026-09-18-refine-element-flow-followups.md` still lists items
  1-4.
