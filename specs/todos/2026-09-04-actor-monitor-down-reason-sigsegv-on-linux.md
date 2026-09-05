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

## Reproduction status — 8,500 runs, NOT reproduced (updated 2026-09-04)

| environment | runs | SIGSEGV (139) |
|---|---|---|
| macOS arm64, `MARCH_NUM_SCHEDULERS=4` | 300 | 0 |
| macOS arm64, `MARCH_NUM_SCHEDULERS=4`, second sweep | 4,000 | 0 |
| Linux aarch64 (Docker, `ci/Dockerfile.ubuntu` base), 14 CPUs | 1,500 | 0 |
| Linux aarch64 (Docker), `--cpus 4` to force CPU-time contention | 3,000 | 0 |

**Beware the neighbouring signal.** The 4,000-run macOS sweep produced 3
non-zero exits, and all three were **137 (SIGKILL)**, not 139 — the machine's
jetsam killing processes under load, the same contamination that reddened an
unrelated `string_codepoint` codegen case the same afternoon. Filter on the
exact code; "non-zero exit" is not the signal here.

**What the negative result argues.** The suspected mechanism was a memory
-ordering / use-after-free race in the death path. aarch64 has a *weaker*
memory model than amd64, so a plain ordering race should surface sooner there,
not later — 4,500 clean Linux-arm runs is therefore evidence against that
class, not merely an absence of evidence. Note the `--cpus 4` container still
reports `nproc` = 14 (a cgroup quota does not change the CPU count the process
sees), so that leg throttled CPU *time* without narrowing the thread count.

## Still untried

- **amd64.** The failing leg is ubuntu-24.04 on amd64; everything above is
  arm64. `docker build --platform linux/amd64` reproduces it under emulation,
  which is slow (a full OCaml switch under QEMU) but is the one axis not yet
  covered, and the only one where "it only happens there" remains plausible.
- A build with `-DMARCH_DEBUG` (arms the scheduler's invariant tripwires) or
  under ASAN, which would convert a latent use-after-free into a loud failure
  well before it becomes a segfault. `specs/progress/`'s note on ASAN needing
  Docker locally applies — Falcon hangs ASAN binaries on this Mac.
## The obvious suspect has been tried and does NOT reproduce

Because the crash follows the LAST line of output, the natural suspect was the
terminal-watcher block: `spawn` a watcher and a target, `monitor`, `kill` the
watcher, `kill` the target (whose death then tries to deliver a Down into the
already-terminal watcher), then read `mailbox_size` on the killed watcher.

That block was narrowed into a standalone fixture and looped 4,000 times per
process:

```march
fn round(n : Int, bad : Int) : Int do
  if n <= 0 do bad
  else
    let w = spawn(Watcher)
    let t = spawn(Target)
    monitor(w, t)
    kill(w)
    kill(t)
    let depth = mailbox_size(w)
    round(n - 1, if depth == 0 do bad else bad + 1 end)
  end
end
```

| scheduler count | runs | terminal claims | SIGSEGV |
|---|---|---|---|
| 1 | 60 | 240,000 | 0 |
| 4 | 60 | 240,000 | 0 |
| 14 | 60 | 240,000 | 0 |

**720,000 exercises of the suspected edge, zero crashes**, and `mailbox_size`
returned 0 every single time (the property the original fixture asserts). On
macOS arm64. So either the crash is not in this block, or it needs something
this narrowing removed — the supervised children, the earlier monitors still
registered, or the specific teardown state the full program reaches.

Whoever picks this up: do not start by re-deriving the terminal-watcher
theory. It has been measured.

## Still untried

- Narrowing the OTHER direction: keep the full fixture but delete the terminal
  block, and see whether it still crashes on Linux amd64. That distinguishes
  "the crash is in teardown after everything" from "the crash is in the
  terminal block" far more cheaply than reading code.

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
