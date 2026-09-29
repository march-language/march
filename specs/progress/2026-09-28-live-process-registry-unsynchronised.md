# `Process.spawn_async`'s registry is locked, never reuses a live slot, and rejects stale handles (fixed 2026-09-28)

**Reproduced on origin/main (216f45fba)** with
`test/native/live_process_registry.march`: hold a `cat` child (`p0`) open, run
70 spawn/read/wait cycles, then write a line to `p0` and read it back.

- compiled: `p0 reads: <none>`. The 65th spawn took slot 0 and `fclose`d
  `p0`'s pipes.
- interpreted: the program hung in `wait_proc(p0)` (killed by a 90 s alarm).
  This was a separate interpreter bug. Its pipes were not close-on-exec, so `cat` inherited
  its own stdin write end and never saw EOF.

**Fix (runtime/march_runtime.c).**
- All slot bookkeeping is under one mutex (`live_proc_mu`). A new slot is the
  first free one. The table is an array of pointers to heap slots that are
  never moved or freed, and it grows on demand, so the fixed limit of 64 is
  gone. It is capped at 2^20 slots; past that, `spawn_async` returns
  `Err("too many live processes")` after reaping the child.
- The handle stored in `LiveProcess` is `(generation << 20) | slot`. Every
  allocation bumps the slot's generation, so a handle used after `wait_proc`
  (or copied before it) fails the check. `read_line` then returns `None` and
  `write` is a no-op, instead of addressing the slot's next owner.
- The blocking I/O (`fgets`, `fwrite`) runs outside the lock. A reader or
  writer marks its stream busy. `wait_proc` closes only idle streams, and a
  busy stream is closed by its user on the way out. A slot is free again only
  once both streams are closed. So `wait_proc` racing `read_line` is no longer
  a use-after-close. It still closes the idle stdin at once, so a reader
  blocked on a child that waits for EOF is released rather than deadlocked.
- The parent's pipe ends are `FD_CLOEXEC`, so a later child does not inherit
  another child's stdin.

**Interpreter (lib/eval/eval_builtins.ml).** The pipes are now created with
`~cloexec:true`, which removes the hang. Its registry was already
unbounded, with monotonic ids.

**Verification.** `test/native/live_process_registry.march`, with compiled
and interpreted dune rules diffed against one `.expected`, checks:
- 70 sequential cycles while `p0` is open, then `p0` still reads its own line;
- a stale `p0` handle after `wait_proc` reads `<none>`, while the new `p1`,
  which may have taken the slot, reads its own line;
- eight `task_spawn`ed tasks each running 25 spawn/read/wait cycles at once,
  with 0 mismatched lines.

Soaked 100 runs of the compiled binary, four at a time: 0 failures. ASAN
results (Linux container) are in the PR description.

---

Original report:

# [P2] `Process.spawn_async`'s registry is unsynchronised and recycles live slots

**Logged:** 2026-09-25
**Found by:** the stdlib audit in `specs/plans/2026-09-25-send-data-race-freedom-plan.md`.
Read from the code; not yet reproduced.

## Symptom

`march_process_spawn_async` (`runtime/march_runtime.c:~9056`) registers each
child in a fixed table:

```c
#define LIVE_PROC_MAX 64
static struct { int used; pid_t pid; FILE *fp; FILE *write_fp; } live_proc_reg[LIVE_PROC_MAX];
static int live_proc_next = 0;
...
int id = live_proc_next++ % LIVE_PROC_MAX;
if (live_proc_reg[id].fp)       { fclose(live_proc_reg[id].fp); ... }
if (live_proc_reg[id].write_fp) { fclose(live_proc_reg[id].write_fp); ... }
```

1. **Race.** `live_proc_next++` and the slot writes are unguarded. Two tasks on
   different scheduler threads calling `Process.spawn_async` can take the same
   slot, and one child's pipes overwrite (and leak) the other's.
2. **Recycling a live slot.** The 65th spawn reuses slot 0 without checking
   `used`, and `fclose`s the pipes of a process that may still be running and
   being read. A later `read_line`/`write` on the first process's
   `LiveProcess` then talks to the wrong child, because the handle stores only
   the slot id.
3. **Use after close across threads.** `read_line`, `write` and `wait_proc`
   index the table without a lock, so a `wait_proc` (which `fclose`s) racing a
   `read_line` on another thread is a use-after-close. Phase C3 of the plan
   makes `LiveProcess` linear, which prevents sharing one handle; items 1 and 2
   are runtime bugs either way.

## Fix

- Take a mutex around slot allocation and release, or make the table
  lock-free with a CAS on `used`.
- Allocate the first free slot rather than `next % MAX`, and fail with
  `Err("too many live processes")` when the table is full.
- Add a generation counter to each slot and store it in `LiveProcess`, so a
  stale handle is detected instead of addressing the slot's new owner.
- Test: spawn more than 64 processes while holding the first one open; and
  spawn from several tasks at once in the compiled suite.
