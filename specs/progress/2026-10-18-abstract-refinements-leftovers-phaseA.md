# Abstract refinements, the leftovers: phase A (richer lambda bodies)

**Date:** 2026-10-18
**Design:** `specs/2026-10-18-abstract-refinements-leftovers-design.md` §2, §6.1, §9.1
**Base:** `c0992ab13` (branch `claude/refinement-todos-73b0dc`)

## What a user sees

A lambda passed for an abstract refinement (`List.filter`'s `pred : a -> Bool[p]`, and any
user combinator declared the same way) used to instantiate `p` only when its body was pure
vocabulary or exactly one eta call `fn y -> g(y)`. Anything else was an
`abstract-refinement-uninstantiated` skip, often with a misleading reason ("mentions a name
other than its own parameter" for an `if`). Now the body is read as the exact predicate it
computes:

| Passed for `p` (demand `sum_pos : List({Int \| _ > 0})`) | Before | After |
|---|---|---|
| `fn y -> is_pos(y) && y < 100` (L1) | uninstantiated | **proved** |
| `fn y -> is_pos(y) \|\| y < 100` (L1c) | uninstantiated | **too-weak**, "(read as `y > 0 \|\| y < 100`)" |
| `fn y -> if y > 0 do y < 100 else false end` (L2) | uninstantiated (wrong reason) | **proved** |
| `fn y -> if y > 0 do true else y > -5 end` (L2c) | uninstantiated | **too-weak** |
| `fn y -> not(is_neg(y)) && y != 0` (L3) | uninstantiated | **proved** |
| `fn y -> not(is_neg(y))` (L3c) | uninstantiated | **too-weak** (admits 0) |
| `fn y -> match y > 0 do true -> y < 100  false -> false end` (L4) | uninstantiated | **proved** |
| `fn y -> gt(y, 0)` (L5, phase-3 row q06) | uninstantiated | **proved** |
| `fn y -> gt(0, y)` (L5c) | uninstantiated | **too-weak** (arguments in order) |
| `fn y -> gt(y, k)`, `k` a caller parameter (L5k) | uninstantiated | uninstantiated (C1) |
| `let f = fn y -> y > 0`, then `fn y -> f(y) && y < 100` (L8) | uninstantiated | **proved** |
| callback `k : ({x : Int \| true}) -> {Bool \| _ == (x > 0)}`, `fn y -> k(y) && y < 100` (L9) | uninstantiated | **proved** |
| `fn y -> is_pos(y + 1)` (L10) | uninstantiated | **too-weak** |
| a block body with `let` (L11) | uninstantiated | uninstantiated (out of scope, design §7) |

The same reading is used at a parameter slot (`need(xs : List(a[p]), keep : a -> Bool[p])`).
A too-weak message prints the lambda and its reading when they differ; a decline names the
construct (a block with `let`, a `match` not on `true`/`false`, an `if` in a non-Bool position,
a call with no proved contract, a self-naming `let`-bound lambda, the depth bound).

## Implementation (`lib/refinecheck/refine_check.ml` only)

- `named_predicate_n` replaces `named_predicate`: a proved `{Bool | _ == e}` over any number of
  parameters, as `(params, e)`. C3: `e` must not mention the result binder or `_`, and every
  application in `e` must be reflected vocabulary. The by-name path (`by_name`) keeps the
  one-parameter requirement and its own error text. Phase 3 admitted `Relational [_]` with the
  binder possibly in `e`; that is now declined (no test or oracle line depended on it).
- `inline_bool_body` (new) is the design's `⟦·⟧`: vocabulary as itself; `if` and a Bool `match`
  (true/false arms in either order, or one Bool arm then `_`, no guards) as
  `(c && t) || (!c && e)`, only in a Bool position (the top of the body, under `&&`/`||`/`not`, or
  an `if`/`match` arm), dropping a literally-false disjunct; a call resolved in §2.2's order
  (own parameter → decline; `let`-bound lambda from `lets` → β-reduce; `callee_sig` proved
  contract → substitute; else decline). Actuals are read first (C6), substitution is
  `subst_params` (simultaneous, C2). A `let`-bound lambda is translated over its OWN parameters
  first and must be closed over them before substitution, so a capture (including one that
  happens to be named like the outer binder) declines rather than being captured. C5: a
  `let`-bound lambda that mentions its own name declines, both inside a body and when passed by
  name. Depth bound `inline_depth_max = 4`.
- `instantiate_abstract`'s `of_lambda` calls it, then requires `classify_pred y [] r = Closed`
  (C1). The `opaque_call` scan is gone.
- `abstract_flow`'s too-weak text: `` `fn y -> <written>` (read as `<reading>`) `` when the reading
  differs from the source, else the old text unchanged. `reading_str` parenthesises `!(…)` and
  an `||` under `&&` (`pred_str` would print `!y > 0`).

Nothing in `Refine_scope`/`Refine_encode` changed; the output is ordinary vocabulary.

## Conservative calls (beyond the design)

- **`if`/`match` only in a Bool position.** The design reads `if` as a Boolean `ite` without
  saying where it may sit. An `if` whose arms are Int (`(if y > 0 do y else 1 end) > 0`) would
  give an ill-sorted term, so it declines ("an `if` whose arms are not Bool"). Tested.
- **A computed call head** (`EApp` whose head is not a name) declines; the old reader let it
  through `opaque_call`'s recursion.
- **Local-lambda captures** are checked on the lambda's own reading, before substitution (see
  above). The design's C1 alone (checking the final `q`) would miss a capture named like the
  outer binder (`let f = fn z -> z > y` with a caller `y`, then `fn y -> f(y)`); tested.
