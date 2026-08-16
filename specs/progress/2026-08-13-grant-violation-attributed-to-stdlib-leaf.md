# Attribute grant violations to the user's module, not the stdlib leaf

**Status:** Landed (2026-08-14). Task 8 (final task) of the capability-UX
plan (`specs/2026-08-13-capability-ux-plan.md`).

## The problem

A whole-program grant violation reached through the stdlib used to name only
the stdlib leaf that directly holds the capability:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileRead`
(reached in `File.read`).
```

`File.read` is the least useful frame in that message — it tells the user
nothing about which of *their own* functions is responsible. They had to
hunt through their call graph to find the actual call site. The sibling
body-scan diagnostic (missing-`needs`, `cap_infer.ml`) already prints a full
chain from `main` (`main → log_error → log`); `check_main_grant`'s violation
branch did not.

## The fix

`check_main_grant` (`lib/typecheck/typecheck.ml`) now calls `cap_reach_chain
env ~from:"main" ~cap:c` to build the same "who reaches what through whom"
evidence, instead of computing a single arbitrary holder via the old
`reached_in`/`reachable_from_main` pair. The message changed from
`(reached in \`%s\`)` to `(reached from \`main\`: %s)`, where `%s` is the
chain (elided to the last 3 frames with a leading `… -> ` when longer than
4 entries, matching the body-scan diagnostic's elision policy) joined with
`" -> "`.

`cap_reach_chain` was defined (but deliberately unused, silenced with
`let _ = cap_reach_chain`) below `check_main_grant` since Task 3 deleted its
only prior caller (`check_fn_grants`). Since `check_main_grant` now calls it,
and OCaml `let`-bindings must be defined before use, `cap_reach_chain` moved
to just above `check_main_grant`'s definition; the `let _ = cap_reach_chain`
silencer is gone since the function is genuinely used again.

The old `reachable_from_main`/`reached_in` local helpers inside
`check_main_grant` (BFS over the whole env to name *a* holder, without
keeping the path) are now dead code — `cap_reach_chain` fully subsumes what
they did, plus keeps the path — and were deleted.

## Tests

`test/test_compiler.ml`, `cap_grant` suite: added
`test_grant_violation_names_the_user_module`. The plan's brief specified a
`File.read(p)` (qualified stdlib module call) reproduction, but that call
does not resolve as a stdlib-capability-bearing call inside the bare
`typecheck` test helper (which parses/desugars/typechecks the module text
directly with no `MARCH_LIB_PATH`/stdlib source loaded) — the same source
typechecks with **zero** diagnostics under the unit-test harness even though
`march --check` on the equivalent file (which does load the real stdlib)
correctly reports the violation. The test was rewritten to call the builtin
`file_read` directly (the same pattern `test_grant_violation_through_helper`
already uses for `file_write`), which reproduces the violation inside the
bare harness without needing the stdlib on disk.

## Verification

Red (before the fix, `git diff` reverted mentally by running the test against
the old message format — verified via a throwaway debug run before the
implementation, see below): `./_build/default/test/run_compiler.exe test -e
"cap_grant" 3` failed — `Expected: 'true', Received: 'false'` — the message
named no user function.

Green (after the fix): same command — `Test Successful in 0.036s. 2 tests
run.`, exit 0.

Manual CLI confirmation (both directions), via `bin/main.exe --check`:

```
mod Attributed do
  needs IO
  fn helper(p : String) : String do
    match file_read(p) do
      Ok(s) -> s
      Err(_) -> ""
    end
  end
  fn main(cap : Cap(IO.Console)) : () do
    println(helper("/etc/passwd"))
  end
end
```

produces:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileRead`
(reached from `main`: helper). The grant is a ceiling on the WHOLE program —
declaring `needs IO.FileRead` does not raise it.
```

Suites run:

- `scripts/run-tests.sh -q compiler eval codegen stdlib` — exit 0, `Test
  Successful in 15.963s. 812 tests run.`
- `./_build/default/test/run_compiler.exe test -e "cap_grant"` (both
  `cap_grant` and `cap_grant_required` suites, includes any Slow-marked
  cases in that filter) — exit 0, `Test Successful in 0.053s. 25 tests run.`
- `./_build/default/test/run_compiler.exe test -e "cap_ceiling"` (Slow tests
  included, no `-q`) — exit 0, `Test Successful in 398.241s. 26 tests run.`
  `grep -rn "reached in\|reached from" test/test_cap_ceiling.ml` found no
  matches — that suite exercises the per-module ceiling, a different check,
  unaffected by this diagnostic's wording.
- `grep -rn "reached in" test/` (repo-wide) — no remaining matches to the old
  phrasing after this change.

**Machine note:** this worktree had at least one other concurrent agent
process running its own `run_compiler.exe -e` invocations throughout
verification (confirmed via `ps`; `git status` showed no unexpected file
changes, so no interference with the diff itself), which made full
whole-suite timing unreliable and caused several run attempts to exceed a
10-minute foreground budget. Verification was narrowed to targeted
suite-name filters instead of the unfiltered full run for that reason.

`scripts/check-docs.sh` — run and exit captured directly; see task-8-report.md
for the full transcript.

Docs updated identically in `specs/lang/capabilities.md` and
`docs/capabilities.md`: the "The grant" transcript's example module gained a
`save` helper (so the transcript's `(reached from \`main\`: save)` has a
concrete referent), and the old `(reached in \`Report.save\`)` line was
replaced. The pre-existing wording divergence between the two files outside
that transcript line (comma vs. parenthetical phrasing, em dash vs. colon)
predates this task and was left untouched — only the transcript's grant-error
line itself needed to stay byte-identical, and does.
