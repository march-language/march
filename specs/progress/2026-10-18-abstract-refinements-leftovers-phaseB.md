# Abstract refinements, the leftovers: phase B (negation, generalized slots, concrete bases)

**Date:** 2026-10-18
**Design:** `specs/2026-10-18-abstract-refinements-leftovers-design.md` §3, §6.2, §9.2
**Base:** `65fee4cc1` (branch `claude/refinement-todos-73b0dc`, phase A merged)

## What a user sees

| Program (design row) | Before | After |
|---|---|---|
| `rej(xs, pred : a -> Bool[p]) : List({a \| !p(_)})`, correct body (P3) | hard `abstract_refinement_misuse` (rule 5); the call `sum_nonpos(rej(ys, fn y -> y > 0))` `parametric-source-unproved` | no error; body and call **proved** |
| the same, branches swapped (P3c) | violation **and** the rule-5 error | violation only; the call is `abstract-refinement-uninstantiated` |
| `{a \| not(p(_))}` (Z2) | rule-5 error | as P3 |
| `pfn filt_go(lst, pred : a -> Bool[p], acc : List(a[p]))` accumulator, delegating caller (D2) | 3 × uninstantiated at the `acc` slot, caller uninstantiated | all **proved** |
| `filt_go` pushing on the failing branch (D2c) | the same skips; caller uninstantiated on this base, **proved** at `ba8db5805` (the design's measurement): the bug behind the skips | **violation** at `Cons(h, acc)` |
| `ifilter(xs : List(Int), f : Int -> Bool[p]) : List(Int[p])` (R1) | call `unreflectable-subject` | **proved**; `fn y -> y >= 0` too-weak |
| `myfilter(xs, pred) = filt(xs, pred)` delegation (D1) | uninstantiated (a phase-A regression, see below) | **proved** again |
| callee slot `List({Int \| p(_) == false})`, caller declaring its own `p` with the same slot | **proved** (the callee's `p` read as the caller's): a false proof | `abstract-refinement-uninstantiated` |

A too-weak skip through a non-exact slot names the slot and its reading:
`` `fn y -> y > 5`, in the element slot `!p(_)` (read as `!(y > 5)`), does not imply `_ <= 0` ``.

## Implementation

- `Refine_abstract.nested_apps`: an application headed `not` is exempt from rule 5 and
  its argument is still walked (`not(p(q(_)))` and `len(q(_))` still nest; `!p(y + 1)`
  is rule 2). New `slot_mentions_only_applied` (does a slot apply `p` only as
  `p(binder)` under `&&`/`||`/`not`) and `subst_abstract` (`inst(S, p ↦ (y, q))`,
  substitution passed in since the module sits below `Refine_scope`).
- `Refine_check.abstract_slot_of_ty ~abs` now returns an `abstract_slot` record
  (container, binder, `S`, the one abstract `S` applies, base `` `Tyvar `` or
  `` `Concrete sort ``) or `Error why`. `instantiate_slot` renames the slot binder to
  the instantiation's parameter (the slot must be closed over its binder once `p` is
  set aside) and substitutes. `abstract_return_slot` reads it under the function's own
  abstracts.
- `abstract_flow`: the body is `inst(S, …)`; §3.4's incoming fact is conjoined
  outside it; a concrete base skips the parametric gate and §3.4 and uses the declared
  base's sort for the `$elem` and for the inliner's discharge.
- `abstract_param_entry`: the widened slot and `inst`; a concrete base supplies its
  own sort. A slot that applies a callee abstract in a shape not read is
  `Some (Error …)` (a recorded uninstantiated skip), never a fall-through to
  `elem_refinement`, where a caller declaring a same-named `p` would read it as its
  own (§3.4's ordering constraint; this is the `p(_) == false` false proof above). A
  by-name reading over `$cb_arg` is renamed to `_` so a diagnostic reads `p(_)`.
- `elem_marker_of_arg ?erased_for` (§3.3): the erased sort (marker `None`, Int) when
  `current_abstracts <> []`, the type map's element type is an unbound type variable,
  and the instantiated predicate applies a current abstract.
- `named_predicate_n`'s C3 vocabulary check (phase A) now also admits an application
  of a current abstract (`p($cb_arg)`). Phase A had made it reject one, which silently
  turned the design's D1 delegation from proved into uninstantiated (no test pinned
  D1); phase B's D2 needs it, and a new test now pins it.
- `Refine_scope.pred_str` prints `not` over an infix operator as `!(…)` (it printed
  `!y > 0`, a different predicate). No existing oracle line contained the shape.

`refine_audit.ml` needed no change: it asks `elem_refinement` under the function's
abstracts, which admits any slot applying one; the new audit test asserts a `!p(_)`
return slot is `Enforced`.

## Conservative calls (beyond, or not settled by, the design)

- **One abstract refinement per slot.** `{a | p(_) && q(_)}` at a call is
  uninstantiated. The design's `inst` is per name; one is enough for every row.
- **The slot must be closed over its binder** (apart from `p`). A slot mentioning a
  callee parameter (`{a | p(_) && _ < n}`) is uninstantiated rather than moved into
  the caller's namespace.
