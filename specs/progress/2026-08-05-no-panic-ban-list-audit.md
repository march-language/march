# `cap no_panic` ban-list audit: false positive, dead entries, coverage holes

**Date:** 2026-08-05
**Files:** `lib/typecheck/typecheck.ml`, `test/test_compiler.ml`

## Summary

`cap no_panic`'s enforcement (`check_no_panic_module` in `lib/typecheck/typecheck.ml`)
includes a purely syntactic ban list, `panic_surface_stdlib`, of dotted stdlib
names that panic. An audit found the list had drifted from the real stdlib in
three ways. This is Task 1 of an 8-task plan
(`docs/superpowers/plans/2026-08-05-no-panic-proof-based-and-group-b.md`) whose
later tasks replace the blunt syntactic ban with a proof-based check that
consults each call's actual refinement contract; this task only corrects the
list's contents using the existing mechanism.

### 1. False positive (removed)

`String.slice_bytes` was banned, but its own docstring
(`stdlib/string.march:38-42`) states it clamps `start`/`len` to valid byte
ranges and never panics. A `cap no_panic` module could not call a function
that cannot panic. Removed from `panic_surface_stdlib`.

### 2. Seven dead entries (removed)

These named functions that do not exist under those names anywhere in the
stdlib (confirmed by grep against `stdlib/*.march`, not assumed from the ban
list's own comments):

- `List.hd`, `List.tl`, `List.min_elt`, `List.max_elt` — no such functions in
  `stdlib/list.march`.
- `String.nth` — no such function in `stdlib/string.march`.
- `NativeArray.get`, `NativeArray.set` — the real accessors in
  `stdlib/native_array.march` are `get_int`/`set_int`/`get_float`/`set_float`.

Harmless (a ban on an uncallable name enforces nothing either way), but a
stale ban list is exactly the kind of drift this audit exists to catch.

### 3. Twelve live coverage holes (added)

Public functions that carry a real refinement precondition and panic when it
is violated, but were absent from the ban list under any spelling — meaning a
`cap no_panic` module could call one unguarded and compile clean. Verified
against current source, each with its actual contract:

| function | contract | source |
|---|---|---|
| `List.tail` | `{List(a) \| len(_) > 0}` | `stdlib/list.march:100` |
| `List.maximum_int` | `{List(Int) \| len(_) > 0}` | `stdlib/list.march:772` |
| `List.minimum_int` | `{List(Int) \| len(_) > 0}` | `stdlib/list.march:786` |
| `Random.normal` | `sigma : {Float \| _ >= 0.0}` | `stdlib/random.march:219` |
| `Random.exponential` | `lambda : {Float \| _ > 0.0}` | `stdlib/random.march:234` |
| `Random.bernoulli` | `p : {Float \| _ >= 0.0 && _ <= 1.0}` | `stdlib/random.march:246` |
| `Random.choice` | `xs : {List(a) \| len(_) > 0}` | `stdlib/random.march:304` |
| `DateTime.fixed_zone` | `offset_seconds : {Int \| _ >= -50400 && _ <= 50400}` | `stdlib/datetime.march:360` |
| `DateTime.fixed_zone_hm` | `minutes : {Int \| _ >= 0 && _ < 60}` | `stdlib/datetime.march:384` |
| `Stats.mean` | `{List(Float) \| len(_) > 0}` | `stdlib/stats.march:27` |
| `Stats.min_val` | `{List(Float) \| len(_) > 0}` | `stdlib/stats.march:38` |
| `Stats.max_val` | `{List(Float) \| len(_) > 0}` | `stdlib/stats.march:47` |

Live repro before the fix (still true against the reverted list — see Step 5
below):

```march
mod Gap do
  cap no_panic
  fn f(xs : List(Int)) : List(Int) do List.tail(xs) end
end
```

→ `exit 0`, only a silent HINT. After the fix: `exit 1`, an ERROR naming
`List.tail`.

## What changed

- `panic_surface_stdlib` (`lib/typecheck/typecheck.ml`): removed 8 names
  (`String.slice_bytes` + the 7 dead entries), added the 12 coverage-hole
  names above.
- `panic_surface_suggestion`: removed the dead-name cases (`List.hd`,
  `List.tl`, `NativeArray.get`/`set` folded into `Array.get`/`set`,
  `String.slice_bytes`/`String.nth` case removed entirely); added one case
  per new name, following the existing style (reusing the `tail`/`List.tail`
  wording already present for `List.tail`; "guard the parameter" wording for
  the `Random.*` functions; "check `List.length(xs) > 0`" wording for
  `Random.choice`/`Stats.*`; explicit range-guard wording for
  `DateTime.fixed_zone`/`fixed_zone_hm`).
- No new mechanism: this is a syntactic ban-list content change only.

## Deliberate over-rejection (blunt until Task 3)

Because Task 1 reuses only the existing syntactic mechanism, a call to one of
the newly-banned names is now rejected **even when it is properly guarded** —
e.g. `if List.length(xs) > 0 do List.tail(xs) else xs end` inside a
`cap no_panic` module still errors today. This is pinned as an explicit test
(`test_cap_no_panic_list_tail_guarded_still_error`) with a docstring noting it
is blunt until Task 3, which will replace the syntactic ban with a check that
consults `Refine_check`'s actual verdict for the call site.

## Testing

Added to the `cap_no_panic` suite in `test/test_compiler.ml`:

- 1 test: `String.slice_bytes` compiles clean under `cap no_panic` (false
  positive fix).
- 12 tests: one per coverage-hole function, each with an unguarded call inside
  a `cap no_panic` module — now an error.
- 1 control: `List.tail` guarded by a length check is STILL banned (proves
  Task 1 does not silently start proving anything; Task 3 has this test to
  flip).

RED (pre-fix): the `String.slice_bytes` case failed because it reported an
error (should report none); all 12 coverage-hole cases + the guarded control
failed because they reported NO error (should report one) — confirmed by
inspecting `has_errors` results directly (`Received: true`/`Received: false`
in the Alcotest failure output), not just an aggregate pass/fail count.

GREEN (post-fix): all 14 new cases pass; the 32 pre-existing `cap no_panic`
tests are unaffected (46 total, 0 failures).

Load-bearing proof (Step 5): reverted `panic_surface_stdlib` only (kept the
test file and the `panic_surface_suggestion` cases as-is), rebuilt, confirmed
all 14 new cases go red again identically, then restored the fix and
confirmed green again.

## Stdlib + corpus sweep

`json_stream.march` is the only stdlib module declaring `cap no_panic`, and it
calls none of the twelve newly-banned functions (grepped directly).

A before/after sweep (`main.exe --check` over every `stdlib/*.march` file,
comparing a binary built from the parent commit's `typecheck.ml` against one
built from the fixed version, CAS caches cleared before each run) showed no
diff other than worktree-path text embedded in an unrelated pre-existing
"Overlapping implementation" diagnostic (the two binaries were built in
different directories).

**Positive control — important finding:** the brief's prescribed positive
control (add an unguarded call to one of the twelve inside `json_stream.march`
and confirm the sweep shows a diff) produced **no diff**, but not because the
fix is inert. `bin/main.ml` filters every diagnostic whose span points into a
stdlib source file before printing (`is_user_file`) — a known trap, see
`project_stdlib_diag_filter_poisoning` in the assistant's own memory. An error
injected into a stdlib file is therefore invisible to `--check` regardless of
whether the underlying check fired. The positive control was re-run instead
against a scratch fixture outside `stdlib/` (`/tmp/.../positive_control.march`,
`cap no_panic` + unguarded `Stats.mean`): the "before" binary compiled it
clean (`exit 0`, only the silent HINT — the exact bug this task fixes), the
"after" binary rejected it (`exit 1`) with the new `Stats.mean` ban message.
`json_stream.march` itself was left untouched (edited only transiently, then
reverted and diffed clean against its original).

Corpus (`specs/lang/types/check_types.sh`) and full suite
(`scripts/run-tests.sh`) results: see the task report.

## Docs checked, no changes needed

`docs/capabilities.md` and `specs/lang/capabilities.md` both describe the
panic-surface ban with an illustrative, non-exhaustive example list (`List.nth`,
`Option.unwrap`, `Result.unwrap`, `Array.get`, "…") — none of the removed or
false-positive names appear there, so no edit was needed for accuracy.
