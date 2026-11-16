`[P2]` A refinement's parameter named like a user function no longer moves that function's contract hash

Found 2026-11-07 by the LSP suite (`lsp/test/test_lsp_refine.ml`, "lsp_invalidate: an edit that
moves no frontier hash re-checks nothing": 1 stale dependent instead of 0) on the branches
adding `Session.Theory` C3-C5 (#1167) and `Actor.Theory` (#1168).

## Cause

`Refine_reflect.refs_of` collects the names a unit's refinements mention, and `resolve` maps
each by its bare name to units (same file first, else every file) to decide which functions'
WHOLE BODIES are part of a contract (`in_predicate`). It took every `EVar`, including the
unit's own parameters and the refinement binders. A stdlib theorem with a parameter `f`
(`Session.Theory`'s `GMsg(f, t, p, k)`, `Actor.Theory`'s `enq_other(s, q, f, p)`) resolved to
a user's `App.f`, marking `App.f` and everything it reaches (`Util.is_small`) as named by a
predicate. `is_small`'s contract hash then differed between `app.march`'s check (which loads
the theory) and `util.march`'s own, so the LSP re-checked `app.march` after an edit that
moved nothing.

## Fix

`refs_of` skips the unit's parameters (`u_params`) and the refinement's binders (`_`, `v` of
`{v : T | ...}`): a value, never a function. Regression: `test_lsp_refine` case "a
refinement's parameter named like a user function marks nothing" (a `lem.march` with
`fn g(f : Int) : {Int | _ == f}`), red without the fix, green with it.
