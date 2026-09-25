# `[P3]` Flake: `test_upgrade_from`'s traffic driver SIGKILLed once under the parallel forge alias

**Seen** 2026-09-24, once in five runs of `dune build --root . --force @forge/test/runtest`
(the fourth, on the merge of step 8 with step 10a), never in isolation (2/2 direct runs
green, 66 s each).

The "clean upgrade passes" case printed every traffic check as ok
(`upgrade traffic: all checks passed`) and the counters were clean
(`converted 0, dropped 0, killed 0`), then `forge test --upgrade-from` reported
`upgrade_traffic killed by signal -7` (OCaml's `Sys.sigkill`). Nothing in
`forge/lib/upgrade_test.ml` or `Procs` sends SIGKILL before the verdict
(`Procs.stop` does, only in the `finally`, and only after a SIGTERM grace), and a
March program cannot SIGKILL itself, so the signal came from outside the test:
under the alias the process suites (`test_procs`, whose fail-fast case SIGKILLs a
process "from outside", `test_topology_run`, `test_topology_reconcile`) run in
parallel with it, and this machine runs many agent sessions. The dune sandbox
deleted the scratch directory, so the driver's log is gone.

**Next time it happens:** run the alias with `-j 1` to see whether it is
cross-suite; keep the sandbox (`--sandbox none`) to read
`.forge/upgrade/run/upgrade_traffic.log`; check `test_procs`'s kill target. A
sturdier driver could `process_exit(0)` right after its last check so a late
SIGKILL cannot change a verdict already earned, but that would hide the cause.
