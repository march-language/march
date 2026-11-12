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

## Read 2026-11-11: no forge suite can reach another suite's process

The pre-1.0 plan (E3) filed this as a harness problem to fix by reading: give each
process suite its own process group, or run them serially. Reading every kill in the
suites says neither would have changed the sighting, so nothing was changed and the
item stays open.

**Every spawned process is already isolated.** `Procs.spawn` (`forge/lib/procs.ml`)
forks, calls `setsid`, then execs, so each child leads its own session and process
group; `Procs.signal_group` signals `-pid`, that one group. The suites' own `forge`
children are started the same way (`spawn_forge` in `test_topology_run.ml` and
`test_topology_reconcile.ml`). No suite shares a group with another suite's
children, and nothing signals group 0 or a group it did not create.

**Every SIGKILL names a pid its sender owns and has not reaped.**

| Site | Target | Why it cannot be someone else's |
|---|---|---|
| `test_procs.ml` fail-fast case | `Procs.pid b` | its own child, reaped only afterwards by `supervise` |
| `Procs.stop` (after the grace) | `-p_pid` | only when `p_status = None`, i.e. not yet reaped |
| `test_topology_run.ml` `cleanup` | `-pid` of its `forge` | its own child; see the one exception below |
| `test_topology_reconcile.ml` | `-x.pid` from `state.json` | read and signalled in the same step, node alive |
| `test_reconcile.ml` | forked fake servers | its own children, waited right after |

The one path that signals a pid after reaping it is `run_until` in
`test_topology_run.ml`: `wait_for_line` reaps a `forge` that exited before its ready
line, then `cleanup` sends SIGKILL to `-pid`. For that to hit the traffic driver the
driver would have to be handed the same pid in the microseconds between the two
calls; pids here are handed out in sequence (about 100 a second on this machine on
2026-11-11, wrapping at 99999). `test_release_build.ml`'s `kill_pidfile` kills a pid
read from a file, but that suite did not exist on 2026-09-24.

**So the signal came from outside the alias**, which is what the first report already
said. Two sources fit a loaded, shared development machine and neither is in this
repository: another agent session's pattern kill (a `pkill -f` from one session has
killed another session's build here before), and the kernel. The kernel's own log for
2026-11-11 shows it killing a non-idle test process of another project
(`memorystatus: killing largest compressed process`), with 7.9 of 9.2 GB of swap in
use. `runtime/` sends SIGKILL nowhere.

**What would close it.** A second sighting with the sender identified, or the D5 soak
rule from the pre-1.0 plan. Process groups and dune locks are not a fix: they change
nothing a SIGKILL by pid can reach.
