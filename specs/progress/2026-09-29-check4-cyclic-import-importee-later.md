# Check 4 fires for mutually importing siblings when the importee is declared later (fixed 2026-09-29)

Residual of `2026-09-28-check4-importee-declared-later.md`, which fixed the
acyclic case with a sort edge. In a cycle the edge is withheld (it closes a
cycle), so the importer is checked first and Check 4 found no `module_caps`
entry for the importee.

**Reproduced on origin/main (76e833797)** with the todo's program:
`march --check` printed two ``Module ... not found`` errors and an unused-import
warning, and **0** Check-4 (``which requires `Cap(IO.Console)```) errors.

**Fix: defer, fail-closed** (`lib/typecheck/typecheck_caps.ml`,
`check_deferred_imports`). When Check 4 meets an import whose target has no
`module_caps` entry yet, `check_module_needs` queues it on the new shared
`env.deferred_check4` ref. After the entry module's own `check_module_needs`,
`check_deferred_imports` resolves the queue against the final `module_caps` and
emits the usual Check-4 diagnostic (same text and span).

**Why fail-closed, not re-check the importer.** The importer's bare references
to the importee never resolved, so they filed no `ie_used_names`; the demand is
unknowable without re-checking the importer, which would re-run its inference
and double-report every diagnostic in it. The deferred check therefore requires
the importee's WHOLE declared set. That is stricter than the importee-first
order for a pure-only reference, but only inside a mutually-importing group
whose importee is checked second; over-requiring is the safe side of a
capability floor, and the fix for a user who hits it is one `needs` line.
`test_check4_cyclic_import_importee_later` pins the asymmetry so it cannot
drift silently.

**Not changed:** the propagated caps still do not reach the importer's
`cap_closures` in this order (as before); only the Check-4 error is restored.
The same-file ``Module `X` not found`` diagnostic is unchanged.

**Verification.** `test/test_compiler.ml` `test_check4_cyclic_import_importee_later`
(group `cap-closure`): 2x3 over (importee before/after) x (impure uncovered /
impure covered by `needs` / pure reference). REJECT rows error in both orders;
covered rows are clean in both orders. RED: with the deferred pass disabled the
"importee AFTER, impure: error" assertion fails. `test_cyclic_modules_still_enforce`
and `test_check4_importee_declared_later` still pass.
