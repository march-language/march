# An opaque actual for a SIBLING parameter still blames the predicate

`[P3]` Filed 2026-09-03. Found by the Task 2 review of
`specs/plans/2026-09-02-unreflectable-predicate-attribution-plan.md`
(finding 2), recorded as a deferred item in
`specs/progress/2026-09-02-unreflectable-predicate-attribution.md` and in
both `docs/refinement-types.md` and `specs/lang/refinement-types.md`, and
confirmed independently by the whole-plan review (finding 6 fixture `f6`,
message reproduced below).

## What is broken

`check_call`'s subject-blame check (`lib/refinecheck/refine_call.ml`,
around the `self_reflection_failed` computation) only consults
`reflect_cache["$self"]`, the memo for the REFINED parameter's own binder.
When the predicate's failure to reflect is actually caused by a SIBLING
parameter's opaque actual, not the self binder, the obligation still files
as `unreflectable-predicate`, naming the sibling as if it were an
untranslatable predicate leaf.

## Repro

```march
mod F6 do
  cap verified

  fn at(i : {Int | _ < n}, n : Int) : Int do i end
  fn lane(k : Int) : Int do k end

  fn go(i : Int) : Int do
    if i < 3 do at(i, lane(4)) else 0 end
  end
end
```

```
$ march --check --refine-report f6.march
refinement obligations (user code): 0 proved, 0 violated, 0 trusted, 1 skipped
  skipped (unreflectable-predicate): 1
  by kind: 1 precondition, 0 postcondition, 0 division

`cap verified` module: cannot verify precondition `_ < n` on `at` (unreflectable-predicate: the predicate's `n` has no SMT translation)
```

`_ < n` is fully inside the supported fragment; what actually failed to
reflect is `lane(4)`, the opaque call passed for `n`. The message reads as
if the bare variable `n` itself had no SMT translation, which is confusing:
`n` is a plain `Int` parameter with no predicate of its own.

## Why it happens

`i`'s own reflection succeeds (`self_reflection_failed` is false), so the
check falls through to reflecting the predicate `_ < n`. Reflecting `n`
inside the predicate resolves it as a sibling variable, which goes through
`reflect_cached name` (`refine_call.ml` around line 1316) and fails there
because `lane(4)`, the actual bound to `n`, is opaque. That failure lands
in `reflect_cache` under the key `"n"` as `Some None`, but the subject-blame
check only ever looks at the key `"$self"`.

## Suggested fix (from the Task 2 review)

Scan `reflect_cache` for any `Some None` entry keyed by a name that is one
of the callee's OTHER parameter names (not `"$self"` and not a
`"$path$..."` internal key). When found, file `Unreflectable_subject`
naming that parameter's own actual (`actual_of_name name`, or the
equivalent lookup `check_call` already has for the call's argument list),
the same way the self binder's failure is filed today.

This is deliberately out of the design's stated scope for the
2026-09-02 plan (every corpus case there is a self-actual failure); this
file exists so a reader scanning `specs/todos/` finds the gap without
having to dig through the progress record's "Deferred items" section.

## Where a fix would land

`lib/refinecheck/refine_call.ml`, the `self_reflection_failed` computation
and the `None` arm that files `Unreflectable_predicate` /
`Unreflectable_subject` (see `specs/progress/2026-09-02-unreflectable-predicate-attribution.md`
for the mechanism as built for the self-binder case).
