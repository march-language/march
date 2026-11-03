# `[P2]` `native_run_until_idle_ping_pong` segfaulted once at 14 schedulers (CI, amd64)

Seen 2026-10-04 in `test (ubuntu-24.04, rest)` of #767's CI run 37167730689 (job
111334108065), on a tree that had just merged Observe R2 (#766: the crash ring and
`spawned_by` in `runtime/march_scheduler.c`). The dune rule runs
`MARCH_NUM_SCHEDULERS=14 ./native_run_until_idle_ping_pong`; it printed
`Segmentation fault (core dumped)` and nothing else. No other CI run in the preceding day
shows it.

Not reproduced: 0/100 on macOS arm64 and 0/300 in `ci/Dockerfile.ubuntu` (linux/arm64),
both at 14 schedulers on the same tree. CI is amd64.

A 14-scheduler segfault has a known cause in this runtime: a `tl_sched`-reading helper
inlined across a green-thread switch, which reads the old thread's scheduler after the proc
migrated (the fix is `noinline`). Check any helper Observe R2 added on the dispatch or
park path for that first. Next step: a loop of this binary on an amd64 machine (or
`--platform linux/amd64` emulation), with a core dump to get the faulting pc.

## TSAN on macOS, 2026-10-11: nothing, apart from a TSAN-only wedge

`MARCH_SANITIZE=thread` build (macOS arm64, LLVM 22), 14 schedulers: no TSAN report, but
every run (11 of 11) wedges before printing anything. A 1000-ball version wedges in 9 of
11 runs at 2 schedulers and finishes at 1. It never wedges in plain or ASAN+UBSan builds,
and it still wedges with the runtime at `-O0` (so it is not the TLS-hoist class named
above) and with `-DMARCH_DEBUG` (no run-queue tripwire fires). That is a lost-proc hang,
not a SIGSEGV, so it does not explain this crash. Filed as
`specs/progress/2026-10-11-macos-tsan-scheduler-wedge.md`. The only refcount race TSAN
reported (the immortal-check read in `march_decrc`, now relaxed-atomic) cannot cause a
fault: a mortal count can never reach the 2^40 immortal threshold.

**Update 2026-10-11:** the wedge was not a lost proc. It was TSAN deadlocking in its own
report path, re-entered through the preemption signal handler; fixed, see
`specs/progress/2026-10-11-macos-tsan-scheduler-wedge.md`. It is unrelated to this crash.

## 2026-10-12: did not reproduce under ASAN on Linux arm64

30 runs at `MARCH_NUM_SCHEDULERS=14` under `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1` (`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`), Docker
`march-ci-ubuntu-step6b` (arm64, glibc 2.39), concurrently with a 6-way ASAN
sweep for load: 0 failures, no sanitizer report. The fixture is also clean in
the full `scripts/native-sanitize-sweep.sh` error pass at 1 and 14 schedulers.

## 2026-10-13: amd64 reproduction attempts, the crash signature, and a dispatch guard

Still open: not reproduced, cause not found. What was learned narrows the class.

### The signature rules most causes out

The CI line is the shell's `Segmentation fault (core dumped)` (dash forked and saw
WIFSIGNALED), with no `march: fatal ...` line before it. `march_sigsegv_handler`
never produces that: every fault it handles either grows a stack and returns, or
writes the `march: fatal` line and calls `_exit(139)` (no core, no shell message).
So the handler did not run. With the handler installed (`march_sched_init`, never
reset; nothing else in the runtime touches SIGSEGV), that leaves three ways:

1. SIGSEGV was blocked on the faulting thread (the kernel then forces the default
   action);
2. the handler itself faulted (SIGSEGV is blocked inside it);
3. the kernel could not push the signal frame (no or bad alternate stack).

Shown by perturbation (Docker `ubuntu:24.04`, linux/amd64, Ubuntu clang 18.1.3,
this branch's runtime with one injected corruption at the 500th dispatch of pid 2,
`sh -c 'MARCH_NUM_SCHEDULERS=14 ./prog'`):

| injected into the saved context before `swapcontext` | output |
|---|---|
| `sigaddset(uc_sigmask, SIGSEGV)` + pc = 0x10 | `Segmentation fault (core dumped)` and nothing else, rc 139: **the CI signature** |
| pc = 0x10 only | `march: fatal SIGSEGV si_code=1 addr=0x10 pc=0x10 sched=13 pid=2 status=1 fault outside its stack` |

So an ordinary wild-pointer fault, a bad pc, a stack overflow into the guard page,
and a fault in a non-scheduler thread all print. Resuming a context the proc did
not save (freed `p->ctx` reused by the allocator, a context torn by two
schedulers resuming one proc, heap corruption over a ucontext) restores a garbage
`uc_sigmask` before jumping, which is case 1. The other known case-1 source is a
lazy green-stack growth fault inside a glibc window that blocks every signal
(`pthread_create`, `pthread_kill`, `posix_spawn`) called on a green stack (the
2026-10-06 shell fix and the 2026-10-12 ASAN pthread_create fixes); this fixture
calls none of those from a green thread (its runtime calls: `march_spawn_main`,
`march_run_scheduler`, `march_spawn` x2, `march_send` x2, `march_run_until_idle`,
`march_get_actor_field`, `march_println`, RC and alloc helpers).

