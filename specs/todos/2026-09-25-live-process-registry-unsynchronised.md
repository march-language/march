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