- The design's §6.1 kept a one-parameter `named_predicate` wrapper; with `by_name`
  destructuring `named_predicate_n` directly it was unused (warning 32), so it is gone.

## Tests (`test/test_refinecheck.ml`, group `abstract-leftovers-a`, 24 cases)

RED on the base (`c0992ab13` with this test file), GREEN after:
A1, A2, A3 (if, match, swapped arms, wildcard arm), A4, A5, A7, A9 (L8, L9), A10, A11 (the base
declines but with "calls `f`, whose result is not reflected" — the test pins the C5 reason),
A12 (the four-chain), A15, A16, A17, A18 (proved, and no skip anywhere in the module), the
non-Bool `match` control (base gave the old misleading "mentions a name" reason), and the
parameter-slot case. Plus `abstract-phase3` q06, flipped to proved and renamed
"q06: a two-parameter call inside a lambda is inlined" (A6).

Guards, green on both: A8 (L5k), A13 (unproved helper contract), A14 (lambda parameter shadowing
`is_pos`), a block body with `let`, an `if` in a non-Bool position, a helper whose contract
mentions its result binder (C3), a `let`-bound lambda capturing a caller name (C1), and one
capturing a name equal to the outer binder.

Re-pointed, not deleted: phase 2's "a lambda that calls a function is uninstantiated, not too
weak" now uses `fn y -> mystery(y) && y < 100` with a contract-less `mystery`.

**Perturbation.** (1) Making the call arm of `inline_bool_body` always decline reddens exactly
A1, A2, A5, A7, A9, A10, A12, A15, A16, A17, the parameter-slot case, and phase-3 q06 and q07
(eta now runs through the inliner). (2) Making the `if`/`match` arms decline reddens exactly A3,
A4, A18 and the non-Bool `match` control. Nothing else moved under either.

**Conformance corpus.** `accept/t331_refine_abstract_lambda_bodies` (L1, L2, L4, L5, L8 under
`cap verified`) and `reject/t332_refine_abstract_lambda_or_too_weak` (L1c, pinned on the
"(read as …) does not imply" text). `check_types.sh`: 446 passed, 0 failed.

## Verification

- `dune build --root . bin/main.exe test/test_refinecheck.exe`: ok.
- `./_build/default/test/test_refinecheck.exe -e`: 1069 tests, all passed, 0 `[SKIP]` (z3 on PATH).
- `scripts/run-tests.sh -q compiler`: 1348 tests, all passed.
- Refine oracle: baseline from a `c0992ab13` scratch worktree, check from a scratch worktree
  of this branch at the same location, private HOME: **REFINEMENT DIAGNOSTICS IDENTICAL**
  (7786 lines over 549 fixtures), as §8 predicted (no stdlib call passes a compound lambda to a
  demanded combinator). Run from the agent worktree instead (nested under the main checkout),
  the check differs in `cap_needs` HINT-vs-ERROR text of `stdlib_*` fixtures, a location
  artifact of where the stdlib sources resolve; the same-location rerun shows it is not this
  change.
- `stdlib/list.march` CI ratchet: 37 skipped (user + stdlib) on base and branch; ceiling 37.
- `test/refine_audit` baselines: not regenerated, no contract site changed.
- Perf (cold `--check --stdlib-source --refine-report stdlib/list.march`, private HOME, VC
  cleared once, base and branch interleaved, load ~8): base 1.43 / 1.14 / 1.15 s, median
  **1.15 s**; branch 1.31 / 1.17 / 1.14 s, median **1.17 s** (102%, within the 110% budget).
  The inliner adds no query.

## Still open (unchanged by this phase)

Phases B–E of the design: `!p(_)` slots and concrete bases, tuple returns and
`List.partition`, the stdlib sweep, nested container fields and `Deque.filter`. Lambda-local
`let` blocks (L11) and Int-valued helpers inside a lambda stay out of scope (design §7).
