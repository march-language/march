# Pid ownership settled: `send` and the read-only actor builtins borrow the pid; every pid-producing builtin returns an owned reference

Closed 2026-09-14. The original note (filed 2026-09-13 as "`send` of a pid
that is still live afterwards leaks one actor reference") follows the
resolution.

## Resolution

Both halves, at once, as the note asked:

- **Borrowed:** `send`, `actor_cast`, `kill`, `actor_stop`, `is_alive`,
  `actor_is_draining`, `mailbox_size`, `get_cap` (`lib/tir/borrow.ml`,
  `extern_borrow_table`). Audited: none of their C implementations stores or
  releases the actor. `send`'s MESSAGE stays owned (the runtime enqueues it).
- **Owned returns:** `pid_of_int` (already), and now `self` /
  `march_self` (`runtime/march_scheduler.c`, with a weak `march_incrc`
  fallback so the standalone scheduler unit harnesses still link — the same
  discipline as `march_signal_drain`). `actor_whereis` and `spawn` already
  transferred a reference.
- **Prerequisite** that made the 2026-09-13 attempt SIGSEGV:
  [[2026-09-14-live-actor-freed-by-dropping-its-last-pid]] — a running actor
  now holds one reference of its own, so releasing the program's pids at
  their last use is safe.

Measured on the way (container, ASAN): with `send` borrowing but `self`
still unowned, `actor_send_to_self`'s count moved by −1 per in-handler
`send(self, m)` — the reference the program released was the actor's own.

The three refcount-probe fixtures now assert the contract rather than the
leak: `actor_send_to_self` asserted `rc_before + 10` for ten sends (the leak
pinned as if it were the rule) and now asserts `rc_before`;
`actor_dispatch_rc_window` and `actor_crash_rc_restore` keep their `victim_pid`
alive across the measurement so the count they compare includes the
program's own reference.

Verified: `@test/runtest` (all native/session goldens), and an ASAN sweep of
50 actor-related native and session fixtures in a Linux container, clean.

---


Found 2026-09-13 while fixing send-to-self
(`specs/progress/2026-09-13-send-to-self-delivers.md`), measured with the
`ffi_test_actor_rc` probe on a supervised child (true count 2 at rest).

## The mismatch

Perceus treats `send`'s first argument as **consumed**. A pid still used after
the send is dup'd (`march_incrc_local`) before the call; one at its last use is
handed over. `march_send` (`runtime/march_runtime.c`) **never releases the
actor reference**: its RC contract comment covers only `msg`.

| call shape | net effect on the actor record |
|---|---|
| `send(pid_of_int(i), m)` (fresh, unowned temp) | 0 |
| `let p = pid_of_int(i)` then `send(p, m)` and a later use of `p` | +1 |
| `send(self, m)` in a handler | +1 per send |
| `let p = spawn(A)`, `send(p, m)`, later use of `p` | +1 |

The first row balanced only by accident: `pid_of_int` also returned without
taking a reference, so an owned-but-unowned temp cancelled a
consumed-but-never-released argument.

**Update 2026-09-14:** `march_pid_of_int` now returns an OWNED reference
(`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`). The
unowned return became a use-after-free once closure parameters were pinned
owned: `List.length` of `Actor.list()` released every pid in the list. So the
first row is now **+1** as well; `send` is the remaining half.

Tried the same day and backed out: classifying `send`, `is_alive`,
`get_actor_field` and `mailbox_size` as borrowing the pid. The runtime
functions only read it, but a borrowed `send` releases the pid `spawn` returned
at its last use, and `actor_mailbox_alarm` SIGSEGV'd along with three other
actor goldens. `spawn`'s return ownership has to be settled first.
`actor_send_to_self` now asserts the count moves by exactly one per send.

## Why it is not simply "make march_send decrc"

That would make the first row −1: a premature free of a live actor. The fix has
to settle both halves together:
- does `send` consume its pid, or borrow it? (borrowed matches the runtime);
- do `march_self` and friends return an owned reference? (`pid_of_int` does,
  since 2026-09-14.)

Settle both in Perceus's builtin borrow table and the runtime at once. Then
re-run `test/native/actor_send_to_self.march`,
`actor_dispatch_rc_window.march` and `actor_crash_rc_restore.march`. All three
read the refcount directly.

**Update 2026-09-14 (later):** the other half is settled for `spawn`: the
runtime now holds its own reference to a live actor, taken in `march_spawn`
and released when the actor's green thread finishes
([[2026-09-14-live-actor-freed-by-dropping-its-last-pid]] in
`specs/progress/`). Dropping every pid to a running actor no longer frees
it, so classifying `send`/`is_alive`/`mailbox_size` as borrowing can be
retried without the SIGSEGVs that backed it out.

## Impact

A leak only: an actor that is sent to while its pid stays live is never freed
by RC. Nothing observable today, since actors are not reclaimed by RC in any
test. It becomes one the day they are.
