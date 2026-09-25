# `[P3]` Flake: compiled native tests die with SIGTRAP under load (three sightings; likely cause found)

Seen 2026-09-23 during local verification of PR #604 (whose change the program does not
exercise: its only IO is Console output). One run of `dune build --root . @runtest`
failed with the test process killed by SIGTRAP; re-running the same binary passed 46 of
46 times with output matching its `.expected`, at load average 20–35.

A SIGTRAP from a compiled March program usually means code reached a compiler-inserted
trap (an LLVM `unreachable`/`llvm.trap`, e.g. a non-exhaustive match or an assertion),
not a timeout — so this should not be dismissed as load noise even though it did not
reproduce. The supervisor restart path re-runs a child's `init` with its captured
arguments (the D24 respawn closure), and supervisor/actor lifetime code was changing in
the same window (proc-struct reclamation, #592 and #609).

## Next sighting

Capture the full output and the exit status. If it recurs, run the program in a loop
under load (and under ASAN in the Linux container) to reproduce, and check which trap
fired (`MARCH_BACKTRACE=full`, or the fatal-fault report line if it prints one).

## Second sighting, 2026-09-24: `native_erased_type_id`

During local verification of PR #629 (erased-render quoting), one run of
`native_erased_type_id` inside dune died with `signal TRAP` while building in parallel
with another golden. It did not recur in 3 cache-disabled dune reruns, 30 direct runs or
45 concurrent runs.

Two different compiled programs, each trapping once under heavy parallel load and never
on rerun, make "load noise" a weak explanation: a timeout or a slow scheduler produces a
wrong result or a kill, not a trap. Something that only fails under contention — a race
that reaches a compiler-inserted trap or an `abort()` path in the runtime (the fatal-fault
report prints for SIGSEGV/SIGBUS; check whether SIGTRAP reaches it) — fits better. Both
programs start actors or scheduler threads. Treat the two sightings as possibly one bug.

## Third sighting, 2026-09-25: `native_compare_nan`

The new `native_compare_nan` golden (PR #642) died with `signal TRAP` on its **first**
run, right after dune built it. It then passed 30 direct runs and 4 forced dune reruns.

A pattern across the sightings: at least two of the three (this one and
`native_erased_type_id`) were the first execution of a freshly linked binary under dune.
The first sighting's record does not say. That could point at something about exec'ing
a just-written file, for example macOS code-signature or page validation of a binary
rewritten in place, rather than load in general. The finding below suggests a simpler
reading: a first run is slower (cold pages, signature checks), which widens the window
that trap needs.

## Likely mechanism, found 2026-09-25 (not fixed)

It was reproduced outside the native goldens, in the C scheduler unit test
`test_scheduler_mbox_runner`, while stress-looping it for
`specs/progress/2026-09-25-flake-scheduler-mbox-drop-new-daemon-exits.md`. Every
build of that test, including unmodified `origin/main`, died about 0.3% of the time
under load (32 copies in parallel, load average 30–145) with `Trace/BPT trap: 5` or
`Killed: 9` and **no output**. The macOS crash reports (2 SIGTRAP, 52 SIGKILL, in
`~/Library/Logs/DiagnosticReports/`) all have the same faulting stack, on a scheduler
worker thread **exiting**:

```
_pthread_start -> _pthread_exit -> _pthread_tsd_cleanup
  -> (dyld TLV teardown: mfm_free)          or
  -> slot_release (march_reclaim.c, touches _Thread_local tl_reclaim)
       -> _tlv_get_addr -> instantiateVariable -> malloc
  <signal> _sigtramp -> march_preempt_signal_handler
       -> _tlv_get_addr -> instantiateVariable -> malloc/mfm_alloc
       -> _os_unfair_lock_recursive_abort          (EXC_BREAKPOINT, reported as SIGKILL)
       or _xzm_xzone_malloc_freelist_outlined trap (EXC_BREAKPOINT, reported as SIGTRAP)
```

The steps:

- `march_preempt_signal_handler` writes the `_Thread_local` `march_tls_reductions` when
  its thread is found in `g_scheds` and has a pending tick. It relies on "TLS already
  materialised in sched_loop" (its own comment).
- That stops being true after `sched_loop` returns. During `pthread_exit`, dyld tears
  the thread's TLV block down. `march_reclaim`'s `slot_release` key destructor then
  touches `tl_reclaim`, which instantiates the TLVs again, and that mallocs.
- A tick the preempt daemon sent before `march_sched_preempt_stop` joined it lands
  inside that malloc. The handler's TLS write re-enters the allocator, and the
  allocator's lock or freelist check traps.

This is the same "first TLS access mallocs inside a signal handler" hazard `sched_loop`
already guards against at thread **start**, now at thread **exit**. Any program with
more than one scheduler thread goes through it at shutdown, compiled March programs
included, so it fits all three sightings: programs that start scheduler threads,
seen only under load, never reproducing on rerun. Two fix directions, untested:

- The handler touches TLS only while `g_scheds[i].running` is set (cleared on
  `sched_loop` exit before the thread leaves), or it consumes the tick flag and skips
  the TLS write once the thread is past `sched_loop`.
- `slot_release` does not touch `tl_reclaim` from the key destructor. It gets the slot
  from its argument and must not re-instantiate TLVs.

`sched_loop` already sets `sched->running` to 0 before `march_reclaim_sched_detach`, but
a tick that is already pending is still delivered.

To confirm a native-golden sighting is this one, look for a crash report in
`~/Library/Logs/DiagnosticReports/<binary>-<date>.ips` with
`march_preempt_signal_handler` under `_pthread_tsd_cleanup`.