### Reproduction: 0 failures in about 6,500 runs

The binary: compiled on macOS for linux/amd64 (`--target linux/amd64` emits x86-64
IR), then linked in the container two ways: by the cross driver (zig cc, glibc
malloc, no mimalloc), and by Ubuntu clang 18 with the native Linux driver's flags
(`-O2 -msse4.2 -DMARCH_USE_MIMALLOC ... -fno-strict-aliasing -fwrapv`), as CI does.
Also the CI tree itself: `git archive 08bed06e1` (#767's head, the failing run's
commit), its own compiler and runtime, same procedure. Docker Desktop on Apple
silicon, so x86-64 under Rosetta (x86 TSO memory model, different timing).
`ulimit -c unlimited`; every run checked for rc != 0 and for output != `total 200000`.

| binary | schedulers | CPUs | load | runs | failures |
|---|---|---|---|---|---|
| this tree, zig cc | 14 | 14 | none | 1000 | 0 |
| this tree, clang 18 + mimalloc | 14 | 14 | none | 1500 | 0 |
| this tree, clang 18 + mimalloc | 14 | 14 | `stress-ng --cpu 14` | 600 | 0 |
| this tree, clang 18 + mimalloc | 14 | 4 (`--cpuset-cpus`, like a CI runner) | none | 800 | 0 |
| this tree, clang 18 + mimalloc | 14 / 4 | 4 | 3 other loops | 400 / 300 | 0 |
| CI tree 08bed06e1, clang 18 + mimalloc | 14 | 14 | other loops | 1210 | 0 |
| CI tree 08bed06e1, clang 18 + mimalloc | 14 / 32 | 4 | 3 other loops | 400 / 300 | 0 |

### Code audit (this tree)

- Every function in `runtime/march_scheduler.c` that reads `tl_sched` after a
  possible green-thread switch is `noinline` or reads it only before the switch:
  `march_sched_yield`, `run_on_sched_stack`, `wait_idle` (captures `self` first,
  loop reads no TLS), `tick`, `exit`, `send` (`sender` read once before the
  loop; the BLOCK guard goes through `on_sched_control_plane`, fixed
  2026-10-12), `recv_actor_ex`, `recv_mode`, `recv_until_mode`, `park_self`,
  `park_self_until`, `wait_fd(s)`. `sched_loop` reads it once, on its own stack.
  Callers in `march_runtime.c` are in another translation unit (no LTO), so a
  call there always re-reads it.
- Observe R2's additions on this path (#766): `slices`/`last_run_ms` (owner
  scheduler, after the claim CAS), `msgs_in` (receiver, under the mailbox
  lock), `msgs_out` (the `sender` proc, read once before any park; the proc
  pointer is the caller's own and stays valid), `march_sched_set_held` and
  `march_observe_count_send` (`noinline`, fresh `tl_sched`). The counters are
  relaxed single-writer load+store pairs; at worst a lost count, never a bad
  pointer. `spawned_by` in `march_spawn_common` is not exercised here (main has
  no actor). The crash ring is written only on a crash. The `aligned(64)` on
  `march_scheduler` is satisfied (`g_scheds` is a static array). Nothing found.
- Fixed since the failing commit and relevant to a silent SIGSEGV of this
  shape: green threads spawned off-scheduler no longer inherit a fully blocked
  mask (2026-10-06; not reachable from this fixture), the preemption handler
  saves errno (2026-10-11).

### Guard added (this branch)

`dispatch_check_ctx` in `sched_loop`, just before the `swapcontext` into a proc:
if the saved context's mask blocks SIGSEGV or SIGBUS, or (Linux x86-64/arm64)
its saved stack pointer is outside the proc's stack reservation, it prints
`march_sched[BUG]: dispatch of pid N on scheduler S with a context it did not
save (...)` with the saved sp, the stack bounds and the status, and aborts.
Verified with the same injection: `march_sched[BUG]: dispatch of pid 2 on
scheduler 11 with a context it did not save (signal mask blocks SIGSEGV/SIGBUS):
saved sp=0x7ffff7ac9d50, stack [0x7ffff79c9000, 0x7ffff7aca000], status=1`,
then `Aborted (core dumped)`. A legitimate context never trips it (no green
thread switches out with the fault signals blocked; spawn strips them). The
cost is two bit tests and two compares next to a `swapcontext` that makes a
`sigprocmask` syscall. A recurrence on CI now names the pid and says which
check failed; if it still dies silently, the bad context was not one being
dispatched (e.g. a fault inside a glibc all-signals-blocked window on a green
stack), which is itself a narrowing.

Next step if it recurs: the CI job's core capture (`Capture test cores (Linux)`
in ci.yml) plus the new line; a real amd64 host (not Rosetta) loop.
