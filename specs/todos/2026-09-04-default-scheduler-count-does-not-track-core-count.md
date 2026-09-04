# The default scheduler-thread count (4) does not track the machine's cores

**Filed 2026-09-04**, out of
`specs/progress/2026-09-04-scheduler-count-env-was-a-silent-ceiling.md`, which
fixed the adjacent bug (the `MARCH_NUM_SCHEDULERS` environment variable was a
silent *ceiling*) and deliberately left this one alone.

## The gap

`MARCH_NUM_SCHEDULERS` now honours whatever the environment asks for, and
`MARCH_NUM_SCHEDULERS=auto` asks for one scheduler per online CPU. But the
**default** is still the compile-time constant **4**, on every machine. A March
program that sets nothing gets four OS scheduler threads on a 4-core laptop and
four on a 96-core server, and nothing in the program's output says so. Four is
therefore the de-facto parallelism limit of every March program that has not
been told otherwise.

## Why it was not simply changed

Making the default `sysconf(_SC_NPROCESSORS_ONLN)` (clamped to
`MARCH_MAX_SCHEDULERS`) changes the concurrency of every run that does not pin
the variable, and the count is directly observable in this repo's tests:
`test/dune` pins `MARCH_NUM_SCHEDULERS` to 1 or 4 in roughly fifteen rules
*precisely because* output ordering, timer behaviour and race windows depend on
it, and several golden outputs assert text that names 4. The change is
plausible and probably right; it is not a change to make in the same commit as
a bug fix, and it needs its own full-suite run plus a flake sweep on both a
high-core and a low-core box.

## What to build

1. Decide the default: `min(cpu_count, MARCH_MAX_SCHEDULERS)`, or a capped
   heuristic such as `min(cpu_count, 16)`, or keep 4 and rely on `auto`.
   A low-core CI box is the risky direction as much as a high-core one: today's
   default of 4 is >1 even on a 2-core runner, and any cpu-count default would
   make some currently-multi-threaded tests single-threaded.
2. Audit every `test/dune` rule and golden that assumes 4, and every doc that
   states it (`specs/lang/parallelism.md`, `docs/parallelism.md`,
   `docs/cookbook/parallel-data.md`, `test/apps/throughput.march`, which prints
   `Worker threads : 4 (MARCH_NUM_SCHEDULERS default)`).
3. Run the full suite repeatedly on a high-core machine, and at least once on a
   2-core container, watching for the ordering flakes that
   `specs/progress/2026-08-21-signal-watch-output-ordering-flake.md` and
   `specs/progress/2026-08-21-actor-monitor-bounded-mailbox-race.md` document
   as scheduler-count-dependent.
4. Consider reporting the resolved count somewhere discoverable (a
   `--version`/`System` field, or `MARCH_DEBUG` output) so that "how many
   threads am I actually running?" has an answer that is not `ps -M`.
