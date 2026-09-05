# The default scheduler-thread count now tracks the machine's cores

**Status:** filed 2026-09-04 out of
`specs/progress/2026-09-04-scheduler-count-env-was-a-silent-ceiling.md`,
**shipped 2026-09-04.** That entry fixed the adjacent bug — the
`MARCH_NUM_SCHEDULERS` environment variable was a silent *ceiling* — and
deliberately left the default alone.

## The gap

The default was the compile-time constant **4**, on every machine: four OS
scheduler threads on a four-core laptop and four on a 96-core server, with
nothing in the program's output saying so. Four was therefore the de-facto
parallelism limit of every March program that had not been told otherwise.

## What shipped

`MARCH_NUM_SCHEDULERS` (the macro) now defaults to **0, meaning auto** — one
scheduler per online CPU, clamped to `MARCH_MAX_SCHEDULERS`. Two helpers in
`runtime/march_scheduler.c` carry it:

- `auto_sched_count()` — `sysconf(_SC_NPROCESSORS_ONLN)`, clamped, floored at
  1 so a failing or nonsensical `sysconf` produces a slow scheduler rather
  than a zero-thread one that would hang.
- `default_sched_count()` — a compile-time pin if the build set one,
  otherwise auto.

**A compile-time pin still wins over auto, and that is load-bearing rather
than a convenience.** The C scheduler harnesses in `test/` pin themselves to 1
or 4 via `-DMARCH_NUM_SCHEDULERS` because their premise *is* a specific thread
count — with one scheduler, pinning a proc is a documented no-op, and
`test_pinned_yield_storm` asserts that unpinned siblings actually run on other
threads. On a single-core box an auto default would quietly turn those
assertions into vacuous no-ops instead of failures. The 0-sentinel keeps
`-DMARCH_NUM_SCHEDULERS=N` meaning exactly what it always did.

The environment variable is unchanged and still wins over both: a count,
`auto`, or nothing.

## Verification

**`test/test_scheduler_count.c` is now built twice from one source**
(`test/dune`), both at `-DMARCH_MAX_SCHEDULERS=8`:

| binary | build | unset must resolve to |
|---|---|---|
| `test_scheduler_count_runner` | unpinned — the shipped configuration | online CPUs, clamped (8 here) |
| `test_scheduler_count_pinned_runner` | `-DMARCH_NUM_SCHEDULERS=3` | exactly 3 |

`expected_default()` in the source is the single place encoding which is
which, so the same seven cases run against both. Both are 7/7.

**RED control** — the assertion that matters is that a pin still beats auto,
so `default_sched_count` was rewritten to `return auto_sched_count();`
(ignoring the pin) and the suite re-run:

| binary | with the pin ignored |
|---|---|
| pinned | **3 of 7 FAIL** — `test_default_when_unset`, `test_malformed_warns_and_uses_default`, `test_zero_warns_and_uses_default` |
| unpinned | still 7/7, correctly — nothing about it changed |

**End-to-end**, a compiled March program on this 14-core M3 Max, OS threads
counted with `ps -M` (count is N+1: N schedulers plus the preemption daemon):

| configuration | OS threads | elapsed |
|---|---|---|
| variable unset (the new default) | 15 | 2487 ms |
| `MARCH_NUM_SCHEDULERS=4` (the old default) | 5 | 4499 ms |
| `MARCH_NUM_SCHEDULERS=auto` | 15 | 2393 ms |

`auto` and unset agree, which the unpinned test also asserts directly so that
the two cannot silently diverge later.

## The container trap, found by the low-core leg and fixed

**`sysconf(_SC_NPROCESSORS_ONLN)` reports the MACHINE, not what the process may
use.** The first version of this change used it directly, and the todo's "run
once on a low-core container" step is what caught the consequence. Measured in
Docker on this 14-core host:

```
$ docker run --cpuset-cpus=0 ... nproc
1
$ docker run --cpuset-cpus=0 ... getconf _NPROCESSORS_ONLN
14
```

So a March program pinned to one CPU would have started **14** scheduler
threads — strictly worse than the flat default of 4 it replaced, in exactly
the environment where oversubscription hurts most. That is a regression, not a
missing nicety, and it makes container-awareness a requirement of this change
rather than a follow-up.

`march_sched_usable_cpus()` (new, exported) takes the smallest of:

- `sysconf(_SC_NPROCESSORS_ONLN)` — the machine's online CPUs;
- `sched_getaffinity` / `CPU_COUNT` — CPU **pinning** (`docker
  --cpuset-cpus`, k8s CPU-manager static policy), invisible to sysconf;