- **A slot shape not read** (`p(_) == false`, `p` under any other operator) is a
  recorded skip at a parameter. At a RETURN it still falls through to the phase-2
  `demand_flow` rule as before, which never reads `p`, so that is sound and unchanged.
- **The erased sort is not used to discharge an inlined helper's preconditions** at a
  parameter slot: it is conditional on the reading, which the discharge precedes. A
  lambda calling a helper with refined parameters inside a declaring definition, at a
  type-variable slot, declines.
- **B7 is a violation, not a skip**: with the callee's `p` instantiated to `y > 0`,
  the caller's `List({Int | !p(_)})` (its own uninterpreted `p`) can hold `1`. The
  design allows either.
- **B11** (a String base) is tested through delegation (`filt(ne(xs), f)`, the slot
  `{String | p(_) && len(_) > 0}` proved from §3.4's incoming `len(_) > 0`). A
  natural-style body over strings does not prove: inside the definition, `f(h)` for a
  `Str`-sorted `h` does not carry `f$ret == $abs_p(h)` (`Refine_call.foreign_var`
  drops string names). Pre-existing, independent of this phase; filed as
  `specs/todos/2026-10-18-abstract-refinement-string-callback-reflection.md`.
- **Not filed, noted:** a definition-side body `if f(h) || h == 0 do Cons(h, …)`
  does not prove a `{Int | p(_) || _ == 0}` slot (a callback call inside an `||`
  condition is not reflected as a branch fact); the nested-`if` spelling does. A
  precision gap of the body walk, not a soundness one; the test uses the nested form.

## Tests (`test/test_refinecheck.ml`, group `abstract-leftovers-b`, 17 cases)

RED on `65fee4cc1` with this test file, GREEN after: B1, B2, B3 (rule-5 error on the
base), B5 and B6 (D2/D2c: skipped slots; B6 no error at all), D1 (delegation
uninstantiated), B7 (no misuse error expected; the base's demand was PROVED through
the caller's `p`), B8 (R1 `unreflectable-subject`), B9 (`parametric-source-unproved`),
B11 (sfilt's return uninstantiated), the `||` slot, the negated too-weak control and
its message, and the `p(_) == false` slot (the base PROVED it).
Guards, green on both: B4 (`not(p(q(_)))` and `len(q(_)) && p(_)` still rule 5,
`!p(y + 1)` rule 2), B10 (the erased sort outside a declaring definition, and inside
one for a reading that does not apply its own `p`), and the audit case.
Every case asserts the whole module's ledger triple plus the moved callee's verdicts.

**Perturbation** (each a one-line change, the phase-A/2/3 groups re-run each time and
stayed green):
1. drop the `not` arm of `nested_apps`: exactly B1, B2, B3, B7 redden;
2. admit only an exact `p(_)` slot: exactly B1, B2, B3, B7, B9, B11, the `||` slot,
   the negated control and its message;
3. no concrete bases: exactly B8, B11, the `||` slot;
4. no erased sort: exactly B5 and B6, and B6's ledger is then the design's false-proof
   shape (`sum_pos` and `return of filt2` proved, the wrong push skipped, no error);
5. no current abstract in `named_predicate_n`'s vocabulary: exactly B5, D1, B6, B11;
6. an unread slot falls through instead of `Error`: exactly the `p(_) == false` case.

**Conformance corpus.** `accept/t350_refine_abstract_negation_concrete_base` (P3, R1
and D2 with `List.reverse`, under `cap verified`; rejected on the base) and
`reject/t351_refine_abstract_negation_wrong_body` (P3c, pinned on the violation text).
`check_types.sh`: 454 passed, 0 failed.

## Verification

- `dune build --root . bin/main.exe test/test_refinecheck.exe test/run_compiler.exe`: ok.
- `./_build/default/test/test_refinecheck.exe -e`: 1109 tests, all passed, 0 `[SKIP]`.
- `scripts/run-tests.sh -q compiler`: 1348 tests, all passed.
- Refine oracle: baseline from a detached `65fee4cc1` worktree at the same depth
  (`.claude/worktrees/phb-base-65fee`), check from this worktree: **REFINEMENT
  DIAGNOSTICS IDENTICAL** (7786 lines over 549 fixtures), as §8 predicts (no stdlib
  signature changed; no corpus program uses a `!p` slot, a concrete-base slot, or a
  delegating definition).
- `stdlib/list.march` CI ratchet: 37 skipped (user + stdlib) on base and branch; ceiling 37.
- `test/refine_audit` baselines: not regenerated (no contract site changed; the audit
  tests in the suite above pass).
- Perf (cold `--check --stdlib-source --refine-report stdlib/list.march`, private HOME,
  VC cleared once, base and branch interleaved, load ~7): base 1.28 / 1.21 / 1.18 s,
  median **1.21 s**; branch 1.25 / 1.20 / 1.20 s, median **1.20 s** (99%). No new query
  outside a declaring definition's previously declined slots.

## Still open

Phases C–E of the design (tuple returns and `List.partition`, the stdlib sweep,
nested container fields and `Deque.filter`), and the String-callback todo above.
