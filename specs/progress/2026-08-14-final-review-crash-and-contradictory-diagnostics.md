# Final whole-branch review: crash + contradictory capability diagnostics

Three findings from a final whole-branch review of the capability-UX branch
(`claude/march-capability-ux-3f2521`), fixed in one pass.

## Critical: ICE on a MARCH_LIB_PATH dependency with no `needs`

`bin/main.ml`'s `cap_ceiling_fix_indent` called `List.nth_opt lines
(span.start_line - 1)`. `List.nth_opt` RAISES `Invalid_argument` on a
negative index rather than returning `None`. A module loaded from a
separate file via `MARCH_LIB_PATH` (the lib-path loader at `bin/main.ml`
around line 361, and `lib/resolver/resolver.ml`'s import resolver) is
synthesized as `DMod (..., March_ast.Ast.dummy_span)` — `dummy_span.file =
"<none>"`, `start_line = 0`. When such a module violates the
`--cap-strict` ceiling and declares no `needs` of its own,
`cap_ceiling_module_spans` fell back to that dummy header span, giving
`start_line - 1 = -1` and crashing the compiler with `internal compiler
error: Invalid_argument("List.nth")` instead of reporting the violation.
This is the shape of every forge project with a freshly-added dependency
that has no `needs` yet — the exact newcomer path the capability-UX work
was supposed to improve.

Fix, both halves:

1. `cap_ceiling_module_spans` (`bin/main.ml`) now falls back to the
   module's first inner declaration carrying a REAL (non-dummy) span when
   its own header span is `dummy_span` — a cross-file module's own
   functions/lets/etc. are parsed from the real file and carry real spans,
   even though the synthesized wrapper `DMod` does not.
2. `cap_ceiling_fix_indent` guards the negative-index case explicitly
   rather than trusting `List.nth_opt`'s (surprising) raise-on-negative
   behavior.
3. Belt-and-suspenders: in the violation-rendering loop
   (`bin/main.ml` around line 3178), an `Undeclared` violation whose span
   is STILL `dummy_span` after (1) — i.e. every declaration in the
   offending module was itself span-less — now falls back to the
   pre-existing bespoke `-- CAPABILITY CEILING --` rendering instead of
   rendering through the normal diagnostic pipeline, which would read
   `dummy_span`'s file (`"<none>"`), raise `Sys_error`, silently fall back
   to the ENTRY file's source, and print line 0 of the wrong file.

Regression test: `test/test_cap_ceiling.ml`'s
`test_lib_path_dependency_with_no_needs_does_not_crash`, using a real
two-file `MARCH_LIB_PATH` scenario (a fresh temp lib dir + entry file) —
the existing nested-module-in-entry-file tests in that file structurally
cannot hit this, since a nested `DMod` always carries a real
parser-assigned span. The dependency module calls a STDLIB-MEDIATED
capability (`File.write`, not `file_write`) so typecheck's Check 1b
doesn't catch it first (same reasoning as
`test_stdlib_route_was_completely_silent` in the same file) — only the
ceiling actually exercises the crash site.

Manual repro (from the review) re-verified fixed: a `MARCH_LIB_PATH`
module with no `needs`, reached from an entry file, now exits 1 with a
`-- CAPABILITY CEILING --`/ordinary-diagnostic violation naming the
dependency, not exit 3.

## Important 2: unknown-capability error contradicts unused-`needs` warning

`lib/typecheck/typecheck.ml`'s Check 0 (unknown capability, rejects
`needs Network` with a did-you-mean) and Check 2 (unused `needs`) fired on
the SAME line for a typo'd/unknown capability, giving opposite advice: fix
the name vs. delete the line. Fix: Check 0 now collects every capability
path it rejects into `unknown_needs`, and Check 2's `declared_needs`
iteration filters those out before checking for "unused."

Test: `test/test_compiler.ml`'s
`test_unknown_capability_does_not_also_warn_unused` (in the
`cap_unknown_name` suite) — asserts the unknown-capability error fires and
the "remove the unused capability declaration" warning does not, for
`needs Network`.

## Important 3: Check 1 / Check 1b propose overlapping redundant fixes

A `Cap(X)` signature parameter (Check 1) and the aggregated missing-`needs`
body scan (Check 1b) could both demand `needs` lines for the same program,
with Check 1b's set redundant with (subsumed by) Check 1's: `fn main(cap :
Cap(IO))` demands `needs IO` from Check 1, while Check 1b separately
listed `needs IO.Clock`/`needs IO.Console`/`needs IO.Random` for the same
body — `needs IO` alone already covers all three, so `forge fix` applying
both wrote four lines. Fix: Check 1 now records every capability it
separately demands (`check1_demanded_caps`); Check 1b's aggregation drops
any capability subsumed (`Cap_lattice.cap_subsumes`) by one of those before
building its message/fix.

Two pre-existing tests (`test_missing_needs_reported_once_per_module`,
`test_missing_needs_dedup_no_orphan_hint`) happened to use a
`main(cap : Cap(IO))` fixture — under the fix, `needs IO` fully subsumes
every capability their bodies use, so Check 1b's aggregated error (and its
`cap_needs:` code, which `bin/main.ml`'s `dedupe_cap_hints` keys off of)
now correctly disappears entirely for that fixture, leaving only Check 1's
own "add `needs IO`" error. Both tests were re-pointed to a `main`-less
library module (no `Cap(...)` signature parameter anywhere) so they keep
testing Check 1b's own aggregation in isolation, undisturbed by Check 1.

New tests: `test_check1b_omits_caps_subsumed_by_check1` (the review's own
repro shape: `Cap(IO)` main subsumes everything, Check 1b's aggregated
error does not also fire) and
`test_check1b_keeps_caps_not_subsumed_by_check1` (the narrower half:
`Cap(IO.Console)` does NOT subsume `IO.FileWrite`, so Check 1b must still
report the capability Check 1 doesn't cover — dropping subsumed caps must
not turn into dropping everything indiscriminately).

## Verification

- `dune build --root . bin/main.exe` / `test/run_compiler.exe` — exit 0.
- `./_build/default/test/run_compiler.exe test cap_ceiling -e` (no `-q` —
  several cap_ceiling tests are `Slow` and pin exact diagnostic wording).
- `./_build/default/test/run_compiler.exe test cap_grant -e`,
  `test cap_unknown_name -e`, `test typecheck 178-183 -e` — all green.
- `dune build --root . --force @types-check` — `291 passed, 0 failed`
  (unchanged; no corpus witness added, covered by alcotest instead).
- `scripts/check-docs.sh` — passed.
- Manual repro from the review (`MARCH_LIB_PATH` dependency, no `needs`)
  re-run: exits 1, names the dependency, no crash.
