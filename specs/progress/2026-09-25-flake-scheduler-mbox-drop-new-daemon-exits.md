# `test_scheduler_mbox`: the prodder wrote to a freed proc; `test_drop_new` got the leftovers

Shipped 2026-09-25. Test-only fix; no runtime change. Closes the `[P3]` todo filed
2026-09-25 (`flake-scheduler-mbox-drop-new-daemon-exits`, original report kept below).
The filed theory, a daemon that exits before it is sent to, was wrong. The actual cause
was a use-after-free in the test itself.

## Cause

`test_block_spurious_wake_while_linked`'s `prodder_loop` sent 3000 messages to txA
through a raw `march_proc *` global (`g_txA`), yielding between sends. txA finishes its
200 sends and dies well before the prodder stops. Since proc-struct reclamation
(#592/#609) a dead proc is retired to `march_reclaim` and **freed** after a grace period,
and a pointer held across a yield does not hold that grace period back: the
`march_proc` LIFETIME contract in `runtime/march_scheduler.h` says a resolved pointer is
valid only inside the critical section that resolved it. So the prodder's later sends
went into freed memory. They read `target->pid` and `target->status` and then **wrote**
it: `mbox_lock`, mailbox links, counters.

Those writes then showed up as the "fresh" state of a later proc. On macOS, `calloc`
does not re-zero a small block it reuses. It relies on the zeroing done at `free`, so
writes made after the free survive into the new allocation. Measured on macOS 26.6.1
with a `march_proc`-sized block (288 bytes): free, write 8 bytes, `calloc` the same
size. Every time `calloc` returned the same block (12 of 1000 trials), the block
still held the write.

Symptoms seen locally, all from that one write:

- `sched_loop`'s PROC_DEAD reap walked a `mbox_send_waiters` list whose head was `0x2`.
  That is the prodder's payload. It faulted at `0xa2` (`march: fatal SIGSEGV ... addr=0xa2
  ... sched=1 (no green thread running on this scheduler)`, symbolized to the
  `dead_w->send_wait_next` load).
- `test_spurious_wake_does_not_end_recv`'s brand-new receiver got `MARCH_RECV_NO_MSG`
  (presumably a dirty `stop_requested`), failing `g_sw_got_nomsg == 0`.

The CI failure fits the same pattern: `test_drop_new`'s brand-new daemon failed its first
send, before any drop could happen. The bare `assert` could not show whether the send
returned DEAD or DROPPED, but a fresh proc with garbage state gives either.

### What it was not

The filed theory needed a scheduler thread to run the `nop` daemon before the test sent
to it. That cannot happen. The deterministic segments run after the last
`march_sched_run()` has joined every scheduler worker and the preemption daemon, so the
process has one OS thread there (probe: `task_threads()` returned 1 at the start of
`test_unbounded_default`). Nothing ever dispatches those daemons. For that reason the
fix does **not** give the daemons a body that stays alive. That change would have gone
green only by chance and hidden the real bug.

## Fix (`test/test_scheduler_mbox.c`)

- `prodder_loop` keeps txA's **pid** (`g_txA_pid`) and resolves it with
  `march_sched_find` on every turn, never across a yield. A green thread is inside a
  critical section between two dispatches, so the pointer is good until the yield. A
  reaped txA resolves to NULL and is skipped. The `g_txA` global is gone.
- `test_spurious_wake_does_not_end_recv` got the same treatment (`g_sw_rx` became
  `g_sw_rx_pid`, resolved per turn). On the fixed runtime its receiver outlives every
  access, but a regression that kills the receiver would otherwise turn a clean
  assertion failure into another use-after-free.
- The deterministic segments (`test_unbounded_default`, `test_drop_new`, `test_drop_old`)
  now use `spawn_fresh_daemon`, which checks that a just-spawned proc really is fresh
  (RUNNABLE, empty mailbox, zero markers and limit), and `expect_send`, which reports the
  send's actual return code. Either one dumps the proc's state on failure, so a
  recurrence of this class names the dirty field instead of a line number.

The other raw-pointer holders in the file (`g_bounded_rx` and `g_bounded_rxC`) were
checked and are safe: their receiver cannot finish until every sender's last send has
returned.

## Evidence

Guard Malloc (`DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib`) unmaps freed memory, so
it turns the use-after-free into an immediate fault:

| binary | runs | result |
|---|---|---|
| `origin/main` test | 20 | **20 × SIGSEGV** in `march_sched_send` (reading `target->pid`), `pid=3` = the prodder |
| fixed test (dune-built `test_scheduler_mbox_runner`) | 20 | 20 pass |
| fixed test, `MARCH_NUM_SCHEDULERS=16` | 20 | 20 pass |

Plain repeat runs (32 in parallel on a 14-CPU machine, load average 30–145 from other
sessions). The use-after-free is timing- and layout-dependent without Guard Malloc. The
unmodified `origin/main` binary happened to show none of its symptoms in 22,300 runs.
An intermediate build with only the diagnostics added (same bug, different layout)
showed them regularly:

| binary | `MARCH_NUM_SCHEDULERS` | runs | use-after-free symptoms |
|---|---|---|---|
| diagnostics only, prodder not fixed | 64 | 18,000 | 17 (SIGSEGV at `0xa2` in the reap ×15, spurious-wake `NO_MSG` ×2) |
| diagnostics only, symbolizing build | 64 | 6,000 | 7 (all the `0xa2` reap fault) |
| fixed | 64 | 9,000 | **0** |
| fixed | `""` (4) | 4,500 | **0** |

Interleaved A/B at 64 schedulers (6 rounds × 1000 each, part of the rows above):
diagnostics-only 9 use-after-free failures, fixed 0 (and 2 of the unrelated SIGTRAPs
below).

### A separate crash these loops also hit (not fixed here)

Every binary, fixed or not, also died about 0.3% of the time under this load with
`Killed: 9` or `Trace/BPT trap: 5` and no output. That is a different, pre-existing
runtime bug. macOS crash reports (52 SIGKILL and 2 SIGTRAP) all show a scheduler
worker thread in `_pthread_exit` → `_pthread_tsd_cleanup` (dyld tearing down TLVs, or
`march_reclaim`'s `slot_release` touching `tl_reclaim` and re-instantiating them). A
preemption tick interrupts it there, and `march_preempt_signal_handler`'s write to the
`_Thread_local` `march_tls_reductions` re-enters the allocator through `_tlv_get_addr`.
That aborts with `_os_unfair_lock_recursive_abort`, reported as SIGKILL, or with an
xzone malloc trap, reported as SIGTRAP. It is recorded in
`specs/progress/2026-09-25-preempt-tick-at-thread-exit-sigtrap.md` (since fixed), whose
SIGTRAP sightings it very likely explains.

---

## Original report (filed 2026-09-25)

Seen once, 2026-09-24, on the `test (macos-15, all)` leg of PR #618 (a forge-only change):
CI run 36041334583, attempt 1, job 107773957020, head 4017a1d3f. Attempt 2 of the same run
passed. The dune rule is the `test_scheduler_mbox_runner` one in `test/dune`
(`MARCH_NUM_SCHEDULERS=""`).

```
Assertion failed: (march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK),
  function test_drop_new, file test_scheduler_mbox.c, line 329.
```

That is the FIRST of the three sends expected to succeed, before any drop happens.

The filed theory (refuted above): the daemon's body is `nop`; if a scheduler thread picked
it up before the first send it would run, return and be reaped, and since #592/#609 a
send to a reaped proc reports DEAD. Suggested fix direction was a daemon body that stays
alive until the test releases it.
