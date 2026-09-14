`[P3]` # `send` of a pid that is still live afterwards leaks one actor reference

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

## Impact

A leak only: an actor that is sent to while its pid stays live is never freed
by RC. Nothing observable today, since actors are not reclaimed by RC in any
test. It becomes one the day they are.
