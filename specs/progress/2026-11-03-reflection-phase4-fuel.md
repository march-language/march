# Refinement reflection, phase 4: repeated unfolding and fuel (2026-11-03)

Design: `specs/2026-10-29-refinement-reflection-design.md` §3.8, §3.9, §10 "Phase 4"
(decisions D13, D14). Plan: `specs/plans/2026-11-03-reflection-phase4-fuel-plan.md`.
Built on phase 2 (lemmas, PR #1061).

## What landed

- **Repeated unfolding (`Refine_reflect.unfold`).** Depth 0 is unchanged: every reflected call in
  the query is unfolded once, with all its arms, as phase 1 has it.
  - A call that an unfolding produces is at the next depth. It is unfolded breadth-first, and only
    while its depth is below its function's fuel and its guard is **decided**; then only the
    decided arm is added.
  - Each level is retried until a round makes no progress, since what one step learns can decide
    another.
  - Every unfolding still goes behind its own assumption literal (the `uses:` core). The 32-unfolding
    budget counts every depth.
- **Decided** is computed without any extra solver query, by rewriting with:
  - constructor equalities and tester facts among the query's top-level assumptions;
  - the values of earlier decided calls;
  - selector-of-constructor simplification;
  - ground integer and Bool evaluation.

  **The decision is not trusted for soundness.** A decided call's equation keeps its arm conditions
  and its domain guard inside the asserted implication, exactly like a depth-0 equation. A wrong
  decision can cost a proof but cannot make one.
- **Fuel.** The default fuel is 2. `@[reflect(fuel: N)]` sets it per function (`1 <= N <= 8`),
  stored as `t_fuel` on the template. `@[reflect]` is an assertion that the function is reflected:
  - `invalid_reflect` when the function is not reflected (naming the blocker), when the fuel is
    out of range, or for an unknown argument;
  - `reflect_conflict` together with `@[opaque]`;
  - `invalid_lemma` (L5) on a lemma.
- **Syntax.** The parser has one new production, `@[name(key: INT)]`. It is accepted only as
  `@[reflect(fuel: N)]`, and anything else is a parse error naming it. The menhir conflict count is
  unchanged (7 states). `tree-sitter-march/grammar.js` has the matching alternative, and the
  regenerated `src/` is committed.

## Tests (group `reflect-fuel`, `test/test_refine_fuel.ml`; 11 cases)

- `undecided_stays`, `fuel_override` (skips at fuel 2, proves at 5), `fuel_lower` (fuel 1 brings
  `a6` back to `reflect-fuel`), `budget_deep` (a true 40-element equation needs more than 32
  unfoldings: `reflect-budget`).
- `sound_domain_depth1`: a depth-1 call outside its callee's domain still says nothing.
- `fuel_cap`, `fuel_zero`, `reflect_assert` (names `println`), `reflect_ok`, `reflect_opaque`,
  and the labelled-payload parse error.

Flipped on purpose:
- Phase 1's `no_second_step` is now `a6` and is **proved**.
- Phase 1's `two_arg` is now **violated**: `count_ge([5], 3)` is 1, so `need_small`'s `_ < 1`
  really fails. Phase 1 could not take the second step.
- Phase 2's `rev_rev_short` is now **admitted** without the five asserts.

Perturbations, each RED:
- `MARCH_REFLECT_PERTURB=no-guard` makes `sound_domain_depth1`'s obligation prove, falsely.
- A default fuel of 1 fails `a6`, `two_arg` and `rev_rev_short`.

## Verification

| Check | Result |
|---|---|
| `reflect-fuel` / `reflect-lemma` / `reflect-unfold` | 11 / 35 / 49 pass |
| golden diagnostics | 307 tests, only the new `invalid_reflect_1` added |
| doc-lint | passes |
| tree-sitter check | ok (1720/1724, the 4 known failures); `@[reflect(fuel: 5)]` parses as an attribute |
| refinecheck suite | 2171 tests; the 5 failures were all phase-1-era expectations of `reflect-fuel` that phase 4 now proves or refutes (below), updated, and their groups rerun green (no code changed in between) |
| compiler `-q` | 1405 tests |
| LSP refine-diagnostics | 11 tests |
| ir-oracle vs `75a88ea2e` (phase 2 head) | IDENTICAL (515 programs) |
| refine-oracle vs `75a88ea2e` | IDENTICAL (7968 lines over 569 fixtures): no corpus fixture moved |

## Expectations that moved with phase 4 (each checked against the program's real values)

- `test/refine/reflect` probes (snapshot, regenerated):
  - `b2` `need_small(count_ge([5], 3))`, `_ <= 1`: skip → **proved** (the count is 1).
  - `c2` `need([1, -2])`, `all_pos`: skip → **violated** (−2 is not positive).
  - `c2b` `need([1])`, `even_len`: skip → **violated** (length 1).
  - `a6_assert_unannot` (`let a = cat([1], [2])`, then `need2(a)`): still a skip; the reason is now
    `unconstrained-subject` instead of `reflect-fuel`. The decided step is taken, but `len(a)` of
    a `let`-bound datatype value is a separate length constant that is not tied to the datatype
    value. This is an older encoding gap, which `reflect-fuel` used to hide. Never a proof
    regression.
- `5a` (hint relabel) used `a6` as its `reflect-fuel` example; it now uses an unknown list.
- `sound_cache`: `need_small` under `small(n)` is now **proved** (one decided step into `g`).
- `infer C1` (two copies): reflection now proves `need_pos(b(3))` outright, leaving nothing to
  infer. `a` is made `@[opaque]` so the tests still exercise the demand chain.

## Soundness review, round 1 (fresh reviewer, 2026-11-03)

The reviewer found **no false proof**. It confirmed the safety claim in the code: the arm recovered
by `List.find` is exactly the decided one, and the arm's conditions and the domain guard stay in
every implication. `resolve_sorts` only ever drops a whole `Implies(lit, ..)` assumption, never a
guard. `st.vals` is never asserted. `norm` is bounded, and `rounds`/`level` terminate.

It did find a **false `violated`**. This was already on main and the phase 2 base, and the fuel
limit is one way to reach it. It is fixed here, with two tests that go RED without the fix:

- **Stage 2.** The element and callback definite-failure shortcut (`Element_domain`,
  `Callback_domain`, `Callback_codomain` in `refine_call.ml`) took the first satisfying model as a
  real failure. In stage 2 that model can give any value to a reflected call left unfolded (past
  its fuel, undecided, or over budget).
  - Example: `List({v : Int | cnt(Cons(v, Cons(1, Cons(2, Nil)))) == 3})` was reported violated at
    `elem = 17702`.
  - Fix: the shortcut is off in stage 2, and such a goal takes the ordinary `¬G` discharge.
  - Test: `sound_definite_stage2`.
- **Stage 1.** A refined local whose own fact does not translate was silently left unconstrained
  (`reflect_scalar`), and the same shortcut then reported a model of it.
  - Example: `List({Int | _ > 5 && _ == one(0) + 4})` with `one` `@[opaque]` was reported violated
    at `elem = 0`.
  - Fix: `Refine_resolve.scope_fact_dropped` records the drop, and the shortcut does not apply.
  - Test: `sound_dropped_fact`.

Suspicions recorded, not changed:
- Element refinements are not part of the unfolding guard `pre`. This is harmless while only
  structurally certified functions are unfolded.
- A NaN literal in a template would make the arm recovery raise. No source syntax produces one.
