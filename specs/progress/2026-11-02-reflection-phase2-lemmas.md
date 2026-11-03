# Refinement reflection, phase 2: lemmas (2026-11-02)

Design: `specs/2026-10-29-refinement-reflection-design.md` §4, §9.1 rows marked (2), §10 "Phase 2".
Plan: `specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md`.

## What landed

- **`@[lemma]`** is a known function attribute. The generic `fn_attr` rule parses it, so the parser
  and the tree-sitter grammar don't change. A lemma that breaks L1-L5 is the error `invalid_lemma`:
  - L1, L2, L3 and L5 are checked in `check_module`. L2 and L3 use the same per-unit events as
    reflectability (`Refine_reflect.lemma_blocked`).
  - L4 is decided after the postcondition gate. A recursive lemma that the gate did not admit, and
    that `ih_prepare` did not make eligible for the induction hypothesis, is invalid.
- **Lemma theorems are checked by the walk.** A lemma's `{Unit | P}` post enters the existing gate
  as a pending contract, through a Unit arm of `return_refine_sorted` for lemmas only.
  - The gate's verdict for a lemma is `lemma_scratch_verdict`: a silent walk of its body
    (`Refine_post.lemma_verdict`).
  - Each tail is a `Lemma_goal` obligation on `P`, phrased like a termination metric as a call to a
    synthetic signature. It is checked under the walk's facts: the arm taken, earlier lemma calls,
    and proved asserts.
  - Ordering between lemmas, and the atomic induction rounds, come from the gate unchanged.
  - Ordinary `{Unit | P}` functions keep today's skip.
- **The static `assert` (I5).** Inside a lemma, `assert e` is an `Assertion` obligation (a new
  `Obligation.kind`), and `e` joins the path only if it was proved. Outside lemmas nothing
  changes.
