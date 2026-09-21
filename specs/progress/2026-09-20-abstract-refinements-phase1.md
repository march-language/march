# Abstract refinements, phase 1: the surface rules (inert)

Landed 2026-09-20. Design:
`specs/2026-09-20-abstract-refinements-design.md` §1. Phase 1 of four; item 6
of `specs/todos/2026-09-18-refine-element-flow-followups.md` stays OPEN until
phase 2, which is what makes `filter` produce a refinement.

## What landed

`lib/refinecheck/refine_abstract.ml`: given a function's declared types, decide
which applied names in its refinements are abstract refinements, and report the
well-formedness rules. `Refine_check`'s `warn_fn` runs it, and passes the
declared names to `warn_predicate_ty` / `warn_predicate_expr` so a declared `p`
is exempt from "`p` is not a measure or known predicate".

Roles, from the design: a **definer** is an application inside an arrow
parameter's codomain refinement, applied to that arrow's domain binder
(`keep : ({x : a | true}) -> {Bool | _ == p(x)}`); a **positive** occurrence is
in the return, a **negative** one in a parameter.

Rules, each with a test that goes RED without the module:

| Rule | Verdict |
|---|---|
| applied to a name that is not the binder in scope | error |
| applied to an expression (`p(q(_))`'s outer application) | error |
| used at two different base types | error |
| a name applied inside another application | error |
| a definer with no positive and no negative occurrence | warning (vacuous) |
| a declared name in the vocabulary warning | exempt |

## The revision the build forced

The design's rule 3 said a name promised in the return with no definer is a
hard error. Probe `a7` showed what that costs: with no definer requirement,
`{List(a) | bogus_fn(_) > 0}` — an ordinary typo — was read as an abstract
refinement, which **swallowed** the "not a measure, so this refinement is not
checked" warning it has always had. A name is therefore abstract only when the
signature also DEFINES it; without a definer nothing changes, warning included.
The design was updated to match (§1 rule 3).

Same class of mistake, caught the same way: the first draft recorded a
definer's type as its `Bool` codomain, so the canonical `filter` signature
tripped the one-type rule (`Bool` vs `a`). A definer's type is its callback's
DOMAIN.

## Inertness, measured

Phase 1 must change no verdict. Against a baseline built at `origin/main`
(`scripts/refine-oracle.sh`, private HOME):

- **refinement diagnostics IDENTICAL**, 7373 lines over 371 fixtures;
- `test/refine_audit/*.baseline`: **no diff**;
- `stdlib/list.march`, cold `.march/cas/artifacts-v2`: 43 proved / 0 violated /
  31 trusted / **40 skipped**, against the CI ceiling of 42 — unchanged;
- `test_refinecheck.exe -e`: 937/937, including the new `abstract-refinements`
  group (8 cases);
- `run-tests.sh -q compiler stdlib_march`: 1079 + 70.

A first oracle run showed an 89-line diff in `stdlib_session_node` only. That
was `main` moving under the branch (a 106-line change to
`stdlib/session_node.march` landed between the baseline and the check), not
this change: after merging `main` the same baseline reports IDENTICAL. Worth
repeating because a shifted line number reads exactly like a real diff.

## Not yet

No SMT arm: `p(_)` is still an `unreflectable-predicate` skip, and row n
(`sum_pos(List.filter(ys, fn y -> y > 0))`) still skips — pinned by the last
test in the group, which is what will flip in phase 2.
