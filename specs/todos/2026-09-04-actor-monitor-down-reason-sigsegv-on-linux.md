# `native_actor_monitor_down_reason` exited 139 (SIGSEGV) on the Linux CI leg

**Filed 2026-09-04.** One observation, not yet reproduced. Recorded rather than
re-run away, because the symptom is a segfault in the actor monitor/death path,
which is not a class of failure to lose track of.

## The observation

`test (ubuntu-24.04)`, run
[33912489505](https://github.com/march-language/march/actions/runs/33912489505/job/101151887101),
on PR #419 (whose entire diff is `test/test_scheduler_pin.c` — a standalone C
harness — plus a markdown file, so it cannot reach this fixture).

`test/dune`'s 100-iteration stress rule around `native_actor_monitor_down_reason`
failed at iteration 34:

```
native_actor_monitor_down_reason: MARCH_NUM_SCHEDULERS=4 iteration 34: binary exited 139
offending output:
down ref=1 target=crashed reason=Crash(bang)
bounded mailbox=1 down=Killed ref=3
late down ref=5 target=killed reason=Killed
down target=nulled reason=Crash(embedded-nul-ok)
terminal watcher mailbox=0
```

**All five expected lines were printed** (in a legal interleaving — the rule
matches each with its own `grep -Eq`, not as an ordered golden). The process
then died of SIGSEGV. So this is a crash at or after the last handler, not a
wrong result.

## What it is NOT

`specs/progress/2026-08-21-actor-monitor-bounded-mailbox-race.md` fixed a
different flake in the same fixture: a `mailbox_size` sample race that produced
`panic: bounded Down or mailbox count mismatch` in roughly 0.1% of runs. That
one exits via a panic with a message, not SIGSEGV, and the offending output
above shows `bounded mailbox=1` — the sample that race got wrong is correct
here.

## What has been ruled out

- **PR #419's own change.** Its diff is `test/test_scheduler_pin.c` (a
  standalone C test binary, linked into nothing else) and one markdown file.
- **The `MARCH_NUM_SCHEDULERS` change**
  (`specs/progress/2026-09-04-scheduler-count-env-was-a-silent-ceiling.md`),
  which had landed on main just before. This rule pins the variable to 4
  explicitly; under both the old and the new resolution code that yields
  exactly 4 scheduler threads. main's own `test (ubuntu-24.04)` leg passed on
  `2ac12751`, which contains that change.

## Reproduction status

- **macOS, 300 runs at `MARCH_NUM_SCHEDULERS=4`, load ~16: 0 crashes.** The
  fixture was built from the same tree.
- Not yet attempted on Linux. `specs/progress/`'s note on running the aarch64
  CI leg locally in Docker
  (`specs/progress/…aarch64-ci-leg-local-docker-repro`, and the memo on
  `alpine:3.21` running natively on an arm64 Mac) is the cheapest next step,
  though the failing leg is ubuntu-24.04 on amd64 and the platform difference
  may matter — a segfault that only shows on one libc/arch usually does.

## What to build

1. Try to reproduce on Linux: the fixture in a loop under `MARCH_NUM_SCHEDULERS=4`,
   then under ASAN (`ci/Dockerfile.ubuntu`; note its own `dune build` fails for
   want of `node`, so build only `bin/main.exe`).
2. If it reproduces, get a backtrace. The suspects are the paths the fixture
   exercises last: `do_actor_death` → `deliver_monitor_down` →
   `march_sched_send_control`, and the terminal-watcher teardown after the
   final `mailbox=0` line — i.e. a use-after-free of a monitor entry or of the
   dying actor's control mailbox during shutdown, which would explain a crash
   *after* correct output.
3. If it does not reproduce in a few thousand Linux iterations, leave this file
   open with the negative result recorded rather than deleting it; a single
   SIGSEGV in the death path is worth a second sighting before it is dismissed.