- **Lemma-call facts.** A statement-position call (`l(..)` or `let _ = l(..)`) adds
  `P[params := args]` to the rest of its block. It does so from the induction hypothesis at an
  eligible span, or from the admitted contract when every precondition at the call proved;
  otherwise it draws `lemma_unproved_call`.
  - The callee is identified by the termination graph's resolved identity (`lemma_call_sites`),
    and the checker's own resolution must reach the same lemma: the theorem expression is compared
    physically.
  - A lemma call inside a reflected body is `()` in the logic (phase 1's `lemma_in_body` row).
- **Erasure.** `lib/desugar/lemma_erase.ml`, after typechecking, on every path that runs code:
  - `--compile`, `--emit-llvm`, the interpreter and `--jit` (`bin/main.ml`, after
    `Refine.shutdown`);
  - `march test` and doctests;
  - `march dap`, which runs no typecheck, so erasure follows desugaring;
  - both REPLs, which blank lemma bodies;
  - the browser compiler (`Js_pipeline`) and the browser REPL.

  A call is erased only when nothing but lemma declarations binds its name anywhere in the
  program, stdlib included, and it is not a builtin (plan ruling 2). Lemma bodies are always
  blanked. A lemma declaration is dropped once nothing names it.
- **`lemma_argument_impure`.** Every argument of a lemma call must be a reflectable term.
- **LSP.** `--reflect-deps` prints `lemma-def` and `lemma-dep` rows. Their hash covers the lemma's
  text and whether it was admitted, so a dependency lemma that changes or stops proving re-checks
  its callers. `Refine_diag.lemma_key` and `lemma_admitted` read them. Hover on a lemma call shows
  its theorem and status.
- **Small fixes.** Lemmas draw no `unused_binding` for parameters (their theorem names them) and
  no `non_tail_recursion` (they never run).

## Encoder fixes the proofs needed (all stage-2-only or lemma-only, so stage 1 is unchanged)

1. **A list tester said only `len$xs = 0`.** `path_resolve_tester` turned `is_Nil(xs)` into a
   length fact, so a stage-2 unfolding of `cat$r(xs, ys)`, which is decided by `xs = Nil`, never
   met it. This was already wrong on main: a plain precondition in a `Nil ->` arm skipped.
   - Stage 2 now also states the datatype tester on the same constant.
2. **Pattern links.** Inside a lemma's `Cons(_, t) ->` arm, the path carries `$link:Cons:1(t, xs)`.
   - Stage 1 drops it as untranslatable.
   - Stage 2 states `t = Cons_1(xs)` (`Reflect_state.links`, `resolve_sorts`).
   - Rebinding a name retires the fact through the path's usual shadowing discipline.
3. **A parametric fact's sort.** A proved `assert rev(Nil) == Nil` has no element in it, so its
   instance resolved to `Elem` while the goal used `Int`.
   - In stage 2, an unconstrained type parameter now takes the query's single concrete element
     sort, when there is exactly one.
   - This is sound: a fact over an uninterpreted element sort holds at any sort.
4. **Assert edges.** The termination graph counted a lemma `assert`'s `==` as a call edge to the
   stdlib `impl Eq` for lists, which is uncertified. That made every lemma with such an assert
   "may diverge", so it got no induction hypothesis. Calls inside a lemma's `assert` now keep
   their sites (the predicate translator resolves calls through them) but add no edges.
5. **Typed assert formals.** An assert's goal formals now take their types from the type map at
   their occurrence. An element `h` was declared `Int` and split the instances.

## Rulings (plan, and made during execution)

- Plan rulings 1-6 stand.
- **`ih_pre_unproved` rewritten.** The spec's version (`dbl(n) >= 0` under `n >= 0`) proves without
  any induction. The test now needs the hypothesis (`cat(xs, Nil) == xs`) and makes the recursive
  call's precondition `len(_) >= 2` fail. The control, `len(_) >= 0`, proves.
- **`sound_domain`** uses a non-recursive guarded `pos`, as phase 1's test does: metric-certified
  functions are not unfolded.
- **`known_overflow`.** Since 0.7.0, Int `+` panics on overflow rather than wrapping. The gap
  stands: the lemma `inc(n) > n` proves, and the test is labelled as a known gap.
- **A refuted assert is `refinement_violated`** (an error), like a refuted lemma theorem. The spec
  says only that it is not assumed.
- **`stdlib_lemma_manifest`** belongs to phase 3, as the spec's table marks it.

## Tests (group `reflect-lemma`, `test/test_refine_lemma.ml`; 32 cases)

They cover:
- L1-L5;
- closed posts and static asserts: `assert_static`, `sound_assert_false`, `sound_domain`,
  `known_overflow`, `assert_runtime` and `unit_post_ordinary`;
- calls: `pre_lemma`, the lemma fact, `lemma_scope`, `cat_nil`, the full §4.6 chain
  (`cat_assoc`, `rev_cat`, `rev_rev` with its five asserts), `rev_rev_short` and
  `sound_eq_float`;
- L4 and the IH: `sound_lemma_ih` and `ih_pre_unproved`;
- erasure: `erase_runtime` (interpreter, compiled and JIT), `sound_erase_ir` (byte-identical
  `--emit-llvm` with and without the lemmas), `sound_erase_paths` (a lemma body whose assert would
  abort never runs, with `MARCH_REFLECT=0` and z3 off PATH), `erase_args` and `lemma_shadow`.

LSP (`lsp/test/test_lsp_refine.ml`): `lsp_lemma_invalidate` and `lsp_lemma_hover`.

Perturbations recorded, each one RED:
- disabling the L-checks fails 8 rule tests;
- assuming every lemma assert fails `assert_static` and `sound_assert_false`;
- dropping the precondition requirement on a lemma fact fails `pre_lemma`;
- turning erasure off in the compile path fails `sound_erase_ir` and `sound_erase_paths`;
- an "admitted" check that passed vacuously, because a lemma was never walked, was caught and
  tightened: admitted now requires proved theorem rows.

## Verification

| Check | Result |
|---|---|
| refinecheck suite (z3, private HOME) | 2157 tests, 0 failures |
| golden diagnostics | 306 cases, only the 4 new cases added |
| compiler `-q` | 1364 tests |
| eval `-q` | 289 tests |
| JIT | 43 tests |
| LSP refine-diagnostics | 11 tests |
| doc-lint | passes |
| ir-oracle vs merge-base fd3d2c23e | IDENTICAL (515 programs) |
| refine-oracle vs merge-base fd3d2c23e | IDENTICAL (7968 lines over 569 fixtures; no corpus fixture has a lemma) |

Not run: `scripts/browser-repl-smoke.js` with a lemma case (todo
`2026-11-02-browser-repl-smoke-lemma-case`).

## Follow-ups filed

- `specs/todos/2026-11-02-lemma-facts-from-non-statement-calls.md`
- `specs/todos/2026-11-02-lemma-uses-note-in-hover.md`
- `specs/todos/2026-11-02-browser-repl-smoke-lemma-case.md`
- `specs/todos/2026-11-02-lemma-uses-beyond-refinement.md` (filed with the plan)
