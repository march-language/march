# Reflection phase 4: repeated unfolding and fuel — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** stage 2 unfolds a produced reflected call again when its guard is **decided**, up to a
per-function fuel (default 2). Single unfolding is no longer the limit of the logic.

**Spec:** `specs/2026-10-29-refinement-reflection-design.md` §3.8 (repeated unfolding and fuel),
§3.9 (running out), §10 "Phase 4". The decisions are D13 and D14.

**Base:** branch `claude/reflection-phase4-fuel`, cut from `claude/reflection-phase2-lemmas`
(PR #1061). Phase 4's tests use lemmas (`rev_rev_short`). The PR is opened against `main` once
#1061 merges.

## Global constraints

- Stage 1 is unchanged, byte for byte (F9). All new work runs only when `Reflect_state.arm_on` is
  set.
- Depth-0 unfolding is unchanged: every reflected call in the query, all arms, each behind its
  guards (D12). Only calls that an unfolding produces are new.
- "Decided" is computed syntactically, never with an extra z3 query (§3.8). That keeps the number
  of unfoldings linear in the frontier.
- The budget stays at 32 unfoldings per query, counting every depth (§3.9).
  `reflect-budget` takes precedence over `reflect-fuel`.
- `reflect-fuel` is reported when stage 2 did not prove the goal and some produced call was not
  unfolded, because it was over fuel or its guard was undecided.
- New code `invalid_reflect`, registered in `lib/errors/code.ml` with a page, a seeded corpus case
  and regenerated golden outputs.
- The parser change keeps the menhir conflict count unchanged. `tree-sitter-march/grammar.js`
  parses the new syntax (`scripts/check-tree-sitter.sh`).
- The oracle gate is monotone: no proved→skipped or proved→violated move. New proofs are expected
  only at sites whose frontier needed a decided second step. Run `scripts/oracle-base.sh refine ir`;
  the IR oracle must be IDENTICAL.
- Docs: edit `specs/lang/refinement-types.md` and run `scripts/gen-lang-docs.py`; add a CHANGELOG
  bullet and `specs/progress/2026-11-03-reflection-phase4-fuel.md`.

## Rulings made while planning

1. **Decided** means that, after rewriting, exactly one arm's conditions all evaluate to true and
   every earlier arm's to false. Rewriting uses:
   - constructor equalities from the query's top-level assumptions (`x = C(..)`, the stage-2 list
     tester, pattern links);
   - tag facts `IsCtor(k, x)`;
   - the results of earlier decided unfoldings (`f(a) = res`, when `res` is a constructor term);
   - selector-of-constructor simplification (`C_i(C(a0, .., an)) = ai`);
   - ground evaluation of integer and Bool literals, comparisons, `not`, `and`, `or`.

   Anything else is undecided. A decided term adds only its arm's equation, still behind the
   domain guard `pre_f(args)` (C1).
2. **Depth.** Terms in the query are depth 0. A call that the unfolding of a depth-`d` term
   produces is at depth `d+1`. It is unfolded only when `d+1 < fuel(g)` and its guard is decided.
   Unfolding is breadth-first, so a shallow term is never starved by a deep chain.
3. **Fuel source.** `@[reflect(fuel: N)]`, `1 <= N <= 8`. The parser produces the attributes
   `reflect` and `reflect:fuel:N`. The template records `t_fuel`; the default is 2.
4. **`@[reflect]` is an assertion** that the function is reflected (§3.8). On a function that is
   not reflected, it is `invalid_reflect`, naming the first blocker.
   - `fuel: 0` and `fuel: 9` and above are `invalid_reflect`.
   - `@[reflect]` with `@[opaque]` or `@[lemma]` is `reflect_conflict` and `invalid_lemma` (L5)
     respectively.
5. **Same worktree.** Phase 4 runs in this worktree on its own branch. On a #1061 Auto-fix event,
   commit the work in progress, switch to `claude/reflection-phase2-lemmas`, fix and push, then
   switch back.

## Tasks

### Task 1: `@[reflect(fuel: N)]` syntax and `invalid_reflect`

- Parser: `AT LBRACKET LOWER_IDENT LPAREN LOWER_IDENT COLON INT RPAREN RBRACKET`. Only
  `reflect` with key `fuel` is accepted, and anything else is a parse error naming it. It yields
  `("reflect", [])` and `("reflect:fuel:N", [])`. Check the conflict count is unchanged.
- `grammar.js`: add `seq('(', $.identifier, ':', $.integer, ')')` to the bracketed attribute.
- `known_fn_attributes` gains `reflect`.
- `check_module` emits `invalid_reflect` when:
  - the function has a reflection blocker (any rule, as `@[measure]` uses);
  - the fuel is out of range.
- It emits `reflect_conflict` for `@[reflect]` together with `@[opaque]`.
- Tests: `fuel_cap` (fuel 9), `fuel_zero`, `reflect_assert` (`noisy` names `println`),
  `reflect_ok` (no diagnostic on `cat`), `reflect_opaque`, `parser` (it parses, the tree-sitter
  check passes, the conflict count is unchanged).

### Task 2: depth, decided guards and fuel in `Refine_reflect.unfold`

- `unfold` keeps a breadth-first queue of `(f, args, depth)`. Depth 0 behaves as today. A produced
  call goes into the queue at `depth + 1`. When it is dequeued it is unfolded only if
  `depth < fuel(f)` and its guard is decided, and then only that arm is added, behind `pre`. Its
  own produced calls enqueue at the next depth.
- The rewriting state (ruling 1) is built once from the assumptions and grows with each decided
  unfolding. That includes depth-0 terms whose guard happens to be decided, so a later term can
  use their value.
- `RS.fuel_pending` is set when a produced call is left over: over fuel, or undecided.
- Tests:
  - `a6`: `need2(cat([1], [2]))` is proved. Flip phase 1's `no_second_step` test.
  - `rev_rev_short`: proved. Flip phase 2's test.
  - `undecided_stays`: `need(len(cat(xs, ys)) == 2)` with `xs` unknown is still `reflect-fuel`.
  - `fuel_override`: a 4-element literal through `cat` skips at fuel 2 and proves with
    `@[reflect(fuel: 5)]`.
  - `fuel_lower`: `@[reflect(fuel: 1)]` on `cat` brings `a6` back to `reflect-fuel`.
  - `budget_deep`: a decided chain past 32 unfoldings is `reflect-budget`.
  - Soundness: `sound_decided_wrong_arm`. A term whose scrutinee is equated to `Nil` only under a
    branch is not decided outside it. Also, `pre` stays on decided arms: phase 1's
    `sound_domain`, run at depth 1.

### Task 3: docs, oracles, review

- Reference: under "Lemmas", note that phase 4 makes the §4.6 asserts unnecessary. Add a "Fuel"
  paragraph and the `invalid_reflect` page. Regenerate the docs, add the CHANGELOG bullet and
  write the progress note.
- Run the full refinecheck suite, the golden diagnostics, `-q compiler`, the LSP refine group,
  `oracle-base.sh refine ir` (refine monotone, IR identical) and the timing from §6.3.
- Get a fresh soundness review, focused on ruling 1 (when "decided" may be wrong) and the fuel
  bookkeeping.
