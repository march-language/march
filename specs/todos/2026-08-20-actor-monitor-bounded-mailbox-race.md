# `actor_monitor_down_reason`'s `PrimeBounded` case is racy at >1 scheduler

Filed 2026-08-20, from the work that gave the `native_actor_monitor_down_reason`
multi-scheduler loop real output assertions (`test/dune`, the
`MARCH_NUM_SCHEDULERS=4` 100-iteration rule).

## The flake

`test/native/actor_monitor_down_reason.march` asserts, in the `Watcher` actor:

```march
on PrimeBounded(expected, watcher) do
  let queued = mailbox_size(watcher)     -- sampled at handler ENTRY
  match receive() do
    Down.Down(ref, target, DownReason.Killed) ->
      if to_string(target) == to_string(expected) && queued == 1 do
```

but `main` sets that up as (lines 155-157):

```march
monitor(watcher, killed)
send(watcher, PrimeBounded(killed, watcher))
kill(killed)                              -- the Down is enqueued HERE
```

`PrimeBounded` is sent *before* `kill`. The `queued == 1` assertion therefore
only holds if `main` reaches `kill(killed)` — and the resulting `Down` is
enqueued on the watcher's mailbox — before the watcher's green thread is
dispatched onto `PrimeBounded`. Under `MARCH_NUM_SCHEDULERS=1` that is
guaranteed: nothing else can run while `main` is running. At >1 scheduler
another OS thread can pick the watcher up immediately after the `send`, sample
`mailbox_size` as 0, block in `receive()` until the `Down` finally arrives,
match the target, and then fail `queued == 1` — so the process dies with

```
panic: bounded Down or mailbox count mismatch
```

and exits 1, having printed only the first of the five expected lines.

## Measured rate

On a loaded 14-core macOS box (other agents' builds plus several 95%-CPU
processes running concurrently; `load average ~15`):

| Harness | Runs | Failures |
|---|---|---|
| Old exit-code-only loop form, 12 workers x 1000 | 12000 | 7 (`panic: bounded Down or mailbox count mismatch`) |
| Old exit-code-only loop form, 8 workers x 100 | 800 | 0 |
| Old exit-code-only loop form, serial | 500 | 0 |
| New capture+grep loop, 25 x the real 100-iteration dune loop | 2500 | 1 (same panic) |

So roughly 0.04–0.06% per run under contention and ~0 when the box is idle,
i.e. a ~4% chance of reddening the 100-iteration CI loop on a busy machine.
These are upper bounds — the box was heavily contended throughout.

**This is not new.** The loop has always propagated the binary's exit status
(`... >/dev/null || exit $?`), so the pre-change form tripped on exactly the
same panic; the table above is a direct A/B of the two loop bodies against the
same binary. Capturing stdout neither caused it nor made it more likely.

## Options

1. **Reorder the fixture**: `kill(killed)` before `send(watcher, PrimeBounded(...))`.
   Mailbox FIFO then puts the `Down` ahead of `PrimeBounded` unconditionally,
   which is what the assertion is actually trying to express ("the queued Down
   is counted exactly once, and a bounded drop_new user mailbox did not drop
   it"). Needs a check that it does not weaken the drop_new coverage the
   current ordering was chosen for, and the single-scheduler golden
   (`native_actor_monitor_down_reason.out`) must be re-confirmed.
2. **Make the watcher wait**, e.g. reuse `wait_for_queued_message` before
   sampling `mailbox_size`, so the sample is taken after the `Down` lands.
   Keeps main's ordering but makes the count assertion less sharp.
3. **Accept and pin**: drop the multi-scheduler loop back to
   `MARCH_NUM_SCHEDULERS=1`. This is the wrong trade — that loop is the only
   thing exercising Down delivery across scheduler threads, which is where
   PR #310's spurious-wake actor kill hid.

Option 1 looks right. Whoever takes it should re-measure with the 12x1000
harness above, not a 60-run spot check: at 0.05% a 60-run sample sees nothing.

## Not to be confused with

Three separate `exit 137` (SIGKILL) observations during the same session, on
three *different* native fixtures (`native_actor_monitor_down_reason`,
`native_task_await_ptr`, `native_actor_stress`), roughly 1 per 300-500 runs.
Nothing in `runtime/` raises or sends `SIGKILL`, the rate did not depend on
scheduler count (`native_task_await_ptr`: 1/1600 at the default count,
0/1400 pinned to 1), and the box was under heavy memory/CPU pressure from
other work — most likely host-level. Worth re-checking on an idle machine
before attributing any of it to March.
