# `DateTime.parse_offset` panicked on a malformed offset instead of returning `Err`

Shipped 2026-09-16. Stdlib fix (`stdlib/datetime.march`) plus test-harness
registration; no compiler or runtime change.

## Symptom

```march
DateTime.parse_offset("2026-01-02T03:04:05+01:75")
-- panic: DateTime.fixed_zone_hm: minutes must be in [0, 60)
```

Every other failure in this parser returns `None`/`Err`; only an out-of-range
offset aborted the process.

## Cause

`parse_offset_suffix` parsed the offset minutes with `parse_digits(r2, 2)`,
which admits any two digits (00-99), and handed the result straight to
`fixed_zone_hm(sign * h, m)` at what were `stdlib/datetime.march:547` and
`:555` (the `+HH:MM` and the colon-less `+HHMM` branch — two separate code
paths, both unguarded). `fixed_zone_hm` declares
`minutes : {Int | _ >= 0 && _ < 60}` and panics when that is violated.

The refinement checker had already flagged both sites: each was an
`unconstrained-subject` skip ("no fact the checker derived constrains `m`") in
`--refine-report` over `stdlib/datetime.march`.

The hour had a second, quieter bug on the same line: `h` is unrefined, so it
never panicked, but `"+99:00"` was accepted and produced a `Tz` 356400 seconds
from UTC. A three-digit hour (`"+100:00"`) was already rejected for an
unrelated reason — `parse_digits` takes exactly two digits, and neither the
`":"` nor the colon-less continuation then parses.

## Fix

`parse_offset_suffix` now parses the minutes once (the `":"` and colon-less
forms differ only in which string the digits come from), range-checks both
fields, and returns `None` when either is out of range:

```march
if h >= 0 && h < 24 && m >= 0 && m < 60 do
  Some((fixed_zone_hm(sign * h, m), r3))
else None end
```

`None` from the suffix parser is what the public `parse_offset` already turns
into `Err("expected offset (Z / +HH:MM / -HH:MM) after time")`, so no new
message was invented. The hour bound follows RFC 3339's `time-hour` (00-23),
which accommodates every real zone (the widest is +14:00). Two dead
`let offset = sign * (h * 3600 + m * 60)` bindings, shadowed by
`fixed_zone_hm`'s own arithmetic, went away with the restructuring.

## Refinement-census effect

Checking `stdlib/datetime.march` with `--refine-report`, before:

```
refinement obligations (user code): 0 proved, 0 violated, 0 trusted, 2 skipped
  skipped (unconstrained-subject): 2
```

after:

```
refinement obligations (user code): 1 proved, 0 violated, 0 trusted, 0 skipped
```

Both skips are gone, and they did not move: they became **one proved
obligation**. The count drops from two to one because the two call sites were
merged into one; the guard's `then` branch gives the checker exactly the
`m >= 0 && m < 60` that `fixed_zone_hm` demands. The stdlib-wide totals move in
step (`unconstrained-subject` 55 -> 53, proved 40 -> 41).

`--refine-report-sites` (which landed on main alongside
`specs/progress/2026-09-16-refine-skip-census.md` while this fix was in
flight) agrees, and is the check the census itself uses:

```
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --check --refine-report-sites stdlib/list.march \
  2>&1 | grep datetime
```

prints nothing, where it used to print the two `datetime.march:547,555` rows.
That run still emits 40 skip rows for other modules, so the empty grep is a
real absence and not an empty run.

## The tests did not run

`test/stdlib/test_datetime.march` existed but was an **orphan**: it was on
`test_stdlib_march.ml`'s `known_unregistered_stdlib_test_files` allowlist and
was reachable from no runner, so its 24 existing tests had never executed. It
is now registered (`("datetime", [... run_stdlib_test "test_datetime.march"
"TestDateTime"])`) and removed from the allowlist, which also required adding
`datetime.march` to the harness's stdlib load list. It is loaded **last**, so
its `Date`/`Time`/`Tz` constructors cannot steal bare-name lookups from the
modules loaded before it.

## Verification

- The repro now prints `Err: expected offset (Z / +HH:MM / -HH:MM) after time`
  for `+01:60`, `+01:99`, `+0199`, `+99:00` and `+24:00`, and still `Ok` for
  `+01:30`, `+0130`, `-05:45`, `Z` and `+23:59`.
- 12 new tests under `describe "parse_offset"` cover both call paths.
- **Non-vacuous.** With one `Err` expectation flipped to `Ok` and one valid
  offset given the wrong second count, the suite reports exactly those two as
  `FAIL` — so the new cases really execute (they would not have before the
  registration above).
- `scripts/run-tests.sh` and `scripts/run-tests.sh stdlib_march` pass.
