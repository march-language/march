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

## Update 2026-08-03: substantially reduced, not closed

The call-chain work landed afterwards, and the two diagnostics no longer carry
the same payload:

```
-- WARNING --  (carries the mechanical `needs …` insertion fix)
function body calls a builtin that requires `Cap(IO.Random)` but `CapErr` does
not declare `needs IO.Random`.

-- HINT --
call to `random_bytes` requires `needs IO.Random` — add `needs IO.Random` to
module `CapErr`
reached from `main`: main → issue → make_token
```

The warning says *where to add the declaration*; the hint says *which path
forced it*. That is the division of labour the header comment intended, arrived
at by giving the hint new information rather than by moving a span.

What remains is cosmetic: both still anchor at the same span, and their first
lines overlap heavily. Worth a tidy — the hint's "add `needs X` to module `Y`"
clause is now redundant with the warning and could be dropped in favour of the
chain alone — but this is no longer a case of one fact printed twice.

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
worth scoping separately. (Landed separately, before this resolution — see the
2026-08-10 update below.)

## Resolution, 2026-08-10 (Tier 3 of specs/2026-08-09-cap-loose-ends-plan.md)

Went with **option 2, presentation-time suppression**, per the prior
investigation's conclusion — not option 1 (moving Check 1b's span). Two
reasons that decided it: (a) Check 1b's span is exactly the useful
"go to error" cursor landing spot for an editor — the call site — and moving
it to the module header would trade that for a worse UX than the duplication
it fixes; (b) `cap_infer.ml` has exactly one production caller
(`bin/main.ml`, both the eval and compile/check pipelines) besides its own
direct-call unit tests in `test/test_compiler.ml`, so "presentation time"
has one unambiguous place to live and no other consumer to accidentally
affect.

Implementation, all at rendering time in `bin/main.ml`, with neither
`cap_infer.ml` nor `typecheck.ml`'s emission logic made conditional on the
other (repeating the mistake documented above):

- Both diagnostics now carry a `~code:"cap_needs:<cap>"` tag (Check 1b in
  `lib/typecheck/typecheck.ml`, the hint in `lib/refinecheck/cap_infer.ml`)
  so a downstream consumer can recognise "these two are about the same
  missing capability" without parsing prose. `lib/errors/errors.ml` gained
  an optional `?code` on `hint` and `error_with_fix` to carry it (existing
  pattern — `warning_with_code`/`warning_with_code_and_fix` already did this
  for `unused_binding`).
- `cap_infer.ml` exports `chain_marker`, the literal separator between the
  hint's "add `needs X`" prefix and its "reached from `main`: …" suffix, so
  a presentation-layer caller can split the hint without hand-rolling a
  parse of its exact wording.
- `bin/main.ml` adds `dedupe_cap_hints`, applied once right after `diags` is
  computed in the compile/check pipeline (covers the human-readable printer,
  `--check-json`, and `--emit-core-ast` uniformly): when a Hint tagged
  `cap_needs:<cap>` shares its span with an Error/Warning carrying the same
  code, the hint is trimmed down to just `reached from \`main\`: …` (its only
  non-redundant content); when there is no chain to show (a library with no
  `main`, or the call site already lands inside `main`), the hint is dropped
  entirely rather than printing a sentence that repeats the error verbatim.
  The eval/test-runner pipeline already only prints Error-severity
  diagnostics, so hints never rendered there regardless — no change needed.
  `march caps` never calls `Cap_infer.check_module` at all, so it is
  unaffected.
- Took the "smaller, in scope" suggestion (trim rather than fully drop the
  hint) instead of the todo's literal option 2 text ("drop the hint") because
  full suppression would have thrown away the call-chain, which is exactly
  the piece of information Check 1b's error does NOT carry.

Verified: `scripts/run-tests.sh -q compiler` and the full suite green
(`cap_infer`'s 12-test group in `test/test_compiler.ml`, which pins the
pass's standalone unconditional-hint contract via `check_cap_infer`/
`cap_hint_messages`, untouched); `specs/lang/types/check_types.sh` green;
manual before/after on a real `--check`/`--check-json` run of a
module-boundary capability violation (`main → issue → make_token`, missing
`needs IO.Random`) confirms the ERROR is unchanged, the HINT collapses to
`reached from \`main\`: main → issue → make_token`, and a library-only
violation with no `main` drops the hint entirely and shows only the ERROR.