- the cgroup **quota** — CPU **bandwidth** (`docker --cpus`, k8s CPU limits),
  invisible to *both* sysconf and affinity. cgroup v2 `cpu.max` first, then
  v1 `cpu.cfs_quota_us`/`cpu.cfs_period_us`. Rounded **up**, so a 1.5-CPU
  limit yields 2 — the count is a parallelism budget, not a hard cap, and
  rounding down would strand a fractional allowance permanently.

Floored at 1 throughout: a probe that fails must yield a slow scheduler, never
a zero-thread one that would hang instead of running slowly.

Verified end-to-end in Docker (`MARCH_MAX_SCHEDULERS=8`, host has 14 CPUs, and
`sysconf` reports 14 in every row):

| container flag | mechanism | usable CPUs | unset resolves to |
|---|---|---|---|
| `--cpuset-cpus=0` | pinning | 1 | **1** |
| `--cpuset-cpus=0,1` | pinning | 2 | **2** |
| `--cpuset-cpus=0,1,2,3` | pinning | 4 | **4** |
| `--cpus=1` | quota | 1 | **1** |
| `--cpus=2` | quota | 2 | **2** |
| `--cpus=3` | quota | 3 | **3** |
| (none) | — | 14 | 8 (clamped by MAX) |

The `--cpus` rows are the ones affinity alone would have got wrong: `nproc`
still reports 14 under a quota.

### A banner that agreed with itself

Worth recording because it wasted a cycle: the first container run reported
"resolves to 8" in every configuration and looked like the fix had not worked.
It had — the **test's banner was printing its own `sysconf`-based prediction**
rather than what `march_sched_init` resolved. A test that predicts and then
checks its own prediction agrees with itself while the runtime disagrees. The
banner now prints `march_sched_num_schedulers()` after a real init, and
`expected_default()` asks the runtime for the CPU count instead of
reimplementing cgroup parsing — which would only have tested the copy.

## The four harnesses that lost their multi-scheduler guarantee

`test/dune` built `test_scheduler_{timer,mbox,churn,mt}` with **no**
`-DMARCH_NUM_SCHEDULERS`, commented "Multi-scheduler (no
-DMARCH_NUM_SCHEDULERS=1)". Under a flat default of 4 that comment was true by
accident. With an auto default it is not: on a 1-CPU machine they would run
single-threaded, and `test_scheduler_mt`'s third case is literally named "via
stealing" — work stealing needs more than one scheduler to mean anything, and
its assertions are completion COUNTS, which still pass at one scheduler. It
would have gone quietly vacuous rather than failing.

All four are now pinned at `-DMARCH_NUM_SCHEDULERS=4` explicitly, with the
reason in the rule. The guarantee they always effectively had is now stated
instead of inherited.

Verified in a 1-CPU and a 2-CPU container: `pin` 2/2, `scheduler` 10/10, `mt`
3/3, `churn` all passed — the compile-time pins hold regardless of the
machine, which is the property the whole 0-sentinel design rests on.

## Docs and goldens audited

Every place that stated the old default:

- `specs/lang/parallelism.md` and `docs/parallelism.md` (both copies — `docs/`
  is what the site serves), in two spots each: the scheduler paragraph and the
  "How many OS threads" section.
- `docs/cookbook/parallel-data.md`, whose speedup table was measured at four
  workers; the table is kept and relabelled as a shape rather than silently
  reinterpreted.
- `test/apps/throughput.march`, which printed
  `Worker threads : 4 (MARCH_NUM_SCHEDULERS default)`. Not run by dune — a
  demo, not a golden — but it was simply wrong after this change.
- `test/native/signal_watch.march`'s ordering-hazard comment, which reasoned
  from "the default of 4".

`docs/pagefind/` regenerated for the docs edits.

## What this does NOT change

`test/dune` pins `MARCH_NUM_SCHEDULERS` in 31 places (18 at 1, 6 at 4, 1 at 8,
6 at `""`). None of them change behaviour: an explicit value still wins, and
the six `""` wrappers still fall through to the build's default, which for
those compile-time-pinned harnesses is still their pin.

## Left open deliberately

The original todo's item 4 — "report the resolved count somewhere
discoverable" — is largely dissolved rather than done. The complaint it came
from was that a silent cap of 4 was invisible; with the default tracking the
machine, "how many threads am I running?" has an obvious answer again. A
`System.scheduler_count()` builtin would still be nice (the C accessor
`march_sched_num_schedulers()` already exists), but adding a builtin touches
nine sites and is its own change.
