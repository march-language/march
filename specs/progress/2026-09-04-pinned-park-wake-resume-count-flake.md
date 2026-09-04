# `test_pinned_park_wake` asserted a resume count that was scheduling luck

**Status:** filed and **fixed 2026-09-04.** Pre-existing; the test landed
2026-09-03 in `specs/progress/2026-09-03-pin-main-green-thread-to-scheduler-0.md`
and started failing on main's macOS leg almost immediately.

## The flake

`test/test_scheduler_pin.c`'s second case parks a **pinned** green thread and
has eight worker-thread "wakers" wake it, to prove that a pinned proc resumes
on the main thread across the cross-thread wake path. It then asserted:

```c
TEST_ASSERT(atomic_load(&g_wakes) >= N_WAKERS, "sleeper was woken (at least once per waker)");
```

`march_sched_wake` is a **no-op when the target is not parked**, so `g_wakes`
counted resumes that happened to be delivered, not resumes the test arranged
for. The sleeper is pinned to scheduler 0 — which is also the OS thread running
`march_sched_run` and a share of the wakers — so on a small, busy runner it can
park once, be woken once, and find `g_wakers_done` already at 8. One resume,
assertion wants eight, red run.

Observed on main's `test (macos-15)` leg three times in two days, always the
same line:

| run | commit | date |
|---|---|---|
| 33820372950 | `1eb43d39` | 2026-09-04 00:06 |
| 33877691194 | `7419c689` | 2026-09-04 13:22 |
| 33892464683 | `eaf7a71c` | 2026-09-04 15:57 |

all reporting `FAIL [test_pinned_park_wake:119]: sleeper was woken (at least
once per waker)` at `File "test/dune", lines 149-152`. It then failed a fourth
time on `2ac12751`, which is what prompted this fix.

**Not reproducible by load alone on a 14-core machine:** 100 runs at load 14,
100 interleaved runs at load 64, and 12 runs each at
`MARCH_NUM_SCHEDULERS=4/16/32/64` all passed. What reproduces it is making the
wakers *finish sooner* — building the same test with `WAKES_PER=1` and
`burn(0)` fails **19 of 20 runs** with the exact CI message. That is the
mechanism stated directly: the assertion holds only while the wakers are still
running when the sleeper gets scheduled.

## The fix

Make the resume count a **requirement the test enforces**, not an observation:

- The sleeper loops until `g_wakers_done == N_WAKERS` **and**
  `g_wakes >= REQUIRED_WAKES`, then sets `g_sleeper_done`.
- Each waker, after its `WAKES_PER` iterations, keeps calling
  `march_sched_wake` (with a yield) until `g_sleeper_done` is set, instead of
  firing one parting wake and hoping it lands. This also closes the
  lost-wakeup window where the sleeper parked just after that single wake.
- The spin is bounded by `WAKE_SPIN_LIMIT` so a broken `march_sched_wake` ends
  the spin rather than burning a CI worker. It still cannot turn that breakage
  into a clean failure — a sleeper that never resumes stays a live parked proc
  and `march_sched_run` waits for it — but that was true before this change
  too, and is recorded in the source comment rather than silently accepted.
- The per-test counters are reset in `test_pinned_park_wake` (they were file
  statics relying on being run once).
- A new assertion, `g_sleeper_done == 1`, states the termination property
  directly.

**This strengthens the test rather than weakening it.** The assertion that
carries the feature — `g_wake_off_main == 0`, every resume on the main thread —
was previously backed by however many resumes the scheduler happened to
deliver, possibly one. It is now backed by at least eight cross-thread wakes on
every run.

## Verification

| run | result |
|---|---|
| the 19/20-red reproduction (`WAKES_PER=1`, `burn(0)`), rebuilt with the fix | **0 / 40 failed** |
| the real test, unmodified, after the fix | 0 / 200 and 0 / 400 failed |
| RED control: `march_sched_spawn` instead of `march_sched_spawn_pinned` for the sleeper | **10 / 10 failed**, on `pinned proc resumed on main thread after every wake` |

The RED control is the one that matters: the fix must not have turned the case
into something that passes regardless. It still fails, and it fails on the
pinning assertion rather than on the resume count.

## Not the scheduler-count change

This surfaced in the same CI run as
`specs/progress/2026-09-04-scheduler-count-env-was-a-silent-ceiling.md`, which
touches `march_sched_init` and adds a `(setenv MARCH_NUM_SCHEDULERS "")`
wrapper to this harness's `test/dune` rule. It is not that change's doing: the
three failures above predate that branch, the `test/dune` line numbers in them
are the pre-edit ones, and at four schedulers with the variable unset the new
resolution code produces exactly the old value. An interleaved A/B of the pin
test built against the pre-change and post-change `march_scheduler.c` came out
0/100 and 0/100.
