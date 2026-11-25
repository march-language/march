# A caught panic leaves the handle uses it jumped out of

Stage A0 step 4 and unit U5 step 1 of `specs/plans/2026-11-23-pre-1.0-bug-first-plan.md`;
the main item of `specs/todos/2026-11-13-handle-stranded-in-flight-after-panic.md` (its two
drain-timeout items stay open there).

**Was.** A use of a handle box is `handle_enter` ... `handle_leave` in the stdlib (about 25
sites, 6 through a helper). A panic between the two never left, so the box's in-flight count
stayed above zero: `close` set CLOSED and then waited for a leave that could not come. A
`Listener` kept its port bound after `close_listener` until the box was dropped.

**Now (option (b) of the plan).** Each green thread keeps the boxes it has entered and not
left, on a stack beside its saved authorities (`march_auth_state.entered`,
`runtime/march_scheduler.h`), each entry with a reference. `march_cap_mark` records its depth
and `march_cap_unwind` pops to it (`march_handle_unwind_to`), so every one of the eleven panic
catch sites leaves the abandoned uses with no stdlib edit and no `try_finally` on the I/O path.
The scheduler's reap leaves whatever a dead green thread was still inside. `close` and
`close_drain` take their own count without an entry (C code, cannot panic).

The cost is on every handle use: a push and a pop, and a reference taken and dropped, next to
a system call. Not measured.

**Tests.**
- `test/test_cap_runtime_slot.ml`, "a caught panic leaves the handle uses it abandoned"
  (compiled and JIT): a panic inside a use of a `Listener`, caught by `__try_call` and by
  `try_finally`, then `close_listener`, then `Socket.listen` on the same port. Before:
  "still bound". After: "released".
- `test/test_handle.c`, `test_unwind_leaves_abandoned_uses`: the mark and unwind, a use from
  before the mark kept, nesting, an out-of-order leave.

**Not covered.**
- The reap path has no test. Cancelling a task parked in `accept` does not reach it: the task
  wakes at the close and leaves normally (checked on main and here, both "released"). An actor
  killed while parked in a use would; no fixture was built.
- The interpreter keeps no in-flight count, so it never had the problem.
- What else a caught panic abandons (closures, locals) is still not released.
