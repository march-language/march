# Refinement reflection, phase 5: function values (2026-11-03)

Design: `specs/2026-10-29-refinement-reflection-design.md` §10 "Phase 5" (decision D10).
Plan: `specs/plans/2026-11-03-reflection-phase5-fnvalues-plan.md`. Built on `origin/main`
(`0a2077574`), independent of phase 3.

## What landed

- **Specialisation per call site (`Refine_reflect`).** A function `g` that takes functions
  has no definition of its own, but each call `g(xs, fn x -> e)` does: a logic symbol `g$k`
  whose template is `g`'s body with the lambda's body put in place of each call of the
  function parameter. `List.filter` and `List.map` are such functions, so a caller that
  filters or maps with a lambda is now reflected.
  - `g` is **specialised** when its only blockers are R7's about its own function
    parameters, every use of such a parameter `p` is a call `p(..)` or `p` passed on in the
    same position of `g`'s own recursive call, no binder in the body is named like `p`,
    `g` makes no lambda, `p`'s domain carries no refinement (the abstract-refinement
    definer's `{x : a | true}` is not one), and `g`'s SCC is `g` alone.
  - A call is **specialised** when each function argument is a lambda literal (right
    arity, unrefined parameters, no nested lambda or local `fn`, literal divisors only) or
    a name the termination graph resolved at that site to a reflected top-level function.
    The lambda's own events and dependencies are its caller's; at a caller that is not
    reflected, those inside the lambda's span are checked on their own.
  - **Captures** (names the lambda reads that it does not bind and the graph did not
    resolve to a function) are extra parameters of `g$k`, after `g`'s non-function ones.
  - One **symbol per call site**,
    `|r:<origin>:<g>#<file>:<l>:<c>$spec:<caller>#<file>:<l>:<c>|`, with the §3.1
    duplicate check. Sorts come from the call's own types.
  - The **template** binds each function parameter to a sentinel constant that only a call
    of it, or its own position in `g`'s self-call, may meet; anything else declines. The
    lambda's body is translated in its own scope (its parameters and captures, never `g`'s
    names). Guard: `g`'s refinements on its non-function parameters. Fuel: `g`'s.
