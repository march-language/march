# Quarantine wiring: derive the nightly alias list, machine-check the inventory

**Landed 2026-09-11.** Design: `specs/2026-09-11-ci-tooling-fixes-design.md` §3.
The inventory todo itself
(`specs/todos/2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026.md`)
stays open: two tests are still dark on the pre-write torn-output race. What
this closes is the wiring around it, which had rotted within two weeks of the
inventory being written and stayed rotten for a month.

## What was wrong

- `nightly.yml`'s quarantine loop hand-listed six aliases; three had been
  deleted on 2026-08-08 (`node_call_loopback`, `rpc_auto_enroll`,
  `forge/test/build_check`). `dune build @<undefined alias>` is a hard error,
  so three iterations failed every night, the `::notice::All quarantined tests
  passed` branch was unreachable, and the job still concluded `success`.
- `task_burst_await_quarantined` was a soak convenience for a test that is
  ALSO on `runtest`, so the derived set of `*_quarantined` aliases did not
  equal the set of dark tests.
- Three `test/dune` comments pointed at `specs/todos.md`, which does not exist.

## What landed

- The nightly loop greps `(alias *_quarantined)` out of `test/dune` and
  `forge/test/dune`, so it is exactly the set of defined quarantine aliases;
  it writes a per-alias pass/fail list to the step summary and fires the
  notice only when there is at least one alias and all passed.
- `task_burst_await_quarantined` renamed to `task_burst_await_soak`.
- `scripts/check-docs.sh` Check E: the `*_quarantined` aliases must equal the
  inventory's live (non-struck) rows, and no dune comment may point at
  `specs/todos.md`. Red on the pre-fix tree (unlisted soak alias + three dead
  pointers); green after the rename and pointer fixes with exactly two aliases.
