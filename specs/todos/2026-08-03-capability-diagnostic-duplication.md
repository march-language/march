# A missing capability is reported twice, at the same place

Filed 2026-08-03 during the phase-2b error-message pass.

## Symptom

One undeclared capability produces two diagnostics anchored at the same span:

```
-- WARNING --
function body calls a builtin that requires `Cap(IO.Random)` but `CapErr` does
not declare `needs IO.Random`.
hint: add `needs IO.Random` to the module body.

4 |     Bytes.to_string(random_bytes(16))
                        ^^^^^^^^^^^^

-- HINT --
call to `random_bytes` requires `needs IO.Random` — add `needs IO.Random` to
module `CapErr`

4 |     Bytes.to_string(random_bytes(16))
                        ^^^^^^^^^^^^
```

Same fact, same location, twice — and only the first carries the mechanical
`needs …` insertion fix (`Err.warning_with_fix`, `lib/typecheck/typecheck.ml`
Check 1b). The second (`lib/refinecheck/cap_infer.ml`) has no fix attached.

## Why it is not simply a bug

`cap_infer.ml`'s header states the overlap is deliberate:

> This is a *soft* pass — the typechecker's own body-scan (Phase 2) already
> emits Err.warning for missing needs; this pass adds Err.hint annotations that
> point directly at the call site rather than at the [needs] insertion point,
> giving a second, finer-grained anchor.

So the intended split is: **warning at the insertion point** (where you would
type `needs`), **hint at the call site** (what forced it). That is a reasonable
design. It just isn't what happens — Check 1b anchors its warning at the call
site too, so both land in the same place and the "second, finer-grained anchor"
is the same anchor.

## Options (a design decision, not a mechanical fix)

1. **Realise the original intent** — move Check 1b's warning span to the module
   header / `needs` insertion point, keeping the call-site hint. Reads well:
   "here is where the declaration goes" plus "here is what needs it". Risk: the
   warning's span is load-bearing for the attached `FInsert` fix and for any
   tooling keyed on it.
2. **Drop the hint** when a stronger diagnostic already covers the same span,
   and let the warning carry both roles.

## What was tried and reverted

Suppressing the hint inside `cap_infer` when a diagnostic at the same span
already mentions the same `needs <cap>`. It works on the CLI path but breaks
three `cap_infer` unit tests (`random_bytes missing needs`, `file_write missing`,
`nested mod missing`) which call the pass directly and assert the hint fires —
correctly, since they pin that pass's standalone contract. Any suppression
therefore belongs at presentation time (where diagnostics are rendered), not
inside the pass.

**Note for whoever picks this up:** the first attempt appeared to pass the suite
because only `bin/main.exe` had been rebuilt, not `test/run_compiler.exe`. Build
the test binary explicitly before believing a green run here.

## Remaining phase-2b work on capabilities

The plan also asks the capability error to *show where in the chain from `main`
the capability should have been threaded*. That needs a call graph from the
entry point to the offending call; `cap_infer` currently walks declarations
per-module with no cross-function reachability. Larger than this cleanup and
worth scoping separately.