- **Where it is used.** In a reflected caller's template, and at program call sites (the
  `let` call-result fact, a subject, a path condition) through `Reflect_state.call_sym`
  plus the new `Reflect_state.site_args`: the expressions the symbol is applied to. Each of
  the three stage-2 call arms applies `args_at` before translating (one line each in
  `refine_scope.ml`, `refine_resolve.ml` and `refine_call.ml`'s `reflect_dt`).
- **Report, attribute, cache.** `--reflect-report` prints `g` as
  `specialised  <n> call sites`. `@[reflect]`/`@[reflect(fuel: N)]` on `g` is accepted.
  A predicate cannot name `g` (it is `encoder_blocked`, with the reason "takes a
  function, so only its calls with a lambda or a function's name are reflected"), and a
  lemma argument calling it is still refused. Each `g$k` has a D17 hash over `g`'s source,
  the lambda's text (or the named function's own hash) and the template; its origin is
  `g`, and `g`'s name gets a logic hash of its own body, so a hot patch of `g` is refused
  when a proof used one of its specialisations.
- **The parity net per specialisation (`Reflect_parity.check_spec`).** The program side
  evaluates `g(args, <the lambda>)` in the interpreter with the captures bound to the
  generated inputs. Rows are named `g[<file>:<line>:<col>]`.

## Soundness table (group `reflect-spec`, `test/test_refine_spec.ml`)

Each row's RED control is a `MARCH_REFLECT_PERTURB` switch; with it the guarded false claim
proves (or the rule's effect shows), without it the row is green.

| Row | Test | RED control |
|---|---|---|
| captures | `spec_capture`: `above([5], 7) == [5]` not proved; `above([5], 3) == [5]` and `above([5], 7) == []` proved | `spec-capture-zero` proves it |
| function-value identity | `spec_identity`: `pos([1]) == neg([1])` not proved | `spec-key-by-callee` (one symbol per `g`) proves it |
| name resolution of a function argument (the "partial application" row: March has none, so the nearest danger is a value whose definition the site does not fix) | `spec_by_name`: a parameter `is_pos` shadowing the top-level `is_pos` is not specialised; `spec_value_args`: a closure from a call, a `let`-bound lambda and a parameter are not | `spec-by-spelling` proves it |
| recursion through the value | `spec_recursion`: `bad(n) = hd0(List.map([n], fn x -> bad(x) + 1))` is R2-blocked; `need(5)` under `bad(0) == bad(0) + 1` not proved | `spec-lambda-own-unit` proves it |
| a function parameter in the wrong place | `spec_swap`: `alt(t, g, f)` is not specialised | `spec-any-position` proves `w([1, 1]) == [2, 2]` |
| an impure lambda at a non-reflected caller | `spec_effect`: `keep` specialised at 0 call sites | `spec-skip-lambda-check`: 1 call site |
| parity per specialisation | `spec_parity`: every specialisation agrees | `spec-swap-arms`: MISMATCH on `keep[..]`, parity RED |

`spec_effect` is defence in depth: the template translator already declines a lambda body
that calls an unreflected function, so no proof could rest on such a call; the per-lambda
check makes the refusal explicit and keeps a definition from ever being registered.

Behaviour tests with no perturbation: `spec_filter`, `spec_stdlib` (`List.filter`,
`List.map`), `spec_named`, `spec_shape` (self-application, a refined domain and a function
passed on are not specialised; `f(f(x))` is), `spec_reflect_attr`, `spec_predicate`.

## Flipped on purpose

- Phase 1's `sound_fnvalue`: `apply(f, x) = f(x)` is now **specialised** and
  `twice(x) = List.map([x], fn y -> y + 1)` is now **reflected**. The test keeps a
  function that is still blocked by R7 for each reason (a function passed on, one applied
  to itself).

## Other expectations that moved (each checked against the program's real values)

- **A skip's reason.** A call of a user-written fold with a lambda now reaches stage 2,
  where the rest of an unknown list is always left unfolded, so the stage-2 override
  would relabel every skip `reflect-fuel`. `Reflect_stage` now keeps a stage-1 reason that
  names which part of a callback failed (`accumulator-base-unproved`,
  `accumulator-step-unproved`, `parametric-source-unproved`, the abstract-refinement
  ones); those diagnoses say more than "more unfolding". Fold test f5's
  `unreflectable-subject` became `reflect-fuel`: the subject now translates.
- **Two skips became correct violations** (fold impostor `k1`, which returns `-5`, and
  control `k9(0, fn a -> a + 1, fn _w -> 0 - 5)`, which is `-4`; both fed to `need_nn`).
  Their tests asserted "the fold hypothesis gives nothing", which still holds.
- `report_fnvalue` (phase 0): `apply` is now `specialised`.

## Soundness review, round 1 (fresh reviewer, 2026-11-03)

No false proof came from phase 5's own code: captures, named-argument resolution, the
template, the domain guard and the symbols all held, across about 30 attack programs
(listed in the reviewer's report: shadowing between lambda parameters and captures, a
captured name rebound after the call by `let`, an arm, `let?`, a local `fn` or a lambda
parameter, nested modules, swapped positions, recursion through a named argument, two
functions of one short name, effects, `% 0`).

It found **one false proof that phase 5 opened a new route to, with a root cause already
on main**, fixed here:

- `let k = 7` then `let k = cnt(Cons(5, Nil), fn x -> x > k)` then `need1(k)` was
  **proved** (at run time `k` is 0). The `let` call-result fact is recorded as
  `(k, rhs)` and read at the obligation, where `k` already names the new binding, so the
  solver saw `k == cnt$k(k)`. The plain-call form (`let k = gt5(k)`) was proved the same way
  on main; phase 5 made the lambda form reach stage 2 too.
- Fix (`refine_check.ml`, the laundering channel): a single-name `let` whose right-hand
  side mentions the name it binds records no entry, as `push_tuple_projs` already did.
  `expr_mentions` looks inside lambda bodies, so one rule covers both forms. (A
  `let`-bound lambda that names itself already declines, with its own message: test A11.)
- Test `spec_let_rebind` (both forms not proved); RED control
  `MARCH_REFLECT_PERTURB=let-self-ref` proves the lambda form.

## Verification

## Not done (follow-ups)

- A `let`-bound lambda (`let keep = fn ..`, then `List.filter(xs, keep)`): the checker
  already reads such a lambda for abstract refinements, with its own shadowing rules.
- A function parameter passed on to another function that takes functions
  (`any(xs, p) = len(filter(xs, p)) > 0`), and mutually recursive higher-order functions.
- A lambda whose body is a `match` with several arms in value position (the translator
  declines such a body, as it does in any value position).

| Check | Result |
|---|---|
| `reflect-spec` | 15 cases pass; each RED control proves (or shows) what its row forbids |
| refinecheck suite (z3 4.16) | 2202 tests; the only failure after the review fix was A11's message (a self-naming `let`-lambda), fixed by keeping the guard to calls; group rerun green |
| compiler `-q` | 1405 tests pass |
| golden diagnostics (`run_errors`) | 334 tests pass |
| ir-oracle vs `0a2077574` | IDENTICAL (515 programs) |
| refine-oracle monotone vs `0a2077574` | GREEN over 139456 sites (569 fixtures): 0 proved lost, 0 new violations; 2 new proofs, both `List.head(List.map([10, 20, 30], dbl))`'s `len(_) > 0` in `test/native/closure_scalar_abi.march` (true) |
