# `march_actor_broadcast_migrate`'s dead-target leak fix has no end-to-end regression guard

Filed 2026-08-18, from the review of the PR that landed the fix
(`specs/progress/2026-08-12-broadcast-migrate-dead-target-message-leak.md`).

## The gap

`test/test_broadcast_migrate_leak.c` is the regression test for that fix, but
it never calls `march_actor_broadcast_migrate`. `test/dune` links it against
`march_scheduler.c` alone, and the function lives in `march_runtime.c`, so it
*cannot* reach it. The test instead re-implements Phase 2's
malloc + send + conditional-free body locally (`phase2_fixed`) and asserts
against that copy, with `phase2_prefix_buggy` as a red control.

**Concretely: delete the `if (march_sched_send(...) == MARCH_SEND_DEAD) free(mm);`
line from `march_actor_broadcast_migrate` and the suite stays green.** The
test is a real test of a real property — `march_sched_send` returns
`MARCH_SEND_DEAD` for an already-dead target and takes no ownership of the
message on that path — but that property is the fix's *premise*, not the fix.

## Why the obvious end-to-end test doesn't work

The bug needs a snapshotted actor whose `meta->green_thread` is still
non-NULL (or Phase 1 skips it — the filter is
`m->dispatch_name_id == dispatch_name_id && m->actor && m->green_thread`)
while its `march_proc` has already reached `PROC_DEAD` (or the send won't
return `MARCH_SEND_DEAD`). Those two conditions are separated by a genuine
race window:

- `march_kill` → `do_actor_death` does **not** mark the proc dead. It flips
  the actor-level alive flag and `march_sched_wake`s the green thread so it
  can notice and exit.
- The proc only becomes `PROC_DEAD` by running its exit path in
  `actor_green_thread` — and *that same path* NULLs `meta->green_thread`
  (both the crash-trap exit and the normal exit do it).

So there is no non-instrumented, deterministic way to hold both conditions at
once. A loop-and-hope stress test would be probabilistic, which is the flaky
shape the original author deliberately avoided.

## Options, if this is worth closing

1. **A test-only seam.** Same shape as
   `specs/todos/2026-08-17-supervision-race-test-seam.md` asks for on the
   supervisor side — an injected stall between Phase 1's unlock and Phase 2's
   send, compiled in only for tests, forcing the interleaving. Closes it
   properly; costs production instrumentation.
2. **Split Phase 2 into a named, externally-linkable helper**
   (`inject_migrate_msg(march_actor_meta *, migrate_fn)`) and have the C test
   link `march_runtime.c` and call *that* directly with an already-dead
   target. No production behavior change, no stall hook, and the test would
   then exercise the real code rather than a copy — probably the cheapest
   honest fix, though it needs the test to pull in `march_runtime.c`'s full
   dependency set (the native rules already list it: `march_heap.c`,
   `march_gc.c`, `march_message.c`, `march_extras.c`, …).
3. **Accept it.** The leak is bounded (`MARCH_MIGRATE_SNAPSHOT` = 2048 per
   call) and the premise *is* tested; just don't let the file read as a guard
   it isn't (the header comment now says so explicitly).

Option 2 is the recommendation if anyone touches this area again.

## Related

- `specs/todos/2026-08-17-supervision-race-test-seam.md` — same class of
  problem (an entire race category with no test venue) on the supervisor
  restart path, with the same two candidate remedies.
