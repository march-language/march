# A `{String | ...}` return refinement files no obligation at all

`[P2]` Filed 2026-09-03, found while implementing
`specs/plans/2026-09-02-unreflectable-predicate-attribution-plan.md` Task 3
(task-3-report.md, "Pre-change slugs for UP1 to UP4"; confirmed independently
by the Task 3 reviewer, finding 5).

## What is broken

A function whose declared return type is a `String` refinement is checked by
nothing: no obligation is filed, `--refine-report` counts it as neither
proved nor skipped, and `cap verified` does not turn the gap into an error.
This is a silent hole, not a reported skip; it is worse than an
`unreflectable-predicate` or `unreflectable-subject` skip, both of which at
least show up in the count.

## Repro

```march
mod StrReturn do
  needs IO.Console

  fn f() : {String | _ == "a"} do "a" end

  fn main(_cap_console : Cap(IO.Console)) : () do
    println(f())
  end
end
```

```
$ march --check --refine-report str_return.march
refinement obligations (user code): 0 proved, 0 violated, 0 trusted, 0 skipped
  by kind: 0 precondition, 0 postcondition, 0 division
```

Zero postconditions filed for this module, even though `f` has exactly one
return refinement. Adding `cap verified` to the module does not turn this
into an error either; `march --check` exits 0.

## Root cause

`return_refine_ext` (`lib/refinecheck/refine_post.ml:41`) only recognizes
Int, Bool, Float, and record return bases. A `String` base falls through its
wildcard match to `None`, so `check_fn_post_verdict` (`refine_post.ml:954`)
routes to `check_post_induction` instead of `check_post`. Nothing in the
induction path records anything for a non-inductive, non-ADT return type; it
exists for measures over recursive ADTs, not for a plain `String` literal
body, so no `smt_of`/`smt_of_r` call, and no `Obligation.note`, is ever
reached for this shape.

This is a different failure from the one
`2026-09-02-unreflectable-predicate-attribution.md` fixed: that plan made a
predicate that DOES reach a goal-building call site name its failure
correctly. This is a predicate that never reaches a goal-building call site
at all, because the return-type dispatch does not recognize `String` as a
scalar base in the first place.

## Where a fix would land

`lib/refinecheck/refine_post.ml`:
- `return_refine_ext` needs a `String` arm alongside its existing Int/Bool/Float
  arms, producing whatever shape `check_post`'s goal site expects for a
  scalar base.
- The goal site itself (`smt_of_r ~resolve_var ~resolve_measure ~resolve_field
  ~resolve_measure_app ret_pred`, ~line 406) already knows how to reflect a
  `String` predicate for a precondition (`refine_call.ml`'s goal site passes
  `~resolve_str_lit`); the postcondition goal site does not currently pass
  one at all, per the Task 3 report's note on UP4's replacement fixture ("the
  goal site ... passes no `~resolve_str_lit` at all, so a string literal
  ALWAYS fails there"). A `String` return fix needs to wire that resolver
  through too, or a `{String | _ == "a"}` return will reach the goal site
  only to file `unreflectable-predicate` on every string-literal comparison,
  which is a real class of return refinement (`Base64.encode`, `Uri.encode`,
  and similar wrappers commonly refine their return by a literal prefix/suffix
  or exact-match check).

## Why it matters

Any stdlib or user function that declares a `{String | ...}` return type
today gets zero enforcement and zero visibility into the fact that it gets
zero enforcement. A `--refine-report` reader has no way to distinguish "this
function's return type has no refinement" from "this function's return
refinement is silently unchecked"; both print nothing. Worth fixing before
any `{String | ...}` return type is relied on for correctness.

## Cross-reference

The refinement coverage audit (`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`)
reproduces this exact repro at `test/refine_audit/holes/string_return.march`,
one of the fixtures in the audit's non-vacuity guard
(`test/refine_audit/holes.baseline`). `--refine-audit` classifies this site
as `Unenforced`, naming both `return_refine_ext` and `post_induction_shape`
as the extractors that decline it; see
`docs/refinement-types.md`/`specs/lang/refinement-types.md`'s "Coverage
audit" section.
